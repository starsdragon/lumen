import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final DateFormat _clock = DateFormat('HH:mm');
final DateFormat _date = DateFormat('M月d日');
final DateFormat _fullDate = DateFormat('yyyy年M月d日');

String formatClock(DateTime time) => _clock.format(time.toLocal());
String formatDate(DateTime time) => _date.format(time.toLocal());
String formatFullDate(DateTime time) => _fullDate.format(time.toLocal());

String formatDuration(Duration duration) {
  if (duration.inSeconds < 1) return '不到 1 秒';
  if (duration.inSeconds < 60) return '${duration.inSeconds} 秒';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return seconds == 0 ? '$minutes 分钟' : '$minutes 分 $seconds 秒';
}

String relativeDay(DateTime time) {
  final now = DateTime.now();
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff < 7) return '$diff 天前';
  if (local.year == now.year) return _date.format(local);
  return _fullDate.format(local);
}

String shortRelative(DateTime time) {
  final diff = DateTime.now().difference(time.toLocal());
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return formatDate(time);
}

String truncate(String value, int max, {String ellipsis = '…'}) {
  if (value.length <= max) return value;
  return '${value.substring(0, max)}$ellipsis';
}

String compactText(String value, [int max = 80]) =>
    truncate(value.replaceAll(RegExp(r'\s+'), ' ').trim(), max);

/// A short plain-text preview for history rows. Removes the most common
/// Markdown noise so the sidebar does not show "## 先说结论 **粗体**".
String plainPreview(String value, [int max = 80]) {
  var text = value;
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' [代码] ');
  text = text.replaceAll(RegExp(r'```[\s\S]*$'), ' [代码] ');
  text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '[图片]');
  text = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1) ?? '');
  text = text.replaceAll(RegExp(r'[#>*_`~]+'), '');
  text = text.replaceAll(RegExp(r'\$+'), '');
  return compactText(text, max);
}

int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF)) {
      cjk++;
    } else {
      latin++;
    }
  }
  return (cjk * 1.45 + latin / 3.8).ceil();
}

String normalizeBaseUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return value;
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'https://$value';
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

bool isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

/// Blocks loopback, private, link-local and cloud-metadata targets. The model
/// can ask us to fetch arbitrary URLs; without this a prompt injection could
/// turn the app into a LAN scanner.
bool isSafeRemoteUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return false;
  final host = uri.host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (host.isEmpty) return false;
  if (host == 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return false;
  if (host == 'metadata.google.internal' || host == 'metadata') return false;
  if (host == '0.0.0.0' || host == '::' || host == '::1') return false;

  final parts = host.split('.');
  if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
    final a = int.parse(parts[0]);
    final b = int.parse(parts[1]);
    if (a == 0 || a == 10 || a == 127) return false;
    if (a == 169 && b == 254) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && b == 168) return false;
    if (a == 100 && b >= 64 && b <= 127) return false;
    if (a == 192 && b == 0) return false;
    if (a == 198 && (b == 18 || b == 19)) return false;
    if (a >= 224) return false;
  }
  if (host.contains(':')) {
    if (host.startsWith('fc') || host.startsWith('fd') || host.startsWith('fe8') || host.startsWith('fe9') || host.startsWith('fea') || host.startsWith('feb')) {
      return false;
    }
  }
  return true;
}

String sanitizeToolName(String input, {String prefix = 'tool'}) {
  final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final base = cleaned.isEmpty ? prefix : cleaned;
  if (base.length <= 64) return base;
  final digest = sha1.convert(utf8.encode(base)).toString().substring(0, 8);
  return '${base.substring(0, 55)}_$digest';
}

String humanizeModelId(String id) {
  var value = id;
  value = value.replaceAll(RegExp(r'[-_/]'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return id;
  return value
      .split(' ')
      .map((word) {
        if (word.isEmpty) return word;
        if (word.length <= 3 && word.toUpperCase() == word) return word;
        final lower = word.toLowerCase();
        if (['gpt', 'glm', 'vl', 'api', 'ai'].contains(lower)) return word.toUpperCase();
        return '${word[0].toUpperCase()}${word.substring(1)}';
      })
      .join(' ');
}

Map<String, dynamic>? parseJsonLoose(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = value.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '');
  value = value.replaceAll(RegExp(r'\s*```$'), '');
  final firstBrace = value.indexOf('{');
  final lastBrace = value.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    value = value.substring(firstBrace, lastBrace + 1);
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
  } catch (_) {
    // Try the common "single quotes / trailing commas" failure mode once.
    try {
      final repaired = value
          .replaceAll(RegExp(r',\s*([}\]])'), r'$1')
          .replaceAll("'", '"');
      final decoded = jsonDecode(repaired);
      if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return null;
    }
  }
  return null;
}

String friendlyNetworkError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  final lower = text.toLowerCase();
  if (lower.contains('insufficient account funds') || lower.contains('insufficient balance')) {
    return 'OpenCode 返回上游余额不足（402）。如果你使用的是 Go 订阅，请确认 Base URL 为 https://opencode.ai/zen/go/v1（不是 /zen/v1），并在 OpenCode Console 确认 Go / Go Plus 订阅与模型可用；某些上游模型也可能临时受限，可以换一个 Go 模型重试。';
  }
  if (lower.contains('missingsessionid') || lower.contains('x-opencode-session')) {
    return 'OpenCode Go 需要 x-opencode-session 会话头。请确认 Base URL 是 /zen/go/v1，并使用最新版 Lumen；应用会自动附带稳定的会话 ID。';
  }
  if (lower.contains('freeusage') || lower.contains('free usage limit')) {
    return 'OpenCode 免费额度已用完。请订阅 OpenCode Go（https://opencode.ai/go），或改用其他厂商模型。';
  }
  if (lower.contains('socketexception') || lower.contains('failed host lookup') || lower.contains('connection')) {
    return '网络连接失败，请检查网络、代理或 Base URL。';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return '请求超时，模型或网络响应过慢。可以重试，或换一个更快的模型。';
  }
  if (lower.contains('401') || lower.contains('unauthorized') || lower.contains('invalid api key')) {
    return 'API Key 无效或已过期，请在“设置 → 模型与厂商”中检查。';
  }
  if (lower.contains('402') || lower.contains('insufficient') || lower.contains('balance')) {
    return '账户余额不足，或当前 Key 没有该模型的权限。';
  }
  if (lower.contains('403') || lower.contains('forbidden')) {
    return '请求被拒绝（403）。请确认 Key 权限、区域限制与模型访问权限。';
  }
  if (lower.contains('404')) {
    return '接口地址或模型不存在（404）。请检查 Base URL 与模型 ID。';
  }
  if (lower.contains('429') || lower.contains('rate limit')) {
    return '请求过于频繁（429），请稍后重试。';
  }
  return text.isEmpty ? '发生了未知错误。' : text;
}

String mimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}

Uint8List? decodeDataUrl(String dataUrl) {
  try {
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

String bytesToDataUrl(Uint8List bytes, String mime) =>
    'data:$mime;base64,${base64Encode(bytes)}';

String sanitizeFileName(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').trim();
  return cleaned.isEmpty ? 'lumen_image' : cleaned;
}

Future<bool> saveBytesToDevice(Uint8List bytes, String fileName, {String mime = 'image/png'}) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: '保存图片',
    fileName: fileName,
    mimeType: mime,
    bytes: bytes,
  );
  return uri != null;
}

Future<void> copyText(BuildContext context, String text, {String message = '已复制'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showToast(context, message);
}

void showToast(BuildContext context, String message, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

String tokenLabel(int tokens) {
  if (tokens <= 0) return '—';
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) return '${(tokens / 1000).toStringAsFixed(tokens < 10000 ? 1 : 0)}k';
  return '${(tokens / 1000000).toStringAsFixed(1)}M';
}

String formatCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '${(value / 1000000).toStringAsFixed(1)}M';
}
