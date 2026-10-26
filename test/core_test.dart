import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/utils.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/api/reasoning_params.dart';
import 'package:lumen/services/api/sse.dart';
import 'package:lumen/services/search_service.dart';
import 'package:lumen/ui/markdown/markdown_view.dart';

void main() {
  group('math preprocessor', () {
    test('converts inline and display math and leaves code alone', () {
      const source = r'''
行内 $E = mc^2$ 会被转换。

```dart
final price = '$5';
```

$$
\text{清晰度} = \frac{a}{b}
$$
''';
      final prepared = preprocessMath(source);
      expect(prepared.contains('`lumen-math:'), isTrue);
      expect(prepared.contains('```lumen-math-display'), isTrue);
      expect(prepared.contains("final price = '\$5';"), isTrue);
    });

    test('does not break unclosed math while streaming', () {
      expect(preprocessMath('正在计算 \$x + 1'), contains('\$x + 1'));
    });
  });

  group('reasoning mapping', () {
    ProviderConfig provider(String id, ReasoningStyle style, {String base = 'https://example.com/v1'}) =>
        ProviderConfig(id: id, name: id, protocol: LlmProtocol.openai, baseUrl: base, reasoningStyle: style);

    const reasoningModel = ModelInfo(id: 'demo-model', name: 'Demo', reasoning: true);

    test('DeepSeek maps thinking and effort', () {
      final params = openAiReasoningParams(
        provider('deepseek', ReasoningStyle.deepseek),
        reasoningModel,
        ReasoningLevel.high,
      );
      expect((params['thinking'] as Map)['type'], 'enabled');
      expect(params['reasoning_effort'], 'high');
    });

    test('Zhipu and Kimi use thinking.type; K2.6 keeps reasoning', () {
      final zhipu = openAiReasoningParams(
        provider('zhipu', ReasoningStyle.zhipu),
        reasoningModel,
        ReasoningLevel.high,
      );
      expect((zhipu['thinking'] as Map)['type'], 'enabled');
      expect(zhipu.containsKey('reasoning_effort'), isFalse);

      final kimi = openAiReasoningParams(
        provider('kimi', ReasoningStyle.moonshot),
        const ModelInfo(id: 'kimi-k2.6', name: 'Kimi K2.6', reasoning: true),
        ReasoningLevel.high,
      );
      expect((kimi['thinking'] as Map)['keep'], 'all');
    });

    test('Qwen and OpenRouter variants', () {
      final qwen = openAiReasoningParams(
        provider('bailian', ReasoningStyle.qwen),
        reasoningModel,
        ReasoningLevel.high,
      );
      expect(qwen['reasoning_effort'], 'high');

      final router = openAiReasoningParams(
        provider('router', ReasoningStyle.openrouter),
        reasoningModel,
        ReasoningLevel.auto,
      );
      expect((router['reasoning'] as Map)['enabled'], isTrue);
    });

    test('Anthropic uses adaptive thinking and output effort', () {
      final params = anthropicThinkingParams(reasoningModel, ReasoningLevel.high);
      expect((params['thinking'] as Map)['type'], 'adaptive');
      expect((params['output_config'] as Map)['effort'], 'high');
    });

    test('Gemini switches between thinkingLevel and budget', () {
      final gemini3 = geminiThinkingConfig(
        const ModelInfo(id: 'gemini-3-pro-preview', name: 'Gemini 3', reasoning: true),
        ReasoningLevel.high,
      )!;
      expect(gemini3['thinkingLevel'], 'high');

      final gemini25 = geminiThinkingConfig(
        const ModelInfo(id: 'gemini-2.5-pro', name: 'Gemini 2.5', reasoning: true),
        ReasoningLevel.high,
      )!;
      expect(gemini25['thinkingBudget'], 8000);
    });
  });

  group('SSE parser', () {
    test('handles chunk boundaries and multi-line data', () async {
      final events = await parseSse(
        Stream<List<int>>.fromIterable([
          utf8.encode('event: message\nda'),
          utf8.encode('ta: {"a":1}\n'),
          utf8.encode('\n'),
          utf8.encode('data: plain\n\n'),
        ]),
      ).toList();
      expect(events.length, 2);
      expect(events.first.event, 'message');
      expect(events.first.data, '{"a":1}');
      expect(events.last.data, 'plain');
    });
  });

  group('URL safety', () {
    test('blocks loopback, private and metadata targets', () {
      expect(isSafeRemoteUrl('https://example.com/article'), isTrue);
      expect(isSafeRemoteUrl('http://127.0.0.1:8080/'), isFalse);
      expect(isSafeRemoteUrl('http://localhost/'), isFalse);
      expect(isSafeRemoteUrl('http://10.1.2.3/'), isFalse);
      expect(isSafeRemoteUrl('http://172.20.1.1/'), isFalse);
      expect(isSafeRemoteUrl('http://192.168.1.10/'), isFalse);
      expect(isSafeRemoteUrl('http://169.254.169.254/latest/meta-data'), isFalse);
      expect(isSafeRemoteUrl('http://[::1]/'), isFalse);
      expect(isSafeRemoteUrl('ftp://example.com/file'), isFalse);
    });
  });

  group('Bing free search parser', () {
    test('extracts b_algo results and unwraps bing redirects', () {
      final encoded = base64Url.encode(utf8.encode('https://example.com/article')).replaceAll('=', '');
      final html = '''
<html><body><ol id="b_results">
<li class="b_algo">
  <h2><a href="https://example.org/direct">Direct result</a></h2>
  <div class="b_caption"><p>Direct snippet</p></div>
</li>
<li class="b_algo">
  <h2><a href="https://www.bing.com/ck/a?!&&p=abc&u=a1$encoded&ntb=1">Redirected result</a></h2>
  <div class="b_caption"><p>Redirect snippet</p></div>
</li>
</ol></body></html>
''';
      final hits = SearchService.parseBingFreeHtml(html);
      expect(hits.length, 2);
      expect(hits[0].title, 'Direct result');
      expect(hits[0].url, 'https://example.org/direct');
      expect(hits[1].url, 'https://example.com/article');
    });
  });
}
