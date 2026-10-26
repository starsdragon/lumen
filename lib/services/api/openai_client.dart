import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/models.dart';
import 'llm_types.dart';
import 'reasoning_params.dart';
import 'sse.dart';

class OpenAiClient implements LlmClient {
  @override
  Stream<LlmEvent> stream(LlmRequest request) async* {
    final client = http.Client();
    try {
      final url = Uri.parse(chatCompletionsUrl(request.provider.baseUrl));
      if (url.host.isEmpty) {
        throw const LlmException('Base URL 为空或格式不正确。');
      }
      var body = _buildBody(request);
      http.StreamedResponse? response;
      String? errorBody;

      for (var attempt = 0; attempt < 4; attempt++) {
        response = await _send(client, url, request, body);
        if (response.statusCode >= 200 && response.statusCode < 300) break;
        errorBody = await response.stream.bytesToString();
        final lower = errorBody.toLowerCase();
        Map<String, dynamic>? retry;
        if (body.containsKey('stream_options') && lower.contains('stream_options')) {
          retry = Map<String, dynamic>.from(body)..remove('stream_options');
        } else if ((lower.contains('thinking') ||
                lower.contains('reasoning') ||
                lower.contains('effort') ||
                lower.contains('output_config')) &&
            reasoningParameterKeys.any(body.containsKey)) {
          retry = stripReasoningParams(body);
        } else if (lower.contains('max_completion_tokens') && body.containsKey('max_tokens')) {
          retry = Map<String, dynamic>.from(body)
            ..remove('max_tokens')
            ..['max_completion_tokens'] = body['max_tokens'];
        } else if (lower.contains('max_tokens') && body.containsKey('max_tokens')) {
          final current = (body['max_tokens'] as num?)?.toInt() ?? 0;
          retry = Map<String, dynamic>.from(body);
          if (current > 8192) {
            retry['max_tokens'] = 8192;
          } else {
            retry.remove('max_tokens');
          }
        } else if (lower.contains('temperature') && body.containsKey('temperature')) {
          retry = Map<String, dynamic>.from(body)..remove('temperature');
        } else if ((lower.contains('tool') || lower.contains('function')) &&
            body.containsKey('tools')) {
          retry = Map<String, dynamic>.from(body)
            ..remove('tools')
            ..remove('tool_choice');
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
        yield* _parseText(request, text);
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
    body['messages'] = _buildMessages(request);
    body['stream'] = true;
    if (request.maxTokens > 0 &&
        !body.containsKey('max_tokens') &&
        !body.containsKey('max_completion_tokens')) {
      // Without this, OpenAI-compatible relays often fall back to a small
      // provider default and long answers are cut off mid-sentence.
      body['max_tokens'] = request.maxTokens;
    }
    if (request.tools.isNotEmpty && request.model.tools) {
      body['tools'] = request.tools
          .map(
            (tool) => {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.inputSchema,
              },
            },
          )
          .toList();
      body['tool_choice'] = 'auto';
    }
    body.addAll(openAiReasoningParams(request.provider, request.model, request.reasoningLevel));
    final reasoningOn = request.model.reasoning && request.reasoningLevel.isEnabled;
    if (!reasoningOn) {
      body['temperature'] = request.temperature;
    }
    return body;
  }

  List<Map<String, dynamic>> _buildMessages(LlmRequest request) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': request.systemPrompt},
    ];
    final style = effectiveReasoningStyle(request.provider);
    for (final message in request.messages) {
      switch (message.role) {
        case ChatRole.user:
          // Do not hard-block on the inferred vision flag. Capability metadata
          // can lag behind new models; the provider is the source of truth.
          if (message.images.isNotEmpty) {
            final content = <Map<String, dynamic>>[];
            if (message.text.trim().isNotEmpty) {
              content.add({'type': 'text', 'text': message.text});
            }
            for (final image in message.images) {
              content.add({
                'type': 'image_url',
                'image_url': {'url': image.dataUrl, 'detail': 'auto'},
              });
            }
            messages.add({'role': 'user', 'content': content});
          } else {
            messages.add({'role': 'user', 'content': message.text});
          }
          break;
        case ChatRole.assistant:
          final item = <String, dynamic>{'role': 'assistant'};
          item['content'] = message.text.isEmpty ? null : message.text;
          if (message.toolCalls.isNotEmpty) {
            item['tool_calls'] = message.toolCalls
                .map(
                  (call) => {
                    'id': call.id,
                    'type': 'function',
                    'function': {'name': call.name, 'arguments': call.argumentsJson},
                  },
                )
                .toList();
          }
          if (request.includeReasoningHistory &&
              message.reasoning.isNotEmpty &&
              (style == ReasoningStyle.deepseek || style == ReasoningStyle.moonshot)) {
            item['reasoning_content'] = message.reasoning;
          }
          messages.add(item);
          break;
        case ChatRole.tool:
          messages.add({
            'role': 'tool',
            'tool_call_id': message.toolCallId ?? '',
            'content': message.text,
          });
          break;
        case ChatRole.system:
          messages.add({'role': 'system', 'content': message.text});
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
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream, application/json',
      'User-Agent': 'Lumen/1.0',
      ...request.provider.customHeaders,
    });
    if (request.apiKey.isNotEmpty &&
        !httpRequest.headers.keys.any((k) => k.toLowerCase() == 'authorization')) {
      httpRequest.headers['Authorization'] = 'Bearer ${request.apiKey}';
    }
    if (usesOpenCodeGo(request.provider) &&
        !httpRequest.headers.keys.any((k) => k.toLowerCase() == 'x-opencode-session')) {
      httpRequest.headers['x-opencode-session'] =
          request.sessionId.isEmpty ? newId('session') : request.sessionId;
    }
    httpRequest.body = jsonEncode(body);
    return client.send(httpRequest).timeout(const Duration(seconds: 90));
  }

  Stream<LlmEvent> _parseSse(LlmRequest request, Stream<List<int>> bytes) async* {
    final accumulators = <int, _OpenAiToolAccumulator>{};
    var finishReason = '';
    var usageInput = 0;
    var usageOutput = 0;

    await for (final event in parseSse(bytes)) {
      final data = event.data.trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) json = decoded.map((k, v) => MapEntry('$k', v));
      } catch (_) {
        continue;
      }
      if (json == null) continue;
      if (json['error'] is Map) {
        final error = json['error'] as Map;
        yield StreamFailure('${error['message'] ?? error['code'] ?? '模型返回错误'}');
        return;
      }
      final usage = json['usage'];
      if (usage is Map) {
        usageInput = _int(usage['prompt_tokens']) ?? usageInput;
        usageOutput = _int(usage['completion_tokens']) ?? usageOutput;
      }
      final choices = json['choices'];
      if (choices is! List) {
        if (usageInput > 0 || usageOutput > 0) {
          yield UsageReported(inputTokens: usageInput, outputTokens: usageOutput);
        }
        continue;
      }
      for (final rawChoice in choices) {
        if (rawChoice is! Map) continue;
        final choice = rawChoice.map((k, v) => MapEntry('$k', v));
        final finish = choice['finish_reason'];
        if (finish is String && finish.isNotEmpty) finishReason = finish;
        final delta = choice['delta'] is Map
            ? (choice['delta'] as Map).map((k, v) => MapEntry('$k', v))
            : choice['message'] is Map
                ? (choice['message'] as Map).map((k, v) => MapEntry('$k', v))
                : null;
        if (delta == null) continue;

        final reasoning = _firstString([
          delta['reasoning_content'],
          delta['reasoning'],
          delta['thinking'],
        ]);
        if (reasoning != null && reasoning.isNotEmpty) {
          yield ReasoningDelta(reasoning);
        }
        final content = _extractContent(delta['content']);
        if (content.isNotEmpty) {
          yield TextDelta(content);
        }

        final toolCalls = delta['tool_calls'];
        if (toolCalls is List) {
          for (var i = 0; i < toolCalls.length; i++) {
            final raw = toolCalls[i];
            if (raw is! Map) continue;
            final tool = raw.map((k, v) => MapEntry('$k', v));
            final index = _int(tool['index']) ?? i;
            final acc = accumulators.putIfAbsent(index, () => _OpenAiToolAccumulator(index));
            final id = tool['id']?.toString();
            if (id != null && id.isNotEmpty && !acc.started) acc.id = id;
            final fn = tool['function'] is Map
                ? (tool['function'] as Map).map((k, v) => MapEntry('$k', v))
                : const <String, dynamic>{};
            final name = fn['name']?.toString();
            if (name != null && name.isNotEmpty) acc.name = name;
            if (!acc.started && acc.name.isNotEmpty) {
              acc.started = true;
              yield ToolCallStarted(id: acc.id, name: acc.name);
            }
            final args = fn['arguments'];
            final argsText = args is String
                ? args
                : args is Map || args is List
                    ? jsonEncode(args)
                    : '';
            if (argsText.isNotEmpty) {
              acc.arguments.write(argsText);
              if (acc.started) {
                yield ToolCallArgumentsDelta(id: acc.id, delta: argsText);
              }
            }
          }
        }
      }
      if (usageInput > 0 || usageOutput > 0) {
        yield UsageReported(inputTokens: usageInput, outputTokens: usageOutput);
      }
    }

    for (final acc in accumulators.values) {
      if (!acc.started && acc.name.isNotEmpty) {
        yield ToolCallStarted(id: acc.id, name: acc.name);
      }
      final call = LlmToolCall(
        id: acc.id,
        name: acc.name,
        argumentsJson: acc.arguments.isEmpty ? '{}' : acc.arguments.toString(),
      );
      yield ToolCallCompleted(call);
    }
    yield TurnCompleted(
      finishReason: finishReason.isEmpty
          ? (accumulators.isNotEmpty ? 'tool_calls' : 'stop')
          : finishReason,
    );
  }

  Stream<LlmEvent> _parseText(LlmRequest request, String text) async* {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final json = decoded.map((k, v) => MapEntry('$k', v));
          if (json['error'] is Map) {
            final error = json['error'] as Map;
            yield StreamFailure('${error['message'] ?? error['code'] ?? '模型返回错误'}');
            return;
          }
          final choices = json['choices'];
          if (choices is List && choices.isNotEmpty) {
            final choice = choices.first is Map
                ? (choices.first as Map).map((k, v) => MapEntry('$k', v))
                : const <String, dynamic>{};
            final message = choice['message'] is Map
                ? (choice['message'] as Map).map((k, v) => MapEntry('$k', v))
                : choice;
            final reasoning = _firstString([message['reasoning_content'], message['reasoning']]);
            if (reasoning != null && reasoning.isNotEmpty) {
              yield* _chunkedText(reasoning, reasoning: true);
            }
            final content = _extractContent(message['content']);
            if (content.isNotEmpty) yield* _chunkedText(content);
            final calls = <LlmToolCall>[];
            final toolCalls = message['tool_calls'];
            if (toolCalls is List) {
              for (final raw in toolCalls) {
                if (raw is! Map) continue;
                final tool = raw.map((k, v) => MapEntry('$k', v));
                final fn = tool['function'] is Map
                    ? (tool['function'] as Map).map((k, v) => MapEntry('$k', v))
                    : const <String, dynamic>{};
                final call = LlmToolCall(
                  id: '${tool['id'] ?? newId('call')}',
                  name: '${fn['name'] ?? ''}',
                  argumentsJson: fn['arguments'] is String
                      ? '${fn['arguments']}'
                      : jsonEncode(fn['arguments'] ?? const {}),
                );
                calls.add(call);
                yield ToolCallStarted(id: call.id, name: call.name);
                yield ToolCallArgumentsDelta(id: call.id, delta: call.argumentsJson);
                yield ToolCallCompleted(call);
              }
            }
            final usage = json['usage'];
            if (usage is Map) {
              yield UsageReported(
                inputTokens: _int(usage['prompt_tokens']) ?? 0,
                outputTokens: _int(usage['completion_tokens']) ?? 0,
              );
            }
            yield TurnCompleted(
              finishReason: '${choice['finish_reason'] ?? (calls.isEmpty ? 'stop' : 'tool_calls')}',
            );
            return;
          }
        }
      } catch (_) {
        // Fall through and treat it as plain text.
      }
    }
    // Some gateways stream SSE without the event-stream content type.
    if (trimmed.contains('data:')) {
      final stream = Stream<List<int>>.fromIterable(utf8.encode(text).map((b) => [b]));
      yield* _parseSse(request, stream);
      return;
    }
    yield* _chunkedText(text);
    yield const TurnCompleted(finishReason: 'stop');
  }

  /// Some OpenAI-compatible relays ignore `stream:true` and return one JSON
  /// body. Reveal it progressively so the UI still feels alive.
  Stream<LlmEvent> _chunkedText(String text, {bool reasoning = false}) async* {
    if (text.isEmpty) return;
    const chunkSize = 32;
    if (text.length <= chunkSize) {
      yield reasoning ? ReasoningDelta(text) : TextDelta(text);
      return;
    }
    for (var index = 0; index < text.length; index += chunkSize) {
      final end = (index + chunkSize).clamp(0, text.length);
      final chunk = text.substring(index, end);
      yield reasoning ? ReasoningDelta(chunk) : TextDelta(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }
}

class _OpenAiToolAccumulator {
  _OpenAiToolAccumulator(this.index) : id = newId('call');

  final int index;
  String id;
  String name = '';
  final StringBuffer arguments = StringBuffer();
  bool started = false;
}

String? _firstString(List<Object?> values) {
  for (final value in values) {
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

String _extractContent(Object? value) {
  if (value is String) return value;
  if (value is List) {
    final buffer = StringBuffer();
    for (final part in value) {
      if (part is String) {
        buffer.write(part);
      } else if (part is Map) {
        final type = part['type']?.toString() ?? '';
        if (type == 'text' || type == 'output_text' || type.isEmpty) {
          final text = part['text'] ?? part['content'];
          if (text is String) buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }
  return '';
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
    // Keep the raw body below.
  }
  final concise = body.length > 600 ? '${body.substring(0, 600)}…' : body;
  return '请求失败${statusCode == null ? '' : '（HTTP $statusCode）'}：$concise';
}
