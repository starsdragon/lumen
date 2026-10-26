import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/search_service.dart';

void main() {
  test('falls back to another configured search source when the primary fails', () async {
    final calls = <String>[];
    Future<http.Response> handler(http.Request request) async {
      calls.add(request.url.host);
      if (request.url.host == 'primary.test') {
        throw http.ClientException('primary search is down', request.url);
      }
      if (request.url.host == 'api.tavily.com') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'title': 'Fallback result',
                'url': 'https://example.com/fallback',
                'content': 'This result came from the fallback search provider.',
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    }

    final service = SearchService(clientFactory: () => MockClient(handler));
    final hits = await service.search(
      'fallback test',
      config: SearchConfig(
        provider: SearchProvider.searxng,
        searxBaseUrl: 'https://primary.test',
        maxResults: 4,
        fetchPageContent: false,
      ),
      credentials: const SearchCredentials(tavily: 'tavily-key'),
    );

    expect(calls, ['primary.test', 'api.tavily.com']);
    expect(hits, hasLength(1));
    expect(hits.single.title, 'Fallback result');
    expect(hits.single.url, 'https://example.com/fallback');
  });

  test('tries later result pages when the first pages all fail', () async {
    final results = [
      for (var i = 1; i <= 6; i++)
        {
          'title': 'Page $i',
          'url': 'https://page$i.test/a',
          'content': 'snippet $i',
        }
    ];
    Future<http.Response> handler(http.Request request) async {
      if (request.url.host == 'searx.test') {
        return http.Response(
          jsonEncode({'results': results}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final match = RegExp(r'^page(\d+)\.test$').firstMatch(request.url.host);
      if (match == null) return http.Response('not found', 404);
      final index = int.parse(match.group(1)!);
      if (index <= 4) {
        throw http.ClientException('page $index is down', request.url);
      }
      return http.Response(
        '<html><head><title>Page $index</title></head><body>${'第 $index 页正文。' * 120}</body></html>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }

    final service = SearchService(clientFactory: () => MockClient(handler));
    final hits = await service.search(
      'tail rescue test',
      config: SearchConfig(
        provider: SearchProvider.searxng,
        searxBaseUrl: 'https://searx.test',
        maxResults: 6,
        fetchPageContent: true,
      ),
      credentials: const SearchCredentials(),
    );

    expect(hits, hasLength(6));
    final rescued = hits.where((hit) => hit.content.contains('页正文')).toList();
    expect(rescued, isNotEmpty);
    expect(rescued.first.url, anyOf('https://page5.test/a', 'https://page6.test/a'));
  });

  test('a broken page does not abort the other pages', () async {
    Future<http.Response> handler(http.Request request) async {
      if (request.url.host == 'searx.test') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'title': 'First page',
                'url': 'https://page1.test/a',
                'content': 'first snippet',
              },
              {
                'title': 'Second page',
                'url': 'https://page2.test/b',
                'content': 'second snippet',
              },
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host == 'page1.test') {
        throw http.ClientException('page one is down', request.url);
      }
      if (request.url.host == 'page2.test') {
        return http.Response(
          '<html><head><title>Second page</title></head><body>${'第二页正文。' * 120}</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    }

    final service = SearchService(clientFactory: () => MockClient(handler));
    final hits = await service.search(
      'broken page test',
      config: SearchConfig(
        provider: SearchProvider.searxng,
        searxBaseUrl: 'https://searx.test',
        maxResults: 4,
        fetchPageContent: true,
      ),
      credentials: const SearchCredentials(),
    );

    expect(hits, hasLength(2));
    final first = hits.firstWhere((hit) => hit.url == 'https://page1.test/a');
    final second = hits.firstWhere((hit) => hit.url == 'https://page2.test/b');
    expect(first.content, isEmpty);
    expect(first.snippet, 'first snippet');
    expect(second.content, contains('第二页正文'));
  });
}
