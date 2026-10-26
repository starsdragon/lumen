import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/controllers.dart';
import '../common/widgets.dart';

Future<void> showModelTokenSettings(
  BuildContext context, {
  required ProviderConfig provider,
  required ModelInfo model,
}) {
  final current = context.read<SettingsController>().modelLimitFor(provider.id, model.id);
  return showLumenSheet<void>(
    context: context,
    builder: (_) => _ModelTokenSettingsSheet(
      provider: provider,
      model: model,
      initial: current,
    ),
  );
}

class _ModelTokenSettingsSheet extends StatefulWidget {
  const _ModelTokenSettingsSheet({
    required this.provider,
    required this.model,
    required this.initial,
  });

  final ProviderConfig provider;
  final ModelInfo model;
  final ModelTokenLimit? initial;

  @override
  State<_ModelTokenSettingsSheet> createState() => _ModelTokenSettingsSheetState();
}

class _ModelTokenSettingsSheetState extends State<_ModelTokenSettingsSheet> {
  late final TextEditingController _input;
  late final TextEditingController _output;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(
      text: '${widget.initial?.inputTokens ?? widget.model.contextWindow}',
    );
    _output = TextEditingController(
      text: widget.initial == null || widget.initial!.outputTokens == 0
          ? ''
          : '${widget.initial!.outputTokens}',
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  int? get _inputValue => int.tryParse(_input.text.trim());
  int? get _outputValue {
    final raw = _output.text.trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw);
  }

  String? get _error {
    final input = _inputValue;
    if (input == null || input < 1024) return '输入上限至少为 1,024 tokens。';
    if (input > 10000000) return '输入上限不能超过 10,000,000 tokens。';
    final output = _outputValue;
    if (output == null) return '输出上限需要填写数字，留空表示自动。';
    if (output != 0 && output < 256) return '输出上限至少为 256 tokens，或留空使用自动。';
    if (output > 131072) return '输出上限不能超过 131,072 tokens。';
    if (output > input) return '输出上限不能超过输入上限。';
    return null;
  }

  int get _effectiveOutput {
    final output = _outputValue ?? 0;
    return output > 0 ? output : autoOutputTokenLimit(_inputValue ?? widget.model.contextWindow);
  }

  bool get _isDefault =>
      _inputValue == widget.model.contextWindow &&
      (_outputValue == null || _outputValue == 0);

  Future<void> _save() async {
    if (_saving || _error != null) return;
    setState(() => _saving = true);
    final settings = context.read<SettingsController>();
    final input = _inputValue ?? widget.model.contextWindow;
    final output = _outputValue ?? 0;
    await settings.setModelLimit(
      widget.provider.id,
      widget.model.id,
      _isDefault ? null : ModelTokenLimit(inputTokens: input, outputTokens: output),
    );
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, _isDefault ? '已使用模型默认上限' : '已保存模型 token 设置');
  }

  Future<void> _reset() async {
    final settings = context.read<SettingsController>();
    await settings.setModelLimit(widget.provider.id, widget.model.id, null);
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, '已恢复默认上限');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final output = _effectiveOutput;
    final error = _error;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.tune_rounded, size: 20, color: c.primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('模型设置', style: context.text.titleLarge?.copyWith(fontSize: 18)),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.provider.name} · ${widget.model.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LimitField(
                label: '输入 token 上限',
                helper: '作为上下文预算；默认 ${tokenLabel(widget.model.contextWindow)}',
                controller: _input,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final preset in const [32768, 131072, 262144, 1000000])
                    ActionChip(
                      label: Text(tokenLabel(preset)),
                      onPressed: () => setState(() => _input.text = '$preset'),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _LimitField(
                label: '输出 token 上限',
                helper: '单次回复上限；留空表示自动，当前约 ${tokenLabel(output)}',
                controller: _output,
                hint: '自动',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  ActionChip(
                    label: const Text('自动'),
                    onPressed: () => setState(() => _output.clear()),
                  ),
                  for (final preset in const [4096, 8192, 16384, 32768, 65536])
                    ActionChip(
                      label: Text(tokenLabel(preset)),
                      onPressed: () => setState(() => _output.text = '$preset'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: c.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '输入上限决定上下文裁剪预算，输出上限用于单次请求。实际可用值仍受服务端限制；模型列表刷新不会覆盖这里的设置。',
                        style: context.text.labelSmall?.copyWith(
                          color: c.textTertiary,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error,
                  style: context.text.labelSmall?.copyWith(color: c.warning, height: 1.45),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : _reset,
                    child: const Text('恢复默认'),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving || error != null ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '当前：${tokenLabel(_inputValue ?? widget.model.contextWindow)} 输入 · ${tokenLabel(output)} 输出',
                style: context.text.labelSmall?.copyWith(color: c.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitField extends StatelessWidget {
  const _LimitField({
    required this.label,
    required this.helper,
    required this.controller,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String helper;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: hint,
        suffixText: 'tokens',
      ),
    );
  }
}
