import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/api/model_sync.dart';

Future<HttpServer> startJsonServer(Future<Object?> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final payload = await handler(request);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  });
  return server;
}

void main() {
  test('OpenAI-compatible model sync parses IDs and infers capabilities', () async {
    final server = await startJsonServer((request) async {
      expect(request.uri.path, '/v1/models');
      expect(request.headers.value('authorization'), 'Bearer key');
      return {
        'data': [
          {'id': 'qwen3-vl-plus'},
          {'id': 'qwen3-coder-plus'},
          {'id': 'wanx2.1-t2i-turbo'},
          {'id': 'text-embedding-v4'},
        ],
      };
    });
    try {
      final provider = ProviderConfig(
        id: 'mock',
        name: 'Mock',
        protocol: LlmProtocol.openai,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        models: const [
          ModelInfo(
            id: 'cogview-4',
            name: 'CogView-4',
            imageGeneration: true,
            reasoning: false,
            tools: false,
          )
        ],
      );
      final models = await ModelSyncService().fetchModels(provider, 'key');
      expect(models.map((m) => m.id), contains('qwen3-vl-plus'));
      expect(models.map((m) => m.id), contains('wanx2.1-t2i-turbo'));
      expect(models.map((m) => m.id), isNot(contains('text-embedding-v4')));
      expect(models.firstWhere((m) => m.id == 'qwen3-vl-plus').vision, isTrue);
      expect(models.firstWhere((m) => m.id == 'wanx2.1-t2i-turbo').imageGeneration, isTrue);
      expect(models.map((m) => m.id), contains('cogview-4'));
    } finally {
      await server.close(force: true);
    }
  });

  test('Anthropic and Gemini model list endpoints', () async {
    final anthropic = await startJsonServer((request) async {
      expect(request.uri.path, '/v1/models');
      expect(request.headers.value('x-api-key'), 'anth-key');
      return {
        'data': [
          {'id': 'claude-opus-5-5', 'display_name': 'Claude Opus 5.5'},
          {'id': 'claude-haiku-4-5', 'display_name': 'Claude Haiku 4.5'},
        ],
      };
    });
    final gemini = await startJsonServer((request) async {
      expect(request.uri.path, '/v1beta/models');
      expect(request.uri.queryParameters['pageSize'], '1000');
      expect(request.headers.value('x-goog-api-key'), 'google-key');
      return {
        'models': [
          {
            'name': 'models/gemini-3-pro-preview',
            'displayName': 'Gemini 3 Pro',
            'inputTokenLimit': 1000000,
            'supportedGenerationMethods': ['generateContent'],
          },
          {
            'name': 'models/gemini-2.5-flash-image',
            'displayName': 'Gemini Image',
            'inputTokenLimit': 32768,
            'supportedGenerationMethods': ['generateContent'],
          },
          {
            'name': 'models/text-embedding-004',
            'displayName': 'Embedding',
            'supportedGenerationMethods': ['embedContent'],
          },
        ],
      };
    });
    try {
      final anthropicProvider = ProviderConfig(
        id: 'a',
        name: 'Anthropic',
        protocol: LlmProtocol.anthropic,
        baseUrl: 'http://127.0.0.1:${anthropic.port}',
      );
      final anthropicModels = await ModelSyncService().fetchModels(anthropicProvider, 'anth-key');
      expect(anthropicModels.map((m) => m.id), contains('claude-opus-5-5'));
      expect(anthropicModels.first.vision, isTrue);
      expect(anthropicModels.first.reasoning, isTrue);

      final geminiProvider = ProviderConfig(
        id: 'g',
        name: 'Gemini',
        protocol: LlmProtocol.gemini,
        baseUrl: 'http://127.0.0.1:${gemini.port}',
      );
      final geminiModels = await ModelSyncService().fetchModels(geminiProvider, 'google-key');
      expect(geminiModels.map((m) => m.id), contains('gemini-3-pro-preview'));
      expect(geminiModels.map((m) => m.id), isNot(contains('text-embedding-004')));
      final image = geminiModels.firstWhere((m) => m.id == 'gemini-2.5-flash-image');
      expect(image.imageGeneration, isTrue);
      expect(image.contextWindow, 32768);
    } finally {
      await anthropic.close(force: true);
      await gemini.close(force: true);
    }
  });
}
