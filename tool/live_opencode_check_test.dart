// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/api/dsml.dart';
import 'package:lumen/services/api/llm_types.dart';
import 'package:lumen/services/api/openai_client.dart';

String head(String value, [int max = 500]) {
  final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

void main() {
  test('live OpenCode Go search then final answer has no DSML', () async {
    final key = Platform.environment['OC_KEY'] ?? '';
    if (key.isEmpty) {
      markTestSkipped('OC_KEY is not set');
      return;
    }
    final provider = ProviderConfig(
      id: 'opencode',
      name: 'OpenCode Go',
      protocol: LlmProtocol.openai,
      baseUrl: 'https://opencode.ai/zen/go/v1',
      reasoningStyle: ReasoningStyle.openai,
    );
    const model = ModelInfo(
      id: 'deepseek-v4.1-flash',
      name: 'DeepSeek V4.1 Flash',
      contextWindow: 131072,
      tools: true,
    );
    const tool = ToolDefinition(
      name: 'web_search',
      description: '搜索公开网页，返回标题、链接和摘要。',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'max_results': {'type': 'integer'},
        },
        'required': ['query'],
      },
    );
    const system = '你是 Lumen。你可以调用 web_search 获取最新信息。'
        '不要在正文中写 [1]、[2] 等来源编号，也不要单列网址或来源列表；'
        '来源由应用在回答下方统一折叠展示。拿到搜索结果后必须给出完整、详细的总结。';

    final first = await OpenAiClient()
        .stream(
          LlmRequest(
            provider: provider,
            apiKey: key,
            model: model,
            systemPrompt: system,
            messages: [
              LlmMessage.user('人工耳蜗是什么？儿童语前聋植入后效果如何？请先联网搜索。'),
            ],
            tools: const [tool],
            maxTokens: 16384,
            sessionId: 'live-check',
          ),
        )
        .toList();
    final firstText = first.whereType<TextDelta>().map((e) => e.text).join();
    final firstCalls = first.whereType<ToolCallCompleted>().map((e) => e.call).toList();
    final firstRecovered = extractDsmlToolCalls(firstText);
    print('first finish=${first.whereType<TurnCompleted>().map((e) => e.finishReason).join()}');
    print('first native calls=${firstCalls.map((e) => e.name).join(',')}');
    print('first dsml calls=${firstRecovered.calls.map((e) => e.name).join(',')}');
    print('first text=${head(firstRecovered.cleanText)}');

    final calls = firstCalls.isNotEmpty ? firstCalls : firstRecovered.calls;
    expect(calls, isNotEmpty, reason: 'model should search first');

    final finalEvents = await OpenAiClient()
        .stream(
          LlmRequest(
            provider: provider,
            apiKey: key,
            model: model,
            systemPrompt: '$system\n\n## 最终回答\n'
                '工具阶段已经结束，web_search 等工具已关闭，不能再调用。'
                '不要输出任何工具调用标记（包括 DSML、XML、JSON 形式）。'
                '请直接基于已经获得的结果给出完整回答；不要在正文中写来源编号或来源列表。',
            messages: [
              LlmMessage.user('人工耳蜗是什么？儿童语前聋植入后效果如何？请先联网搜索。'),
              LlmMessage.assistant('', toolCalls: calls),
              LlmMessage.toolResult(
                calls.first.id,
                calls.first.name,
                '标题：人工耳蜗植入科普\n'
                    '链接：https://example.com/cochlear\n'
                    '内容：人工耳蜗通过体外声音处理器采集声音，经植入体转换为电信号，刺激耳蜗内的听觉神经。'
                    '儿童语前聋越早植入，听觉语言发育通常越好；术后需要长期康复训练。',
              ),
            ],
            tools: const [],
            maxTokens: 16384,
            sessionId: 'live-check',
          ),
        )
        .toList();
    final finalText = finalEvents.whereType<TextDelta>().map((e) => e.text).join();
    final finalRecovered = extractDsmlToolCalls(finalText);
    print('final finish=${finalEvents.whereType<TurnCompleted>().map((e) => e.finishReason).join()}');
    print('final native calls=${finalEvents.whereType<ToolCallCompleted>().length}');
    print('final dsml markup=${finalRecovered.foundMarkup}');
    print('final text=${head(finalRecovered.cleanText)}');

    expect(finalRecovered.foundMarkup, isFalse);
    expect(RegExp(r'\[\d+\]').hasMatch(finalRecovered.cleanText), isFalse);
    expect(finalRecovered.cleanText.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
