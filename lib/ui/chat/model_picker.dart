import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/controllers.dart';
import '../common/widgets.dart';
import '../settings/model_editor_dialog.dart';
import 'model_settings_sheet.dart';

class ModelPickerOutcome {
  const ModelPickerOutcome.selection(this.selection) : configure = false;
  const ModelPickerOutcome.configure()
      : selection = null,
        configure = true;

  final ModelSelection? selection;
  final bool configure;
}

Future<ModelPickerOutcome?> showModelPicker(
  BuildContext context, {
  required bool imageMode,
  required String providerId,
  required String modelId,
}) {
  return showLumenSheet<ModelPickerOutcome>(
    context: context,
    builder: (context) => _ModelPickerSheet(
      imageMode: imageMode,
      providerId: providerId,
      modelId: modelId,
    ),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.imageMode,
    required this.providerId,
    required this.modelId,
  });

  final bool imageMode;
  final String providerId;
  final String modelId;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _editModel(ProviderConfig provider, ModelInfo model) async {
    final updated = await showModelEditorDialog(
      context,
      existingIds: provider.models.map((m) => m.id).toSet(),
      initial: model,
    );
    if (updated == null || !mounted) return;
    await context.read<ProvidersController>().updateModel(provider, updated);
    if (mounted) showToast(context, '已更新「${updated.name}」的能力');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final providers = context.watch<ProvidersController>();
    final appSettings = context.watch<SettingsController>();
    final query = _search.text.trim().toLowerCase();
    final ready = providers.readyProviders;
    final grouped = <(ProviderConfig, List<ModelInfo>)>[];
    for (final provider in ready) {
      final pool = widget.imageMode ? provider.imageModels : provider.chatModels;
      final filtered = pool.where((model) {
        if (query.isEmpty) return true;
        return model.id.toLowerCase().contains(query) ||
            model.name.toLowerCase().contains(query) ||
            provider.name.toLowerCase().contains(query);
      }).toList();
      if (filtered.isNotEmpty) grouped.add((provider, filtered));
    }
    final unconfigured = providers.providers
        .where((p) => !p.demo && !p.ready)
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList(growable: false);
    final hasContent = grouped.isNotEmpty || unconfigured.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.imageMode ? '选择生图模型' : '选择模型', style: context.text.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          widget.imageMode
                              ? '不同厂商的图像模型，支持比例与提示词'
                              : '来自各平台原生 /models 接口；齿轮可设置输入/输出上限',
                          style: context.text.bodySmall?.copyWith(color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  if (providers.syncing.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: '刷新全部模型列表',
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: () async {
                        await providers.refreshAll();
                        if (context.mounted) {
                          final failures = providers.providers
                              .where((p) => p.syncError != null && p.hasKey)
                              .length;
                          showToast(
                            context,
                            failures == 0 ? '模型列表已刷新' : '已刷新，$failures 个厂商同步失败',
                          );
                        }
                      },
                    ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索模型或厂商',
                  prefixIcon: Icon(Icons.search_rounded, size: 19, color: c.textTertiary),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
            Expanded(
              child: !hasContent
                  ? EmptyState(
                      icon: Icons.tune_rounded,
                      title: widget.imageMode ? '没有可用的生图模型' : '没有匹配的模型',
                      message: widget.imageMode
                          ? '先在设置中配置支持生图的厂商（智谱、MiniMax、百炼、Gemini 或自定义 OpenAI 图像接口）。'
                          : '尝试换一个关键词，或去配置更多厂商。',
                      action: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, const ModelPickerOutcome.configure()),
                        icon: const Icon(Icons.settings_outlined, size: 17),
                        label: const Text('配置厂商'),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                      children: [
                        for (final group in grouped) ...[
                          _ProviderHeader(provider: group.$1),
                          for (final model in group.$2)
                            _ModelRow(
                              provider: group.$1,
                              model: model,
                              limit: appSettings.settings.modelLimits[
                                  modelLimitKey(group.$1.id, model.id)],
                              selected: group.$1.id == widget.providerId &&
                                  model.id == widget.modelId,
                              onTap: () => Navigator.pop(
                                context,
                                ModelPickerOutcome.selection(ModelSelection(group.$1, model)),
                              ),
                              onSettings: () => showModelTokenSettings(
                                context,
                                provider: group.$1,
                                model: model,
                              ),
                              onEdit: group.$1.demo
                                  ? null
                                  : () => _editModel(group.$1, model),
                            ),
                          const SizedBox(height: 8),
                        ],
                        if (unconfigured.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 5),
                            child: Text(
                              '其他平台',
                              style: context.text.labelSmall?.copyWith(
                                color: c.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final provider in unconfigured)
                            _UnconfiguredProviderRow(
                              provider: provider,
                              onTap: () => Navigator.pop(
                                context,
                                const ModelPickerOutcome.configure(),
                              ),
                            ),
                          const SizedBox(height: 4),
                        ],
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '模型能力标签由 ID 与厂商元数据推断；若平台新增模型，点右上角刷新即可。',
                                  style: context.text.bodySmall?.copyWith(color: c.textTertiary),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    Navigator.pop(context, const ModelPickerOutcome.configure()),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('更多厂商'),
                              ),
                            ],
                          ),
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

class _UnconfiguredProviderRow extends StatelessWidget {
  const _UnconfiguredProviderRow({required this.provider, required this.onTap});

  final ProviderConfig provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                ProviderLogo(provider: provider, size: 26),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: context.text.bodyMedium?.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        provider.hasKey ? '已停用 · 点此查看' : '未配置 API Key',
                        style: context.text.labelSmall?.copyWith(
                          color: c.textTertiary,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '去配置',
                  style: context.text.labelSmall?.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: c.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({required this.provider});

  final ProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 7),
      child: Row(
        children: [
          ProviderLogo(provider: provider, size: 25),
          const SizedBox(width: 9),
          Text(provider.name, style: context.text.labelLarge?.copyWith(fontSize: 13)),
          const SizedBox(width: 7),
          if (provider.demo)
            const CapabilityChip(label: '无需 Key', color: Color(0xFF0F9F78))
          else if (provider.modelsSyncedAt != null)
            Text(
              '${provider.models.length} 个模型',
              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
            ),
          const Spacer(),
          if (provider.syncError != null)
            Tooltip(
              message: provider.syncError!,
              child: Icon(Icons.cloud_off_outlined, size: 15, color: c.warning),
            ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.provider,
    required this.model,
    required this.limit,
    required this.selected,
    required this.onTap,
    required this.onSettings,
    this.onEdit,
  });

  final ProviderConfig provider;
  final ModelInfo model;
  final ModelTokenLimit? limit;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSettings;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final input = effectiveInputLimit(model, limit);
    final output = effectiveOutputLimit(model, limit);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: selected ? c.primary : c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${tokenLabel(input)} 输入 · ${tokenLabel(output)} 输出',
                            style: context.text.labelSmall?.copyWith(
                              color: limit == null ? c.textTertiary : c.primary,
                              fontSize: 9.5,
                            ),
                          ),
                          if (model.vision) const CapabilityChip(label: '视觉', icon: Icons.image_outlined),
                          if (model.reasoning) ...[
                            const CapabilityChip(label: '思考', icon: Icons.psychology_alt_outlined),
                          ],
                          if (model.imageGeneration) ...[
                            const CapabilityChip(label: '生图', icon: Icons.auto_awesome_outlined),
                          ],
                          if (model.tools && !model.imageGeneration) ...[
                            const CapabilityChip(label: '工具', icon: Icons.build_outlined),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: '编辑模型能力',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.edit_outlined, size: 16, color: c.textTertiary),
                    onPressed: onEdit,
                  ),
                IconButton(
                  tooltip: limit == null ? '设置输入/输出 token 上限' : '已自定义 token 上限',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 17,
                    color: limit == null ? c.textTertiary : c.primary,
                  ),
                  onPressed: onSettings,
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 19, color: c.primary)
                else
                  Icon(Icons.circle_outlined, size: 18, color: c.borderStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
