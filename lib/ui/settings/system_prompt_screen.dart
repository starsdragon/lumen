import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

class SystemPromptScreen extends StatefulWidget {
  const SystemPromptScreen({super.key, required this.initial});

  final String initial;

  @override
  State<SystemPromptScreen> createState() => _SystemPromptScreenState();
}

class _SystemPromptScreenState extends State<SystemPromptScreen> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '系统提示词不能为空。可以恢复默认后再修改。');
      return;
    }
    Navigator.pop(context, value);
  }

  void _reset() {
    setState(() {
      _controller.text = defaultSystemPrompt;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('系统提示词'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Text(
                '决定 Lumen 的角色、语气与回答规则。长期记忆和联网说明会自动追加在它后面。',
                style: context.text.bodySmall?.copyWith(
                  color: c.textSecondary,
                  height: 1.55,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: TextField(
                    controller: _controller,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: context.text.bodyMedium?.copyWith(height: 1.6),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '你希望 Lumen 怎样回答？',
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: context.text.labelSmall?.copyWith(color: c.danger),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('恢复默认'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
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
