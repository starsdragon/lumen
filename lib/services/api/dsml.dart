import 'dart:convert';

import '../../data/models.dart';
import 'llm_types.dart';

/// DeepSeek V4 can emit its native DSML tool-call markup inside normal
/// assistant text when a gateway does not translate it to OpenAI tool_calls.
/// The markup has appeared with full-width and ASCII pipes, with and without
/// closing tags, so this parser is deliberately tolerant.
class DsmlExtraction {
  const DsmlExtraction({
    required this.cleanText,
    required this.calls,
    required this.foundMarkup,
  });

  final String cleanText;
  final List<LlmToolCall> calls;
  final bool foundMarkup;
}

const _sep = r'(?:[|｜]\s*){1,2}';

final RegExp _tagPattern = RegExp(
  r'[<＜]\s*(/\s*)?\s*' +
      _sep +
      r'DSML\s*' +
      _sep +
      r'\s*([A-Za-z_][A-Za-z0-9_-]*)([^>＞]*)[>＞]',
  caseSensitive: false,
);

DsmlExtraction extractDsmlToolCalls(String text) {
  if (!text.toLowerCase().contains('dsml') && !text.contains('ｄｓｍｌ')) {
    return DsmlExtraction(cleanText: text, calls: const [], foundMarkup: false);
  }
  final tags = _parseTags(text);
  if (tags.isEmpty) {
    return DsmlExtraction(cleanText: text, calls: const [], foundMarkup: false);
  }

  final calls = <LlmToolCall>[];
  final ranges = <_Range>[];

  // First handle explicit <...tool_calls> / <...calls> wrappers.
  for (var i = 0; i < tags.length; i++) {
    final tag = tags[i];
    if (tag.close || !_isCallsTag(tag.name) || _inside(tag.start, ranges)) continue;
    var closeIndex = -1;
    for (var j = i + 1; j < tags.length; j++) {
      final candidate = tags[j];
      if (_isCallsTag(candidate.name) && candidate.close) {
        closeIndex = j;
        break;
      }
      if (_isCallsTag(candidate.name) && !candidate.close) break;
    }
    final end = closeIndex >= 0 ? tags[closeIndex].end : text.length;
    ranges.add(_Range(tag.start, end));
    calls.addAll(_parseInvokes(text, tags, i + 1, closeIndex >= 0 ? closeIndex : tags.length, end));
    i = closeIndex >= 0 ? closeIndex : tags.length;
  }

  // Some gateways strip the wrapper and leave only invoke/parameter tags.
  for (var i = 0; i < tags.length; i++) {
    final tag = tags[i];
    if (tag.close || !_isInvokeTag(tag.name) || _inside(tag.start, ranges)) continue;
    var closeIndex = -1;
    var nextInvoke = -1;
    for (var j = i + 1; j < tags.length; j++) {
      final candidate = tags[j];
      if (!_isInvokeTag(candidate.name)) continue;
      if (candidate.close) {
        closeIndex = j;
        break;
      }
      nextInvoke = j;
      break;
    }
    final int end;
    if (closeIndex >= 0) {
      end = tags[closeIndex].end;
    } else if (nextInvoke >= 0) {
      end = tags[nextInvoke].start;
    } else {
      end = text.length;
    }
    ranges.add(_Range(tag.start, end));
    final upper = closeIndex >= 0
        ? closeIndex + 1
        : (nextInvoke >= 0 ? nextInvoke : tags.length);
    calls.addAll(_parseInvokes(text, tags, i, upper, end));
    i = closeIndex >= 0 ? closeIndex : (nextInvoke >= 0 ? nextInvoke - 1 : i);
  }

  // Remove any stray DSML tags that were not part of a parsed block.
  for (final tag in tags) {
    if (!_inside(tag.start, ranges)) ranges.add(_Range(tag.start, tag.end));
  }

  return DsmlExtraction(
    cleanText: _removeRanges(text, ranges),
    calls: calls,
    foundMarkup: true,
  );
}

List<_DsmlTag> _parseTags(String text) {
  final result = <_DsmlTag>[];
  for (final match in _tagPattern.allMatches(text)) {
    final closing = (match.group(1) ?? '').trim().isNotEmpty;
    final name = (match.group(2) ?? '').toLowerCase();
    result.add(
      _DsmlTag(
        start: match.start,
        end: match.end,
        name: name,
        close: closing,
        attrs: match.group(3) ?? '',
      ),
    );
  }
  return result;
}

List<LlmToolCall> _parseInvokes(
  String text,
  List<_DsmlTag> tags,
  int from,
  int to,
  int endOffset,
) {
  final calls = <LlmToolCall>[];
  for (var i = from; i < to; i++) {
    final tag = tags[i];
    if (tag.close || !_isInvokeTag(tag.name)) continue;
    final name = _attr(tag.attrs, 'name')?.trim() ?? '';
    if (name.isEmpty) continue;

    var regionEnd = endOffset;
    var next = to;
    for (var j = i + 1; j < to; j++) {
      final candidate = tags[j];
      if (_isCallsTag(candidate.name) && candidate.close) {
        regionEnd = candidate.start;
        next = j;
        break;
      }
      if (_isInvokeTag(candidate.name)) {
        regionEnd = candidate.start;
        next = j;
        break;
      }
    }
    final args = _parseParameters(text, tags, i + 1, next, regionEnd);
    calls.add(
      LlmToolCall(
        id: newId('dsml'),
        name: name,
        argumentsJson: jsonEncode(args),
      ),
    );
    if (next > i) i = next - 1;
  }
  return calls;
}

Map<String, dynamic> _parseParameters(
  String text,
  List<_DsmlTag> tags,
  int from,
  int to,
  int endOffset,
) {
  final args = <String, dynamic>{};
  _ParamBuilder? current;

  void finish(int end) {
    final builder = current;
    if (builder == null) return;
    final raw = _cleanValue(text.substring(builder.valueStart, end.clamp(builder.valueStart, text.length)));
    args[builder.name] = builder.isString ? raw : _typedValue(raw);
    current = null;
  }

  for (var i = from; i < to; i++) {
    final tag = tags[i];
    if (_isParameterTag(tag.name)) {
      finish(tag.start);
      if (tag.close) continue;
      final name = _attr(tag.attrs, 'name')?.trim() ?? '';
      if (name.isEmpty) continue;
      final stringFlag = (_attr(tag.attrs, 'string') ?? 'true').toLowerCase();
      current = _ParamBuilder(
        name: name,
        isString: stringFlag != 'false',
        valueStart: tag.end,
      );
      continue;
    }
    // A closing invoke or the next wrapper ends the current value.
    if (current != null) finish(tag.start);
    if (_isInvokeTag(tag.name)) break;
  }
  finish(endOffset);
  return args;
}

String _cleanValue(String value) {
  var result = value.replaceAll(_tagPattern, '');
  result = result.trim();
  if (result.startsWith('```') && result.endsWith('```')) {
    result = result.substring(3, result.length - 3).trim();
  }
  return result;
}

Object? _typedValue(String raw) {
  if (raw.isEmpty) return raw;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is num || decoded is bool || decoded is Map || decoded is List || decoded == null) {
      return decoded;
    }
    return raw;
  } catch (_) {
    // Not JSON; preserve the literal text.
  }
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  if (raw == 'null') return null;
  return num.tryParse(raw) ?? raw;
}

String? _attr(String attrs, String name) {
  final match = RegExp(
    '\\b${RegExp.escape(name)}\\s*=\\s*"([^"]*)"',
    caseSensitive: false,
  ).firstMatch(attrs);
  return match?.group(1);
}

bool _isCallsTag(String name) => name == 'calls' || name == 'tool_calls' || name == 'tool-call';

bool _isInvokeTag(String name) => name == 'invoke' || name == 'tool_call';

bool _isParameterTag(String name) => name == 'parameter' || name == 'param';

bool _inside(int offset, List<_Range> ranges) =>
    ranges.any((range) => offset >= range.start && offset < range.end);

String _removeRanges(String text, List<_Range> ranges) {
  if (ranges.isEmpty) return text.trim();
  ranges.sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Range>[];
  for (final range in ranges) {
    if (range.end <= range.start) continue;
    if (merged.isNotEmpty && range.start <= merged.last.end) {
      if (range.end > merged.last.end) merged.last.end = range.end;
    } else {
      merged.add(_Range(range.start, range.end));
    }
  }
  final buffer = StringBuffer();
  var cursor = 0;
  for (final range in merged) {
    if (range.start > cursor) buffer.write(text.substring(cursor, range.start));
    if (range.end > cursor) cursor = range.end;
  }
  if (cursor < text.length) buffer.write(text.substring(cursor));
  var clean = buffer.toString();
  clean = clean.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  clean = clean.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return clean.trim();
}

class _DsmlTag {
  const _DsmlTag({
    required this.start,
    required this.end,
    required this.name,
    required this.close,
    required this.attrs,
  });

  final int start;
  final int end;
  final String name;
  final bool close;
  final String attrs;
}

class _ParamBuilder {
  const _ParamBuilder({
    required this.name,
    required this.isString,
    required this.valueStart,
  });

  final String name;
  final bool isString;
  final int valueStart;
}

class _Range {
  _Range(this.start, this.end);

  final int start;
  int end;
}
