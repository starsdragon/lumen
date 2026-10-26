import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../services/controllers.dart';
import '../chat/model_picker.dart';
import '../common/widgets.dart';
import '../memory/memory_screen.dart';
import 'mcp_screen.dart';
import 'providers_screen.dart';
import 'search_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _textScale;

  @override
  void initState() {
    super.initState();
    _textScale = context.read<SettingsController>().settings.textScale;
  }

  Future<void> _pickDefaultModel() async {
    final settings = context.read<SettingsController>();
    final outcome = await showModelPicker(
      context,
      imageMode: false,
      providerId: settings.settings.lastUsedProviderId,
      modelId: settings.settings.lastUsedModelId,
    );
    if (!mounted || outcome == null) return;
    if (outcome.configure) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProvidersScreen()),
      );
      return;
    }
    final selection = outcome.selection;
    if (selection != null) {
      await settings.update(
        settings.settings.copyWith(
          defaultProviderId: selection.provider.id,
          defaultModelId: selection.model.id,
          lastUsedProviderId: selection.provider.id,
          lastUsedModelId: selection.model.id,
        ),
      );
      if (mounted) showToast(context, '默认模型已更新');
    }
  }

  Future<void> _updateMemoryModel() async {
    final settings = context.read<SettingsController>();
    final outcome = await showModelPicker(
      context,
      imageMode: false,
      providerId: settings.settings.memoryProviderId,
      modelId: settings.settings.memoryModelId,
    );
    if (!mounted || outcome == null) return;
    if (outcome.configure) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProvidersScreen()),
      );
      return;
    }
    final selection = outcome.selection;
    if (selection != null) {
      await settings.update(
        settings.settings.copyWith(
          memoryProviderId: selection.provider.id,
          memoryModelId: selection.model.id,
        ),
      );
    }
  }

  Future<void> _editSystemPrompt() async {
    final settings = context.read<SettingsController>();
    final controller = TextEditingController(text: settings.settings.systemPrompt);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = context.colors;
        return AlertDialog(
          title: const Text('系统提示词'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '决定 Lumen 的角色、语气与回答规则。长期记忆和联网说明会自动追加在它后面。',
                  style: context.text.bodySmall?.copyWith(color: c.textTertiary, height: 1.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  minLines: 6,
                  maxLines: 12,
                  style: context.text.bodySmall?.copyWith(height: 1.55),
                  decoration: const InputDecoration(hintText: '你希望 Lumen 怎样回答？'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => controller.text = defaultSystemPrompt,
                    icon: const Icon(Icons.restart_alt_rounded, size: 15),
                    label: const Text('恢复默认'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (result != null && result.trim().isNotEmpty) {
      await settings.update(settings.settings.copyWith(systemPrompt: result.trim()));
      if (mounted) showToast(context, '系统提示词已更新');
    }
    controller.dispose();
  }

  Future<void> _exportData() async {
    final repo = context.read<AppRepository>();
    try {
      final json = await repo.db.exportJson();
      if (!mounted) return;
      await copyText(context, json, message: '全部数据已复制为 JSON');
    } catch (error) {
      if (mounted) showToast(context, '导出失败：$error');
    }
  }

  Future<void> _clearMemories() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空全部记忆？',
      message: '画像与记忆条目会从本机删除，无法恢复。对话记录不受影响。',
      confirmLabel: '清空',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<MemoriesController>().clearAll();
    if (mounted) showToast(context, '记忆已清空');
  }

  Future<void> _resetOnboarding() async {
    final ok = await showConfirmDialog(
      context,
      title: '重新查看新手引导？',
      message: '会回到欢迎页，现有对话、记忆与厂商配置不会丢失。',
      confirmLabel: '重新查看',
    );
    if (!ok || !mounted) return;
    await context.read<SettingsController>().setOnboardingDone(false);
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _about() {
    final c = context.colors;
    showAboutDialog(
      context: context,
      applicationName: 'Lumen',
      applicationVersion: '1.0.6',
      applicationIcon: const LumenMark(size: 44),
      children: [
        Text(
          '一个本地优先的多厂商 AI Agent：长期记忆、流式对话、联网搜索、MCP 工具与图像生成。',
          style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 12),
        Text(
          '界面节奏参考 DeepSeek 官方 App 的克制风格；思考强度参数映射参考 RikkaHub 对各家 API 的公开实现。所有厂商名称与图标归各自权利人所有。',
          style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.5),
        ),
        const SizedBox(height: 10),
        Text(
          '你的对话与记忆默认保存在本机。使用联网、模型或生图服务时，相关请求会直接发送给对应服务商。',
          style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.5),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<SettingsController>();
    final providers = context.watch<ProvidersController>();
    final memories = context.watch<MemoriesController>();
    final mcp = context.watch<McpController>();
    final s = settings.settings;
    final configuredProviders = providers.providers.where((p) => p.hasKey && !p.demo).length;
    final memoryModel = s.memoryProviderId.isEmpty
        ? '跟随当前对话'
        : '${providers.byId(s.memoryProviderId)?.name ?? '未知厂商'} · ${providers.modelOf(s.memoryProviderId, s.memoryModelId)?.shortName ?? s.memoryModelId}';
    final searchReady = switch (s.search.provider) {
      SearchProvider.none => false,
      SearchProvider.tavily => settings.credentials.tavily.isNotEmpty,
      SearchProvider.google =>
        settings.credentials.google.isNotEmpty && s.search.googleCx.trim().isNotEmpty,
      SearchProvider.bing => settings.credentials.bing.isNotEmpty,
      SearchProvider.bingFree => true,
      SearchProvider.searxng => s.search.searxBaseUrl.trim().isNotEmpty,
      SearchProvider.duckduckgo => true,
    };

    final content = SafeArea(
      top: !widget.embedded,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(widget.embedded ? 32 : 20, widget.embedded ? 26 : 18, widget.embedded ? 32 : 20, 42),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.embedded) ...[
                  Text('设置', style: context.text.headlineSmall?.copyWith(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text(
                    '模型、记忆、联网、MCP 与外观都集中在这里。',
                    style: context.text.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: 22),
                ],
                SettingsSection(
                  title: '模型与厂商',
                  children: [
                    SettingsTile(
                      leading: const _StackedProviderLogos(),
                      title: '模型与厂商',
                      subtitle: '$configuredProviders 个已配置 · 支持自定义中转站',
                      trailing: Text(
                        '${providers.providers.where((p) => !p.demo).length}',
                        style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProvidersScreen()),
                      ),
                    ),
                    SettingsTile(
                      title: '默认对话模型',
                      subtitle: providers.readyProviders.isEmpty
                          ? '尚未配置'
                          : s.lastUsedProviderId.isEmpty
                              ? '新对话会使用最近一次选择'
                              : '最近使用：${providers.byId(s.lastUsedProviderId)?.name ?? '演示'}',
                      icon: Icons.tune_rounded,
                      onTap: _pickDefaultModel,
                    ),
                  ],
                ),
                SettingsSection(
                  title: '长期记忆',
                  footer: '画像与记忆保存在本机。注入上下文时，相关内容会发送给你选择的模型厂商。',
                  children: [
                    SettingsTile(
                      title: '启用长期记忆',
                      subtitle: '在对话中注入画像与相关记忆',
                      icon: Icons.auto_awesome_outlined,
                      trailing: Switch(
                        value: s.memoryEnabled,
                        onChanged: (value) =>
                            settings.update(s.copyWith(memoryEnabled: value)),
                      ),
                    ),
                    SettingsTile(
                      title: '自动提取',
                      subtitle: '每 ${s.memoryExtractEvery} 轮用户消息后分析一次',
                      icon: Icons.psychology_alt_outlined,
                      trailing: Switch(
                        value: s.autoExtractMemory,
                        onChanged: s.memoryEnabled
                            ? (value) =>
                                settings.update(s.copyWith(autoExtractMemory: value))
                            : null,
                      ),
                    ),
                    SettingsTile(
                      title: '提取频率',
                      subtitle: '对话较多时可调低频率以节省费用',
                      icon: Icons.speed_rounded,
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: [1, 2, 3, 5, 10].contains(s.memoryExtractEvery)
                              ? s.memoryExtractEvery
                              : 2,
                          isDense: true,
                          style: context.text.labelSmall?.copyWith(color: c.textSecondary),
                          items: [
                            for (final item in [1, 2, 3, 5, 10])
                              DropdownMenuItem(
                                value: item,
                                child: Text(item == 1 ? '每轮' : '每 $item 轮'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            settings.update(s.copyWith(memoryExtractEvery: value));
                          },
                        ),
                      ),
                    ),
                    SettingsTile(
                      title: '记忆提取模型',
                      subtitle: memoryModel,
                      icon: Icons.memory_rounded,
                      trailing: s.memoryProviderId.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '恢复跟随当前对话',
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () => settings.update(
                                s.copyWith(memoryProviderId: '', memoryModelId: ''),
                              ),
                            ),
                      onTap: _updateMemoryModel,
                    ),
                    SettingsTile(
                      title: '打开记忆库',
                      subtitle: memories.memories.isEmpty
                          ? '还没有记忆'
                          : '${memories.memories.length} 条记忆 · 画像',
                      icon: Icons.folder_open_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MemoryScreen()),
                      ),
                    ),
                  ],
                ),
                SettingsSection(
                  title: '能力扩展',
                  children: [
                    SettingsTile(
                      title: '联网搜索',
                      subtitle: '${s.search.provider.label} · ${searchReady ? '已就绪' : '待配置'}',
                      icon: Icons.travel_explore_rounded,
                      trailing: searchReady
                          ? const CapabilityChip(label: '可用', color: Color(0xFF0F9F78))
                          : const CapabilityChip(label: '待配置', color: Color(0xFFE08A00)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchSettingsScreen()),
                      ),
                    ),
                    SettingsTile(
                      title: 'MCP 工具',
                      subtitle: mcp.servers.isEmpty
                          ? '连接外部工具服务器，如文件、数据库、浏览器'
                          : '${mcp.servers.length} 个服务器 · ${mcp.servers.fold<int>(0, (sum, server) => sum + server.tools.length)} 个工具',
                      icon: Icons.extension_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const McpScreen()),
                      ),
                    ),
                  ],
                ),
                SettingsSection(
                  title: '对话与外观',
                  children: [
                    SettingsTile(
                      title: '主题',
                      icon: Icons.palette_outlined,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ThemeChip(
                            label: '系统',
                            selected: s.themeMode == ThemeMode.system,
                            onTap: () => settings.setTheme(ThemeMode.system),
                          ),
                          _ThemeChip(
                            label: '浅色',
                            selected: s.themeMode == ThemeMode.light,
                            onTap: () => settings.setTheme(ThemeMode.light),
                          ),
                          _ThemeChip(
                            label: '深色',
                            selected: s.themeMode == ThemeMode.dark,
                            onTap: () => settings.setTheme(ThemeMode.dark),
                          ),
                        ],
                      ),
                    ),
                    SettingsTile(
                      title: '文字大小',
                      subtitle: '${(_textScale * 100).round()}%',
                      icon: Icons.format_size_rounded,
                      trailing: SizedBox(
                        width: 150,
                        child: Slider(
                          value: _textScale,
                          min: 0.9,
                          max: 1.2,
                          divisions: 6,
                          onChanged: (value) => setState(() => _textScale = value),
                          onChangeEnd: (value) =>
                              settings.update(s.copyWith(textScale: value)),
                        ),
                      ),
                    ),
                    SettingsTile(
                      title: 'Enter 发送消息',
                      subtitle: '关闭后用 Ctrl / Cmd + Enter 发送',
                      icon: Icons.keyboard_return_rounded,
                      trailing: Switch(
                        value: s.sendOnEnter,
                        onChanged: (value) => settings.update(s.copyWith(sendOnEnter: value)),
                      ),
                    ),
                    SettingsTile(
                      title: '系统提示词',
                      subtitle: truncate(s.systemPrompt.replaceAll(RegExp(r'\s+'), ' '), 70),
                      icon: Icons.article_outlined,
                      onTap: _editSystemPrompt,
                    ),
                  ],
                ),
                SettingsSection(
                  title: '数据',
                  footer: '所有数据默认保存在本机。导出的 JSON 包含对话、记忆与厂商配置（不含 API Key）。',
                  children: [
                    SettingsTile(
                      title: '导出全部数据',
                      subtitle: '复制为 JSON，可自行备份',
                      icon: Icons.download_outlined,
                      onTap: _exportData,
                    ),
                    SettingsTile(
                      title: '清空记忆',
                      subtitle: '删除画像与全部记忆条目',
                      icon: Icons.delete_sweep_outlined,
                      danger: true,
                      onTap: _clearMemories,
                    ),
                    SettingsTile(
                      title: '重新查看新手引导',
                      subtitle: '回到欢迎页重新选择厂商',
                      icon: Icons.replay_rounded,
                      onTap: _resetOnboarding,
                    ),
                  ],
                ),
                SettingsSection(
                  title: '关于',
                  children: [
                    SettingsTile(
                      title: 'Lumen 1.0.6',
                      subtitle: '本地优先 · 多厂商 · 长期记忆',
                      icon: Icons.info_outline_rounded,
                      onTap: _about,
                    ),
                    SettingsTile(
                      title: '隐私说明',
                      subtitle: 'Key 加密存储；请求直达厂商',
                      icon: Icons.shield_outlined,
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('隐私说明'),
                            content: Text(
                              'API Key 保存在系统安全存储中，不写入对话数据库，也不会发送到 Lumen 的服务器。\n\n'
                              '对话、画像与记忆保存在本机。调用模型、联网搜索或生图时，相关请求会直接发送到你配置的服务商。\n\n'
                              '抓取网页时仅允许公开的 http/https 地址，并拒绝访问本机、局域网与云元数据地址。',
                              style: context.text.bodySmall?.copyWith(height: 1.65),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('知道了'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                Center(
                  child: Text(
                    'Lumen · 本地优先的 AI Agent',
                    style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('设置'),
      ),
      body: content,
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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

class _StackedProviderLogos extends StatelessWidget {
  const _StackedProviderLogos();

  @override
  Widget build(BuildContext context) {
    final providers = context.watch<ProvidersController>();
    final items = providers.providers
        .where((p) => !p.demo && p.logo.isNotEmpty)
        .take(3)
        .toList();
    return SizedBox(
      width: 78,
      height: 34,
      child: Row(
        children: [
          for (final provider in items)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: ProviderLogo(provider: provider, size: 24),
            ),
        ],
      ),
    );
  }
}
