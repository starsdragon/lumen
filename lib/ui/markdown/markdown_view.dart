import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';

class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.compact = false,
  });

  final String text;
  final bool isStreaming;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final prepared = preprocessMath(text);
    final body = compact ? context.text.bodyMedium : context.text.bodyLarge;
    final styleSheet = MarkdownStyleSheet(
      p: body?.copyWith(height: compact ? 1.62 : 1.78),
      pPadding: const EdgeInsets.only(bottom: 9),
      a: body?.copyWith(color: c.primary, decoration: TextDecoration.underline, decorationColor: c.primary.withValues(alpha: 0.45)),
      em: body?.copyWith(fontStyle: FontStyle.italic),
      strong: body?.copyWith(fontWeight: FontWeight.w600),
      del: body?.copyWith(decoration: TextDecoration.lineThrough),
      h1: context.text.headlineSmall?.copyWith(fontSize: compact ? 20 : 22, height: 1.35),
      h2: context.text.titleLarge?.copyWith(fontSize: compact ? 18 : 19.5, height: 1.4),
      h3: context.text.titleMedium?.copyWith(fontSize: compact ? 15.5 : 16.5, height: 1.45),
      h1Padding: const EdgeInsets.only(top: 16, bottom: 6),
      h2Padding: const EdgeInsets.only(top: 14, bottom: 5),
      h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
      listBullet: body?.copyWith(color: c.textSecondary),
      listIndent: 22,
      listBulletPadding: const EdgeInsets.only(right: 7),
      blockquote: body?.copyWith(color: c.textSecondary, height: 1.65),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      blockquoteDecoration: BoxDecoration(
        color: c.surfaceAlt,
        border: Border(left: BorderSide(color: c.primary.withValues(alpha: 0.65), width: 3)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
      ),
      code: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: const ['NotoSansSC', 'monospace'],
        fontSize: compact ? 12 : 12.8,
        height: 1.5,
        color: c.textPrimary,
        backgroundColor: c.surfaceAlt,
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(color: Colors.transparent),
      tableHead: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
      tableBody: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.55),
      tableHeadAlign: TextAlign.left,
      tablePadding: const EdgeInsets.symmetric(vertical: 8),
      tableBorder: TableBorder.all(color: c.border, width: 1, borderRadius: BorderRadius.circular(10)),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      tableColumnWidth: const FlexColumnWidth(),
      tableScrollbarThumbVisibility: false,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      blockSpacing: 8,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data: prepared,
          // Flutter web has a known SelectionArea edge case when the message
          // list is re-laid out; keep web taps reliable and selection on mobile.
          selectable: !kIsWeb,
          styleSheet: styleSheet,
          builders: {
            'pre': _CodeBlockBuilder(),
            'code': _InlineMathBuilder(),
          },
          onTapLink: (text, href, title) async {
            if (href == null || !isHttpUrl(href)) return;
            final uri = Uri.parse(href);
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {
              // Ignore a missing browser / invalid link.
            }
          },
        ),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(left: 1, top: 2),
            child: BlinkingCursorInline(),
          ),
      ],
    );
    if (kIsWeb) return content;
    return SelectionArea(child: content);
  }
}

class BlinkingCursorInline extends StatefulWidget {
  const BlinkingCursorInline({super.key});

  @override
  State<BlinkingCursorInline> createState() => _BlinkingCursorInlineState();
}

class _BlinkingCursorInlineState extends State<BlinkingCursorInline>
    with SingleTickerProviderStateMixin {
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
      opacity: Tween<double>(begin: 1, end: 0.1).animate(_controller),
      child: Container(
        width: 8,
        height: 17,
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (!text.startsWith(_inlineMathPrefix)) return null;
    final tex = _decodeMath(text.substring(_inlineMathPrefix.length));
    if (tex == null) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Math.tex(
        tex,
        mathStyle: MathStyle.text,
        textStyle: (parentStyle ?? preferredStyle ?? context.text.bodyLarge)?.copyWith(
          fontSize: (parentStyle?.fontSize ?? 16) * 0.98,
        ),
        onErrorFallback: (error) => Text(
          tex,
          style: context.text.bodyMedium?.copyWith(color: context.colors.danger),
        ),
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final codeElement = element.children?.whereType<md.Element>().firstWhere(
          (child) => child.tag == 'code',
          orElse: () => md.Element.empty('code'),
        );
    final className = codeElement?.attributes['class'] ?? element.attributes['class'] ?? '';
    final language = className.replaceFirst(RegExp(r'^language-'), '').trim();
    final code = (codeElement?.textContent ?? element.textContent).replaceFirst(RegExp(r'\n$'), '');
    if (language == 'lumen-math-display') {
      final tex = _decodeMath(code.trim());
      if (tex == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            tex,
            mathStyle: MathStyle.display,
            textStyle: context.text.bodyLarge?.copyWith(fontSize: 18),
            onErrorFallback: (error) => Text(
              tex,
              style: context.text.bodyMedium?.copyWith(color: context.colors.danger),
            ),
          ),
        ),
      );
    }
    return CodeBlockView(code: code, language: language);
  }
}

class CodeBlockView extends StatefulWidget {
  const CodeBlockView({super.key, required this.code, this.language = ''});

  final String code;
  final String language;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.isDark ? atomOneDarkTheme : githubTheme;
    final lang = _languageAlias(widget.language);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: c.codeBackground,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.only(left: 13, right: 6),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 14, color: c.textTertiary),
                const SizedBox(width: 6),
                Text(
                  lang.isEmpty ? '代码' : lang.toUpperCase(),
                  style: context.text.labelSmall?.copyWith(
                    color: c.textTertiary,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await copyText(context, widget.code, message: '代码已复制');
                    if (!mounted) return;
                    setState(() => _copied = true);
                    await Future<void>.delayed(const Duration(seconds: 2));
                    if (mounted) setState(() => _copied = false);
                  },
                  icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 14),
                  label: Text(_copied ? '已复制' : '复制', style: const TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(50, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectionArea(
              child: HighlightView(
                widget.code,
                language: lang,
                theme: theme,
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 14),
                textStyle: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontFamilyFallback: ['NotoSansSC', 'monospace'],
                  fontSize: 12.5,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _inlineMathPrefix = 'lumen-math:';

String? _decodeMath(String payload) {
  try {
    return utf8.decode(base64Decode(payload));
  } catch (_) {
    return null;
  }
}

String _languageAlias(String value) {
  final lower = value.toLowerCase();
  return switch (lower) {
    'js' => 'javascript',
    'ts' => 'typescript',
    'py' => 'python',
    'sh' || 'shell' || 'zsh' => 'bash',
    'yml' => 'yaml',
    'md' => 'markdown',
    'c++' || 'cpp' => 'cpp',
    'c#' || 'cs' => 'csharp',
    'rb' => 'ruby',
    'rs' => 'rust',
    'kt' || 'kts' => 'kotlin',
    'plaintext' || 'text' || '' => 'plaintext',
    _ => lower,
  };
}

/// Rewrites LaTeX math into fenced/inline code nodes before Markdown parsing.
/// This avoids raw-HTML handling differences and keeps code samples intact.
String preprocessMath(String input) {
  final lines = input.split('\n');
  final buffer = StringBuffer();
  final normal = StringBuffer();
  var inFence = false;

  void flushNormal() {
    if (normal.isEmpty) return;
    buffer.write(_processMathSegment(normal.toString()));
    normal.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    final isFence = trimmed.startsWith('```');
    if (isFence) {
      if (!inFence) {
        flushNormal();
        inFence = true;
        buffer.writeln(line);
      } else {
        inFence = false;
        buffer.writeln(line);
      }
      continue;
    }
    if (inFence) {
      buffer.writeln(line);
    } else {
      normal.writeln(line);
    }
  }
  flushNormal();
  return buffer.toString();
}

String _processMathSegment(String segment) {
  final out = StringBuffer();
  var i = 0;
  while (i < segment.length) {
    final char = segment[i];
    if (char == r'\' && i + 1 < segment.length && segment[i + 1] == r'$') {
      out.write(r'\$');
      i += 2;
      continue;
    }
    if (char == '`') {
      // Copy an entire inline code span untouched.
      final end = segment.indexOf('`', i + 1);
      if (end < 0) {
        out.write(segment.substring(i));
        break;
      }
      out.write(segment.substring(i, end + 1));
      i = end + 1;
      continue;
    }
    if (char == r'$') {
      final isDisplay = i + 1 < segment.length && segment[i + 1] == r'$';
      final marker = isDisplay ? r'$$' : r'$';
      final start = i + marker.length;
      final end = segment.indexOf(marker, start);
      if (end < 0) {
        out.write(char);
        i++;
        continue;
      }
      final tex = segment.substring(start, end);
      if (tex.trim().isEmpty) {
        out.write(segment.substring(i, end + marker.length));
        i = end + marker.length;
        continue;
      }
      final encoded = base64Encode(utf8.encode(tex.trim()));
      if (isDisplay) {
        out.writeln();
        out.writeln('```lumen-math-display');
        out.writeln(encoded);
        out.writeln('```');
        out.writeln();
      } else {
        out.write('`$_inlineMathPrefix$encoded`');
      }
      i = end + marker.length;
      continue;
    }
    out.write(char);
    i++;
  }
  return out.toString();
}
