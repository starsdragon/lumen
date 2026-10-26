import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../services/controllers.dart';
import 'chat/chat_screen.dart';
import 'common/widgets.dart';
import 'memory/memory_screen.dart';
import 'settings/settings_screen.dart';

enum _Destination { chat, memory, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedId;
  _Destination _destination = _Destination.chat;
  bool _bootstrapping = true;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final conversations = context.read<ConversationsController>();
    if (conversations.conversations.isEmpty) {
      await _createConversation();
    } else {
      final visible = conversations.conversations
          .where((c) => c.userTurns > 0 || c.lastPreview.isNotEmpty)
          .toList();
      _selectedId = visible.isNotEmpty
          ? visible.first.id
          : conversations.conversations.first.id;
    }
    if (mounted) {
      setState(() => _bootstrapping = false);
    }
  }

  ModelSelection _defaultSelection() {
    final settings = context.read<SettingsController>().settings;
    final providers = context.read<ProvidersController>();
    final providerId = settings.lastUsedProviderId.isNotEmpty
        ? settings.lastUsedProviderId
        : settings.defaultProviderId;
    final modelId = settings.lastUsedModelId.isNotEmpty
        ? settings.lastUsedModelId
        : settings.defaultModelId;
    return providers.resolve(providerId, modelId);
  }

  Future<void> _createConversation() async {
    final conversations = context.read<ConversationsController>();
    final selection = _defaultSelection();
    final conversation = await conversations.create(
      providerId: selection.provider.id,
      modelId: selection.model.id,
    );
    if (!mounted) return;
    setState(() {
      _selectedId = conversation.id;
      _destination = _Destination.chat;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  bool get _currentIsEmpty {
    final conversation = context.read<ConversationsController>().byId(_selectedId ?? '');
    return conversation == null || (conversation.userTurns == 0 && conversation.lastPreview.isEmpty);
  }

  Future<void> _newChat() async {
    if (_currentIsEmpty) {
      _scaffoldKey.currentState?.closeDrawer();
      setState(() => _destination = _Destination.chat);
      return;
    }
    await _createConversation();
  }

  void _selectConversation(String id) {
    _scaffoldKey.currentState?.closeDrawer();
    setState(() {
      _selectedId = id;
      _destination = _Destination.chat;
    });
  }

  Future<void> _afterDelete(Conversation deleted) async {
    final conversations = context.read<ConversationsController>();
    if (_selectedId != deleted.id) return;
    if (conversations.conversations.isEmpty) {
      await _createConversation();
    } else {
      final next = conversations.conversations.first;
      if (mounted) {
        setState(() {
          _selectedId = next.id;
          _destination = _Destination.chat;
        });
      }
    }
  }

  Future<void> _onConversationDeleted() async {
    final conversations = context.read<ConversationsController>();
    if (conversations.conversations.isEmpty) {
      await _createConversation();
    } else {
      final next = conversations.conversations.first;
      if (mounted) {
        setState(() {
          _selectedId = next.id;
          _destination = _Destination.chat;
        });
      }
    }
  }

  Future<void> _openMemory({required bool embedded}) async {
    _scaffoldKey.currentState?.closeDrawer();
    if (embedded) {
      setState(() => _destination = _Destination.memory);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MemoryScreen()),
    );
  }

  Future<void> _openSettings({required bool embedded}) async {
    _scaffoldKey.currentState?.closeDrawer();
    if (embedded) {
      setState(() => _destination = _Destination.settings);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 980;
    if (_bootstrapping || _selectedId == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LumenMark(size: 46),
              const SizedBox(height: 18),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
              ),
            ],
          ),
        ),
      );
    }

    if (wide) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Row(
            children: [
              SizedBox(
                width: 292,
                child: _Sidebar(
                selectedId: _selectedId,
                embedded: true,
                onNewChat: _newChat,
                onSelect: _selectConversation,
                onMemory: () => _openMemory(embedded: true),
                onSettings: () => _openSettings(embedded: true),
                onDeleted: _afterDelete,
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: c.border),
            Expanded(
              child: IndexedStack(
                index: _destination.index,
                children: [
                  ChatScreen(
                    key: ValueKey(_selectedId),
                    conversationId: _selectedId!,
                    narrow: false,
                    onOpenDrawer: () {},
                    onNewConversation: _newChat,
                    onConversationDeleted: _onConversationDeleted,
                  ),
                  const MemoryScreen(embedded: true),
                  const SettingsScreen(embedded: true),
                ],
              ),
            ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.background,
      drawer: Drawer(
        backgroundColor: c.sidebar,
        width: width * 0.86 > 330 ? 330 : width * 0.86,
        child: SafeArea(
          child: _Sidebar(
            selectedId: _selectedId,
            embedded: false,
            onNewChat: _newChat,
            onSelect: _selectConversation,
            onMemory: () => _openMemory(embedded: false),
            onSettings: () => _openSettings(embedded: false),
            onDeleted: _afterDelete,
          ),
        ),
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) => ChatScreen(
            key: ValueKey(_selectedId),
            conversationId: _selectedId!,
            narrow: true,
            onOpenDrawer: () => Scaffold.of(context).openDrawer(),
            onNewConversation: _newChat,
            onConversationDeleted: _onConversationDeleted,
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.selectedId,
    required this.embedded,
    required this.onNewChat,
    required this.onSelect,
    required this.onMemory,
    required this.onSettings,
    required this.onDeleted,
  });

  final String? selectedId;
  final bool embedded;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelect;
  final VoidCallback onMemory;
  final VoidCallback onSettings;
  final ValueChanged<Conversation> onDeleted;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conversations = context.watch<ConversationsController>().conversations;
    final memories = context.watch<MemoriesController>();
    final query = _search.text.trim().toLowerCase();
    final visible = conversations
        .where((conversation) =>
            conversation.userTurns > 0 ||
            conversation.lastPreview.isNotEmpty ||
            conversation.id == widget.selectedId ||
            conversation.pinned)
        .where((conversation) {
      if (query.isEmpty) return true;
      return conversation.title.toLowerCase().contains(query) ||
          conversation.lastPreview.toLowerCase().contains(query);
    }).toList();

    final pinned = visible.where((c) => c.pinned).toList();
    final normal = visible.where((c) => !c.pinned).toList();
    final groups = <String, List<Conversation>>{};
    for (final conversation in normal) {
      final label = relativeDay(conversation.updatedAt);
      final group = switch (label) {
        '今天' => '今天',
        '昨天' => '昨天',
        _ when label.endsWith('天前') => '最近 7 天',
        _ => '更早',
      };
      groups.putIfAbsent(group, () => []).add(conversation);
    }

    return Container(
      color: c.sidebar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                const LumenMark(size: 31),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lumen',
                      style: context.text.titleMedium?.copyWith(
                        fontSize: 17,
                        letterSpacing: -0.25,
                      ),
                    ),
                    Text(
                      '会记住你的 AI 伙伴',
                      style: context.text.labelSmall?.copyWith(
                        color: c.textTertiary,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (!widget.embedded)
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 9),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton.icon(
                onPressed: widget.onNewChat,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新对话'),
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: context.text.labelLarge?.copyWith(fontSize: 13.5),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: context.text.bodySmall,
                decoration: InputDecoration(
                  hintText: '搜索对话',
                  prefixIcon: Icon(Icons.search_rounded, size: 17, color: c.textTertiary),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 14),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: c.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        query.isEmpty ? '还没有对话\n开始第一次聊天吧' : '没有匹配的对话',
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall?.copyWith(color: c.textTertiary, height: 1.6),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        const _GroupLabel('置顶'),
                        for (final conversation in pinned)
                          _ConversationTile(
                            conversation: conversation,
                            selected: conversation.id == widget.selectedId,
                            onTap: () => widget.onSelect(conversation.id),
                            onDeleted: widget.onDeleted,
                          ),
                        const SizedBox(height: 4),
                      ],
                      for (final entry in groups.entries) ...[
                        _GroupLabel(entry.key),
                        for (final conversation in entry.value)
                          _ConversationTile(
                            conversation: conversation,
                            selected: conversation.id == widget.selectedId,
                            onTap: () => widget.onSelect(conversation.id),
                            onDeleted: widget.onDeleted,
                          ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Column(
              children: [
                _NavTile(
                  icon: Icons.auto_awesome_outlined,
                  label: '长期记忆',
                  trailing: memories.memories.isEmpty ? null : '${memories.memories.length}',
                  onTap: widget.onMemory,
                ),
                _NavTile(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  onTap: widget.onSettings,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 11, color: c.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        '本地优先 · Lumen 1.0.5',
                        style: context.text.labelSmall?.copyWith(
                          color: c.textTertiary,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 5),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: c.textTertiary,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _ConversationTile extends StatefulWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onDeleted,
  });

  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Conversation> onDeleted;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hover = false;

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '对话标题'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.trim().isNotEmpty && mounted) {
      await context.read<ConversationsController>().rename(widget.conversation, title);
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这段对话？',
      message: '对话与消息会从本机删除，无法恢复。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    final conversation = widget.conversation;
    await context.read<ConversationsController>().delete(conversation);
    if (mounted) widget.onDeleted(conversation);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conversation = widget.conversation;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: widget.selected
              ? c.primarySoft
              : (_hover ? c.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 5, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conversation.title.isEmpty ? '新对话' : conversation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium?.copyWith(
                            color: widget.selected ? c.primary : c.textPrimary,
                            fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 12.5,
                          ),
                        ),
                        if (conversation.lastPreview.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            plainPreview(conversation.lastPreview, 80),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              color: c.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (conversation.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.push_pin_outlined, size: 11, color: c.textTertiary),
                    ),
                  if (_hover || widget.selected)
                    PopupMenuButton<String>(
                      tooltip: '更多',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: Icon(Icons.more_horiz_rounded, size: 16, color: c.textTertiary),
                      onSelected: (value) async {
                        switch (value) {
                          case 'rename':
                            await _rename();
                            break;
                          case 'pin':
                            await context
                                .read<ConversationsController>()
                                .setPinned(conversation, !conversation.pinned);
                            break;
                          case 'delete':
                            await _delete();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(conversation.pinned ? '取消置顶' : '置顶'),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    )
                  else
                    const SizedBox(width: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.label, required this.onTap, this.trailing});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 17, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: c.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              if (trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    trailing!,
                    style: context.text.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
