import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/models.dart';
import 'llm_types.dart';
import 'reasoning_params.dart';
import 'sse.dart';

class GeminiClient implements LlmClient {
  @override
  Stream<LlmEvent> stream(LlmRequest request) async* {
    final client = http.Client();
    try {
      final url = Uri.parse(geminiGenerateUrl(request.provider.baseUrl, request.model.id));
      var body = _buildBody(request);
      http.StreamedResponse? response;
      String? errorBody;

      for (var attempt = 0; attempt < 4; attempt++) {
        response = await _send(client, url, request, body);
        if (response.statusCode >= 200 && response.statusCode < 300) break;
        errorBody = await response.stream.bytesToString();
        final lower = errorBody.toLowerCase();
        Map<String, dynamic>? retry;
        if ((lower.contains('thinking') || lower.contains('thought')) &&
            (body['generationConfig'] is Map) &&
            (body['generationConfig'] as Map).containsKey('thinkingConfig')) {
          final config = Map<String, dynamic>.from(body['generationConfig'] as Map);
          config.remove('thinkingConfig');
          retry = Map<String, dynamic>.from(body)..['generationConfig'] = config;
        } else if ((lower.contains('tool') || lower.contains('function')) &&
            body.containsKey('tools')) {
          retry = Map<String, dynamic>.from(body)
            ..remove('tools')
            ..remove('toolConfig');
        } else if (lower.contains('temperature') &&
            body['generationConfig'] is Map &&
            (body['generationConfig'] as Map).containsKey('temperature')) {
          final config = Map<String, dynamic>.from(body['generationConfig'] as Map)
            ..remove('temperature');
          retry = Map<String, dynamic>.from(body)..['generationConfig'] = config;
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
        yield* _parseSse(response.stream.timeout(const Duration(seconds: 180)));
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
    body['systemInstruction'] = {
      'parts': [
        {'text': request.systemPrompt},
      ],
    };
    body['contents'] = _buildContents(request);

    final generationConfig = <String, dynamic>{
      'maxOutputTokens': request.maxTokens.clamp(1024, 65536),
    };
    final reasoningOn = request.model.reasoning && request.reasoningLevel.isEnabled;
    if (!reasoningOn) {
      generationConfig['temperature'] = request.temperature;
    }
    final thinkingConfig = geminiThinkingConfig(request.model, request.reasoningLevel);
    if (thinkingConfig != null) generationConfig['thinkingConfig'] = thinkingConfig;
    body['generationConfig'] = generationConfig;

    if (request.tools.isNotEmpty && request.model.tools) {
      body['tools'] = [
        {
          'functionDeclarations': request.tools
              .map(
                (tool) => {
                  'name': tool.name,
                  'description': tool.description,
                  'parameters': sanitizeSchemaForGemini(tool.inputSchema),
                },
              )
              .toList(),
        },
      ];
      body['toolConfig'] = {
        'functionCallingConfig': {'mode': 'AUTO'},
      };
    }
    return body;
  }

  List<Map<String, dynamic>> _buildContents(LlmRequest request) {
    final contents = <Map<String, dynamic>>[];

    void append(String role, List<Map<String, dynamic>> parts) {
      if (parts.isEmpty) return;
      if (contents.isNotEmpty && contents.last['role'] == role) {
        final existing = contents.last['parts'];
        if (existing is List) existing.addAll(parts);
      } else {
        contents.add({'role': role, 'parts': parts});
      }
    }

    for (final message in request.messages) {
      switch (message.role) {
        case ChatRole.user:
          final parts = <Map<String, dynamic>>[];
          if (message.text.trim().isNotEmpty) {
            parts.add({'text': message.text});
          }
          if (message.images.isNotEmpty) {
            for (final image in message.images) {
              parts.add({
                'inlineData': {
                  'mimeType': dataUrlMime(image.dataUrl, fallback: image.mime),
                  'data': stripDataUrlPrefix(image.dataUrl),
                },
              });
            }
          }
          append('user', parts);
          break;
        case ChatRole.assistant:
          if (message.rawContent != null && message.rawContent!.isNotEmpty) {
            append('model', message.rawContent!);
          } else {
            final parts = <Map<String, dynamic>>[];
            if (message.text.trim().isNotEmpty) parts.add({'text': message.text});
            for (final call in message.toolCalls) {
              Object args = const <String, dynamic>{};
              try {
                args = jsonDecode(call.argumentsJson);
              } catch (_) {
                args = const <String, dynamic>{};
              }
              parts.add({
                'functionCall': {'name': call.name, 'args': args},
              });
            }
            append('model', parts);
          }
          break;
        case ChatRole.tool:
          append('user', [
            {
              'functionResponse': {
                'name': message.toolName ?? '',
                'response': {'result': message.text},
              },
            },
          ]);
          break;
        case ChatRole.system:
          append('user', [
            {'text': message.text},
          ]);
          break;
      }
    }
    return contents;
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
      'User-Agent': 'Lumen/1.0',
      ...request.provider.customHeaders,
    });
    if (request.apiKey.isNotEmpty &&
        !httpRequest.headers.keys.any((k) => k.toLowerCase() == 'x-goog-api-key')) {
      httpRequest.headers['x-goog-api-key'] = request.apiKey;
    }
    httpRequest.body = jsonEncode(body);
    return client.send(httpRequest).timeout(const Duration(seconds: 90));
  }

  Stream<LlmEvent> _parseSse(Stream<List<int>> bytes) async* {
    var rawParts = <Map<String, dynamic>>[];
    var calls = <LlmToolCall>[];
    var inputTokens = 0;
    var outputTokens = 0;
    var finishReason = '';
    final seenCalls = <String>{};

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
      if (json['error'] is Map) {
        final error = json['error'] as Map;
        yield StreamFailure('${error['message'] ?? 'Gemini API 错误'}');
        return;
      }
      final feedback = json['promptFeedback'];
      if (feedback is Map && feedback['blockReason'] != null) {
        yield StreamFailure('请求被安全策略拦截：${feedback['blockReason']}');
        return;
      }
      final usage = json['usageMetadata'];
      if (usage is Map) {
        inputTokens = _int(usage['promptTokenCount']) ?? inputTokens;
        outputTokens = _int(usage['candidatesTokenCount']) ?? outputTokens;
        final thoughts = _int(usage['thoughtsTokenCount']);
        if (thoughts != null) outputTokens += thoughts;
      }
      final candidates = json['candidates'];
      if (candidates is! List) continue;
      for (final rawCandidate in candidates) {
        if (rawCandidate is! Map) continue;
        final candidate = rawCandidate.map((k, v) => MapEntry('$k', v));
        final finish = candidate['finishReason'];
        if (finish is String && finish.isNotEmpty) finishReason = finish;
        final content = candidate['content'];
        if (content is! Map) continue;
        final parts = content['parts'];
        if (parts is! List) continue;
        for (final rawPart in parts) {
          if (rawPart is! Map) continue;
          final part = rawPart.map((k, v) => MapEntry('$k', v));
          rawParts.add(part);
          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            if (part['thought'] == true) {
              yield ReasoningDelta(text);
            } else {
              yield TextDelta(text);
            }
          }
          final functionCall = part['functionCall'];
          if (functionCall is Map) {
            final call = functionCall.map((k, v) => MapEntry('$k', v));
            final name = '${call['name'] ?? ''}';
            final id = '${call['id'] ?? part['id'] ?? newId('call')}';
            final args = call['args'] is Map || call['args'] is List
                ? jsonEncode(call['args'])
                : '{}';
            final key = name.isEmpty ? id : '$name|$args';
            if (name.isNotEmpty && seenCalls.add(key)) {
              final result = LlmToolCall(id: id, name: name, argumentsJson: args);
              calls.add(result);
              yield ToolCallStarted(id: id, name: name);
              yield ToolCallArgumentsDelta(id: id, delta: args);
              yield ToolCallCompleted(result);
            }
          }
        }
      }
    }
    yield UsageReported(inputTokens: inputTokens, outputTokens: outputTokens);
    yield TurnCompleted(
      finishReason: finishReason.isEmpty ? (calls.isEmpty ? 'stop' : 'tool_calls') : finishReason,
      rawAssistantContent: rawParts.isEmpty ? null : rawParts,
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
        yield StreamFailure('${error['message'] ?? 'Gemini API 错误'}');
        return;
      }
      final candidates = json['candidates'];
      final rawParts = <Map<String, dynamic>>[];
      final calls = <LlmToolCall>[];
      var finishReason = '';
      if (candidates is List && candidates.isNotEmpty && candidates.first is Map) {
        final candidate = (candidates.first as Map).map((k, v) => MapEntry('$k', v));
        finishReason = '${candidate['finishReason'] ?? ''}';
        final content = candidate['content'];
        if (content is Map) {
          final parts = content['parts'];
          if (parts is List) {
            for (final rawPart in parts) {
              if (rawPart is! Map) continue;
              final part = rawPart.map((k, v) => MapEntry('$k', v));
              rawParts.add(part);
              final value = part['text'];
              if (value is String && value.isNotEmpty) {
                if (part['thought'] == true) {
                  yield ReasoningDelta(value);
                } else {
                  yield TextDelta(value);
                }
              }
              final functionCall = part['functionCall'];
              if (functionCall is Map) {
                final call = functionCall.map((k, v) => MapEntry('$k', v));
                final name = '${call['name'] ?? ''}';
                final id = '${call['id'] ?? part['id'] ?? newId('call')}';
                final args = call['args'] is Map || call['args'] is List
                    ? jsonEncode(call['args'])
                    : '{}';
                if (name.isNotEmpty) {
                  final result = LlmToolCall(id: id, name: name, argumentsJson: args);
                  calls.add(result);
                  yield ToolCallStarted(id: id, name: name);
                  yield ToolCallArgumentsDelta(id: id, delta: args);
                  yield ToolCallCompleted(result);
                }
              }
            }
          }
        }
      }
      final usage = json['usageMetadata'];
      if (usage is Map) {
        yield UsageReported(
          inputTokens: _int(usage['promptTokenCount']) ?? 0,
          outputTokens: (_int(usage['candidatesTokenCount']) ?? 0) +
              (_int(usage['thoughtsTokenCount']) ?? 0),
        );
      }
      yield TurnCompleted(
        finishReason: finishReason.isEmpty ? (calls.isEmpty ? 'stop' : 'tool_calls') : finishReason,
        rawAssistantContent: rawParts.isEmpty ? null : rawParts,
      );
    } catch (error) {
      yield StreamFailure('解析响应失败：$error');
    }
  }
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
