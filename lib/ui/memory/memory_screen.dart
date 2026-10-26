import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/controllers.dart';
import '../common/widgets.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final TextEditingController _search = TextEditingController();
  MemoryCategory? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addMemory() async {
    final memories = context.read<MemoriesController>();
    await showMemoryEditor(context, memories: memories);
  }

  Future<void> _editProfile() async {
    final memories = context.read<MemoriesController>();
    await showProfileEditor(context, memories: memories);
  }

  Future<void> _clear() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空全部记忆？',
      message: '画像与所有记忆条目会从本机删除，无法恢复。对话记录不受影响。',
      confirmLabel: '清空',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<MemoriesController>().clearAll();
    if (mounted) showToast(context, '记忆已清空');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final memories = context.watch<MemoriesController>();
    final settings = context.watch<SettingsController>();
    final enabled = settings.settings.memoryEnabled;
    final content = SafeArea(
      top: !widget.embedded,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(widget.embedded ? 30 : 20, widget.embedded ? 26 : 18, widget.embedded ? 30 : 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.embedded)
                  _Header(
                    embedded: widget.embedded,
                    count: memories.memories.length,
                    onAdd: _addMemory,
                    onClear: memories.memories.isEmpty && memories.profile.isEmpty ? null : _clear,
                  )
                else
                  _PushedHeader(count: memories.memories.length),
                const SizedBox(height: 18),
                if (!enabled)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                    decoration: BoxDecoration(
                      color: c.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: c.warning.withValues(alpha: 0.24)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 17, color: c.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '长期记忆已在设置中关闭。画像仍保存在本机，但不会注入对话。',
                            style: context.text.bodySmall?.copyWith(color: c.textSecondary),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final controller = context.read<SettingsController>();
                            await controller.update(
                              controller.settings.copyWith(memoryEnabled: true),
                            );
                          },
                          child: const Text('开启'),
                        ),
                      ],
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth > 980;
                    final profileCard = _ProfileCard(
                      profile: memories.profile,
                      onEdit: _editProfile,
                      onSample: memories.loadSample,
                      loading: memories.loading,
                    );
                    final list = _MemoryList(
                      memories: memories,
                      search: _search,
                      category: _category,
                      onCategory: (value) => setState(() => _category = value),
                      onChanged: () => setState(() {}),
                      onEdit: (memory) => showMemoryEditor(context, memories: memories, memory: memory),
                      onDelete: (memory) async {
                        final ok = await showConfirmDialog(
                          context,
                          title: '删除这条记忆？',
                          message: memory.content,
                          confirmLabel: '删除',
                          danger: true,
                        );
                        if (ok && context.mounted) {
                          await memories.deleteMemory(memory);
                        }
                      },
                      onPin: memories.togglePinned,
                      onSample: memories.loadSample,
                    );
                    if (!twoColumns) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          profileCard,
                          const SizedBox(height: 20),
                          list,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 400, child: profileCard),
                        const SizedBox(width: 22),
                        Expanded(child: list),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) return content;
    final hasData = memories.memories.isNotEmpty || !memories.profile.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('长期记忆'),
        actions: [
          if (hasData)
            IconButton(
              tooltip: '清空记忆',
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: _clear,
            ),
          IconButton(
            tooltip: '添加记忆',
            icon: const Icon(Icons.add_rounded),
            onPressed: _addMemory,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: content,
    );
  }
}

class _PushedHeader extends StatelessWidget {
  const _PushedHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Lumen 会从对话中提炼稳定的信息，形成画像（人格、职业、思维方式）与可检索的记忆。所有内容都保存在本机。',
            style: context.text.bodySmall?.copyWith(
              color: c.textSecondary,
              height: 1.55,
              fontSize: 12.3,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.border),
          ),
          child: Text(
            '$count 条',
            style: context.text.labelSmall?.copyWith(color: c.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.embedded,
    required this.count,
    required this.onAdd,
    this.onClear,
  });

  final bool embedded;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '长期记忆',
                style: context.text.headlineSmall?.copyWith(
                  fontSize: embedded ? 24 : 22,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lumen 会从对话中提炼稳定的信息，形成画像（人格、职业、思维方式）与可检索的记忆。所有内容都保存在本机。',
                style: context.text.bodySmall?.copyWith(
                  color: c.textSecondary,
                  height: 1.55,
                  fontSize: 12.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                if (onClear != null)
                  IconButton(
                    tooltip: '清空记忆',
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    onPressed: onClear,
                  ),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('添加记忆'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                ),
              ],
            ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 3),
                child: Text(
                  '$count 条长期记忆',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onEdit,
    required this.onSample,
    required this.loading,
  });

  final UserProfile profile;
  final VoidCallback onEdit;
  final Future<void> Function() onSample;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return Container(
        height: 260,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (profile.isEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.person_outline_rounded, size: 27, color: c.primary),
            ),
            const SizedBox(height: 14),
            Text('还没有形成画像', style: context.text.titleMedium),
            const SizedBox(height: 6),
            Text(
              '正常聊几轮后，Lumen 会自动提取你的偏好与背景；也可以先手动添加，或填入一份示例看看效果。',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: onEdit,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  child: const Text('手动创建画像'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await onSample();
                    if (context.mounted) showToast(context, '已填入示例画像与记忆');
                  },
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  child: const Text('填入示例'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final initial = profile.name.isNotEmpty ? profile.name.substring(0, 1) : '你';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF426EFE), Color(0xFF7A5CFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 19,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium?.copyWith(fontSize: 16.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (profile.occupation.isNotEmpty) profile.occupation,
                        if (profile.location.isNotEmpty) profile.location,
                      ].isEmpty
                          ? 'Lumen 对你的长期画像'
                          : [
                              if (profile.occupation.isNotEmpty) profile.occupation,
                              if (profile.location.isNotEmpty) profile.location,
                            ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑画像',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
              ),
            ],
          ),
          if (profile.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              profile.summary,
              style: context.text.bodySmall?.copyWith(
                color: c.textSecondary,
                height: 1.65,
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _ProfileGroup(label: '性格', values: profile.personality),
          _ProfileGroup(label: '专业', values: profile.expertise),
          _ProfileGroup(label: '兴趣', values: profile.interests),
          _ProfileGroup(label: '价值观', values: profile.values),
          _ProfileGroup(label: '目标', values: profile.goals),
          _ProfileGroup(label: '沟通偏好', values: profile.communicationStyle),
          if (profile.thinkingStyle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '思维方式',
              style: context.text.labelSmall?.copyWith(
                color: c.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              profile.thinkingStyle,
              style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.6),
            ),
          ],
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: c.textTertiary),
              const SizedBox(width: 4),
              Text(
                profile.updatedAt == null
                    ? '本地画像'
                    : '更新于 ${shortRelative(profile.updatedAt!)} · 本地画像',
                style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9.5),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded, size: 14),
                label: const Text('编辑'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 30)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileGroup extends StatelessWidget {
  const _ProfileGroup({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  color: c.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final value in values)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      value,
                      style: context.text.labelSmall?.copyWith(color: c.textSecondary, fontSize: 10.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryList extends StatelessWidget {
  const _MemoryList({
    required this.memories,
    required this.search,
    required this.category,
    required this.onCategory,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    required this.onSample,
  });

  final MemoriesController memories;
  final TextEditingController search;
  final MemoryCategory? category;
  final ValueChanged<MemoryCategory?> onCategory;
  final VoidCallback onChanged;
  final ValueChanged<MemoryItem> onEdit;
  final ValueChanged<MemoryItem> onDelete;
  final ValueChanged<MemoryItem> onPin;
  final Future<void> Function() onSample;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final query = search.text.trim().toLowerCase();
    final categories = memories.memories.map((m) => m.category).toSet().toList();
    final filtered = memories.memories.where((memory) {
      if (category != null && memory.category != category) return false;
      if (query.isEmpty) return true;
      return memory.content.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('记忆条目', style: context.text.titleMedium),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: c.primarySoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${memories.memories.length}',
                  style: context.text.labelSmall?.copyWith(color: c.primary, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 160,
                height: 34,
                child: TextField(
                  controller: search,
                  onChanged: (_) => onChanged(),
                  style: context.text.labelSmall,
                  decoration: InputDecoration(
                    hintText: '搜索记忆',
                    prefixIcon: Icon(Icons.search_rounded, size: 15, color: c.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (categories.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: '全部',
                    selected: category == null,
                    onTap: () => onCategory(null),
                  ),
                  for (final item in categories)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: _FilterChip(
                        label: item.label,
                        selected: category == item,
                        onTap: () => onCategory(item),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 26, color: c.textTertiary),
                    const SizedBox(height: 9),
                    Text(
                      memories.memories.isEmpty ? '还没有记忆条目' : '没有匹配的记忆',
                      style: context.text.bodySmall?.copyWith(color: c.textSecondary),
                    ),
                    if (memories.memories.isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '聊几轮后会自动出现，也可以手动添加。',
                        style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () async {
                          await onSample();
                          if (context.mounted) showToast(context, '已填入示例记忆');
                        },
                        child: const Text('填入示例'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            for (final memory in filtered)
              _MemoryTile(
                memory: memory,
                onEdit: () => onEdit(memory),
                onDelete: () => onDelete(memory),
                onPin: () => onPin(memory),
              ),
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.memory,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
  });

  final MemoryItem memory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 9),
      decoration: BoxDecoration(
        color: memory.pinned ? c.primarySoft.withValues(alpha: 0.55) : c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: memory.pinned ? c.primary.withValues(alpha: 0.2) : c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(memory.category.icon, size: 15, color: c.primary),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.content,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textPrimary,
                    height: 1.55,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      memory.category.label,
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9.5),
                    ),
                    const SizedBox(width: 7),
                    for (var i = 0; i < 5; i++)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < memory.importance ? c.primary : c.borderStrong,
                        ),
                      ),
                    const SizedBox(width: 7),
                    Text(
                      relativeDay(memory.createdAt),
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9.5),
                    ),
                    if (memory.pinned) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.push_pin_outlined, size: 10, color: c.primary),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '操作',
            padding: EdgeInsets.zero,
            iconSize: 16,
            icon: Icon(Icons.more_horiz_rounded, size: 16, color: c.textTertiary),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                  break;
                case 'pin':
                  onPin();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'pin', child: Text(memory.pinned ? '取消置顶' : '置顶')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? c.primary.withValues(alpha: 0.35) : c.border),
        ),
        child: Text(
          label,
          style: context.text.labelSmall?.copyWith(
            color: selected ? c.primary : c.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }
}

Future<void> showMemoryEditor(
  BuildContext context, {
  required MemoriesController memories,
  MemoryItem? memory,
}) async {
  final content = TextEditingController(text: memory?.content ?? '');
  var category = memory?.category ?? MemoryCategory.other;
  var importance = memory?.importance ?? 3;
  final saved = await showLumenSheet<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        final c = context.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(memory == null ? '添加记忆' : '编辑记忆', style: context.text.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '写一条未来仍有用的事实、偏好或目标。不要保存密码、证件号等敏感信息。',
                style: context.text.bodySmall?.copyWith(color: c.textTertiary, height: 1.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: content,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '记忆内容',
                  hintText: '例如：用户是一名产品经理，偏好先看结论。',
                ),
              ),
              const SizedBox(height: 13),
              Text('分类', style: context.text.labelSmall?.copyWith(color: c.textTertiary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final item in MemoryCategory.values)
                    ChoiceChip(
                      label: Text(item.label, style: const TextStyle(fontSize: 11)),
                      selected: category == item,
                      onSelected: (_) => setLocal(() => category = item),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('重要性', style: context.text.labelSmall?.copyWith(color: c.textTertiary)),
                  Expanded(
                    child: Slider(
                      value: importance.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      onChanged: (value) => setLocal(() => importance = value.round()),
                    ),
                  ),
                  Text('$importance', style: context.text.labelMedium),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(memory == null ? '保存记忆' : '保存修改'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  final text = content.text.trim();
  content.dispose();
  if (saved != true || text.isEmpty) return;
  if (memory == null) {
    await memories.addMemory(text, category: category, importance: importance);
  } else {
    memory.content = text;
    memory.category = category;
    memory.importance = importance;
    await memories.updateMemory(memory);
  }
  if (context.mounted) showToast(context, '记忆已保存');
}

Future<void> showProfileEditor(
  BuildContext context, {
  required MemoriesController memories,
}) async {
  final profile = memories.profile;
  final name = TextEditingController(text: profile.name);
  final occupation = TextEditingController(text: profile.occupation);
  final location = TextEditingController(text: profile.location);
  final education = TextEditingController(text: profile.education);
  final summary = TextEditingController(text: profile.summary);
  final thinking = TextEditingController(text: profile.thinkingStyle);
  final personality = TextEditingController(text: profile.personality.join('，'));
  final expertise = TextEditingController(text: profile.expertise.join('，'));
  final interests = TextEditingController(text: profile.interests.join('，'));
  final values = TextEditingController(text: profile.values.join('，'));
  final goals = TextEditingController(text: profile.goals.join('，'));
  final communication = TextEditingController(text: profile.communicationStyle.join('，'));
  final controllers = [
    name,
    occupation,
    location,
    education,
    summary,
    thinking,
    personality,
    expertise,
    interests,
    values,
    goals,
    communication,
  ];

  final saved = await showLumenSheet<bool>(
    context: context,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('编辑用户画像', style: context.text.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '这些字段会作为长期记忆注入对话。留空表示不知道；多个值用中文逗号分隔。',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.textTertiary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _FieldRow(
            children: [
              Expanded(child: _EditField(controller: name, label: '称呼')),
              const SizedBox(width: 10),
              Expanded(child: _EditField(controller: occupation, label: '职业')),
            ],
          ),
          const SizedBox(height: 10),
          _FieldRow(
            children: [
              Expanded(child: _EditField(controller: location, label: '所在地')),
              const SizedBox(width: 10),
              Expanded(child: _EditField(controller: education, label: '教育背景')),
            ],
          ),
          const SizedBox(height: 10),
          _EditField(controller: summary, label: '综合画像', maxLines: 3),
          const SizedBox(height: 10),
          _EditField(controller: thinking, label: '思维方式', maxLines: 2),
          const SizedBox(height: 14),
          Text(
            '特征与偏好（逗号分隔）',
            style: context.text.labelSmall?.copyWith(
              color: context.colors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _EditField(controller: personality, label: '性格特点'),
          const SizedBox(height: 8),
          _EditField(controller: expertise, label: '专业领域'),
          const SizedBox(height: 8),
          _EditField(controller: interests, label: '兴趣'),
          const SizedBox(height: 8),
          _EditField(controller: values, label: '价值观'),
          const SizedBox(height: 8),
          _EditField(controller: goals, label: '目标与计划'),
          const SizedBox(height: 8),
          _EditField(controller: communication, label: '沟通偏好'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存画像'),
            ),
          ),
        ],
      ),
    ),
  );

  final next = profile.copyWith(
    name: name.text.trim(),
    occupation: occupation.text.trim(),
    location: location.text.trim(),
    education: education.text.trim(),
    summary: summary.text.trim(),
    thinkingStyle: thinking.text.trim(),
    personality: _splitList(personality.text),
    expertise: _splitList(expertise.text),
    interests: _splitList(interests.text),
    values: _splitList(values.text),
    goals: _splitList(goals.text),
    communicationStyle: _splitList(communication.text),
    updatedAt: DateTime.now().toUtc(),
    version: profile.version + 1,
  );
  for (final controller in controllers) {
    controller.dispose();
  }
  if (saved != true) return;
  await memories.saveProfile(next);
  if (context.mounted) showToast(context, '画像已保存');
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(children: children);
}

class _EditField extends StatelessWidget {
  const _EditField({required this.controller, required this.label, this.maxLines = 1});

  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: context.text.bodySmall,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

List<String> _splitList(String value) => value
    .split(RegExp(r'[，,\n]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();
