import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/controllers.dart';
import '../common/widgets.dart';
import '../chat/model_settings_sheet.dart';
import 'model_editor_dialog.dart';

class ProvidersScreen extends StatelessWidget {
  const ProvidersScreen({super.key});

  Future<void> _addCustom(BuildContext context) async {
    final provider = ProviderConfig(
      id: newId('prov'),
      name: '自定义中转站',
      protocol: LlmProtocol.openai,
      baseUrl: '',
      logo: '',
      builtin: false,
      sortOrder: 1000 + DateTime.now().millisecondsSinceEpoch ~/ 1000,
      description: '兼容 OpenAI Chat Completions 的中转站或自建网关',
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProviderEditScreen(newProvider: provider)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final providers = context.watch<ProvidersController>();
    final configured = providers.providers
        .where((p) => !p.demo && p.hasKey)
        .toList(growable: false);
    final unconfigured = providers.providers
        .where((p) => !p.demo && !p.hasKey)
        .toList(growable: false);
    final demo = providers.byId('demo');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('模型与厂商'),
        actions: [
          if (providers.syncing.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: '刷新全部模型',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () async {
                await providers.refreshAll();
                if (context.mounted) showToast(context, '模型列表刷新完成');
              },
            ),
          IconButton(
            tooltip: '添加自定义中转站',
            icon: const Icon(Icons.add_rounded, size: 21),
            onPressed: () => _addCustom(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '添加你常用的平台，填入 Key 后会自动拉取模型列表。也可以接入任意 OpenAI 兼容中转站。',
                  style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.55),
                ),
                const SizedBox(height: 16),
                if (demo != null) ...[
                  _ProviderCard(provider: demo, onTap: null),
                  const SizedBox(height: 18),
                ],
                if (configured.isNotEmpty) ...[
                  _SectionLabel('已配置', count: configured.length),
                  for (final provider in configured)
                    _ProviderCard(
                      provider: provider,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProviderEditScreen(providerId: provider.id),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                ],
                if (unconfigured.isNotEmpty) ...[
                  _SectionLabel('其他平台', count: unconfigured.length),
                  for (final provider in unconfigured)
                    _ProviderCard(
                      provider: provider,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProviderEditScreen(providerId: provider.id),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                ],
                OutlinedButton.icon(
                  onPressed: () => _addCustom(context),
                  icon: const Icon(Icons.hub_outlined, size: 17),
                  label: const Text('添加自定义中转站'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Key 使用系统安全存储保存；模型列表来自各平台原生接口，失败时保留上次缓存。',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 0, 3, 8),
      child: Row(
        children: [
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: c.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: context.text.labelSmall?.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, this.onTap});

  final ProviderConfig provider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ready = provider.demo || (provider.enabled && provider.hasKey);
    final status = provider.demo
        ? '内置演示'
        : !provider.hasKey
            ? '未配置 Key'
            : provider.enabled
                ? '已启用'
                : '已停用';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                ProviderLogo(provider: provider, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleMedium?.copyWith(fontSize: 14.5),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              provider.protocol.label,
                              style: context.text.labelSmall?.copyWith(
                                color: c.textTertiary,
                                fontSize: 8.5,
                              ),
                            ),
                          ),
                          if (provider.demo) ...[
                            const SizedBox(width: 5),
                            const CapabilityChip(label: '无需 Key', color: Color(0xFF0F9F78)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider.baseUrl.isEmpty
                            ? (provider.description.isNotEmpty ? provider.description : '尚未设置 Base URL')
                            : provider.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ready ? c.success : c.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            style: context.text.labelSmall?.copyWith(
                              color: ready ? c.success : c.textTertiary,
                              fontSize: 9.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${provider.models.length} 个模型',
                            style: context.text.labelSmall?.copyWith(
                              color: c.textTertiary,
                              fontSize: 9.5,
                            ),
                          ),
                          if (provider.syncError != null) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: provider.syncError!,
                              child: Icon(Icons.cloud_off_outlined, size: 12, color: c.warning),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded, size: 19, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProviderEditScreen extends StatefulWidget {
  const ProviderEditScreen({super.key, this.providerId, this.newProvider});

  final String? providerId;
  final ProviderConfig? newProvider;

  @override
  State<ProviderEditScreen> createState() => _ProviderEditScreenState();
}

class _ProviderEditScreenState extends State<ProviderEditScreen> {
  late ProviderConfig _provider;
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _key;
  late final TextEditingController _headers;
  late final TextEditingController _body;
  bool _obscure = true;
  bool _saving = false;
  String? _error;
  bool _isNew = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.newProvider ?? _providerFromContext();
    _isNew = widget.newProvider != null;
    _provider = existing == null
        ? ProviderConfig(
            id: newId('prov'),
            name: '自定义中转站',
            protocol: LlmProtocol.openai,
            baseUrl: '',
          )
        : ProviderConfig.fromJson(existing.toJson());
    _name = TextEditingController(text: _provider.name);
    _baseUrl = TextEditingController(text: _provider.baseUrl);
    _key = TextEditingController();
    _headers = TextEditingController(
      text: _provider.customHeaders.isEmpty
          ? ''
          : const JsonEncoder.withIndent('  ').convert(_provider.customHeaders),
    );
    _body = TextEditingController(
      text: _provider.customBody.isEmpty
          ? ''
          : const JsonEncoder.withIndent('  ').convert(_provider.customBody),
    );
  }

  ProviderConfig? _providerFromContext() {
    final providers = context.read<ProvidersController>();
    final id = widget.providerId;
    if (id == null) return null;
    return providers.byId(id);
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _key.dispose();
    _headers.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<bool> _save({bool pop = true}) async {
    final providers = context.read<ProvidersController>();
    if (_provider.demo) return true;
    final base = normalizeBaseUrl(_baseUrl.text.trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '厂商名称不能为空。');
      return false;
    }
    if (base.isEmpty) {
      setState(() => _error = 'Base URL 不能为空。');
      return false;
    }
    Map<String, String> headers;
    Map<String, dynamic> body;
    try {
      headers = _parseStringMap(_headers.text);
      body = _parseObject(_body.text);
    } catch (error) {
      setState(() => _error = '高级 JSON 格式错误：$error');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _provider
        ..name = _name.text.trim()
        ..baseUrl = base
        ..enabled = _provider.enabled
        ..customHeaders = headers
        ..customBody = body;
      await providers.saveProvider(
        _provider,
        apiKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
        syncAfterSave: pop,
      );
      _key.clear();
      if (!mounted) return true;
      if (pop) Navigator.of(context).pop(true);
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = friendlyNetworkError(error));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refresh() async {
    final providers = context.read<ProvidersController>();
    final saved = await _save(pop: false);
    if (!saved || !mounted) return;
    try {
      await providers.refreshModels(_provider);
      final current = providers.byId(_provider.id);
      if (mounted) {
        setState(() => _provider.models = current?.models ?? _provider.models);
        showToast(context, '已获取 ${current?.models.length ?? 0} 个模型');
      }
    } catch (error) {
      if (mounted) showToast(context, friendlyNetworkError(error));
    }
  }

  Future<void> _clearKey() async {
    final ok = await showConfirmDialog(
      context,
      title: '清除 API Key？',
      message: '清除后该厂商将无法发起请求，模型列表仍会保留。',
      confirmLabel: '清除',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<ProvidersController>().saveProvider(_provider, clearKey: true);
    if (mounted) {
      setState(() {});
      showToast(context, 'Key 已清除');
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这个厂商？',
      message: '只会删除本机的厂商配置与 Key，不影响平台上的账号。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<ProvidersController>().deleteProvider(_provider);
    if (mounted) Navigator.of(context).pop(true);
  }

  Map<String, String> _parseStringMap(String raw) {
    if (raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('需要一个 JSON 对象');
    return decoded.map((key, value) => MapEntry('$key', '$value'));
  }

  Map<String, dynamic> _parseObject(String raw) {
    if (raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('需要一个 JSON 对象');
    return decoded.map((key, value) => MapEntry('$key', value));
  }

  String _tokenSummary(AppSettings settings, ProviderConfig provider, ModelInfo model) {
    final limit = settings.modelLimits[modelLimitKey(provider.id, model.id)];
    return '${tokenLabel(effectiveInputLimit(model, limit))} 输入 · '
        '${tokenLabel(effectiveOutputLimit(model, limit))} 输出';
  }

  bool _hasCustomLimit(AppSettings settings, ProviderConfig provider, ModelInfo model) =>
      settings.modelLimits[modelLimitKey(provider.id, model.id)] != null;

  Future<void> _addModel() async {
    final model = await showModelEditorDialog(
      context,
      existingIds: _provider.models.map((m) => m.id).toSet(),
    );
    if (model == null || !mounted) return;
    final providers = context.read<ProvidersController>();
    final exists = providers.byId(_provider.id) != null;
    setState(() => _provider.models = [..._provider.models, model]);
    if (exists) {
      await providers.updateModel(_provider, model);
    }
    if (mounted) {
      showToast(context, exists ? '已添加「${model.name}」' : '已添加「${model.name}」，保存厂商后生效');
    }
  }

  Future<void> _editModel(ModelInfo model) async {
    final updated = await showModelEditorDialog(
      context,
      existingIds: _provider.models.map((m) => m.id).toSet(),
      initial: model,
    );
    if (updated == null || !mounted) return;
    final providers = context.read<ProvidersController>();
    final exists = providers.byId(_provider.id) != null;
    setState(() {
      _provider.models = [
        for (final item in _provider.models)
          if (item.id == model.id) updated else item,
      ];
    });
    if (exists) {
      await providers.updateModel(_provider, updated);
    }
    if (mounted) {
      showToast(context, exists ? '已更新「${updated.name}」' : '已更新「${updated.name}」，保存厂商后生效');
    }
  }

  Future<void> _removeModel(ModelInfo model) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这个模型？',
      message: '「${model.name}」会从当前厂商的模型列表移除。已同步的模型会在下次刷新时恢复。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    final providers = context.read<ProvidersController>();
    final settings = context.read<SettingsController>();
    final exists = providers.byId(_provider.id) != null;
    setState(() => _provider.models = _provider.models.where((m) => m.id != model.id).toList());
    if (exists) {
      await providers.removeModel(_provider, model.id);
    }
    await settings.setModelLimit(_provider.id, model.id, null);
    if (mounted) showToast(context, '已删除「${model.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final providers = context.watch<ProvidersController>();
    final appSettings = context.watch<SettingsController>();
    final current = providers.byId(_provider.id) ?? _provider;
    final models = _provider.models;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(_isNew ? '添加厂商' : current.name),
        actions: [
          if (!_isNew && !_provider.demo)
            IconButton(
              tooltip: '删除厂商',
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _saving ? null : () => _save(),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ProviderLogo(provider: current, size: 46),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(current.name, style: context.text.titleLarge),
                          Text(
                            current.demo
                                ? '内置演示，无需 Key'
                                : '${current.protocol.label} · ${current.hasKey ? 'Key 已保存' : '尚未配置 Key'}',
                            style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    if (current.demo)
                      const CapabilityChip(label: '演示', color: Color(0xFF0F9F78)),
                  ],
                ),
                const SizedBox(height: 20),
                if (current.demo)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.primarySoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      '演示模型用于体验界面、流式输出和记忆流程，不会调用外部服务。要获得真实回答，请在下方添加其他厂商。',
                      style: context.text.bodySmall?.copyWith(
                        color: c.textSecondary,
                        height: 1.55,
                      ),
                    ),
                  )
                else ...[
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: '显示名称'),
                  ),
                  const SizedBox(height: 12),
                  Text('接口协议', style: context.text.labelSmall?.copyWith(color: c.textTertiary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final protocol in LlmProtocol.values)
                        ChoiceChip(
                          label: Text(protocol.label, style: const TextStyle(fontSize: 11.5)),
                          selected: _provider.protocol == protocol,
                          onSelected: (selected) {
                            if (!selected) return;
                            setState(() {
                              _provider.protocol = protocol;
                              if (protocol == LlmProtocol.anthropic &&
                                  _baseUrl.text == 'https://api.openai.com/v1') {
                                _baseUrl.text = 'https://api.anthropic.com';
                              }
                              if (protocol == LlmProtocol.gemini &&
                                  _baseUrl.text == 'https://api.anthropic.com') {
                                _baseUrl.text = 'https://generativelanguage.googleapis.com';
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      hintText: switch (_provider.protocol) {
                        LlmProtocol.openai => 'https://api.example.com/v1',
                        LlmProtocol.anthropic => 'https://api.anthropic.com',
                        LlmProtocol.gemini => 'https://generativelanguage.googleapis.com',
                      },
                      helperText: _provider.protocol == LlmProtocol.openai
                          ? '填到 /v1 或中转站根路径；会自动补 /chat/completions'
                          : _provider.protocol == LlmProtocol.anthropic
                              ? '会自动补 /v1/messages'
                              : '会自动补 /v1beta/models',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _key,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: current.hasKey ? '已保存，留空则不修改' : '粘贴平台 Key',
                      prefixIcon: const Icon(Icons.key_rounded, size: 18),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (current.hasKey)
                            IconButton(
                              tooltip: '清除已保存的 Key',
                              icon: const Icon(Icons.delete_outline_rounded, size: 17),
                              onPressed: _clearKey,
                            ),
                          IconButton(
                            tooltip: _obscure ? '显示' : '隐藏',
                            icon: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_provider.protocol == LlmProtocol.openai) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ReasoningStyle>(
                      initialValue: _provider.reasoningStyle,
                      decoration: const InputDecoration(
                        labelText: '思考参数风格',
                        helperText: '中转站若直接透传，可保持“自动”；特殊平台可手动指定',
                      ),
                      items: [
                        for (final style in ReasoningStyle.values)
                          DropdownMenuItem(
                            value: style,
                            child: Text(style.label, style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _provider.reasoningStyle = value);
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用该厂商'),
                    subtitle: const Text('关闭后不会出现在模型选择器中'),
                    value: _provider.enabled,
                    onChanged: (value) => setState(() => _provider.enabled = value),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: c.border),
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 13),
                      childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text('高级设置', style: context.text.labelMedium),
                      subtitle: Text(
                        '自定义请求头、额外请求体',
                        style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                      ),
                      children: [
                        TextField(
                          controller: _headers,
                          maxLines: 4,
                          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
                          decoration: const InputDecoration(
                            labelText: '自定义 Headers（JSON）',
                            hintText: '{"X-Custom": "value"}',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _body,
                          maxLines: 4,
                          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
                          decoration: const InputDecoration(
                            labelText: '额外请求体（JSON）',
                            hintText: '{"enable_thinking": true}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '额外请求体会与标准字段合并；同名标准字段（model / messages / stream）以应用为准。'
                          'Headers 与额外请求体保存在本地数据库（非安全存储），请优先把长期密钥放在 API Key 字段。',
                          style: context.text.labelSmall?.copyWith(
                            color: c.textTertiary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: context.text.bodySmall?.copyWith(color: c.danger, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _refresh,
                          icon: providers.syncing.contains(current.id)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 1.8),
                                )
                              : const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('保存并测试连接'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _save(),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('模型列表', style: context.text.labelMedium),
                      const SizedBox(width: 6),
                      Text(
                        '${models.length}',
                        style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        onPressed: _addModel,
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('添加模型'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const Spacer(),
                      if (current.modelsSyncedAt != null)
                        Text(
                          '同步于 ${shortRelative(current.modelsSyncedAt!)}',
                          style: context.text.labelSmall?.copyWith(
                            color: c.textTertiary,
                            fontSize: 9.5,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  if (current.syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        current.syncError!,
                        style: context.text.labelSmall?.copyWith(color: c.warning, height: 1.45),
                      ),
                    ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: c.border),
                    ),
                    child: models.isEmpty
                        ? Center(
                            child: Text(
                              '还没有模型。保存 Key 后点击“保存并测试连接”。',
                              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                for (final model in models)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 5),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            model.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.text.labelSmall?.copyWith(
                                              color: c.textSecondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        if (model.source == 'manual')
                                          const CapabilityChip(label: '手动'),
                                        if (model.vision) const CapabilityChip(label: '视觉'),
                                        if (model.reasoning) ...[
                                          const SizedBox(width: 3),
                                          const CapabilityChip(label: '思考'),
                                        ],
                                        if (model.imageGeneration) ...[
                                          const SizedBox(width: 3),
                                          const CapabilityChip(label: '生图'),
                                        ],
                                        const SizedBox(width: 5),
                                        Text(
                                          _tokenSummary(appSettings.settings, current, model),
                                          style: context.text.labelSmall?.copyWith(
                                            color: _hasCustomLimit(appSettings.settings, current, model)
                                                ? c.primary
                                                : c.textTertiary,
                                            fontSize: 9,
                                          ),
                                        ),
                                        if (!current.demo)
                                          IconButton(
                                            tooltip: '编辑模型能力',
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            padding: EdgeInsets.zero,
                                            icon: Icon(
                                              Icons.edit_outlined,
                                              size: 15,
                                              color: c.textTertiary,
                                            ),
                                            onPressed: () => _editModel(model),
                                          ),
                                        IconButton(
                                          tooltip: '设置输入/输出 token 上限',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            Icons.tune_rounded,
                                            size: 15,
                                            color: _hasCustomLimit(appSettings.settings, current, model)
                                                ? c.primary
                                                : c.textTertiary,
                                          ),
                                          onPressed: () => showModelTokenSettings(
                                            context,
                                            provider: current,
                                            model: model,
                                          ),
                                        ),
                                        if (model.source == 'manual')
                                          PopupMenuButton<String>(
                                            tooltip: '编辑或删除模型',
                                            padding: EdgeInsets.zero,
                                            icon: Icon(
                                              Icons.more_vert_rounded,
                                              size: 16,
                                              color: c.textTertiary,
                                            ),
                                            onSelected: (value) {
                                              if (value == 'delete') _removeModel(model);
                                            },
                                            itemBuilder: (context) => const [
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text('删除模型'),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  if (current.docsUrl != null) ...[
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await launchUrl(Uri.parse(current.docsUrl!), mode: LaunchMode.externalApplication);
                        } catch (_) {
                          // Ignore.
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: const Text('查看官方 API 文档'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Key 仅保存在本机安全存储；请求由本应用直接发往上方 Base URL。',
                    style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
