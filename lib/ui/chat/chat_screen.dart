import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../services/chat_session.dart';
import '../../services/controllers.dart';
import '../common/widgets.dart';
import '../settings/providers_screen.dart';
import '../settings/settings_screen.dart';
import 'composer.dart';
import 'message_view.dart';
import 'model_picker.dart';
import 'reasoning_picker.dart';
import 'welcome_view.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.narrow,
    required this.onOpenDrawer,
    required this.onNewConversation,
    required this.onConversationDeleted,
  });

  final String conversationId;
  final bool narrow;
  final VoidCallback onOpenDrawer;
  final VoidCallback onNewConversation;
  final VoidCallback onConversationDeleted;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  ChatSession? _session;
  Conversation? _conversation;
  bool _initialized = false;
  bool _stickToBottom = true;
  String? _boundId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final distance = _scroll.position.maxScrollExtent - _scroll.position.pixels;
      _stickToBottom = distance < 160;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _bind();
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _bind();
    }
  }

  void _bind() {
    if (_boundId == widget.conversationId && _session != null) return;
    _boundId = widget.conversationId;
    _session?.removeListener(_onSessionChanged);
    final old = _session;
    _session = null;
    _conversation = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    final conversations = context.read<ConversationsController>();
    final conversation = conversations.byId(widget.conversationId);
    if (conversation == null) {
      setState(() {});
      return;
    }
    _conversation = conversation;
    final session = ChatSession(
      repo: context.read<AppRepository>(),
      conversation: conversation,
      providers: context.read<ProvidersController>(),
      settings: context.read<SettingsController>(),
      memories: context.read<MemoriesController>(),
      mcp: context.read<McpController>(),
      conversations: conversations,
      onMemoryUpdated: (changed) {
        if (!mounted) return;
        showToast(context, '已更新长期记忆（$changed 项），可在记忆页查看');
      },
    );
    session.addListener(_onSessionChanged);
    _session = session;
    setState(() {});
    unawaited(session.load().then((_) {
      if (!mounted || _session != session) return;
      setState(() {});
      _scrollToBottom(animate: false);
    }));
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session?.busy == true || _stickToBottom) {
      _scheduleScroll();
    }
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_stickToBottom || _session?.busy == true) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (animate) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _openModelPicker() async {
    final session = _session;
    if (session == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final selection = session.selection;
    final outcome = await showModelPicker(
      context,
      imageMode: session.conversation.imageMode,
      providerId: selection.provider.id,
      modelId: selection.model.id,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted || outcome == null) return;
    if (outcome.configure) {
      await _openProviders();
      return;
    }
    final selected = outcome.selection;
    if (selected != null) {
      await session.setModel(selected.provider, selected.model);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openReasoning() async {
    final session = _session;
    if (session == null) return;
    final selection = session.selection;
    if (!selection.model.reasoning) {
      showToast(context, '当前模型不支持思考参数。');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final level = await showReasoningPicker(
      context,
      current: session.conversation.reasoningLevel,
      provider: selection.provider,
      model: selection.model,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (level != null) await session.setReasoning(level);
  }

  Future<void> _openProviders() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProvidersScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _remember(ChatMessage message) async {
    final memories = context.read<MemoriesController>();
    final settings = context.read<SettingsController>();
    if (!settings.settings.memoryEnabled) {
      showToast(context, '记忆功能已关闭，可在设置中开启。');
      return;
    }
    final controller = TextEditingController(
      text: compactText(message.text, 400),
    );
    var category = MemoryCategory.other;
    var importance = 3;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final c = context.colors;
          return AlertDialog(
            title: const Text('加入长期记忆'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: '以第三人称写一句事实'),
                  ),
                  const SizedBox(height: 12),
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
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (saved == true && text.isNotEmpty) {
      await memories.addMemory(text, category: category, importance: importance);
      if (mounted) showToast(context, '已加入长期记忆');
    }
  }

  Future<void> _rename() async {
    final conversation = _conversation;
    if (conversation == null) return;
    final controller = TextEditingController(text: conversation.title);
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
      await context.read<ConversationsController>().rename(conversation, title);
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteConversation() async {
    final conversation = _conversation;
    if (conversation == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除这段对话？',
      message: '对话与其中的消息会从本机删除，无法恢复。相关的长期记忆不会自动删除。',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok && mounted) {
      await context.read<ConversationsController>().delete(conversation);
      if (mounted) widget.onConversationDeleted();
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = _session;
    if (session == null || _conversation == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final selection = session.selection;
    final conversation = _conversation!;
    final lastAssistantId = () {
      for (var i = session.messages.length - 1; i >= 0; i--) {
        if (session.messages[i].role == ChatRole.assistant) return session.messages[i].id;
      }
      return null;
    }();
    final isDemo = selection.provider.demo;

    return Column(
      children: [
        _Header(
          narrow: widget.narrow,
          conversation: conversation,
          selection: selection,
          onMenu: widget.onOpenDrawer,
          onModel: _openModelPicker,
          onNewChat: widget.onNewConversation,
          onRename: _rename,
          onPin: () async {
            await context.read<ConversationsController>().setPinned(conversation, !conversation.pinned);
            if (mounted) setState(() {});
          },
          onDelete: _deleteConversation,
          onSettings: _openSettings,
        ),
        if (isDemo)
          Material(
            color: c.primarySoft,
            child: InkWell(
              onTap: _openProviders,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
                child: Row(
                  children: [
                    Icon(Icons.science_outlined, size: 14, color: c.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '演示模式：不会调用真实模型。接入 API 后即可使用你选择的厂商。',
                        style: context.text.labelSmall?.copyWith(color: c.primary),
                      ),
                    ),
                    Text(
                      '接入模型',
                      style: context.text.labelSmall?.copyWith(
                        color: c.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 15, color: c.primary),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: session.messages.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: WelcomeView(
                          session: session,
                          onSuggestion: (prompt) {
                            _stickToBottom = true;
                            unawaited(session.send(prompt));
                          },
                          onConfigure: _openProviders,
                        ),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(widget.narrow ? 15 : 28, 22, widget.narrow ? 15 : 28, 10),
                  itemCount: session.messages.length,
                  itemBuilder: (context, index) {
                    final message = session.messages[index];
                    String? imagePrompt;
                    if (message.isImageGeneration) {
                      for (var i = index - 1; i >= 0; i--) {
                        if (session.messages[i].role == ChatRole.user) {
                          imagePrompt = session.messages[i].text;
                          break;
                        }
                      }
                    }
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: ChatMessageView(
                          key: ValueKey(message.id),
                          message: message,
                          isLastAssistant: message.id == lastAssistantId,
                          busy: session.busy,
                          imagePrompt: imagePrompt,
                          onRegenerate: message.id == lastAssistantId && !session.busy
                              ? () {
                                  _stickToBottom = true;
                                  unawaited(session.regenerateLast());
                                }
                              : null,
                          onRemember: () => _remember(message),
                          onConfigure: _openProviders,
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (session.lastError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: c.danger.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: c.danger.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 15, color: c.danger),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          session.lastError!,
                          style: context.text.labelSmall?.copyWith(color: c.danger),
                        ),
                      ),
                      TextButton(
                        onPressed: _openProviders,
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        child: const Text('配置'),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 15, color: c.danger),
                        onPressed: session.clearLastError,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (session.extractingMemory)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: c.textTertiary),
                ),
                const SizedBox(width: 6),
                Text(
                  '正在更新对你的了解…',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
        ChatComposer(
          session: session,
          selection: selection,
          narrow: widget.narrow,
          onOpenModelPicker: _openModelPicker,
          onOpenReasoning: _openReasoning,
          onNeedSettings: _openSettings,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.narrow,
    required this.conversation,
    required this.selection,
    required this.onMenu,
    required this.onModel,
    required this.onNewChat,
    required this.onRename,
    required this.onPin,
    required this.onDelete,
    required this.onSettings,
  });

  final bool narrow;
  final Conversation conversation;
  final ModelSelection selection;
  final VoidCallback onMenu;
  final VoidCallback onModel;
  final VoidCallback onNewChat;
  final VoidCallback onRename;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 62,
      padding: EdgeInsets.fromLTRB(narrow ? 6 : 18, 0, 8, 0),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.96),
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.7))),
      ),
      child: Row(
        children: [
          if (narrow)
            LumenIconButton(
              icon: Icons.menu_rounded,
              tooltip: '对话与菜单',
              onTap: onMenu,
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LumenMark(size: 25, plain: true),
            ),
          const SizedBox(width: 2),
          Expanded(
            child: InkWell(
              onTap: onModel,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title.isEmpty ? '新对话' : conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelLarge?.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        ProviderLogo(provider: selection.provider, size: 16),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${selection.provider.name} · ${selection.model.shortName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              color: c.textTertiary,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 13, color: c.textTertiary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          LumenIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: '新对话',
            onTap: onNewChat,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_rounded, size: 21),
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  onRename();
                  break;
                case 'pin':
                  onPin();
                  break;
                case 'settings':
                  onSettings();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('重命名对话')),
              PopupMenuItem(
                value: 'pin',
                child: Text(conversation.pinned ? '取消置顶' : '置顶对话'),
              ),
              const PopupMenuItem(value: 'settings', child: Text('设置')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除对话', style: TextStyle(color: Color(0xFFE5484D))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
