import 'dart:async';
import 'dart:convert';

import '../../data/models.dart';
import 'llm_types.dart';

/// A local, deterministic model used for onboarding and UI previews. It never
/// calls the network (except when the web_search tool is executed by the agent
/// loop), and clearly labels itself as a demo.
class DemoClient implements LlmClient {
  @override
  Stream<LlmEvent> stream(LlmRequest request) async* {
    final last = request.messages.isEmpty ? null : request.messages.last;
    final lastUser = request.messages.lastWhere(
      (m) => m.role == ChatRole.user,
      orElse: () => LlmMessage.user(''),
    );
    final prompt = lastUser.text.trim();
    final hasSearchTool = request.tools.any((t) => t.name == 'web_search');

    // Simulate a tool call once, then answer with the real search results.
    if (last?.role != ChatRole.tool &&
        hasSearchTool &&
        RegExp(r'搜索|最新|今天|新闻|动态|查一下|联网|search', caseSensitive: false).hasMatch(prompt)) {
      final reasoning = _shortReasoning(request.reasoningLevel, '这个问题需要最新公开信息，我先搜索，再基于来源回答。');
      yield* _streamReasoning(reasoning, request.reasoningLevel);
      final id = newId('call');
      final args = jsonEncode({'query': _searchQuery(prompt)});
      yield ToolCallStarted(id: id, name: 'web_search');
      yield ToolCallArgumentsDelta(id: id, delta: args);
      yield ToolCallCompleted(LlmToolCall(id: id, name: 'web_search', argumentsJson: args));
      yield const TurnCompleted(finishReason: 'tool_calls');
      return;
    }

    final reasoning = _reasoningFor(request, prompt);
    yield* _streamReasoning(reasoning, request.reasoningLevel);

    String answer;
    if (last?.role == ChatRole.tool) {
      answer = _searchAnswer(last!.text, prompt);
    } else if (RegExp(r'记忆|了解我|记住', caseSensitive: false).hasMatch(prompt)) {
      answer = _memoryAnswer(request);
    } else if (RegExp(r'代码|python|dart|程序|脚本', caseSensitive: false).hasMatch(prompt)) {
      answer = _codeAnswer(prompt);
    } else if (RegExp(r'计划|规划|安排|方案', caseSensitive: false).hasMatch(prompt)) {
      answer = _planAnswer(prompt);
    } else {
      answer = _generalAnswer(prompt, lastUser.images.length);
    }

    for (final chunk in _chunks(answer)) {
      yield TextDelta(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 9));
    }
    yield UsageReported(
      inputTokens: estimateDemoTokens(request.systemPrompt) +
          request.messages.fold<int>(0, (sum, m) => sum + estimateDemoTokens(m.text)),
      outputTokens: estimateDemoTokens(reasoning + answer),
    );
    yield TurnCompleted(finishReason: 'stop');
  }

  String _searchQuery(String prompt) {
    final compact = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 80 ? compact.substring(0, 80) : compact;
  }

  String _reasoningFor(LlmRequest request, String prompt) {
    if (request.reasoningLevel == ReasoningLevel.off) return '';
    final core = prompt.isEmpty ? '用户还没有输入内容。' : '用户的问题是“${truncateDemo(prompt, 42)}”。';
    final base = '$core 这是演示模式，不会调用真实模型；我会展示 Lumen 的流式输出、思考过程、Markdown 与工具卡片。';
    return _shortReasoning(request.reasoningLevel, base);
  }

  String _shortReasoning(ReasoningLevel level, String base) {
    if (level == ReasoningLevel.off) return '';
    switch (level) {
      case ReasoningLevel.low:
        return base;
      case ReasoningLevel.medium:
        return '$base\n我先判断问题类型，再决定是直接回答、给出结构，还是先调用工具。';
      case ReasoningLevel.high:
        return '$base\n我会先确认关键约束，再给出可验证的步骤；如果信息不足，会明确说明假设。';
      case ReasoningLevel.xhigh:
      case ReasoningLevel.max:
        return '$base\n我会把问题拆成目标、约束、可选路径和验证方式，避免只给一个看似正确但没有依据的答案。';
      default:
        return base;
    }
  }

  Stream<LlmEvent> _streamReasoning(String reasoning, ReasoningLevel level) async* {
    if (reasoning.isEmpty) return;
    for (final chunk in _chunks(reasoning, size: 14)) {
      yield ReasoningDelta(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 18));
    }
  }

  Iterable<String> _chunks(String text, {int size = 12}) sync* {
    var index = 0;
    while (index < text.length) {
      final end = (index + size).clamp(0, text.length);
      yield text.substring(index, end);
      index = end;
    }
  }

  String _generalAnswer(String prompt, int imageCount) {
    final quoted = prompt.isEmpty ? '你的问题' : '“${truncateDemo(prompt, 60)}”';
    final imageNote = imageCount > 0 ? '\n\n我收到了 **$imageCount 张图片**。演示模式不会做真实视觉识别；接入支持视觉的模型后，图片会随消息一起发送。' : '';
    return '''
## 先说结论

这是 **Lumen 演示模式** 的回复。它用于展示完整的对话体验，不会调用真实模型，也不消耗 API 额度。你可以在「设置 → 模型与厂商」填入任意平台的 Key，然后切换到对应模型。

针对 $quoted，真实模型会在这里给出有依据、可执行的答案。演示回复主要展示以下几件事：

| 能力 | 表现 |
|---|---|
| 流式输出 | 文字与思考过程逐块到达 |
| Markdown | 标题、列表、表格、引用、代码块 |
| 数学公式 | 行内 \$E = mc^2\$ 与块级公式 |
| 工具调用 | 开启联网后可展示搜索卡片与来源 |
| 长期记忆 | 画像与记忆会注入系统提示（可在记忆页查看） |

### 一个可验证的小例子

```dart
Future<void> main() async {
  final answer = await think(
    question: '我真正想解决的是什么？',
    constraints: ['时间有限', '信息不完整'],
  );
  print(answer);
}
```

块级公式：

\$\$
\\text{清晰度} = \\frac{\\text{可验证的结论}}{\\text{未说明的假设} + 1}
\$\$

> 演示模式的意义是把交互跑通：流式、记忆、搜索、MCP、生图都可以先看到形状，再接入真实能力。$imageNote

如果你愿意，可以告诉我一个具体问题，我会用真实的结构化方式继续拆解。
''';
  }

  String _memoryAnswer(LlmRequest request) {
    final section = _extractMemorySection(request.systemPrompt);
    if (section.isEmpty) {
      return '''
## 目前还没有长期记忆

我们还没有进行足够的对话，所以画像和记忆都是空的。你可以：

1. 在「记忆」页手动添加一条关于自己的信息；
2. 正常聊天，Lumen 会在几轮后自动提取稳定的偏好与背景；
3. 点击记忆页的「填入示例」查看完整效果（仅用于演示）。

> 记忆保存在本机，不会上传到 Lumen 的服务器；但注入上下文时，相关内容会发送给你选择的模型厂商。
''';
    }
    return '''
## 根据当前注入的长期记忆

$section

### 我会怎样使用这些信息

- 在相关话题里自然调整解释深度与例子，而不是每轮复述；
- 当你明确改变偏好时，以更新的信息为准；
- 对可能过时或不确定的记忆，先向你确认，而不是当成事实。

> 以上内容来自本机记忆库。你可以在「记忆」页编辑、置顶或删除任何一条。
''';
  }

  String _extractMemorySection(String systemPrompt) {
    final marker = '## 你了解的用户';
    final index = systemPrompt.indexOf(marker);
    if (index < 0) return '';
    final rest = systemPrompt.substring(index + marker.length);
    final next = rest.indexOf('\n## ');
    final body = (next >= 0 ? rest.substring(0, next) : rest).trim();
    if (body.isEmpty || body.contains('（暂无')) return '';
    return body.length > 900 ? '${body.substring(0, 900)}…' : body;
  }

  String _searchAnswer(String toolResult, String prompt) {
    final sources = RegExp(r'^标题：', multiLine: true).allMatches(toolResult).length;
    if (sources == 0) {
      return '''
## 搜索没有返回可读结果

请检查「设置 → 联网搜索」中的搜索服务配置，或换一个搜索源再试。

> 当前是演示回复；搜索工具本身已经执行。
''';
    }
    return '''
## 搜索完成

我根据你的问题完成了联网搜索，拿到 $sources 个可读网页。完整来源已经收在回答下方的“$sources 个网页”里，展开就能查看标题、域名和发布时间。

### 怎么读这次结果

- 真实模型会综合这些网页的内容，先给结论，再分点解释关键事实与差异；
- 回答正文不会插入来源编号或网址列表，来源统一放在下方折叠卡片里；
- 如果多个来源冲突，优先采用一手来源，并说明分歧。

> 当前是演示回复；搜索本身是真实执行的，结果取决于你配置的搜索服务。
''';
  }

  String _codeAnswer(String prompt) {
    return '''
## 一个可运行的最小实现

下面用 Dart 写一个带超时与重试的请求函数，重点不是代码本身，而是**边界条件**：

```dart
Future<String> fetchWithRetry(
  Future<String> Function() request, {
  int attempts = 3,
}) async {
  Object? lastError;
  for (var i = 0; i < attempts; i++) {
    try {
      return await request().timeout(const Duration(seconds: 30));
    } catch (error) {
      lastError = error;
      if (i < attempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }
  }
  throw StateError('请求失败：\$lastError');
}
```

### 关键点

1. **超时**：没有超时的网络请求会把 UI 卡在“加载中”；
2. **退避**：重试间隔递增，避免在 429 时继续加压；
3. **错误保真**：保留最后一次错误，不要把根因吞掉。

针对你的问题“${truncateDemo(prompt, 48)}”，接入真实模型后我可以继续补上参数校验、取消与单元测试。
''';
  }

  String _planAnswer(String prompt) {
    return '''
## 一个可执行的拆解

先不急着给“完整方案”。针对“${truncateDemo(prompt, 52)}”，建议按下面的顺序推进：

### 1. 明确目标与约束

- 你希望得到的结果是什么？用一句话写下来；
- 截止时间、预算、必须满足的条件分别是什么；
- 哪些事情是**不能牺牲**的。

### 2. 找出关键不确定性

| 假设 | 验证方式 | 成本 |
|---|---|---|
| 用户真的需要这个功能 | 5 次访谈 | 低 |
| 现有方案无法满足 | 对比 3 个替代品 | 中 |
| 团队能在两周内交付 | 拆出最小版本 | 中 |

### 3. 设计最小验证

不要一次做完整方案。先做一个能在 **3 天内**得到反馈的小实验，把“是否继续”变成可观察的结果。

### 4. 复盘与扩展

- 哪些假设被证实/推翻？
- 下一步是加码、转向，还是停止？

> 如果你愿意补充目标、时间和资源约束，我可以把上面的框架变成具体的周计划。
''';
  }
}

int estimateDemoTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.runes.length / 2.2).ceil();
}

String truncateDemo(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max)}…';
