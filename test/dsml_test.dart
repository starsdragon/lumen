import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/services/api/dsml.dart';

void main() {
  test('parses ASCII DSML tool calls with closing tags', () {
    const raw = '我先搜索一下。\n'
        '<||DSML||calls>'
        '<||DSML||invoke name="web_search">'
        '<||DSML||parameter name="max_results" string="false">6</||DSML||parameter>'
        '<||DSML||parameter name="query" string="true">人工耳蜗 儿童 语前聋</||DSML||parameter>'
        '</||DSML||invoke>'
        '</||DSML||calls>';

    final result = extractDsmlToolCalls(raw);

    expect(result.foundMarkup, isTrue);
    expect(result.cleanText, '我先搜索一下。');
    expect(result.calls, hasLength(1));
    expect(result.calls.single.name, 'web_search');
    expect(
      jsonDecode(result.calls.single.argumentsJson),
      {'max_results': 6, 'query': '人工耳蜗 儿童 语前聋'},
    );
  });

  test('parses full-width DSML without closing tags', () {
    const raw = '需要查最新资料。\n'
        '<｜DSML｜tool_calls>\n'
        '<｜DSML｜invoke name="fetch_url">\n'
        '<｜DSML｜parameter name="url" string="true">https://example.com/a?x=1&y=2\n';

    final result = extractDsmlToolCalls(raw);

    expect(result.foundMarkup, isTrue);
    expect(result.cleanText, '需要查最新资料。');
    expect(result.calls, hasLength(1));
    expect(result.calls.single.name, 'fetch_url');
    expect(
      jsonDecode(result.calls.single.argumentsJson),
      {'url': 'https://example.com/a?x=1&y=2'},
    );
  });

  test('handles consecutive parameters without per-parameter closing tags', () {
    const raw = '<||DSML||calls>'
        '<||DSML||invoke name="web_search">'
        '<||DSML||parameter name="query" string="true">AI 新闻'
        '<||DSML||parameter name="limit" string="false">5'
        '</||DSML||invoke>'
        '</||DSML||calls>';

    final result = extractDsmlToolCalls(raw);

    expect(result.calls, hasLength(1));
    expect(
      jsonDecode(result.calls.single.argumentsJson),
      {'query': 'AI 新闻', 'limit': 5},
    );
    expect(result.cleanText, isEmpty);
  });

  test('handles multiple calls in one block', () {
    const raw = '<||DSML||calls>'
        '<||DSML||invoke name="web_search">'
        '<||DSML||parameter name="query" string="true">A</||DSML||parameter>'
        '</||DSML||invoke>'
        '<||DSML||invoke name="fetch_url">'
        '<||DSML||parameter name="url" string="true">https://a.example</||DSML||parameter>'
        '</||DSML||invoke>'
        '</||DSML||calls>';

    final result = extractDsmlToolCalls(raw);

    expect(result.calls, hasLength(2));
    expect(result.calls[0].name, 'web_search');
    expect(result.calls[1].name, 'fetch_url');
    expect(result.cleanText, isEmpty);
  });

  test('tolerates spaces inside the DSML marker', () {
    const raw = '开始。\n'
        '< | | DSML | | calls>'
        '< | | DSML | | invoke name="web_search">'
        '< | | DSML | | parameter name="query" string="true">测试'
        '</ | | DSML | | parameter>'
        '</ | | DSML | | invoke>'
        '</ | | DSML | | calls>';

    final result = extractDsmlToolCalls(raw);

    expect(result.foundMarkup, isTrue);
    expect(result.cleanText, '开始。');
    expect(result.calls, hasLength(1));
    expect(jsonDecode(result.calls.single.argumentsJson)['query'], '测试');
  });

  test('leaves ordinary text untouched', () {
    const raw = '普通回答，包含 [1] 和一个 array[2] 示例。\n';
    final result = extractDsmlToolCalls(raw);

    expect(result.foundMarkup, isFalse);
    expect(result.cleanText, raw);
    expect(result.calls, isEmpty);
  });
}
