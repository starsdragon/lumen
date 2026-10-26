import '../../data/models.dart';

ReasoningStyle effectiveReasoningStyle(ProviderConfig provider) {
  if (provider.reasoningStyle != ReasoningStyle.auto) return provider.reasoningStyle;
  final host = Uri.tryParse(provider.baseUrl)?.host.toLowerCase() ?? '';
  if (host.contains('openrouter.ai')) return ReasoningStyle.openrouter;
  if (host.contains('deepseek.com')) return ReasoningStyle.deepseek;
  if (host.contains('bigmodel.cn') || host.contains('zhipu')) return ReasoningStyle.zhipu;
  if (host.contains('moonshot.cn') || host.contains('kimi.com')) return ReasoningStyle.moonshot;
  if (host.contains('dashscope.aliyuncs.com') || host.contains('aliyuncs.com')) {
    return ReasoningStyle.qwen;
  }
  if (host.contains('minimaxi.com') || host.contains('minimax.io')) {
    return ReasoningStyle.minimax;
  }
  if (host.contains('opencode.ai')) return ReasoningStyle.openai;
  return switch (provider.id) {
    'deepseek' => ReasoningStyle.deepseek,
    'zhipu' => ReasoningStyle.zhipu,
    'kimi' => ReasoningStyle.moonshot,
    'bailian' => ReasoningStyle.qwen,
    'minimax' => ReasoningStyle.minimax,
    'openrouter' => ReasoningStyle.openrouter,
    _ => ReasoningStyle.openai,
  };
}

String _effortForOpenAi(ReasoningLevel level) => switch (level) {
      ReasoningLevel.off => 'none',
      ReasoningLevel.auto => 'auto',
      ReasoningLevel.low => 'low',
      ReasoningLevel.medium => 'medium',
      ReasoningLevel.high => 'high',
      ReasoningLevel.xhigh => 'high',
      ReasoningLevel.max => 'high',
    };

String _effortForQwen(ReasoningLevel level) => switch (level) {
      ReasoningLevel.off => 'none',
      ReasoningLevel.auto => 'auto',
      ReasoningLevel.low => 'low',
      ReasoningLevel.medium => 'medium',
      ReasoningLevel.high => 'high',
      ReasoningLevel.xhigh => 'high',
      ReasoningLevel.max => 'high',
    };

String _effortForDeepSeek(ReasoningLevel level) => switch (level) {
      ReasoningLevel.off => 'none',
      ReasoningLevel.auto => 'auto',
      ReasoningLevel.low => 'low',
      ReasoningLevel.medium => 'high',
      ReasoningLevel.high => 'high',
      ReasoningLevel.xhigh => 'xhigh',
      ReasoningLevel.max => 'max',
    };

bool _kimiSupportsKeep(String modelId) {
  final id = modelId.toLowerCase();
  return RegExp(r'k2[.\-_]?(6|[7-9])').hasMatch(id);
}

/// Parameters for OpenAI-compatible endpoints. The mapping follows each
/// platform's current API contract (DeepSeek thinking, Zhipu/Kimi thinking,
/// DashScope reasoning_effort, OpenRouter reasoning, etc.).
Map<String, dynamic> openAiReasoningParams(
  ProviderConfig provider,
  ModelInfo model,
  ReasoningLevel level,
) {
  if (!model.reasoning) return const {};
  final style = effectiveReasoningStyle(provider);
  switch (style) {
    case ReasoningStyle.none:
      return const {};
    case ReasoningStyle.deepseek:
      final params = <String, dynamic>{
        'thinking': {'type': level.isEnabled ? 'enabled' : 'disabled'},
      };
      if (level.isEnabled && level != ReasoningLevel.auto) {
        params['reasoning_effort'] = _effortForDeepSeek(level);
      }
      return params;
    case ReasoningStyle.zhipu:
      return {
        'thinking': {'type': level.isEnabled ? 'enabled' : 'disabled'},
      };
    case ReasoningStyle.moonshot:
      final thinking = <String, dynamic>{
        'type': level.isEnabled ? 'enabled' : 'disabled',
      };
      if (level.isEnabled && _kimiSupportsKeep(model.id)) {
        thinking['keep'] = 'all';
      }
      return {'thinking': thinking};
    case ReasoningStyle.qwen:
      if (level == ReasoningLevel.auto) return const {};
      return {'reasoning_effort': _effortForQwen(level)};
    case ReasoningStyle.minimax:
      if (level == ReasoningLevel.auto) return const {};
      return {'reasoning_effort': _effortForOpenAi(level)};
    case ReasoningStyle.openrouter:
      return {
        'reasoning': switch (level) {
          ReasoningLevel.off => {'effort': 'none'},
          ReasoningLevel.auto => {'enabled': true},
          _ => {'effort': level.effort},
        },
      };
    case ReasoningStyle.openai:
    case ReasoningStyle.auto:
      if (level == ReasoningLevel.auto) return const {};
      return {'reasoning_effort': _effortForOpenAi(level)};
  }
}

const reasoningParameterKeys = <String>[
  'thinking',
  'reasoning_effort',
  'reasoning',
  'thinking_budget',
  'enable_thinking',
  'thinking_mode',
  'output_config',
];

Map<String, dynamic> stripReasoningParams(Map<String, dynamic> body) {
  final copy = Map<String, dynamic>.from(body);
  for (final key in reasoningParameterKeys) {
    copy.remove(key);
  }
  return copy;
}

/// Anthropic's current API uses adaptive thinking + output_config.effort for
/// current models. Older models still accept a fixed thinking budget; the
/// client retries with that shape if the first request is rejected.
Map<String, dynamic> anthropicThinkingParams(ModelInfo model, ReasoningLevel level) {
  if (!model.reasoning) return const {};
  return switch (level) {
    ReasoningLevel.off => {
        'thinking': {'type': 'disabled'},
      },
    ReasoningLevel.auto => {
        'thinking': {'type': 'adaptive', 'display': 'summarized'},
      },
    _ => {
        'thinking': {'type': 'adaptive', 'display': 'summarized'},
        'output_config': {'effort': level.effort},
      },
  };
}

Map<String, dynamic> legacyAnthropicThinkingParams(ReasoningLevel level) {
  if (!level.isEnabled) return const {};
  final budget = level == ReasoningLevel.auto ? 4000 : level.budgetTokens;
  return {
    'thinking': {'type': 'enabled', 'budget_tokens': budget.clamp(1024, 60000)},
  };
}

bool geminiUsesThinkingLevel(String modelId) {
  final id = modelId.toLowerCase();
  return RegExp(r'gemini[-_]?(3|4)([.\-]|$|[-_]?(pro|flash))').hasMatch(id) ||
      id.contains('gemini-3') ||
      id.contains('gemini-4');
}

Map<String, dynamic>? geminiThinkingConfig(ModelInfo model, ReasoningLevel level) {
  if (!model.reasoning) return null;
  final usesLevel = geminiUsesThinkingLevel(model.id);
  final isPro = RegExp(r'2[.\-]5.*pro', caseSensitive: false).hasMatch(model.id);
  switch (level) {
    case ReasoningLevel.auto:
      return {'includeThoughts': true};
    case ReasoningLevel.off:
      if (usesLevel) {
        return {'includeThoughts': true, 'thinkingLevel': 'minimal'};
      }
      if (!isPro) {
        return {'includeThoughts': false, 'thinkingBudget': 0};
      }
      return {'includeThoughts': true};
    case ReasoningLevel.low:
      return usesLevel
          ? {'includeThoughts': true, 'thinkingLevel': 'low'}
          : {'includeThoughts': true, 'thinkingBudget': 1000};
    case ReasoningLevel.medium:
      return usesLevel
          ? {'includeThoughts': true, 'thinkingLevel': 'medium'}
          : {'includeThoughts': true, 'thinkingBudget': 2000};
    case ReasoningLevel.high:
    case ReasoningLevel.xhigh:
    case ReasoningLevel.max:
      return usesLevel
          ? {'includeThoughts': true, 'thinkingLevel': 'high'}
          : {'includeThoughts': true, 'thinkingBudget': level.budgetTokens};
  }
}
