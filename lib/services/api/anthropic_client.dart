import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/models.dart';
import 'llm_types.dart';
import 'reasoning_params.dart';
import 'sse.dart';

class AnthropicClient implements LlmClient {
  static const _apiVersion = '2023-06-01';

  @override
  Stream<LlmEvent> stream(LlmRequest request) async* {
    final client = http.Client();
    try {
      final url = Uri.parse(anthropicMessagesUrl(request.provider.baseUrl));
      var body = _buildBody(request);
      http.StreamedResponse? response;
      String? errorBody;

      for (var attempt = 0; attempt < 4; attempt++) {
        response = await _send(client, url, request, body);
        if (response.statusCode >= 200 && response.statusCode < 300) break;
        errorBody = await response.stream.bytesToString();
        final lower = errorBody.toLowerCase();
        Map<String, dynamic>? retry;
        if ((lower.contains('thinking') ||
                lower.contains('adaptive') ||
                lower.contains('output_config') ||
                lower.contains('effort')) &&
            (body.containsKey('thinking') || body.containsKey('output_config'))) {
          retry = Map<String, dynamic>.from(body)
            ..remove('thinking')
            ..remove('output_config');
          final legacy = legacyAnthropicThinkingParams(request.reasoningLevel);
          if (legacy.isNotEmpty) {
            retry.addAll(legacy);
            final budget = (legacy['thinking'] as Map)['budget_tokens'] as int;
            final maxTokens = (retry['max_tokens'] as num?)?.toInt() ?? 8192;
            retry['max_tokens'] = maxTokens > budget + 1024 ? maxTokens : budget + 2048;
          }
        } else if ((lower.contains('tool') || lower.contains('function')) &&
            body.containsKey('tools')) {
          retry = Map<String, dynamic>.from(body)
            ..remove('tools')
            ..remove('tool_choice');
        } else if (lower.contains('max_tokens') && body.containsKey('max_tokens')) {
          retry = Map<String, dynamic>.from(body)..remove('max_tokens');
        }
        if (retry == null || retry.isEmpty) break;
        body = retry;
        response = null;
      }

      if (response == null || response.statusCode < 200 || response.statusCode >= 300) {
        throw LlmException(
          _errorMessage(errorBody, response?.statusCode),
          statusCode: response?.statusCode,
          details: errorBody,
        );
      }

      final contentType = (response.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('event-stream') || contentType.contains('stream')) {
        yield* _parseSse(request, response.stream.timeout(const Duration(seconds: 180)));
      } else {
        final text = await response.stream.bytesToString();
        yield* _parseFull(text);
      }
    } on LlmException catch (error) {
      yield StreamFailure(error.message, details: error.details, statusCode: error.statusCode);
    } on TimeoutException {
      yield const StreamFailure('请求超时。请检查网络或稍后重试。');
    } catch (error) {
      yield StreamFailure('请求失败：$error');
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _buildBody(LlmRequest request) {
    final body = <String, dynamic>{...request.provider.customBody};
    body['model'] = request.model.id;
    body['max_tokens'] = request.maxTokens.clamp(1024, 64000);
    body['system'] = request.systemPrompt;
    body['messages'] = _buildMessages(request);
    body['stream'] = true;
    if (request.tools.isNotEmpty && request.model.tools) {
      body['tools'] = request.tools
          .map(
            (tool) => {
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.inputSchema,
            },
          )
          .toList();
    }
    final thinking = anthropicThinkingParams(request.model, request.reasoningLevel);
    if (thinking.isNotEmpty) body.addAll(thinking);
    if (!(request.model.reasoning && request.reasoningLevel.isEnabled)) {
      body['temperature'] = request.temperature;
    }
    return body;
  }

  List<Map<String, dynamic>> _buildMessages(LlmRequest request) {
    final messages = <Map<String, dynamic>>[];

    void append(String role, List<Map<String, dynamic>> blocks) {
      if (blocks.isEmpty) return;
      if (messages.isNotEmpty && messages.last['role'] == role) {
        final content = messages.last['content'];
        if (content is List) content.addAll(blocks);
      } else {
        messages.add({'role': role, 'content': blocks});
      }
    }

    for (final message in request.messages) {
      switch (message.role) {
        case ChatRole.user:
          final blocks = <Map<String, dynamic>>[];
          if (message.text.trim().isNotEmpty) {
            blocks.add({'type': 'text', 'text': message.text});
          }
          if (message.images.isNotEmpty) {
            for (final image in message.images) {
              blocks.add({
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': dataUrlMime(image.dataUrl, fallback: image.mime),
                  'data': stripDataUrlPrefix(image.dataUrl),
                },
              });
            }
          }
          append('user', blocks);
          break;
        case ChatRole.assistant:
          final blocks = <Map<String, dynamic>>[];
          if (message.rawContent != null && message.rawContent!.isNotEmpty) {
            blocks.addAll(message.rawContent!);
          } else {
            if (message.text.trim().isNotEmpty) {
              blocks.add({'type': 'text', 'text': message.text});
            }
            for (final call in message.toolCalls) {
              Object input = const <String, dynamic>{};
              try {
                input = jsonDecode(call.argumentsJson);
              } catch (_) {
                input = const <String, dynamic>{};
              }
              blocks.add({
                'type': 'tool_use',
                'id': call.id,
                'name': call.name,
                'input': input,
              });
            }
          }
          append('assistant', blocks);
          break;
        case ChatRole.tool:
          append('user', [
            {
              'type': 'tool_result',
              'tool_use_id': message.toolCallId ?? '',
              'content': [
                {'type': 'text', 'text': message.text},
              ],
              'is_error': message.toolIsError,
            },
          ]);
          break;
        case ChatRole.system:
          append('user', [
            {'type': 'text', 'text': message.text},
          ]);
          break;
      }
    }
    return messages;
  }

  Future<http.StreamedResponse> _send(
    http.Client client,
    Uri url,
    LlmRequest request,
    Map<String, dynamic> body,
  ) async {
    final httpRequest = http.Request('POST', url);
    httpRequest.headers.addAll({
      'content-type': 'application/json',
      'accept': 'text/event-stream, application/json',
      'anthropic-version': _apiVersion,
      'User-Agent': 'Lumen/1.0',
      ...request.provider.customHeaders,
    });
    if (request.apiKey.isNotEmpty &&
        !httpRequest.headers.keys.any((k) => k.toLowerCase() == 'x-api-key')) {
      httpRequest.headers['x-api-key'] = request.apiKey;
    }
    httpRequest.body = jsonEncode(body);
    return client.send(httpRequest).timeout(const Duration(seconds: 90));
  }

  Stream<LlmEvent> _parseSse(LlmRequest request, Stream<List<int>> bytes) async* {
    final blocks = <int, _AnthropicBlock>{};
    var inputTokens = 0;
    var outputTokens = 0;
    var stopReason = '';

    await for (final event in parseSse(bytes)) {
      final data = event.data.trim();
      if (data.isEmpty) continue;
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) json = decoded.map((k, v) => MapEntry('$k', v));
      } catch (_) {
        continue;
      }
      if (json == null) continue;
      final type = '${json['type'] ?? event.event ?? ''}';
      if (type == 'error') {
        final error = json['error'];
        final message = error is Map ? '${error['message'] ?? error['type'] ?? 'API 错误'}' : '$error';
        yield StreamFailure(message);
        return;
      }
      if (type == 'message_start') {
        final message = json['message'];
        if (message is Map) {
          final usage = message['usage'];
          if (usage is Map) inputTokens = _int(usage['input_tokens']) ?? inputTokens;
        }
      } else if (type == 'content_block_start') {
        final index = _int(json['index']) ?? blocks.length;
        final block = json['content_block'];
        if (block is Map) {
          final blockMap = block.map((k, v) => MapEntry('$k', v));
          final blockType = '${blockMap['type'] ?? 'text'}';
          final acc = _AnthropicBlock(index: index, type: blockType);
          if (blockType == 'text') {
            acc.text.write('${blockMap['text'] ?? ''}');
            if (acc.text.isNotEmpty) yield TextDelta(acc.text.toString());
          } else if (blockType == 'thinking') {
            acc.thinking.write('${blockMap['thinking'] ?? ''}');
            acc.signature.write('${blockMap['signature'] ?? ''}');
            if (acc.thinking.isNotEmpty) yield ReasoningDelta(acc.thinking.toString());
          } else if (blockType == 'redacted_thinking') {
            acc.redacted = '${blockMap['data'] ?? ''}';
          } else if (blockType == 'tool_use') {
            acc.toolId = '${blockMap['id'] ?? newId('call')}';
            acc.toolName = '${blockMap['name'] ?? ''}';
            if (acc.toolName.isNotEmpty) {
              yield ToolCallStarted(id: acc.toolId, name: acc.toolName);
            }
            final input = blockMap['input'];
            if (input is Map && input.isNotEmpty || input is List && input.isNotEmpty) {
              acc.args.write(jsonEncode(input));
              acc.hasInitialInput = true;
            }
          }
          blocks[index] = acc;
        }
      } else if (type == 'content_block_delta') {
        final index = _int(json['index']) ?? 0;
        final delta = json['delta'];
        if (delta is Map) {
          final deltaMap = delta.map((k, v) => MapEntry('$k', v));
          final deltaType = '${deltaMap['type'] ?? ''}';
          final acc = blocks.putIfAbsent(index, () => _AnthropicBlock(index: index, type: 'text'));
          if (deltaType == 'text_delta') {
            final text = '${deltaMap['text'] ?? ''}';
            if (text.isNotEmpty) {
              acc.text.write(text);
              yield TextDelta(text);
            }
          } else if (deltaType == 'thinking_delta') {
            final text = '${deltaMap['thinking'] ?? ''}';
            if (text.isNotEmpty) {
              acc.thinking.write(text);
              yield ReasoningDelta(text);
            }
          } else if (deltaType == 'signature_delta') {
            acc.signature.write('${deltaMap['signature'] ?? ''}');
          } else if (deltaType == 'input_json_delta') {
            final partial = '${deltaMap['partial_json'] ?? ''}';
            if (partial.isNotEmpty) {
              if (acc.hasInitialInput) {
                acc.args.clear();
                acc.hasInitialInput = false;
              }
              acc.args.write(partial);
              if (acc.toolName.isNotEmpty) {
                yield ToolCallArgumentsDelta(id: acc.toolId, delta: partial);
              }
            }
          }
        }
      } else if (type == 'content_block_stop') {
        final index = _int(json['index']) ?? 0;
        final acc = blocks[index];
        if (acc != null && acc.type == 'tool_use' && acc.toolName.isNotEmpty) {
          final args = acc.args.isEmpty ? '{}' : acc.args.toString();
          yield ToolCallCompleted(
            LlmToolCall(id: acc.toolId, name: acc.toolName, argumentsJson: args),
          );
        }
      } else if (type == 'message_delta') {
        final delta = json['delta'];
        if (delta is Map && delta['stop_reason'] != null) {
          stopReason = '${delta['stop_reason']}';
        }
        final usage = json['usage'];
        if (usage is Map) outputTokens = _int(usage['output_tokens']) ?? outputTokens;
      } else if (type == 'message_stop') {
        yield UsageReported(inputTokens: inputTokens, outputTokens: outputTokens);
        yield TurnCompleted(
          finishReason: stopReason.isEmpty ? 'stop' : stopReason,
          rawAssistantContent: _rawBlocks(blocks),
        );
        return;
      }
    }
    yield UsageReported(inputTokens: inputTokens, outputTokens: outputTokens);
    yield TurnCompleted(
      finishReason: stopReason.isEmpty ? 'stop' : stopReason,
      rawAssistantContent: _rawBlocks(blocks),
    );
  }

  Stream<LlmEvent> _parseFull(String text) async* {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        yield TextDelta(text);
        yield const TurnCompleted();
        return;
      }
      final json = decoded.map((k, v) => MapEntry('$k', v));
      if (json['error'] is Map) {
        final error = json['error'] as Map;
        yield StreamFailure('${error['message'] ?? error['type'] ?? 'API 错误'}');
        return;
      }
      final content = json['content'];
      final blocks = <int, _AnthropicBlock>{};
      final calls = <LlmToolCall>[];
      if (content is List) {
        for (var i = 0; i < content.length; i++) {
          final raw = content[i];
          if (raw is! Map) continue;
          final block = raw.map((k, v) => MapEntry('$k', v));
          final type = '${block['type'] ?? ''}';
          final acc = _AnthropicBlock(index: i, type: type);
          if (type == 'text') {
            final value = '${block['text'] ?? ''}';
            if (value.isNotEmpty) yield TextDelta(value);
            acc.text.write(value);
          } else if (type == 'thinking') {
            final value = '${block['thinking'] ?? ''}';
            if (value.isNotEmpty) yield ReasoningDelta(value);
            acc.thinking.write(value);
            acc.signature.write('${block['signature'] ?? ''}');
          } else if (type == 'redacted_thinking') {
            acc.redacted = '${block['data'] ?? ''}';
          } else if (type == 'tool_use') {
            acc.toolId = '${block['id'] ?? newId('call')}';
            acc.toolName = '${block['name'] ?? ''}';
            final args = jsonEncode(block['input'] ?? const {});
            acc.args.write(args);
            final call = LlmToolCall(id: acc.toolId, name: acc.toolName, argumentsJson: args);
            calls.add(call);
            yield ToolCallStarted(id: call.id, name: call.name);
            yield ToolCallArgumentsDelta(id: call.id, delta: args);
            yield ToolCallCompleted(call);
          }
          blocks[i] = acc;
        }
      }
      final usage = json['usage'];
      if (usage is Map) {
        yield UsageReported(
          inputTokens: _int(usage['input_tokens']) ?? 0,
          outputTokens: _int(usage['output_tokens']) ?? 0,
        );
      }
      yield TurnCompleted(
        finishReason: '${json['stop_reason'] ?? (calls.isEmpty ? 'stop' : 'tool_use')}',
        rawAssistantContent: _rawBlocks(blocks),
      );
    } catch (error) {
      yield StreamFailure('解析响应失败：$error');
    }
  }

  List<Map<String, dynamic>>? _rawBlocks(Map<int, _AnthropicBlock> blocks) {
    if (blocks.isEmpty) return null;
    final indexes = blocks.keys.toList()..sort();
    final result = <Map<String, dynamic>>[];
    for (final index in indexes) {
      final block = blocks[index]!;
      switch (block.type) {
        case 'text':
          result.add({'type': 'text', 'text': block.text.toString()});
          break;
        case 'thinking':
          result.add({
            'type': 'thinking',
            'thinking': block.thinking.toString(),
            'signature': block.signature.toString(),
          });
          break;
        case 'redacted_thinking':
          if (block.redacted.isNotEmpty) {
            result.add({'type': 'redacted_thinking', 'data': block.redacted});
          }
          break;
        case 'tool_use':
          Object input = const <String, dynamic>{};
          try {
            input = jsonDecode(block.args.isEmpty ? '{}' : block.args.toString());
          } catch (_) {
            input = const <String, dynamic>{};
          }
          result.add({
            'type': 'tool_use',
            'id': block.toolId,
            'name': block.toolName,
            'input': input,
          });
          break;
        default:
          break;
      }
    }
    return result.isEmpty ? null : result;
  }
}

class _AnthropicBlock {
  _AnthropicBlock({required this.index, required this.type});

  final int index;
  final String type;
  final StringBuffer text = StringBuffer();
  final StringBuffer thinking = StringBuffer();
  final StringBuffer signature = StringBuffer();
  final StringBuffer args = StringBuffer();
  String redacted = '';
  String toolId = '';
  String toolName = '';
  bool hasInitialInput = false;
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _errorMessage(String? body, int? statusCode) {
  if (body == null || body.trim().isEmpty) {
    return '请求失败${statusCode == null ? '' : '（HTTP $statusCode）'}';
  }
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] != null) return '${error['message']}';
      if (decoded['message'] != null) return '${decoded['message']}';
    }
  } catch (_) {
    // Fall through.
  }
  final concise = body.length > 600 ? '${body.substring(0, 600)}…' : body;
  return '请求失败${statusCode == null ? '' : '（HTTP $statusCode）'}：$concise';
}
