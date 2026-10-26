import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../core/utils.dart';
import '../data/models.dart';

class SearchException implements Exception {
  const SearchException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => message;
}

class SearchCredentials {
  const SearchCredentials({this.tavily = '', this.google = '', this.bing = ''});

  final String tavily;
  final String google;
  final String bing;

  String forProvider(SearchProvider provider) => switch (provider) {
        SearchProvider.tavily => tavily,
        SearchProvider.google => google,
        SearchProvider.bing => bing,
        _ => '',
      };
}

class SearchService {
  SearchService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Lumen/1.0';

  Future<List<SearchHit>> search(
    String query, {
    required SearchConfig config,
    required SearchCredentials credentials,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) throw const SearchException('搜索词为空。');
    if (config.provider == SearchProvider.none) {
      throw const SearchException('联网搜索未启用。');
    }
    final errors = <String>[];
    List<SearchHit> hits = const [];
    for (final provider in _searchCandidates(config, credentials)) {
      final client = _clientFactory();
      try {
        final result = await _searchProvider(client, provider, trimmed, config, credentials)
            .timeout(const Duration(seconds: 8));
        if (result.isNotEmpty) {
          hits = result;
          break;
        }
        errors.add('${provider.label} 没有返回结果');
      } on http.ClientException catch (error) {
        errors.add(
          kIsWeb && (provider == SearchProvider.bingFree || provider == SearchProvider.duckduckgo)
              ? '${provider.label} 被浏览器 CORS 拦截'
              : '${provider.label} 网络请求失败：${error.message}',
        );
      } on TimeoutException {
        errors.add('${provider.label} 超时');
      } on SearchException catch (error) {
        errors.add('${provider.label}：${error.message}');
      } catch (error) {
        errors.add('${provider.label} 失败：${compactText('$error', 120)}');
      } finally {
        client.close();
      }
    }
    if (hits.isEmpty) {
      if (errors.isEmpty) return const [];
      throw SearchException('所有搜索源都没有成功：${errors.take(3).join('；')}');
    }

    final seen = <String>{};
    final unique = hits.where((hit) => hit.url.isNotEmpty && seen.add(hit.url)).toList();
    final filtered = config.includeDomains.isEmpty
        ? unique
        : unique.where((hit) {
            final host = Uri.tryParse(hit.url)?.host.toLowerCase() ?? '';
            return config.includeDomains.any((domain) {
              final clean = domain.trim().toLowerCase();
              return clean.isNotEmpty && (host == clean || host.endsWith('.$clean'));
            });
          }).toList();
    if (!config.fetchPageContent) return filtered;

    // Read several pages in parallel. A dead page must never kill the search;
    // when a page fails, try the next result pages as replacements.
    final head = filtered.take(4).toList();
    final tail = filtered.skip(4).toList();
    final enriched = [...await _enrichPages(head)];
    final failed = enriched.where((hit) => hit.content.trim().isEmpty).length;
    if (failed > 0 && tail.isNotEmpty) {
      final attempts = failed > 2 ? 2 : failed;
      final rescueCandidates = tail.take(attempts).toList();
      final rescued = (await _enrichPages(rescueCandidates))
          .where((hit) => hit.content.trim().isNotEmpty)
          .toList();
      final rescuedUrls = rescued.map((hit) => hit.url).toSet();
      tail.removeWhere((hit) => rescuedUrls.contains(hit.url));
      enriched.addAll(rescued);
    }
    return [...enriched, ...tail];
  }

  Future<List<SearchHit>> _enrichPages(List<SearchHit> hits) {
    return Future.wait(
      hits.map((hit) async {
        try {
          final page = await fetchPage(hit.url).timeout(const Duration(seconds: 10));
          return SearchHit(
            title: hit.title,
            url: hit.url,
            snippet: hit.snippet,
            content: page.content.isEmpty ? hit.snippet : page.content,
            publishedAt: hit.publishedAt,
          );
        } catch (_) {
          return hit;
        }
      }),
    );
  }

  List<SearchProvider> _searchCandidates(
    SearchConfig config,
    SearchCredentials credentials,
  ) {
    final result = <SearchProvider>[];
    void add(SearchProvider provider) {
      if (provider != SearchProvider.none && !result.contains(provider)) {
        result.add(provider);
      }
    }

    add(config.provider);
    if (credentials.tavily.trim().isNotEmpty) add(SearchProvider.tavily);
    if (credentials.google.trim().isNotEmpty && config.googleCx.trim().isNotEmpty) {
      add(SearchProvider.google);
    }
    if (credentials.bing.trim().isNotEmpty) add(SearchProvider.bing);
    if (config.searxBaseUrl.trim().isNotEmpty) add(SearchProvider.searxng);
    add(SearchProvider.bingFree);
    add(SearchProvider.duckduckgo);
    // Three attempts keep a broken primary source from stalling the answer.
    return result.take(3).toList();
  }

  Future<List<SearchHit>> _searchProvider(
    http.Client client,
    SearchProvider provider,
    String query,
    SearchConfig config,
    SearchCredentials credentials,
  ) {
    return switch (provider) {
      SearchProvider.tavily => _tavily(client, query, config, credentials.tavily),
      SearchProvider.google => _google(client, query, config, credentials.google),
      SearchProvider.bing => _bing(client, query, config, credentials.bing),
      SearchProvider.bingFree => _bingFree(client, query, config),
      SearchProvider.searxng => _searxng(client, query, config),
      SearchProvider.duckduckgo => _duckDuckGo(client, query, config),
      SearchProvider.none => Future.value(const <SearchHit>[]),
    };
  }

  Future<List<SearchHit>> _tavily(
    http.Client client,
    String query,
    SearchConfig config,
    String apiKey,
  ) async {
    if (apiKey.isEmpty) {
      throw const SearchException('Tavily 需要 API Key，请在「设置 → 联网搜索」中填写。');
    }
    final body = <String, dynamic>{
      'query': query,
      'search_depth': 'basic',
      'include_answer': false,
      'include_raw_content': false,
      'max_results': config.maxResults,
      if (config.includeDomains.isNotEmpty) 'include_domains': config.includeDomains,
    };
    var response = await client
        .post(
          Uri.parse('https://api.tavily.com/search'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401) {
      // Older Tavily deployments still expect the key in the JSON body.
      body['api_key'] = apiKey;
      response = await client
          .post(
            Uri.parse('https://api.tavily.com/search'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchException(
        'Tavily 搜索失败（HTTP ${response.statusCode}）',
        details: _short(response.body),
      );
    }
    final json = _json(response.body);
    final results = json['results'];
    final hits = <SearchHit>[];
    if (results is List) {
      for (final raw in results) {
        if (raw is! Map) continue;
        hits.add(
          SearchHit(
            title: '${raw['title'] ?? ''}'.trim(),
            url: '${raw['url'] ?? ''}',
            snippet: '${raw['content'] ?? ''}'.trim(),
            publishedAt: '${raw['published_date'] ?? raw['publishedDate'] ?? ''}',
          ),
        );
      }
    }
    return hits;
  }

  Future<List<SearchHit>> _google(
    http.Client client,
    String query,
    SearchConfig config,
    String apiKey,
  ) async {
    if (apiKey.isEmpty || config.googleCx.trim().isEmpty) {
      throw const SearchException('Google 搜索需要 API Key 与搜索引擎 ID (cx)。');
    }
    final uri = Uri.https('www.googleapis.com', '/customsearch/v1', {
      'key': apiKey,
      'cx': config.googleCx.trim(),
      'q': query,
      'num': '${config.maxResults.clamp(1, 10)}',
    });
    final response = await client.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchException(
        'Google 搜索失败（HTTP ${response.statusCode}）',
        details: _short(response.body),
      );
    }
    final json = _json(response.body);
    final items = json['items'];
    final hits = <SearchHit>[];
    if (items is List) {
      for (final raw in items) {
        if (raw is! Map) continue;
        hits.add(
          SearchHit(
            title: '${raw['title'] ?? ''}'.trim(),
            url: '${raw['link'] ?? ''}',
            snippet: '${raw['snippet'] ?? ''}'.trim(),
            publishedAt: _googlePublishedAt(raw),
          ),
        );
      }
    }
    return hits;
  }

  static String _googlePublishedAt(Map raw) {
    final pagemap = raw['pagemap'];
    if (pagemap is Map) {
      final metatags = pagemap['metatags'];
      if (metatags is List && metatags.isNotEmpty && metatags.first is Map) {
        final tags = (metatags.first as Map).map((key, value) => MapEntry('$key', '$value'));
        for (final key in ['article:published_time', 'og:updated_time', 'date', 'pubdate']) {
          final value = tags[key];
          if (value != null && value.trim().isNotEmpty) return value.trim();
        }
      }
    }
    return '';
  }

  Future<List<SearchHit>> _bing(
    http.Client client,
    String query,
    SearchConfig config,
    String apiKey,
  ) async {
    if (apiKey.isEmpty) throw const SearchException('Bing 搜索需要 Azure 订阅 Key。');
    final uri = Uri.https('api.bing.microsoft.com', '/v7.0/search', {
      'q': query,
      'count': '${config.maxResults.clamp(1, 10)}',
      'mkt': 'zh-CN',
    });
    final response = await client
        .get(uri, headers: {'Ocp-Apim-Subscription-Key': apiKey})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchException(
        'Bing 搜索失败（HTTP ${response.statusCode}）',
        details: _short(response.body),
      );
    }
    final json = _json(response.body);
    final webPages = json['webPages'];
    final values = webPages is Map ? webPages['value'] : null;
    final hits = <SearchHit>[];
    if (values is List) {
      for (final raw in values) {
        if (raw is! Map) continue;
        hits.add(
          SearchHit(
            title: '${raw['name'] ?? ''}'.trim(),
            url: '${raw['url'] ?? ''}',
            snippet: '${raw['snippet'] ?? ''}'.trim(),
            publishedAt: '${raw['dateLastCrawled'] ?? raw['datePublished'] ?? ''}',
          ),
        );
      }
    }
    return hits;
  }

  Future<List<SearchHit>> _bingFree(
    http.Client client,
    String query,
    SearchConfig config,
  ) async {
    final uri = Uri.https('www.bing.com', '/search', {
      'q': query,
      'setlang': 'zh-Hans',
      'cc': 'CN',
    });
    final response = await client
        .get(
          uri,
          headers: {
            'User-Agent': _browserUserAgent,
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchException(
        'Bing 免费搜索失败（HTTP ${response.statusCode}）',
        details: _short(response.body),
      );
    }
    final hits = parseBingFreeHtml(_text(response), maxResults: config.maxResults);
    if (hits.isEmpty) {
      throw const SearchException(
        'Bing 没有返回可解析的结果。可能触发了验证码，请稍后重试或改用 Tavily/SearXNG。',
      );
    }
    return hits;
  }

  /// Pure HTML parser kept public for unit tests.
  static List<SearchHit> parseBingFreeHtml(String html, {int maxResults = 6}) {
    final document = html_parser.parse(html);
    final hits = <SearchHit>[];
    for (final node in document.querySelectorAll('li.b_algo')) {
      final anchor = node.querySelector('h2 a') ?? node.querySelector('a');
      if (anchor == null) continue;
      final title = anchor.text.trim();
      final rawUrl = anchor.attributes['href'] ?? '';
      final url = _unwrapBingUrl(rawUrl);
      if (title.isEmpty || url.isEmpty) continue;
      final snippet = (node.querySelector('.b_caption p') ??
                  node.querySelector('.b_snippet') ??
                  node.querySelector('.b_caption') ??
                  node.querySelector('p'))
              ?.text
              .trim() ??
          '';
      hits.add(SearchHit(title: title, url: url, snippet: snippet));
      if (hits.length >= maxResults) break;
    }
    return hits;
  }

  static String _unwrapBingUrl(String href) {
    var value = href.trim();
    if (value.startsWith('//')) value = 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri == null) return '';
    if (uri.host.toLowerCase().endsWith('bing.com') && uri.path.startsWith('/ck/')) {
      final encoded = uri.queryParameters['u'];
      if (encoded != null && encoded.startsWith('a1')) {
        try {
          final payload = encoded.substring(2);
          final normalized = base64Url.normalize(payload);
          return utf8.decode(base64Url.decode(normalized));
        } catch (_) {
          return '';
        }
      }
      return '';
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') return value;
    return '';
  }

  Future<List<SearchHit>> _searxng(
    http.Client client,
    String query,
    SearchConfig config,
  ) async {
    final base = normalizeBaseUrl(config.searxBaseUrl);
    if (base.isEmpty) throw const SearchException('请填写 SearXNG 实例地址。');
    final uri = Uri.parse(base).replace(
      path: '${Uri.parse(base).path.replaceAll(RegExp(r'/+$'), '')}/search',
      queryParameters: {
        'q': query,
        'format': 'json',
        'language': 'zh-CN',
        'safesearch': '0',
      },
    );
    final response = await client
        .get(uri, headers: {'accept': 'application/json'})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchException(
        'SearXNG 搜索失败（HTTP ${response.statusCode}）',
        details: _short(response.body),
      );
    }
    final json = _json(response.body);
    final results = json['results'];
    final hits = <SearchHit>[];
    if (results is List) {
      for (final raw in results) {
        if (raw is! Map) continue;
        hits.add(
          SearchHit(
            title: '${raw['title'] ?? ''}'.trim(),
            url: '${raw['url'] ?? ''}',
            snippet: '${raw['content'] ?? ''}'.trim(),
            publishedAt: '${raw['publishedDate'] ?? raw['published_date'] ?? ''}',
          ),
        );
        if (hits.length >= config.maxResults) break;
      }
    }
    return hits;
  }

  Future<List<SearchHit>> _duckDuckGo(
    http.Client client,
    String query,
    SearchConfig config,
  ) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
    final response = await client
        .get(
          uri,
          headers: {
            'User-Agent': _browserUserAgent,
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchException(
        'DuckDuckGo 搜索失败（HTTP ${response.statusCode}）。可以改用 Tavily、Google CSE、Bing 或自建 SearXNG。',
      );
    }
    final document = html_parser.parse(_text(response));
    final hits = <SearchHit>[];
    for (final result in document.querySelectorAll('div.result')) {
      final anchor = result.querySelector('.result__a');
      if (anchor == null) continue;
      final rawUrl = anchor.attributes['href'] ?? '';
      final url = _unwrapDuckDuckGo(rawUrl);
      if (url.isEmpty) continue;
      final snippet = result.querySelector('.result__snippet')?.text.trim() ?? '';
      hits.add(
        SearchHit(
          title: anchor.text.trim(),
          url: url,
          snippet: snippet,
        ),
      );
      if (hits.length >= config.maxResults) break;
    }
    if (hits.isEmpty) {
      for (final anchor in document.querySelectorAll('a.result-link')) {
        final rawUrl = anchor.attributes['href'] ?? '';
        final url = _unwrapDuckDuckGo(rawUrl);
        if (url.isEmpty) continue;
        hits.add(
          SearchHit(
            title: anchor.text.trim(),
            url: url,
            snippet: document.querySelector('.result-snippet')?.text.trim() ?? '',
          ),
        );
        if (hits.length >= config.maxResults) break;
      }
    }
    if (hits.isEmpty) {
      throw const SearchException(
        'DuckDuckGo 没有返回可解析的结果。它可能被网络或验证码拦截，建议配置 Tavily 或自建 SearXNG。',
      );
    }
    return hits;
  }

  Future<PageContent> fetchPage(String url) async {
    final target = url.trim();
    if (!isSafeRemoteUrl(target)) {
      throw const SearchException('这个地址不允许抓取（仅支持公开的 http/https 页面）。');
    }
    final client = _clientFactory();
    try {
      final response = await _safeGet(
        client,
        Uri.parse(target),
        headers: {
          'User-Agent': _browserUserAgent,
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      );
      final finalUrl = response.request?.url.toString() ?? target;
      if (!isSafeRemoteUrl(finalUrl)) {
        throw const SearchException('页面跳转到了不允许访问的地址。');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SearchException('读取网页失败（HTTP ${response.statusCode}）。');
      }
      final contentType = (response.headers['content-type'] ?? '').toLowerCase();
      final raw = _text(response);
      if (contentType.contains('text/html') || raw.trimLeft().startsWith('<')) {
        final page = _extractHtml(raw);
        if (page.content.length >= 200) return page;
        // JS-heavy pages: fall back to Jina Reader's readable extraction.
        try {
          final reader = await _safeGet(
            client,
            Uri.parse('https://r.jina.ai/$target'),
            headers: {'accept': 'text/plain'},
          );
          if (reader.statusCode >= 200 && reader.statusCode < 300) {
            final text = _text(reader).trim();
            if (text.length > page.content.length) {
              return PageContent(
                title: page.title.isEmpty ? target : page.title,
                content: text.length > 16000 ? '${text.substring(0, 16000)}…' : text,
              );
            }
          }
        } catch (_) {
          // Keep the local extraction.
        }
        return page;
      }
      final trimmed = raw.trim();
      return PageContent(
        title: Uri.tryParse(target)?.host ?? target,
        content: trimmed.length > 16000 ? '${trimmed.substring(0, 16000)}…' : trimmed,
      );
    } finally {
      client.close();
    }
  }

  /// Fetches a public URL without letting the HTTP client follow redirects
  /// into loopback/private networks. Every hop is validated before sending.
  Future<http.Response> _safeGet(
    http.Client client,
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    var current = uri;
    for (var hop = 0; hop < 6; hop++) {
      if (!isSafeRemoteUrl(current.toString())) {
        throw const SearchException('这个地址不允许访问（仅支持公开的 http/https 页面）。');
      }
      final request = http.Request('GET', current)..followRedirects = false;
      request.headers.addAll(headers);
      final streamed = await client.send(request).timeout(const Duration(seconds: 25));
      if (const [301, 302, 303, 307, 308].contains(streamed.statusCode)) {
        final location = streamed.headers['location'];
        await streamed.stream.drain<void>();
        if (location == null || location.isEmpty) {
          throw SearchException('网页返回了无效跳转（HTTP ${streamed.statusCode}）。');
        }
        current = current.resolve(location);
        continue;
      }
      final bytes = await streamed.stream.toBytes().timeout(const Duration(seconds: 30));
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
        isRedirect: false,
      );
    }
    throw const SearchException('网页跳转次数过多，已停止访问。');
  }

  PageContent _extractHtml(String html) {
    final document = html_parser.parse(html);
    final title = document.querySelector('title')?.text.trim() ?? '';
    for (final selector in ['script', 'style', 'noscript', 'svg', 'header', 'footer', 'nav', 'form', 'aside']) {
      for (final element in document.querySelectorAll(selector)) {
        element.remove();
      }
    }
    final main = document.querySelector('article') ??
        document.querySelector('main') ??
        document.body;
    var text = main?.text ?? document.documentElement?.text ?? '';
    text = text.replaceAll(RegExp(r'\r'), '').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    if (text.length > 16000) text = '${text.substring(0, 16000)}…';
    return PageContent(title: title, content: text);
  }

  String _unwrapDuckDuckGo(String href) {
    var value = href.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) value = 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri == null) return '';
    final host = uri.host.toLowerCase();
    if (host.endsWith('duckduckgo.com')) {
      final target = uri.queryParameters['uddg'] ?? uri.queryParameters['u'];
      if (target != null && target.isNotEmpty) {
        return Uri.decodeComponent(target);
      }
      return '';
    }
    return value;
  }

  Map<String, dynamic> _json(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      // Fall through.
    }
    throw SearchException('搜索服务返回了无法解析的数据。', details: _short(body));
  }

  String _text(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return response.body;
    }
  }

  String _short(String value) => value.length > 500 ? '${value.substring(0, 500)}…' : value;
}

class PageContent {
  const PageContent({required this.title, required this.content});

  final String title;
  final String content;
}
