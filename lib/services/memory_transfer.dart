import 'dart:convert';

import '../data/models.dart';

class MemoryBundle {
  const MemoryBundle({
    required this.profile,
    required this.memories,
    this.exportedAt,
  });

  final UserProfile profile;
  final List<MemoryItem> memories;
  final DateTime? exportedAt;

  Map<String, dynamic> toJson() => {
        'app': 'Lumen',
        'kind': 'memory',
        'version': 1,
        'exportedAt': (exportedAt ?? nowUtc()).toIso8601String(),
        'profile': profile.toJson(),
        'memories': memories.map((memory) => memory.toJson()).toList(growable: false),
      };

  String encode({bool pretty = true}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson()) : jsonEncode(toJson());

  static MemoryBundle decode(String raw) {
    var source = raw.trim();
    if (source.startsWith('\uFEFF')) source = source.substring(1);
    if (source.isEmpty) {
      throw const FormatException('文件为空。');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const FormatException('不是有效的 JSON 文件。');
    }
    if (decoded is! Map) {
      throw const FormatException('记忆文件的根节点必须是对象。');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    final app = '${map['app'] ?? 'Lumen'}';
    if (app != 'Lumen') {
      throw const FormatException('这不是 Lumen 的记忆文件。');
    }
    final kind = '${map['kind'] ?? 'memory'}';
    if (kind != 'memory') {
      throw const FormatException('文件类型不是长期记忆。');
    }
    final version = (map['version'] as num?)?.toInt() ?? 1;
    if (version > 1) {
      throw const FormatException('这个文件来自更新版本的 Lumen，当前版本无法导入。');
    }
    return MemoryBundle.fromJson(map);
  }

  factory MemoryBundle.fromJson(Map<String, dynamic> map) {
    final rawProfile = map['profile'];
    final profile = rawProfile is Map
        ? UserProfile.fromJson(_unwrapRecord(rawProfile))
        : UserProfile();
    final rawMemories = map['memories'];
    if (rawMemories != null && rawMemories is! List) {
      throw const FormatException('memories 必须是数组。');
    }
    final memories = <MemoryItem>[];
    for (final raw in (rawMemories as List? ?? const [])) {
      if (raw is! Map) continue;
      final item = MemoryItem.fromJson(_unwrapRecord(raw));
      final content = item.content.trim();
      if (content.isEmpty) continue;
      if (content.length > 4000) {
        throw const FormatException('单条记忆不能超过 4000 个字符。');
      }
      memories.add(
        MemoryItem(
          id: item.id,
          content: content,
          category: item.category,
          importance: item.importance.clamp(1, 5),
          confidence: item.confidence.clamp(0, 1),
          sourceConversationId: item.sourceConversationId,
          createdAt: item.createdAt,
          lastUsedAt: item.lastUsedAt,
          pinned: item.pinned,
          manual: item.manual,
        ),
      );
      if (memories.length > 5000) {
        throw const FormatException('记忆条目超过 5000 条，文件可能不完整。');
      }
    }
    return MemoryBundle(
      profile: profile,
      memories: memories,
      exportedAt: DateTime.tryParse('${map['exportedAt'] ?? ''}'),
    );
  }

  static Map<String, dynamic> _unwrapRecord(Map raw) {
    // Also accepts a full-database export's {id, value} record shape.
    if (raw['value'] is Map) {
      return (raw['value'] as Map).map((key, value) => MapEntry('$key', value));
    }
    return raw.map((key, value) => MapEntry('$key', value));
  }
}

enum MemoryImportMode { merge, replace }

class MemoryImportResult {
  const MemoryImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.replaced,
  });

  final int added;
  final int updated;
  final int skipped;
  final bool replaced;

  int get total => added + updated + skipped;

  String get summary {
    if (replaced) return '已替换为 $added 条记忆';
    final parts = <String>[];
    if (added > 0) parts.add('新增 $added 条');
    if (updated > 0) parts.add('更新 $updated 条');
    if (skipped > 0) parts.add('跳过 $skipped 条');
    return parts.isEmpty ? '没有可导入的记忆' : parts.join('，');
  }
}
