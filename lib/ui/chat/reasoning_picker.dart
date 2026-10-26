import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/api/reasoning_params.dart';
import '../common/widgets.dart';

Future<ReasoningLevel?> showReasoningPicker(
  BuildContext context, {
  required ReasoningLevel current,
  required ProviderConfig provider,
  required ModelInfo model,
}) {
  return showLumenSheet<ReasoningLevel>(
    context: context,
    builder: (context) => _ReasoningSheet(
      current: current,
      provider: provider,
      model: model,
    ),
  );
}

class _ReasoningSheet extends StatefulWidget {
  const _ReasoningSheet({
    required this.current,
    required this.provider,
    required this.model,
  });

  final ReasoningLevel current;
  final ProviderConfig provider;
  final ModelInfo model;

  @override
  State<_ReasoningSheet> createState() => _ReasoningSheetState();
}

class _ReasoningSheetState extends State<_ReasoningSheet> {
  late ReasoningLevel _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = effectiveReasoningStyle(widget.provider);
    final mapping = widget.provider.protocol == LlmProtocol.anthropic
        ? 'Anthropic：adaptive thinking + output_config.effort'
        : widget.provider.protocol == LlmProtocol.gemini
            ? 'Gemini：thinkingLevel / thinkingBudget'
            : switch (style) {
                ReasoningStyle.deepseek => 'DeepSeek：thinking.type + reasoning_effort',
                ReasoningStyle.zhipu => '智谱：thinking.type',
                ReasoningStyle.moonshot => 'Kimi：thinking.type（K2.6 自动保留思考）',
                ReasoningStyle.qwen => '百炼：reasoning_effort',
                ReasoningStyle.openrouter => 'OpenRouter：reasoning.effort',
                ReasoningStyle.minimax => 'MiniMax：reasoning_effort',
                ReasoningStyle.none => '该厂商不发送思考参数',
                _ => 'OpenAI 兼容：reasoning_effort',
              };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.psychology_alt_outlined, size: 20, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('思考强度', style: context.text.titleLarge),
                    Text(
                      widget.model.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '档位会按当前厂商的官方参数映射；厂商不支持的档位会自动降级或忽略。',
            style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.55),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                for (final level in ReasoningLevelX.selectable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: _selected == level ? c.primarySoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => setState(() => _selected = level),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              _LevelDots(level: level, selected: _selected == level),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      level.label,
                                      style: context.text.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: _selected == level ? c.primary : c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      level.hint,
                                      style: context.text.labelSmall?.copyWith(
                                        color: c.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_selected == level)
                                Icon(Icons.check_rounded, size: 18, color: c.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: c.primarySoft.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: c.primary.withValues(alpha: 0.14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mapping,
                        style: context.text.labelSmall?.copyWith(
                          color: c.primary,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '强度越高，思考时间与费用通常越高；简单问题建议“自动”或“轻量”。',
                        style: context.text.labelSmall?.copyWith(
                          color: c.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('应用'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelDots extends StatelessWidget {
  const _LevelDots({required this.level, required this.selected});

  final ReasoningLevel level;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = switch (level) {
      ReasoningLevel.off => 0,
      ReasoningLevel.auto => 1,
      ReasoningLevel.low => 2,
      ReasoningLevel.medium => 3,
      ReasoningLevel.high => 4,
      ReasoningLevel.xhigh => 5,
      ReasoningLevel.max => 6,
    };
    return SizedBox(
      width: 30,
      height: 30,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 2,
        children: List.generate(7, (index) {
          final filled = index < count;
          return Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (selected ? c.primary : c.textSecondary)
                  : c.borderStrong,
            ),
          );
        }),
      ),
    );
  }
}
