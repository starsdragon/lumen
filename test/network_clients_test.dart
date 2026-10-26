import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/api/anthropic_client.dart';
import 'package:lumen/services/api/gemini_client.dart';
import 'package:lumen/services/api/image_generation.dart';
import 'package:lumen/services/api/llm_types.dart';
import 'package:lumen/services/api/openai_client.dart';
import 'package:lumen/services/mcp_client.dart';

Future<HttpServer> startServer(Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    handler(request).catchError((Object error, StackTrace stack) async {
      request.response.statusCode = 500;
      request.response.write('$error\n$stack');
      await request.response.close();
    });
  });
  return server;
}

String serverBase(HttpServer server) => 'http://127.0.0.1:${server.port}';

Future<Map<String, dynamic>> readJson(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  final decoded = jsonDecode(body);
  return (decoded as Map).map((key, value) => MapEntry('$key', value));
}

void sse(HttpResponse response, Map<String, dynamic> data, {String? event}) {
  if (event != null) response.write('event: $event\n');
  response.write('data: ${jsonEncode(data)}\n\n');
}

void main() {
  test('OpenAI-compatible streams reasoning, text and tool calls with DeepSeek effort', () async {
    final requests = <HttpRequest>[];
    final bodies = <Map<String, dynamic>>[];
    final server = await startServer((request) async {
      requests.add(request);
      final body = await readJson(request);
      bodies.add(body);
      request.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      sse(request.response, {
        'choices': [
          {
            'delta': {'reasoning_content': '我先想一想。'}
          }
        ]
      });
      sse(request.response, {
        'choices': [
          {
            'delta': {'content': '这是答案。'}
          }
        ]
      });
      sse(request.response, {
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_1',
                  'function': {'name': 'web_search', 'arguments': '{"query":'}
                }
              ]
            }
          }
        ]
      });
      sse(request.response, {
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '"AI"}'}
                }
              ]
            },
            'finish_reason': 'tool_calls',
          }
        ],
        'usage': {'prompt_tokens': 11, 'completion_tokens': 6},
      });
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 'mock-openai',
        name: 'Mock',
        protocol: LlmProtocol.openai,
        baseUrl: '${serverBase(server)}/v1',
        reasoningStyle: ReasoningStyle.deepseek,
      );
      const model = ModelInfo(
        id: 'deepseek-v4-pro',
        name: 'DeepSeek V4 Pro',
        reasoning: true,
        vision: true,
        tools: true,
      );
      const tool = ToolDefinition(
        name: 'web_search',
        description: 'search',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'}
          },
          'required': ['query'],
        },
      );
      final events = await OpenAiClient()
          .stream(
            LlmRequest(
              provider: provider,
              apiKey: 'test-key',
              model: model,
              systemPrompt: 'You are a test.',
              messages: [LlmMessage.user('你好')],
              tools: const [tool],
              reasoningLevel: ReasoningLevel.high,
            ),
          )
          .toList();

      final reasoning = events.whereType<ReasoningDelta>().map((e) => e.text).join();
      final text = events.whereType<TextDelta>().map((e) => e.text).join();
      final calls = events.whereType<ToolCallCompleted>().toList();
      final done = events.whereType<TurnCompleted>().single;
      expect(reasoning, contains('想一想'));
      expect(text, contains('这是答案'));
      expect(calls, hasLength(1));
      expect(calls.first.call.name, 'web_search');
      expect(jsonDecode(calls.first.call.argumentsJson), {'query': 'AI'});
      expect(done.finishReason, 'tool_calls');
      expect(requests.single.headers.value('authorization'), 'Bearer test-key');
      expect(bodies.single['thinking'], {'type': 'enabled'});
      expect(bodies.single['reasoning_effort'], 'high');
      expect((bodies.single['tools'] as List), hasLength(1));
      expect(bodies.single['max_tokens'], 16384);
    } finally {
      await server.close(force: true);
    }
  });

  test('switches max_tokens to max_completion_tokens when a provider requires it', () async {
    final bodies = <Map<String, dynamic>>[];
    var attempt = 0;
    final server = await startServer((request) async {
      bodies.add(await readJson(request));
      if (attempt++ == 0) {
        request.response.statusCode = 400;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'error': {
              'message': "Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead.",
            }
          }),
        );
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'OK'},
                'finish_reason': 'stop',
              }
            ]
          }),
        );
      }
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 'custom',
        name: 'Custom',
        protocol: LlmProtocol.openai,
        baseUrl: '${serverBase(server)}/v1',
      );
      const model = ModelInfo(id: 'reasoning-model', name: 'Reasoning', reasoning: false);
      final events = await OpenAiClient()
          .stream(
            LlmRequest(
              provider: provider,
              apiKey: 'key',
              model: model,
              systemPrompt: 'system',
              messages: [LlmMessage.user('hello')],
            ),
          )
          .toList();

      expect(events.whereType<TextDelta>().map((e) => e.text).join(), 'OK');
      expect(bodies, hasLength(2));
      expect(bodies.first['max_tokens'], 16384);
      expect(bodies.last.containsKey('max_tokens'), isFalse);
      expect(bodies.last['max_completion_tokens'], 16384);
    } finally {
      await server.close(force: true);
    }
  });

  test('sends images even when the inferred vision flag is stale', () async {
    Map<String, dynamic>? requestBody;
    final server = await startServer((request) async {
      requestBody = await readJson(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'seen'},
              'finish_reason': 'stop',
            }
          ]
        }),
      );
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 'custom',
        name: 'Custom',
        protocol: LlmProtocol.openai,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      );
      const model = ModelInfo(
        id: 'new-multimodal-model',
        name: 'New Multimodal',
        vision: false,
        reasoning: false,
      );
      await OpenAiClient()
          .stream(
            LlmRequest(
              provider: provider,
              apiKey: 'key',
              model: model,
              systemPrompt: 'system',
              messages: [
                LlmMessage.user(
                  '这张图是什么？',
                  images: const [
                    Attachment(
                      id: 'att-1',
                      name: 'photo.png',
                      mime: 'image/png',
                      dataUrl: 'data:image/png;base64,iVBORw0KGgo=',
                    )
                  ],
                ),
              ],
            ),
          )
          .toList();
      final messages = requestBody!['messages'] as List;
      final user = messages.last as Map;
      final content = user['content'];
      expect(content, isA<List>());
      expect(jsonEncode(content), contains('image_url'));
    } finally {
      await server.close(force: true);
    }
  });

  test('OpenCode Go adds stable session and agent user agent headers', () async {
    HttpHeaders? captured;
    final server = await startServer((request) async {
      captured = request.headers;
      expect(request.uri.path, '/zen/go/v1/chat/completions');
      final body = await readJson(request);
      expect(body['model'], 'glm-5.3-flash');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'OK'},
              'finish_reason': 'stop',
            }
          ]
        }),
      );
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 'opencode',
        name: 'OpenCode Go',
        protocol: LlmProtocol.openai,
        baseUrl: 'http://127.0.0.1:${server.port}/zen/go/v1',
      );
      const model = ModelInfo(id: 'glm-5.3-flash', name: 'GLM-5.3 Flash');
      final events = await OpenAiClient()
          .stream(
            LlmRequest(
              provider: provider,
              apiKey: 'go-key',
              model: model,
              systemPrompt: 'system',
              messages: [LlmMessage.user('hello')],
              sessionId: 'conv-42',
            ),
          )
          .toList();
      expect(events.whereType<TextDelta>().map((e) => e.text).join(), 'OK');
      expect(captured?.value('x-opencode-session'), 'conv-42');
      expect(captured?.value('user-agent'), 'Lumen/1.0');
      expect(captured?.value('authorization'), 'Bearer go-key');
    } finally {
      await server.close(force: true);
    }
  });

  test('Anthropic streams adaptive thinking with signature and tool input', () async {
    Map<String, dynamic>? requestBody;
    final server = await startServer((request) async {
      requestBody = await readJson(request);
      request.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      sse(request.response, {
        'type': 'message_start',
        'message': {
          'usage': {'input_tokens': 12}
        }
      });
      sse(request.response, {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'thinking', 'thinking': ''}
      });
      sse(request.response, {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'thinking_delta', 'thinking': '先分析。'}
      });
      sse(request.response, {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'signature_delta', 'signature': 'sig-123'}
      });
      sse(request.response, {
        'type': 'content_block_stop',
        'index': 0
      });
      sse(request.response, {
        'type': 'content_block_start',
        'index': 1,
        'content_block': {'type': 'text', 'text': ''}
      });
      sse(request.response, {
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'text_delta', 'text': '最终答案。'}
      });
      sse(request.response, {
        'type': 'content_block_stop',
        'index': 1
      });
      sse(request.response, {
        'type': 'content_block_start',
        'index': 2,
        'content_block': {'type': 'tool_use', 'id': 'toolu_1', 'name': 'web_search', 'input': {}}
      });
      sse(request.response, {
        'type': 'content_block_delta',
        'index': 2,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"query":"AI"}'}
      });
      sse(request.response, {
        'type': 'content_block_stop',
        'index': 2
      });
      sse(request.response, {
        'type': 'message_delta',
        'delta': {'stop_reason': 'tool_use'},
        'usage': {'output_tokens': 20}
      });
      sse(request.response, {'type': 'message_stop'});
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 'mock-anthropic',
        name: 'Mock Claude',
        protocol: LlmProtocol.anthropic,
        baseUrl: serverBase(server),
      );
      const model = ModelInfo(
        id: 'claude-opus-5-5',
        name: 'Claude Opus 5.5',
        reasoning: true,
        vision: true,
        tools: true,
      );
      final events = await AnthropicClient()
          .stream(
            LlmRequest(
              provider: provider,
              apiKey: 'sk-ant',
              model: model,
              systemPrompt: 'system',
              messages: [LlmMessage.user('你好')],
              tools: const [
                ToolDefinition(
                  name: 'web_search',
                  description: 'search',
                  inputSchema: {'type': 'object', 'properties': {}},
                )
              ],
              reasoningLevel: ReasoningLevel.high,
            ),
          )
          .toList();
      expect(events.whereType<ReasoningDelta>().map((e) => e.text).join(), contains('先分析'));
      expect(events.whereType<TextDelta>().map((e) => e.text).join(), contains('最终答案'));
      expect(events.whereType<ToolCallCompleted>().single.call.argumentsJson, '{"query":"AI"}');
      final done = events.whereType<TurnCompleted>().single;
      expect(done.finishReason, 'tool_use');
      final raw = done.rawAssistantContent!;
      final thinking = raw.firstWhere((b) => b['type'] == 'thinking');
      expect(thinking['signature'], 'sig-123');
      expect(requestBody!['thinking'], {'type': 'adaptive', 'display': 'summarized'});
      expect((requestBody!['output_config'] as Map)['effort'], 'high');
      expect(requestBody!['system'], 'system');
    } finally {
      await server.close(force: true);
    }
  });

  test('Gemini streams thought parts, text and function calls', () async {
    Map<String, dynamic>? requestBody;
    String? path;
    final server = await startServer((request) async {
      path = request.uri.toString();
      requestBody = await readJson(request);
      request.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      sse(request.response, {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '先思考', 'thought': true}
              ]
            }
          }
        ],
        'usageMetadata': {'promptTokenCount': 8}
      });
      sse(request.response, {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Gemini 答案'}
              ]
            }
          }
        ]
      });
      sse(request.response, {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'name': 'web_search',
                    'args': {'query': 'AI'}
                  }
                }
              ]
            },
            'finishReason': 'STOP',
          }
        ],
        'usageMetadata': {'candidatesTokenCount': 5}
      });
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 'mock-gemini',
        name: 'Mock Gemini',
        protocol: LlmProtocol.gemini,
        baseUrl: serverBase(server),
      );
      const model = ModelInfo(
        id: 'gemini-3-pro-preview',
        name: 'Gemini 3 Pro',
        reasoning: true,
        vision: true,
        tools: true,
      );
      final events = await GeminiClient()
          .stream(
            LlmRequest(
              provider: provider,
              apiKey: 'google-key',
              model: model,
              systemPrompt: 'system',
              messages: [LlmMessage.user('你好')],
              tools: const [
                ToolDefinition(
                  name: 'web_search',
                  description: 'search',
                  inputSchema: {
                    'type': 'object',
                    'properties': {
                      'query': {'type': 'string'}
                    },
                    'additionalProperties': false,
                  },
                )
              ],
              reasoningLevel: ReasoningLevel.high,
            ),
          )
          .toList();
      expect(events.whereType<ReasoningDelta>().map((e) => e.text).join(), contains('先思考'));
      expect(events.whereType<TextDelta>().map((e) => e.text).join(), contains('Gemini 答案'));
      expect(events.whereType<ToolCallCompleted>().single.call.name, 'web_search');
      expect(path, contains('gemini-3-pro-preview:streamGenerateContent'));
      final config = requestBody!['generationConfig'] as Map;
      expect((config['thinkingConfig'] as Map)['thinkingLevel'], 'high');
      final declaration =
          ((requestBody!['tools'] as List).first as Map)['functionDeclarations'] as List;
      expect((declaration.first as Map).containsKey('parameters'), isTrue);
      expect(
        jsonEncode(declaration).contains('additionalProperties'),
        isFalse,
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('OpenAI image generation returns image bytes', () async {
    final pngBytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    Map<String, dynamic>? requestBody;
    final server = await startServer((request) async {
      requestBody = await readJson(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': [
            {'b64_json': base64Encode(pngBytes)}
          ]
        }),
      );
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 'mock-image',
        name: 'Mock Image',
        protocol: LlmProtocol.openai,
        baseUrl: '${serverBase(server)}/v1',
      );
      const model = ModelInfo(
        id: 'gpt-image-1',
        name: 'GPT Image',
        imageGeneration: true,
        reasoning: false,
        tools: false,
      );
      final result = await ImageGenerationService().generate(
        provider: provider,
        apiKey: 'img-key',
        model: model,
        prompt: 'a glass city at dusk',
        aspectRatio: '16:9',
      );
      expect(result.bytes, pngBytes);
      expect(requestBody!['prompt'], 'a glass city at dusk');
      expect(requestBody!['model'], 'gpt-image-1');
    } finally {
      await server.close(force: true);
    }
  });

  test('MCP Streamable HTTP handshake lists and calls tools', () async {
    final methods = <String>[];
    final server = await startServer((request) async {
      final body = await readJson(request);
      final method = '${body['method']}';
      methods.add(method);
      request.response.headers.contentType = ContentType.json;
      if (method == 'initialize') {
        request.response.headers.set('mcp-session-id', 'sess-1');
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'protocolVersion': '2025-03-26',
              'capabilities': {'tools': {}},
              'serverInfo': {'name': 'mock', 'version': '1'},
            },
          }),
        );
      } else if (method == 'notifications/initialized') {
        request.response.statusCode = 202;
      } else if (method == 'tools/list') {
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'tools': [
                {
                  'name': 'echo',
                  'description': 'Echo text',
                  'inputSchema': {
                    'type': 'object',
                    'properties': {
                      'text': {'type': 'string'}
                    },
                  },
                }
              ]
            },
          }),
        );
      } else if (method == 'tools/call') {
        final args = body['params'] as Map;
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'content': [
                {'type': 'text', 'text': 'echo: ${(args['arguments'] as Map)['text']}'}
              ],
              'isError': false,
            },
          }),
        );
      }
      await request.response.close();
    });
    try {
      final config = McpServerConfig(
        id: 'mock-mcp',
        name: 'Mock MCP',
        transport: McpTransport.streamableHttp,
        url: '${serverBase(server)}/mcp',
      );
      final service = McpService();
      final tools = await service.listTools(config);
      expect(tools.single.name, 'echo');
      final result = await service.callTool(config, 'echo', {'text': 'hi'});
      expect(result, contains('echo: hi'));
      expect(methods, contains('initialize'));
      expect(methods, contains('notifications/initialized'));
      expect(methods, contains('tools/list'));
      expect(methods, contains('tools/call'));
    } finally {
      await server.close(force: true);
    }
  });
}
