import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';

Future<ModelInfo?> showModelEditorDialog(
  BuildContext context, {
  required Set<String> existingIds,
  ModelInfo? initial,
}) {
  return showDialog<ModelInfo>(
    context: context,
    builder: (_) => _ModelEditorDialog(existingIds: existingIds, initial: initial),
  );
}

class _ModelEditorDialog extends StatefulWidget {
  const _ModelEditorDialog({required this.existingIds, this.initial});

  final Set<String> existingIds;
  final ModelInfo? initial;

  @override
  State<_ModelEditorDialog> createState() => _ModelEditorDialogState();
}

class _ModelEditorDialogState extends State<_ModelEditorDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _context;
  late bool _vision;
  late bool _reasoning;
  late bool _tools;
  String? _error;

  @override
  void initState() {
    super.initState();
    _id = TextEditingController(text: widget.initial?.id ?? '');
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _context = TextEditingController(text: '${widget.initial?.contextWindow ?? 131072}');
    _vision = widget.initial?.vision ?? false;
    _reasoning = widget.initial?.reasoning ?? true;
    _tools = widget.initial?.tools ?? true;
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _context.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _id.text.trim();
    final contextWindow = int.tryParse(_context.text.trim());
    if (id.isEmpty) {
      setState(() => _error = '模型 ID 不能为空。');
      return;
    }
    if (id.contains(RegExp(r'\s'))) {
      setState(() => _error = '模型 ID 不能包含空格。');
      return;
    }
    if (widget.existingIds.contains(id) && widget.initial?.id != id) {
      setState(() => _error = '这个厂商下已经有同名模型。');
      return;
    }
    if (contextWindow == null || contextWindow < 1024) {
      setState(() => _error = '上下文窗口至少为 1,024 tokens。');
      return;
    }
    if (contextWindow > 10000000) {
      setState(() => _error = '上下文窗口不能超过 10,000,000 tokens。');
      return;
    }
    Navigator.pop(
      context,
      ModelInfo(
        id: id,
        name: _name.text.trim().isEmpty ? id : _name.text.trim(),
        contextWindow: contextWindow,
        vision: _vision,
        reasoning: _reasoning,
        tools: _tools,
        source: 'manual',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? '编辑模型' : '添加模型'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用于不支持 /models 接口或需要手动接入的中转站。模型 ID 必须与服务端一致。',
                style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.55),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _id,
                autocorrect: false,
                enabled: !editing,
                decoration: const InputDecoration(
                  labelText: '模型 ID',
                  hintText: '例如 gpt-4.1-mini',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '显示名称（可选）',
                  hintText: '留空则使用模型 ID',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _context,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '上下文窗口',
                  helperText: '当前填写：${tokenLabel(int.tryParse(_context.text) ?? 0)} tokens',
                  suffixText: 'tokens',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text(
                '输入能力',
                style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('纯文本'),
                    selected: !_vision,
                    onSelected: (_) => setState(() => _vision = false),
                  ),
                  ChoiceChip(
                    label: const Text('多模态'),
                    selected: _vision,
                    onSelected: (_) => setState(() => _vision = true),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _vision ? '发送图片时使用 image_url 内容。' : '只发送文本；图片附件仍会保留在本地。',
                style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.45),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _reasoning,
                onChanged: (value) => setState(() => _reasoning = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('支持思考参数'),
                subtitle: const Text('在模型选择器和请求中显示思考选项'),
              ),
              SwitchListTile(
                value: _tools,
                onChanged: (value) => setState(() => _tools = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('支持工具调用'),
                subtitle: const Text('允许模型返回 function / tool calls'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: context.text.bodySmall?.copyWith(color: c.danger, height: 1.45),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? '保存' : '添加'),
        ),
      ],
    );
  }
}
