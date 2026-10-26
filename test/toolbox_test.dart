import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/mcp_client.dart';
import 'package:lumen/services/search_service.dart';
import 'package:lumen/services/toolbox.dart';

void main() {
  test('web_search returns readable sources without numbered citation instructions', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/search');
      expect(request.uri.queryParameters['q'], '人工耳蜗');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'results': [
            {
              'title': '人工耳蜗植入科普',
              'url': 'https://example.com/cochlear',
              'content': '人工耳蜗通过电刺激听神经帮助重度听损者重建听觉。',
              'publishedDate': '2026-10-01',
            },
            {
              'title': '儿童语前聋与康复',
              'url': 'https://example.com/children',
              'content': '儿童越早植入，通常越有利于听觉语言发育。',
            },
          ],
        }),
      );
      await request.response.close();
    });

    try {
      final toolbox = Toolbox(
        searchConfig: SearchConfig(
          provider: SearchProvider.searxng,
          searxBaseUrl: 'http://127.0.0.1:${server.port}',
          maxResults: 4,
        ),
        credentials: const SearchCredentials(),
        webSearchEnabled: true,
        memoryEnabled: false,
        searchService: SearchService(),
        mcpService: McpService(),
        mcpServers: const [],
        mcpTools: const {},
      );
      final outcome = await toolbox.execute(
        ToolCallRecord(
          id: 'call-1',
          name: 'web_search',
          argumentsJson: '{"query":"人工耳蜗","max_results":4}',
        ),
      );

      expect(outcome.isError, isFalse);
      expect(outcome.citations, hasLength(2));
      expect(outcome.text, contains('标题：人工耳蜗植入科普'));
      expect(outcome.text, contains('链接：https://example.com/cochlear'));
      expect(RegExp(r'^\[\d+\]', multiLine: true).hasMatch(outcome.text), isFalse);
      expect(outcome.text, contains('来源由应用统一展示'));
    } finally {
      await server.close(force: true);
    }
  });
}
