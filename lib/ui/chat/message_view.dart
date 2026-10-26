import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/file_import_service.dart';
import '../common/widgets.dart';
import '../markdown/markdown_view.dart';

class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    this.isLastAssistant = false,
    this.busy = false,
    this.imagePrompt,
    this.onRegenerate,
    this.onRemember,
    this.onConfigure,
  });

  final ChatMessage message;
  final bool isLastAssistant;
  final bool busy;
  final String? imagePrompt;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRemember;
  final VoidCallback? onConfigure;

  bool get _streaming => message.isStreaming;

  @override
  Widget build(BuildContext context) {
    if (message.role == ChatRole.user) return _UserMessage(message: message);
    return _AssistantMessage(
      message: message,
      isLastAssistant: isLastAssistant,
      busy: busy,
      imagePrompt: imagePrompt,
      onRegenerate: onRegenerate,
      onRemember: onRemember,
      onConfigure: onConfigure,
      streaming: _streaming,
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxWidth = MediaQuery.sizeOf(context).width < 700 ? 0.86 : 0.74;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 22),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _AttachmentWrap(
                  attachments: message.attachments,
                  alignEnd: true,
                  generated: message.attachments.any((a) => a.generated),
                ),
              ),
            if (message.text.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
                decoration: BoxDecoration(
                  color: c.userBubble,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(17),
                    topRight: Radius.circular(17),
                    bottomLeft: Radius.circular(17),
                    bottomRight: Radius.circular(5),
                  ),
                ),
                child: SelectableText(
                  message.text,
                  style: context.text.bodyLarge?.copyWith(
                    color: c.userBubbleText,
                    fontSize: 15.5,
                    height: 1.62,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      await copyText(context, message.text, message: '已复制');
                    },
                    child: Icon(Icons.copy_rounded, size: 12, color: c.textTertiary),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    formatClock(message.createdAt),
                    style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({
    required this.message,
    required this.isLastAssistant,
    required this.busy,
    required this.streaming,
    this.imagePrompt,
    this.onRegenerate,
    this.onRemember,
    this.onConfigure,
  });

  final ChatMessage message;
  final bool isLastAssistant;
  final bool busy;
  final bool streaming;
  final String? imagePrompt;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRemember;
  final VoidCallback? onConfigure;

  bool get _hasContent =>
      message.text.trim().isNotEmpty || message.reasoning.trim().isNotEmpty || message.attachments.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showActions = !streaming && _hasContent && message.error == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: LumenMark(size: 25, radius: 8),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Lumen',
                      style: context.text.labelLarge?.copyWith(
                        fontSize: 12.5,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (message.modelLabel.trim().isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·', style: context.text.labelSmall?.copyWith(color: c.textTertiary)),
                      ),
                      Flexible(
                        child: Text(
                          message.modelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                        ),
                      ),
                    ],
                    if (message.isImageGeneration) ...[
                      const SizedBox(width: 6),
                      const CapabilityChip(label: '图像生成', color: Color(0xFF7A5CFF)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (message.reasoning.trim().isNotEmpty)
                  _ThinkingPanel(
                    reasoning: message.reasoning,
                    streaming: streaming,
                    seconds: message.reasoningSeconds,
                  ),
                if (message.toolCalls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final call in message.toolCalls) _ToolCard(call: call),
                ],
                if (message.isImageGeneration)
                  _GeneratedImageCard(
                    message: message,
                    busy: busy && message.attachments.isEmpty && message.error == null,
                    prompt: imagePrompt,
                  )
                else if (message.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: MarkdownView(text: message.text, isStreaming: streaming),
                  )
                else if (streaming && message.toolCalls.isEmpty)
                  const _TypingIndicator()
                else if (streaming && message.toolCalls.isNotEmpty)
                  _WorkingIndicator(calls: message.toolCalls, startedAt: message.createdAt),
                if (message.attachments.isNotEmpty && !message.isImageGeneration)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _AttachmentWrap(attachments: message.attachments),
                  ),
                if (message.error != null) ...[
                  const SizedBox(height: 8),
                  _ErrorCard(
                    error: message.error!,
                    onRetry: onRegenerate,
                    onConfigure: onConfigure,
                  ),
                ],
                if (message.citations.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _Citations(citations: message.citations),
                ],
                if (showActions)
                  _MessageActions(
                    message: message,
                    isLastAssistant: isLastAssistant,
                    onRegenerate: onRegenerate,
                    onRemember: onRemember,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingPanel extends StatefulWidget {
  const _ThinkingPanel({required this.reasoning, required this.streaming, required this.seconds});

  final String reasoning;
  final bool streaming;
  final int seconds;

  @override
  State<_ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<_ThinkingPanel> {
  late bool _expanded = widget.streaming;
  bool _userToggled = false;

  @override
  void didUpdateWidget(covariant _ThinkingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streaming && !widget.streaming && !_userToggled) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = widget.streaming
        ? '正在思考…'
        : widget.seconds > 0
            ? '已思考 ${widget.seconds} 秒'
            : '思考过程';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() {
                _expanded = !_expanded;
                _userToggled = true;
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 10, 8),
                child: Row(
                  children: [
                    Icon(
                      widget.streaming ? Icons.auto_awesome_rounded : Icons.psychology_alt_outlined,
                      size: 15,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        style: context.text.labelMedium?.copyWith(
                          color: c.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (widget.streaming)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: c.textTertiary,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 17,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _expanded
                  ? Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 11),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          widget.reasoning,
                          style: context.text.bodySmall?.copyWith(
                            color: c.textSecondary,
                            height: 1.65,
                            fontSize: 12.3,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.call});

  final ToolCallRecord call;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _expanded = false;

  IconData get _icon {
    final name = widget.call.name;
    if (name == 'web_search') return Icons.travel_explore_rounded;
    if (name == 'fetch_url') return Icons.link_rounded;
    if (name.startsWith('save_memory') || name.startsWith('search_memory')) {
      return Icons.auto_awesome_outlined;
    }
    return Icons.extension_outlined;
  }

  String get _subtitle {
    Map<String, dynamic>? args;
    try {
      final decoded = jsonDecode(widget.call.argumentsJson);
      if (decoded is Map) args = decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      // Ignore malformed args.
    }
    if (args != null) {
      if (args['query'] != null) return '${args['query']}';
      if (args['url'] != null) return '${args['url']}';
      if (args['content'] != null) return compactText('${args['content']}', 70);
      if (args['name'] != null) return '${args['name']}';
      final values = args.entries.take(2).map((e) => '${e.key}: ${e.value}').join(' · ');
      if (values.isNotEmpty) return values;
    }
    if (widget.call.resultText.trim().isNotEmpty) return compactText(widget.call.resultText, 90);
    return '准备调用工具';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final call = widget.call;
    final statusColor = call.isError
        ? c.danger
        : call.status == ToolCallStatus.success
            ? c.success
            : c.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 9, 9),
                child: Row(
                  children: [
                    Container(
                      width: 27,
                      height: 27,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_icon, size: 15, color: statusColor),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            call.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (call.status == ToolCallStatus.running || call.status == ToolCallStatus.pending)
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.7, color: c.primary),
                      )
                    else
                      Icon(
                        call.isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                        size: 15,
                        color: statusColor,
                      ),
                    if (call.durationMs > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Text(
                          '${(call.durationMs / 1000).toStringAsFixed(1)}s',
                          style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9.5),
                        ),
                      ),
                    const SizedBox(width: 3),
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              child: _expanded
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (call.argumentsJson.trim().isNotEmpty)
                            _ToolField(label: '参数', value: _prettyJson(call.argumentsJson)),
                          if (call.resultText.trim().isNotEmpty)
                            _ToolField(
                              label: call.isError ? '错误' : '结果',
                              value: truncate(call.resultText, 4000),
                              color: call.isError ? c.danger : null,
                            ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  String _prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }
}

class _ToolField extends StatelessWidget {
  const _ToolField({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 170),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                value,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontFamilyFallback: const ['NotoSansSC', 'monospace'],
                  fontSize: 10.5,
                  height: 1.5,
                  color: color ?? c.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratedImageCard extends StatelessWidget {
  const _GeneratedImageCard({required this.message, required this.busy, this.prompt});

  final ChatMessage message;
  final bool busy;
  final String? prompt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (busy) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 26, color: c.primary),
            const SizedBox(height: 10),
            Text('正在生成图片…', style: context.text.bodyMedium),
            const SizedBox(height: 4),
            Text(
              prompt == null ? '这可能需要 10–60 秒' : compactText(prompt!, 70),
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(minHeight: 3),
              ),
            ),
          ],
        ),
      );
    }
    if (message.attachments.isEmpty) return const SizedBox.shrink();
    final attachment = message.attachments.first;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = math.min(constraints.maxWidth, 460.0);
                return Center(
                  child: AttachmentImage(
                    attachment: attachment,
                    width: width,
                    radius: 0,
                    fit: BoxFit.contain,
                    onTap: () => openImageViewer(context, attachment, caption: message.text),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 10, 8, 9),
              child: Row(
                children: [
                  const CapabilityChip(label: 'AI 生成', color: Color(0xFF7A5CFF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.text.trim().isEmpty ? '点击图片查看大图' : message.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                    ),
                  ),
                  IconButton(
                    tooltip: '保存图片',
                    icon: const Icon(Icons.download_rounded, size: 18),
                    onPressed: () async {
                      final bytes = decodeDataUrl(attachment.dataUrl);
                      if (bytes == null) return;
                      final ok = await saveBytesToDevice(
                        bytes,
                        sanitizeFileName(attachment.name),
                        mime: attachment.mime,
                      );
                      if (context.mounted && ok) showToast(context, '已保存');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentWrap extends StatelessWidget {
  const _AttachmentWrap({required this.attachments, this.alignEnd = false, this.generated = false});

  final List<Attachment> attachments;
  final bool alignEnd;
  final bool generated;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final images = attachments.where((a) => a.isImage).toList();
    final files = attachments.where((a) => a.isFile).toList();
    final imageWidget = images.isEmpty
        ? const SizedBox.shrink()
        : images.length == 1
            ? Align(
                alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360, maxHeight: 280),
                  child: AttachmentImage(
                    attachment: images.first,
                    radius: 14,
                    fit: BoxFit.contain,
                    onTap: () => openImageViewer(context, images.first),
                  ),
                ),
              )
            : Wrap(
                alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final attachment in images)
                    AttachmentImage(
                      attachment: attachment,
                      width: 108,
                      height: 108,
                      radius: 11,
                      onTap: () => openImageViewer(context, attachment),
                    ),
                ],
              );
    if (files.isEmpty) return imageWidget;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final file in files) _FileAttachmentChip(attachment: file),
          ],
        ),
        if (images.isNotEmpty) ...[const SizedBox(height: 6), imageWidget],
      ],
    );
  }
}

class _FileAttachmentChip extends StatelessWidget {
  const _FileAttachmentChip({required this.attachment});

  final Attachment attachment;

  IconData get _icon {
    final name = attachment.name.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.docx')) return Icons.description_outlined;
    if (name.endsWith('.xlsx')) return Icons.table_chart_outlined;
    if (name.endsWith('.pptx')) return Icons.slideshow_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showFilePreviewDialog(context, attachment),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.fromLTRB(9, 7, 10, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 17, color: c.primary),
              const SizedBox(width: 7),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${formatFileSize(attachment.sizeBytes)} · ${attachment.extractedText.length} 字',
                      style: context.text.labelSmall?.copyWith(
                        color: c.textTertiary,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.visibility_outlined, size: 14, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, this.onRetry, this.onConfigure});

  final String error;
  final VoidCallback? onRetry;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final needsKey = error.contains('API Key') ||
        error.contains('Key') ||
        error.contains('配置') ||
        error.contains('厂商');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.danger.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
              const SizedBox(width: 7),
              Expanded(
                child: SelectableText(
                  error,
                  style: context.text.bodySmall?.copyWith(color: c.danger, height: 1.5),
                ),
              ),
            ],
          ),
          if (onRetry != null || (needsKey && onConfigure != null))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (needsKey && onConfigure != null)
                    TextButton(
                      onPressed: onConfigure,
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      child: const Text('配置厂商'),
                    ),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('重试'),
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Citations extends StatelessWidget {
  const _Citations({required this.citations});

  final List<Citation> citations;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final previews = citations.take(3).toList();
    final width = 14.0 * (previews.length - 1) + 22;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showSourcesSheet(context, citations),
          child: Container(
            height: 34,
            padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: width,
                  height: 22,
                  child: Stack(
                    children: [
                      for (var i = 0; i < previews.length; i++)
                        Positioned(
                          left: i * 14.0,
                          child: _SourceBadge(citation: previews[i], size: 22, border: c.surfaceAlt),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${citations.length} 个网页',
                  style: context.text.labelSmall?.copyWith(
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 15, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSourcesSheet(BuildContext context, List<Citation> citations) {
  return showLumenSheet<void>(
    context: context,
    builder: (context) => _SourcesSheet(citations: citations),
  );
}

class _SourcesSheet extends StatelessWidget {
  const _SourcesSheet({required this.citations});

  final List<Citation> citations;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 6),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.travel_explore_rounded, size: 19, color: c.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('搜索结果', style: context.text.titleLarge),
                      Text(
                        '点击来源查看详情，再确认是否打开网页',
                        style: context.text.labelSmall?.copyWith(color: c.textTertiary),
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
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
              itemCount: citations.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
              itemBuilder: (context, index) => _SourceRow(
                citation: citations[index],
                index: index + 1,
                onOpen: () => _confirmOpenSource(context, citations[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.citation, required this.index, required this.onOpen});

  final Citation citation;
  final int index;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final host = _sourceHost(citation.url);
    final date = _sourceDate(citation.publishedAt);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SourceBadge(citation: citation, size: 36, border: c.background),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          citation.title.isEmpty ? host : citation.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.border),
                        ),
                        child: Text(
                          '$index',
                          style: context.text.labelSmall?.copyWith(
                            color: c.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.language_rounded, size: 12, color: c.textTertiary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                        ),
                      ),
                      if (date.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        Text(
                          date,
                          style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                        ),
                      ],
                    ],
                  ),
                  if (citation.snippet.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      citation.snippet,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: c.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new_rounded, size: 15, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.citation, required this.size, required this.border});

  final Citation citation;
  final double size;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final host = _sourceHost(citation.url);
    final letter = host.isEmpty ? '?' : host.substring(0, 1).toUpperCase();
    final color = _sourceColor(host);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

const _sourcePalette = [
  Color(0xFF5B7CFA),
  Color(0xFF13A88A),
  Color(0xFFE08A00),
  Color(0xFFEC4899),
  Color(0xFF7A5CFF),
  Color(0xFF0EA5E9),
  Color(0xFFEF4444),
];

Color _sourceColor(String host) {
  if (host.isEmpty) return _sourcePalette.first;
  var hash = 0;
  for (final unit in host.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _sourcePalette[hash % _sourcePalette.length];
}

String _sourceHost(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host.replaceFirst(RegExp(r'^www\.'), '');
}

String _sourceDate(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final parsed = DateTime.tryParse(value);
  if (parsed != null) {
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}/$month/$day';
  }
  if (value.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)) {
    return value.substring(0, 10).replaceAll('-', '/');
  }
  return value.length > 16 ? value.substring(0, 16) : value;
}

Future<void> _confirmOpenSource(BuildContext context, Citation citation) async {
  final c = context.colors;
  final host = _sourceHost(citation.url);
  final date = _sourceDate(citation.publishedAt);
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          _SourceBadge(citation: citation, size: 32, border: c.surface),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              citation.title.isEmpty ? host : citation.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language_rounded, size: 14, color: c.textTertiary),
                const SizedBox(width: 5),
                Text(host, style: context.text.labelSmall?.copyWith(color: c.textTertiary)),
                if (date.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(date, style: context.text.labelSmall?.copyWith(color: c.textTertiary)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                citation.url,
                style: context.text.labelSmall?.copyWith(color: c.textSecondary, height: 1.45),
              ),
            ),
            if (citation.snippet.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                citation.snippet,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.55),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '打开后会离开 Lumen，进入外部浏览器。请确认来源可信。',
              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: const Text('打开网页'),
        ),
      ],
    ),
  );
  if (open != true || !context.mounted) return;
  try {
    await launchUrl(Uri.parse(citation.url), mode: LaunchMode.externalApplication);
  } catch (_) {
    if (context.mounted) showToast(context, '无法打开这个链接。');
  }
}

class _WorkingIndicator extends StatefulWidget {
  const _WorkingIndicator({required this.calls, required this.startedAt});

  final List<ToolCallRecord> calls;
  final DateTime startedAt;

  @override
  State<_WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<_WorkingIndicator> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final running = widget.calls.any(
      (call) => call.status == ToolCallStatus.running || call.status == ToolCallStatus.pending,
    );
    final failed = widget.calls.any((call) => call.isError);
    final elapsed = DateTime.now().difference(widget.startedAt).inSeconds;
    final label = running
        ? '正在执行搜索/工具…'
        : failed
            ? '部分来源不可用，正在继续整理…'
            : '正在整理搜索结果与答案…';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.7, color: c.primary),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(width: 6),
          Text(
            '${elapsed}s',
            style: context.text.labelSmall?.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.message,
    required this.isLastAssistant,
    this.onRegenerate,
    this.onRemember,
  });

  final ChatMessage message;
  final bool isLastAssistant;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRemember;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          _Action(
            icon: Icons.copy_rounded,
            tooltip: '复制',
            onTap: () => copyText(context, message.text, message: '已复制'),
          ),
          _Action(
            icon: Icons.bookmark_add_outlined,
            tooltip: '记住这条',
            onTap: onRemember,
          ),
          if (isLastAssistant)
            _Action(
              icon: Icons.refresh_rounded,
              tooltip: '重新生成',
              onTap: onRegenerate,
            ),
          const Spacer(),
          if (message.usageInput + message.usageOutput > 0)
            Text(
              '${tokenLabel(message.usageInput + message.usageOutput)} tokens',
              style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9.5),
            ),
          const SizedBox(width: 6),
          Text(
            formatClock(message.createdAt),
            style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 15,
            color: onTap == null ? c.borderStrong : c.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value - index * 0.18) % 1;
            final opacity = 0.25 + 0.75 * (1 - (phase - 0.5).abs() * 2).clamp(0, 1);
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.textTertiary.withValues(alpha: opacity),
              ),
            );
          }),
        ),
      ),
    );
  }
}
