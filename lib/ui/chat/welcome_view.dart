import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/defaults.dart';
import '../../services/chat_session.dart';
import '../common/widgets.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.session,
    required this.onSuggestion,
    required this.onConfigure,
  });

  final ChatSession session;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDemo = session.selection.provider.demo;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 700;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: narrow ? 18 : 28, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LumenMark(size: 58),
              const SizedBox(height: 20),
              Text(
                '你好，我是 Lumen',
                textAlign: TextAlign.center,
                style: context.text.displaySmall?.copyWith(
                  fontSize: narrow ? 27 : 32,
                  letterSpacing: -0.9,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '一个会记住你的 AI 伙伴。今天想聊点什么？',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: c.textSecondary,
                  fontSize: narrow ? 13.5 : 14.5,
                ),
              ),
              const SizedBox(height: 13),
              if (isDemo)
                Material(
                  color: c.primarySoft,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: onConfigure,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.science_outlined, size: 14, color: c.primary),
                          const SizedBox(width: 6),
                          Text(
                            '演示模式 · 不会调用真实模型',
                            style: context.text.labelSmall?.copyWith(
                              color: c.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 12, color: c.primary),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 13, color: c.textTertiary),
                    const SizedBox(width: 5),
                    Text(
                      '${session.selection.provider.name} · ${session.selection.model.name}',
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: const [
                  CapabilityChip(label: '长期记忆', icon: Icons.auto_awesome_outlined, color: Color(0xFF5B7CFA)),
                  CapabilityChip(label: '多厂商模型', icon: Icons.hub_outlined, color: Color(0xFF13A88A)),
                  CapabilityChip(label: '联网搜索', icon: Icons.travel_explore_rounded, color: Color(0xFFE08A00)),
                  CapabilityChip(label: 'MCP 工具', icon: Icons.extension_outlined, color: Color(0xFF7A5CFF)),
                  CapabilityChip(label: '图像生成', icon: Icons.image_outlined, color: Color(0xFFEC4899)),
                ],
              ),
              SizedBox(height: narrow ? 24 : 34),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 ? 2 : 1;
                  final gap = 10.0;
                  final cardWidth = columns == 2
                      ? (constraints.maxWidth - gap) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final suggestion in welcomeSuggestions)
                        SizedBox(
                          width: cardWidth,
                          child: _SuggestionCard(
                            suggestion: suggestion,
                            onTap: () => onSuggestion(suggestion.prompt),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 12, color: c.textTertiary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '对话与记忆保存在本机；API Key 使用系统安全存储加密。',
                      textAlign: TextAlign.center,
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatefulWidget {
  const _SuggestionCard({required this.suggestion, required this.onTap});

  final PromptSuggestion suggestion;
  final VoidCallback onTap;

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final suggestion = widget.suggestion;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: _hover ? c.surfaceAlt : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hover ? c.borderStrong : c.border),
          boxShadow: _hover
              ? [BoxShadow(color: c.shadow, blurRadius: 18, offset: const Offset(0, 5))]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: suggestion.tint.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(suggestion.icon, size: 19, color: suggestion.tint),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.title,
                          style: context.text.labelLarge?.copyWith(fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          suggestion.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(
                            color: c.textTertiary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedOpacity(
                    opacity: _hover ? 1 : 0.4,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.arrow_outward_rounded, size: 15, color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
