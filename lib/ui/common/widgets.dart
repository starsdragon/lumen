import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';

class LumenMark extends StatelessWidget {
  const LumenMark({
    super.key,
    this.size = 40,
    this.plain = false,
    this.radius,
  });

  final double size;
  final bool plain;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (plain) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SparkPainter(color: c.primary)),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF426EFE), Color(0xFF7A5CFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.22),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _SparkPainter(color: Colors.white, companionColor: Colors.white70),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.color, this.companionColor});

  final Color color;
  final Color? companionColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.34;
    final paint = Paint()..color = color;
    canvas.drawPath(_sparkPath(center, radius), paint);
    if (companionColor != null) {
      final small = Offset(center.dx + radius * 0.72, center.dy - radius * 0.68);
      canvas.drawPath(_sparkPath(small, radius * 0.18), Paint()..color = companionColor!);
    }
  }

  Path _sparkPath(Offset center, double radius) {
    final path = Path();
    const steps = 160;
    for (var i = 0; i <= steps; i++) {
      final theta = 2 * math.pi * i / steps;
      final r = radius * (0.22 + 0.78 * math.pow(math.cos(2 * theta).abs(), 2.2));
      final point = Offset(center.dx + r * math.cos(theta), center.dy + r * math.sin(theta));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.companionColor != companionColor;
}

class ProviderLogo extends StatelessWidget {
  const ProviderLogo({super.key, required this.provider, this.size = 32});

  final ProviderConfig provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget child;
    if (provider.demo) {
      child = LumenMark(size: size * 0.72);
    } else if (provider.logo.isEmpty) {
      child = Icon(Icons.hub_outlined, size: size * 0.5, color: c.primary);
    } else {
      child = SvgPicture.asset(
        provider.logo,
        width: size * 0.56,
        height: size * 0.56,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Icon(Icons.auto_awesome, size: size * 0.45, color: c.primary),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: c.border.withValues(alpha: 0.9)),
      ),
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: child,
      ),
    );
  }
}

class ProviderName extends StatelessWidget {
  const ProviderName({
    super.key,
    required this.provider,
    required this.model,
    this.compact = false,
  });

  final ProviderConfig provider;
  final ModelInfo? model;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProviderLogo(provider: provider, size: compact ? 24 : 28),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(
                  color: c.textSecondary,
                  fontSize: compact ? 11 : 12,
                ),
              ),
              if (model != null)
                Text(
                  model!.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    fontSize: compact ? 12.5 : 13.5,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class CapabilityChip extends StatelessWidget {
  const CapabilityChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.dense = true,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: tint),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: tint,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: selected ? c.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: selected ? c.primary.withValues(alpha: 0.32) : c.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: selected ? c.primary : c.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: selected ? c.primary : c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final wrapped = Opacity(opacity: enabled ? 1 : 0.45, child: child);
    if (tooltip == null) return wrapped;
    return Tooltip(message: tooltip!, child: wrapped);
  }
}

class LumenIconButton extends StatelessWidget {
  const LumenIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 38,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = Material(
      color: background ?? Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.5,
            color: onTap == null ? c.textTertiary : c.textSecondary,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: context.text.bodySmall?.copyWith(color: c.textTertiary)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: context.text.labelMedium?.copyWith(
              color: c.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 15, endIndent: 15, color: c.border),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(footer!, style: context.text.bodySmall?.copyWith(color: c.textTertiary)),
          ),
        const SizedBox(height: 22),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (danger ? c.danger : c.primary).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: danger ? c.danger : c.primary),
            ),
          if (leading != null || icon != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: danger ? c.danger : c.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.text.bodySmall?.copyWith(color: c.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!] else if (onTap != null)
            Icon(Icons.chevron_right_rounded, size: 19, color: c.textTertiary),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: content,
    );
  }
}

class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.attachment,
    this.width,
    this.height,
    this.radius = 14,
    this.onTap,
    this.fit = BoxFit.cover,
  });

  final Attachment attachment;
  final double? width;
  final double? height;
  final double radius;
  final VoidCallback? onTap;
  final BoxFit fit;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = decodeDataUrl(widget.attachment.dataUrl);
  }

  @override
  void didUpdateWidget(covariant AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.dataUrl != widget.attachment.dataUrl) {
      _bytes = decodeDataUrl(widget.attachment.dataUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final image = _bytes == null
        ? Container(
            width: widget.width,
            height: widget.height,
            color: c.surfaceAlt,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined, color: c.textTertiary),
          )
        : Image.memory(
            _bytes!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => Container(
              width: widget.width,
              height: widget.height,
              color: c.surfaceAlt,
              alignment: Alignment.center,
              child: Icon(Icons.broken_image_outlined, color: c.textTertiary),
            ),
          );
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: image,
      ),
    );
  }
}

Future<void> showFilePreviewDialog(BuildContext context, Attachment attachment) {
  final c = context.colors;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.description_outlined, size: 20, color: c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${attachment.mime} · 已提取 ${attachment.extractedText.length} 字',
              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 420),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  attachment.extractedText.isEmpty ? '（没有可预览的文本）' : attachment.extractedText,
                  style: context.text.bodySmall?.copyWith(
                    height: 1.6,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> openImageViewer(
  BuildContext context,
  Attachment attachment, {
  String? caption,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) =>
          _ImageViewerScreen(attachment: attachment, caption: caption),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.attachment, this.caption});

  final Attachment attachment;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeDataUrl(attachment.dataUrl);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '保存图片',
            icon: const Icon(Icons.download_rounded),
            onPressed: bytes == null
                ? null
                : () async {
                    final ok = await saveBytesToDevice(
                      bytes,
                      sanitizeFileName(attachment.name.isEmpty ? 'lumen.png' : attachment.name),
                      mime: attachment.mime,
                    );
                    if (context.mounted && ok) showToast(context, '已保存');
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: bytes == null
                      ? const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)
                      : Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            if (caption != null && caption!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showLumenSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
}) {
  // Prevent a closing sheet from restoring focus to the composer, which would
  // pop the keyboard open again on mobile.
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: context.colors.overlay.withValues(alpha: 0.35),
    builder: (context) => _SheetFrame(child: builder(context)),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width > 760 ? 680 : size.width,
          maxHeight: size.height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: c.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 9),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool danger = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: context.text.bodyMedium?.copyWith(color: c.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? c.danger : c.primary,
            minimumSize: const Size(72, 42),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: c.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 27, color: c.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 7),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(color: c.textTertiary, height: 1.55),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, this.color, this.width = 2, this.height = 16});

  final Color? color;
  final double width;
  final double height;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.15).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        margin: const EdgeInsets.only(left: 2, top: 2),
        decoration: BoxDecoration(
          color: widget.color ?? context.colors.primary,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

class ShimmerLine extends StatefulWidget {
  const ShimmerLine({super.key, this.width = 120, this.height = 10});

  final double width;
  final double height;

  @override
  State<ShimmerLine> createState() => _ShimmerLineState();
}

class _ShimmerLineState extends State<ShimmerLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.height),
          gradient: LinearGradient(
            colors: [
              c.border,
              c.borderStrong,
              c.border,
            ],
            stops: [
              (_controller.value - 0.3).clamp(0, 1),
              _controller.value,
              (_controller.value + 0.3).clamp(0, 1),
            ],
          ),
        ),
      ),
    );
  }
}
