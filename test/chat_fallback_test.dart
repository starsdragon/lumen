import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/database.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/chat_session.dart';
import 'package:lumen/services/controllers.dart';
import 'package:sembast/sembast_memory.dart';

class _MemorySecrets extends SecretStore {
  @override
  Future<String?> read(String key) async => 'test-key';

  @override
  Future<void> write(String key, String value) async {}
}

Future<HttpServer> _startModelServer({
  required bool answerFallback,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    final messages = (body['messages'] as List).cast<Map>();
    final system = '${messages.first['content'] ?? ''}';
    final fallbackRequest =
        system.contains('现在必须直接输出正文回答') || system.contains('直接、认真地回答用户的问题');
    request.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    final content = fallbackRequest && answerFallback ? '这是兜底回答，不会让用户换模型。' : '';
    request.response.write(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': content},
            'finish_reason': 'stop',
          }
        ]
      })}\n\n',
    );
    request.response.write('data: [DONE]\n\n');
    await request.response.close();
  });
  return server;
}

Future<ChatSession> _makeSession(HttpServer server) async {
  final raw = await databaseFactoryMemory.openDatabase(
    'lumen-chat-fallback-${DateTime.now().microsecondsSinceEpoch}.db',
  );
  final repo = AppRepository(AppDatabase(raw), _MemorySecrets());
  final settings = SettingsController(repo);
  await settings.load();
  settings.settings.memoryEnabled = false;
  settings.settings.search = SearchConfig(provider: SearchProvider.none);

  final providers = ProvidersController(repo);
  providers.providers = [
    ProviderConfig(
      id: 'mock',
      name: 'Mock',
      protocol: LlmProtocol.openai,
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      hasKey: true,
      models: const [
        ModelInfo(id: 'mock-model', name: 'Mock Model', contextWindow: 131072, reasoning: false),
      ],
    ),
  ];
  providers.loading = false;

  final memories = MemoriesController(repo);
  final mcp = McpController(repo);
  final conversations = ConversationsController(repo);
  final conversation = Conversation(
    id: 'conv-fallback',
    title: 'fallback',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    providerId: 'mock',
    modelId: 'mock-model',
  );
  conversations.conversations = [conversation];

  return ChatSession(
    repo: repo,
    conversation: conversation,
    providers: providers,
    settings: settings,
    memories: memories,
    mcp: mcp,
    conversations: conversations,
  );
}

void main() {
  test('empty model answer triggers a clean fallback completion', () async {
    final server = await _startModelServer(answerFallback: true);
    try {
      final session = await _makeSession(server);
      await session.send('你好，回答我。');

      expect(session.messages.last.role, ChatRole.assistant);
      expect(session.messages.last.error, isNull);
      expect(session.messages.last.text, contains('这是兜底回答'));
      expect(session.messages.last.finishReason, 'stop');
    } finally {
      await server.close(force: true);
    }
  });

  test('empty model answer still yields local text instead of a dead-end error', () async {
    final server = await _startModelServer(answerFallback: false);
    try {
      final session = await _makeSession(server);
      await session.send('你好，回答我。');

      expect(session.messages.last.role, ChatRole.assistant);
      expect(session.messages.last.error, isNull);
      expect(session.messages.last.text.trim(), isNotEmpty);
      expect(session.messages.last.text, isNot(contains('换一个更擅长总结的模型')));
      expect(session.messages.last.finishReason, 'fallback');
    } finally {
      await server.close(force: true);
    }
  });
}
