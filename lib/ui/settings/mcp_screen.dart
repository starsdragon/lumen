import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/controllers.dart';
import '../common/widgets.dart';

class McpScreen extends StatelessWidget {
  const McpScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final server = McpServerConfig(
      id: newId('mcp'),
      name: '新的 MCP 服务器',
      transport: McpTransport.streamableHttp,
      url: '',
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => McpEditScreen(newServer: server)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<McpController>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('MCP 工具'),
        actions: [
          if (controller.servers.isNotEmpty)
            IconButton(
              tooltip: '刷新全部工具',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () async {
                await controller.refreshAll();
                if (context.mounted) showToast(context, 'MCP 工具刷新完成');
              },
            ),
          IconButton(
            tooltip: '添加 MCP 服务器',
            icon: const Icon(Icons.add_rounded, size: 21),
            onPressed: () => _add(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MCP（Model Context Protocol）让模型调用外部工具服务器，例如文件系统、数据库、浏览器或你自己的服务。',
                  style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.55),
                ),
                const SizedBox(height: 6),
                Text(
                  '远程 HTTP/SSE 在所有平台可用；stdio 本地进程仅桌面端可用（Android/Web 不支持）。',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.5),
                ),
                const SizedBox(height: 16),
                if (controller.servers.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.extension_outlined, size: 30, color: c.primary),
                        const SizedBox(height: 12),
                        Text('还没有接入 MCP 服务器', style: context.text.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          '添加一个远程 MCP 端点，或在本机运行一个 stdio 服务器。接入后，模型会在需要时自动调用工具。',
                          textAlign: TextAlign.center,
                          style: context.text.bodySmall?.copyWith(
                            color: c.textSecondary,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => _add(context),
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('添加服务器'),
                        ),
                      ],
                    ),
                  )
                else
                  for (final server in controller.servers) ...[
                    _ServerCard(
                      server: server,
                      syncing: controller.syncing.contains(server.id),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => McpEditScreen(serverId: server.id),
                        ),
                      ),
                      onToggle: (value) async {
                        await controller.save(server.copyWith(enabled: value));
                      },
                      onRefresh: () async {
                        final updated = await controller.refreshTools(server);
                        if (context.mounted) {
                          showToast(
                            context,
                            updated.error == null
                                ? '已连接，发现 ${updated.tools.length} 个工具'
                                : updated.error!,
                          );
                        }
                      },
                      onDelete: () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: '删除 MCP 服务器？',
                          message: '只会删除本机配置，不会影响服务器本身。',
                          confirmLabel: '删除',
                          danger: true,
                        );
                        if (ok && context.mounted) await controller.delete(server);
                      },
                    ),
                    const SizedBox(height: 2),
                  ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('添加 MCP 服务器'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
                ),
                const SizedBox(height: 12),
                Text(
                  '提示：远程服务器需要支持 Streamable HTTP 或旧版 SSE 传输；调用工具前，应用会先发送 MCP initialize 握手。',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.syncing,
    required this.onTap,
    required this.onToggle,
    required this.onRefresh,
    required this.onDelete,
  });

  final McpServerConfig server;
  final bool syncing;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final connected = server.tools.isNotEmpty && server.error == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: c.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      server.transport == McpTransport.stdio
                          ? Icons.terminal_rounded
                          : Icons.cloud_outlined,
                      size: 18,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(fontSize: 14),
                        ),
                        Text(
                          server.transport.label,
                          style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: server.enabled,
                    onChanged: onToggle,
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    iconSize: 18,
                    onSelected: (value) {
                      if (value == 'refresh') onRefresh();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'refresh', child: Text('刷新工具')),
                      const PopupMenuItem(value: 'delete', child: Text('删除服务器')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.url.isNotEmpty ? server.url : '${server.command} ${server.args.join(' ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (syncing)
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        else
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: connected
                                  ? c.success
                                  : (server.error != null ? c.danger : c.textTertiary),
                            ),
                          ),
                        const SizedBox(width: 5),
                        Text(
                          server.error != null
                              ? '连接失败'
                              : server.tools.isEmpty
                                  ? '尚未同步工具'
                                  : '${server.tools.length} 个工具',
                          style: context.text.labelSmall?.copyWith(
                            color: server.error != null
                                ? c.danger
                                : (connected ? c.success : c.textTertiary),
                            fontSize: 9.5,
                          ),
                        ),
                        if (server.lastSyncedAt != null) ...[
                          const SizedBox(width: 7),
                          Text(
                            shortRelative(server.lastSyncedAt!),
                            style: context.text.labelSmall?.copyWith(
                              color: c.textTertiary,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (server.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          server.error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(
                            color: c.danger,
                            fontSize: 9.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    if (server.tools.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final tool in server.tools.take(6))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.surfaceAlt,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  tool.name,
                                  style: context.text.labelSmall?.copyWith(
                                    color: c.textSecondary,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            if (server.tools.length > 6)
                              Text(
                                '+${server.tools.length - 6}',
                                style: context.text.labelSmall?.copyWith(
                                  color: c.textTertiary,
                                  fontSize: 9,
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
        ),
      ),
    );
  }
}

class McpEditScreen extends StatefulWidget {
  const McpEditScreen({super.key, this.serverId, this.newServer});

  final String? serverId;
  final McpServerConfig? newServer;

  @override
  State<McpEditScreen> createState() => _McpEditScreenState();
}

class _McpEditScreenState extends State<McpEditScreen> {
  late McpServerConfig _server;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _command;
  late final TextEditingController _args;
  late final TextEditingController _env;
  late final TextEditingController _headers;
  bool _saving = false;
  bool _testing = false;
  String? _error;
  bool _isNew = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.newServer != null;
    final controller = context.read<McpController>();
    final existing = widget.newServer ??
        (widget.serverId == null
            ? null
            : controller.servers.where((s) => s.id == widget.serverId).firstOrNull);
    _server = existing ??
        McpServerConfig(
          id: newId('mcp'),
          name: '新的 MCP 服务器',
        );
    _name = TextEditingController(text: _server.name);
    _url = TextEditingController(text: _server.url);
    _command = TextEditingController(text: _server.command);
    _args = TextEditingController(text: jsonEncode(_server.args));
    _env = TextEditingController(
      text: _server.env.isEmpty ? '{}' : const JsonEncoder.withIndent('  ').convert(_server.env),
    );
    _headers = TextEditingController(
      text: _server.headers.isEmpty
          ? '{}'
          : const JsonEncoder.withIndent('  ').convert(_server.headers),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _command.dispose();
    _args.dispose();
    _env.dispose();
    _headers.dispose();
    super.dispose();
  }

  List<String> _parseArgs() {
    final raw = _args.text.trim();
    if (raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('参数需要是 JSON 数组');
    return decoded.map((e) => '$e').toList();
  }

  Map<String, String> _parseStringMap(String raw, String label) {
    if (raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw FormatException('$label 需要是 JSON 对象');
    return decoded.map((k, v) => MapEntry('$k', '$v'));
  }

  Future<bool> _save({bool pop = true}) async {
    final controller = context.read<McpController>();
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '名称不能为空。');
      return false;
    }
    if (_server.transport == McpTransport.stdio) {
      if (_command.text.trim().isEmpty) {
        setState(() => _error = 'stdio 服务器需要填写启动命令。');
        return false;
      }
    } else if (!isHttpUrl(_url.text.trim())) {
      setState(() => _error = '请填写有效的 http/https MCP 地址。');
      return false;
    }
    List<String> args;
    Map<String, String> env;
    Map<String, String> headers;
    try {
      args = _parseArgs();
      env = _parseStringMap(_env.text, '环境变量');
      headers = _parseStringMap(_headers.text, 'Headers');
    } catch (error) {
      setState(() => _error = 'JSON 格式错误：$error');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _server
        ..name = _name.text.trim()
        ..url = _url.text.trim()
        ..command = _command.text.trim()
        ..args = args
        ..env = env
        ..headers = headers;
      await controller.save(_server);
      if (!mounted) return true;
      if (pop) Navigator.of(context).pop(true);
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final saved = await _save(pop: false);
    if (!saved || !mounted) return;
    setState(() => _testing = true);
    try {
      final updated = await context.read<McpController>().refreshTools(_server);
      if (!mounted) return;
      if (updated.error != null) {
        showToast(context, updated.error!);
      } else {
        showToast(context, '连接成功，发现 ${updated.tools.length} 个工具');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除 MCP 服务器？',
      message: '只会删除本机配置，不影响服务器本身。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<McpController>().delete(_server);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<McpController>();
    final current = controller.servers.where((s) => s.id == _server.id).firstOrNull ?? _server;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(_isNew ? '添加 MCP 服务器' : current.name),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _saving ? null : () => _save(),
            child: const Text('保存'),
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
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：本地文件系统',
                  ),
                ),
                const SizedBox(height: 13),
                Text('传输方式', style: context.text.labelSmall?.copyWith(color: c.textTertiary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final transport in McpTransport.values)
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(transport.label, style: const TextStyle(fontSize: 11.5)),
                            if (transport == McpTransport.stdio && !controller.supportsStdio) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.desktop_windows_outlined, size: 12),
                            ],
                          ],
                        ),
                        selected: _server.transport == transport,
                        onSelected: (selected) {
                          if (!selected) return;
                          if (transport == McpTransport.stdio && !controller.supportsStdio) {
                            showToast(context, 'stdio 仅支持桌面端。当前平台无法启动本地进程。');
                            return;
                          }
                          setState(() => _server.transport = transport);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                if (_server.transport != McpTransport.stdio) ...[
                  TextField(
                    controller: _url,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      labelText: 'MCP 服务器 URL',
                      hintText: _server.transport == McpTransport.sse
                          ? 'https://example.com/sse'
                          : 'https://example.com/mcp',
                      helperText: _server.transport == McpTransport.sse
                          ? '填写 SSE 事件流地址，应用会等待 endpoint 事件'
                          : 'Streamable HTTP：向该地址 POST JSON-RPC',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _headers,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: 'Headers（JSON）',
                      hintText: '{"Authorization": "Bearer ..."}',
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _command,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: '启动命令',
                      hintText: 'npx',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _args,
                    maxLines: 3,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: '参数（JSON 数组）',
                      hintText: '["-y", "@modelcontextprotocol/server-filesystem", "C:\\\\data"]',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _env,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: '环境变量（JSON）',
                      hintText: '{"API_KEY": "..."}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'stdio 服务器会继承当前系统环境变量；不需要时保持 {}。仅桌面端可用。'
                    '环境变量与 Headers 会保存在本地数据库（非安全存储），敏感值请谨慎填写。',
                    style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.45),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  subtitle: const Text('启用后，模型会在需要时调用该服务器的工具'),
                  value: _server.enabled,
                  onChanged: (value) => setState(() => _server.enabled = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: context.text.bodySmall?.copyWith(color: c.danger, height: 1.5),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.8),
                              )
                            : const Icon(Icons.bolt_rounded, size: 17),
                        label: const Text('保存并测试'),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('已发现的工具', style: context.text.labelMedium),
                    const SizedBox(width: 6),
                    Text(
                      '${current.tools.length}',
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                    ),
                    const Spacer(),
                    if (current.lastSyncedAt != null)
                      Text(
                        shortRelative(current.lastSyncedAt!),
                        style: context.text.labelSmall?.copyWith(
                          color: c.textTertiary,
                          fontSize: 9.5,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                if (current.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      current.error!,
                      style: context.text.labelSmall?.copyWith(color: c.danger, height: 1.45),
                    ),
                  ),
                if (current.tools.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      '保存后点击“保存并测试”，应用会完成 MCP initialize 握手并列出工具。',
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                    ),
                  )
                else
                  for (final tool in current.tools)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tool.name,
                            style: context.text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          if (tool.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              tool.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelSmall?.copyWith(
                                color: c.textTertiary,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                const SizedBox(height: 10),
                Text(
                  'MCP 工具会以 mcp__ 前缀暴露给模型；调用结果会显示在对话中，可能需要几秒。',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
