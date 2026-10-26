import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/chat_session.dart';
import '../../services/controllers.dart';
import '../../services/file_import_service.dart';
import '../common/widgets.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.session,
    required this.selection,
    required this.onOpenModelPicker,
    required this.onOpenReasoning,
    required this.onNeedSettings,
    this.narrow = false,
  });

  final ChatSession session;
  final ModelSelection selection;
  final VoidCallback onOpenModelPicker;
  final VoidCallback onOpenReasoning;
  final VoidCallback onNeedSettings;
  final bool narrow;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final FileImportService _fileImporter = FileImportService();
  final List<Attachment> _attachments = [];
  bool _focused = false;
  bool _picking = false;

  bool get _canSend =>
      !widget.session.busy && (_text.text.trim().isNotEmpty || _attachments.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focused != _focus.hasFocus) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (widget.session.busy) return;
    if (!widget.session.providerReady) {
      showToast(
        context,
        '当前厂商尚未配置 API Key，请先在设置中完成配置。',
        action: SnackBarAction(label: '去设置', onPressed: widget.onNeedSettings),
      );
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (widget.session.conversation.imageMode) {
      if (text.isEmpty) {
        showToast(context, '请先描述你想生成的画面。');
        return;
      }
      await widget.session.send(text);
      if (!mounted) return;
      _text.clear();
      setState(() {});
      return;
    }
    HapticFeedback.lightImpact();
    final attachments = List<Attachment>.from(_attachments);
    _attachments.clear();
    _text.clear();
    setState(() {});
    await widget.session.send(text, attachments: attachments);
    if (mounted) _focus.requestFocus();
  }

  Future<void> _toggleSearch() async {
    final settings = context.read<SettingsController>();
    final config = settings.settings.search;
    if (!widget.session.conversation.webSearch) {
      final ready = switch (config.provider) {
        SearchProvider.none => false,
        SearchProvider.tavily => settings.credentials.tavily.isNotEmpty,
        SearchProvider.google =>
          settings.credentials.google.isNotEmpty && config.googleCx.trim().isNotEmpty,
        SearchProvider.bing => settings.credentials.bing.isNotEmpty,
        SearchProvider.bingFree => true,
        SearchProvider.searxng => config.searxBaseUrl.trim().isNotEmpty,
        SearchProvider.duckduckgo => true,
      };
      if (!ready) {
        showToast(
          context,
          '联网搜索尚未配置完整。请先在「设置 → 联网搜索」中填写 Key 或选择 DuckDuckGo。',
          action: SnackBarAction(label: '去设置', onPressed: widget.onNeedSettings),
        );
        return;
      }
    }
    await widget.session.setWebSearch(!widget.session.conversation.webSearch);
  }

  Future<void> _toggleImageMode() async {
    final next = !widget.session.conversation.imageMode;
    if (next) {
      final settings = context.read<SettingsController>();
      final providers = context.read<ProvidersController>();
      final hasImage = providers.readyProviders.any((p) => p.imageModels.isNotEmpty);
      if (!hasImage) {
        showToast(
          context,
          '当前没有可用的生图模型，请先在设置中配置智谱、MiniMax、百炼、Gemini 或自定义图像接口。',
          action: SnackBarAction(label: '去设置', onPressed: widget.onNeedSettings),
        );
        return;
      }
      _attachments.clear();
      if (settings.settings.memoryEnabled) {
        // Image generation does not run memory extraction; nothing else to do.
      }
    }
    await widget.session.setImageMode(next);
    if (mounted) setState(() {});
  }

  int get _imageCount => _attachments.where((a) => a.isImage).length;
  int get _fileCount => _attachments.where((a) => a.isFile).length;

  Future<void> _pickImages() async {
    if (_picking) return;
    if (widget.session.conversation.imageMode) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final choice = await showLumenSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                subtitle: const Text('最多 4 张，会自动压缩'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('导入文件'),
                subtitle: const Text('PDF / Word / Excel / PPT / 文本，最大 20MB'),
                onTap: () => Navigator.pop(context, 'file'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'file') {
      await _pickFiles();
      return;
    }
    setState(() => _picking = true);
    try {
      final remaining = 4 - _imageCount;
      if (remaining <= 0) {
        showToast(context, '最多附加 4 张图片。');
        return;
      }
      final List<XFile> files;
      if (choice == 'camera') {
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
          maxWidth: 1600,
        );
        files = photo == null ? const [] : [photo];
      } else {
        files = await _picker.pickMultiImage(
          imageQuality: 88,
          maxWidth: 1600,
        );
      }
      for (final file in files.take(remaining)) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        if (bytes.length > 8 * 1024 * 1024) {
          showToast(context, '图片「${file.name}」超过 8MB，已跳过。');
          continue;
        }
        final mime = mimeFromName(file.name);
        _attachments.add(
          Attachment(
            id: newId('att'),
            name: file.name,
            mime: mime,
            dataUrl: bytesToDataUrl(bytes, mime),
          ),
        );
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showToast(context, '选择图片失败：$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickFiles() async {
    if (_picking) return;
    if (widget.session.conversation.imageMode) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (result.isEmpty) return;
      var imported = 0;
      for (final file in result) {
        final length = await file.length();
        if (length != null && length > FileImportService.maxBytes) {
          if (mounted) showToast(context, '「${file.name}」超过 20MB，已跳过。');
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          if (mounted) showToast(context, '无法读取「${file.name}」的内容。');
          continue;
        }
        final extension = (file.extension ?? '').toLowerCase();
        if (const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'].contains(extension)) {
          if (_imageCount >= 4) {
            if (mounted) showToast(context, '图片最多 4 张，已跳过「${file.name}」。');
            continue;
          }
          if (bytes.length > 8 * 1024 * 1024) {
            if (mounted) showToast(context, '图片「${file.name}」超过 8MB，已跳过。');
            continue;
          }
          final mime = mimeFromName(file.name);
          _attachments.add(
            Attachment(
              id: newId('att'),
              name: file.name,
              mime: mime,
              dataUrl: bytesToDataUrl(bytes, mime),
              sizeBytes: bytes.length,
            ),
          );
          imported++;
          continue;
        }
        if (_fileCount >= 3) {
          if (mounted) showToast(context, '文件最多 3 个，已跳过「${file.name}」。');
          continue;
        }
        try {
          final extracted = await _fileImporter.extract(
            name: file.name,
            mime: '',
            bytes: bytes,
          );
          _attachments.add(
            Attachment(
              id: newId('att'),
              name: extracted.name,
              mime: extracted.mime,
              dataUrl: '',
              extractedText: extracted.text,
              sizeBytes: extracted.sizeBytes,
            ),
          );
          imported++;
          if (extracted.warning.isNotEmpty && mounted) {
            showToast(context, '${extracted.name}：${extracted.warning}');
          }
        } on FileImportException catch (error) {
          if (mounted) showToast(context, '${file.name}：${error.message}');
        }
      }
      if (mounted && imported > 0) {
        setState(() {});
        showToast(context, '已添加 $imported 个附件');
      }
    } catch (error) {
      if (mounted) showToast(context, '导入文件失败：$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    final sendOnEnter = context.read<SettingsController>().settings.sendOnEnter;
    if (!sendOnEnter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = widget.session;
    final imageMode = session.conversation.imageMode;
    final canSend = _canSend;
    final compact = widget.narrow || MediaQuery.sizeOf(context).width < 430;
    final model = widget.selection.model;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      decoration: BoxDecoration(
        color: c.background,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _focused ? c.primary.withValues(alpha: 0.55) : c.borderStrong,
                    width: _focused ? 1.4 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.shadow.withValues(alpha: _focused ? 0.9 : 0.55),
                      blurRadius: _focused ? 24 : 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 66,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (var index = 0; index < _attachments.length; index++)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: _PendingAttachmentTile(
                                          attachment: _attachments[index],
                                          onRemove: () => setState(() => _attachments.removeAt(index)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (_imageCount > 0 && !model.vision)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '当前模型未标注视觉能力；图片会照常发送，若模型不支持会返回错误。',
                                  style: context.text.labelSmall?.copyWith(
                                    color: c.warning,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (imageMode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
                        child: Row(
                          children: [
                            Icon(Icons.aspect_ratio_rounded, size: 15, color: c.textTertiary),
                            const SizedBox(width: 6),
                            Text(
                              '比例',
                              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final ratio in const ['1:1', '3:4', '4:3', '9:16', '16:9'])
                                      Padding(
                                        padding: const EdgeInsets.only(right: 5),
                                        child: _AspectChip(
                                          label: ratio,
                                          selected: session.imageAspect == ratio,
                                          onTap: () => session.setImageAspect(ratio),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, imageMode ? 8 : 12, 16, 5),
                      child: Focus(
                        onKeyEvent: _handleKey,
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 8,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: context.text.bodyLarge?.copyWith(height: 1.55, fontSize: 15.5),
                          decoration: InputDecoration(
                            filled: false,
                            hintText: imageMode
                                ? '描述画面、风格、光线…'
                                : (_attachments.isNotEmpty ? '给图片补充说明…' : '给 Lumen 发送消息'),
                            hintStyle: context.text.bodyLarge?.copyWith(
                              color: c.textTertiary,
                              fontSize: 15.5,
                              height: 1.55,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                      child: Row(
                        children: [
                          if (!imageMode)
                            _picking
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : _RoundAction(
                                    icon: Icons.add_rounded,
                                    tooltip: '添加图片或文件',
                                    onTap: _pickImages,
                                  ),
                          if (!imageMode) const SizedBox(width: 2),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  if (!imageMode) ...[
                                    _CompactToggle(
                                      icon: Icons.language_rounded,
                                      label: compact ? '联网' : '联网搜索',
                                      selected: session.conversation.webSearch,
                                      onTap: _toggleSearch,
                                    ),
                                    const SizedBox(width: 6),
                                    _CompactToggle(
                                      icon: Icons.psychology_alt_outlined,
                                      label: model.reasoning
                                          ? (compact || !session.conversation.reasoningLevel.isEnabled
                                              ? '思考'
                                              : session.conversation.reasoningLevel.label)
                                          : '思考',
                                      selected: session.conversation.reasoningLevel.isEnabled,
                                      enabled: model.reasoning,
                                      onTap: () {
                                        if (!model.reasoning) {
                                          showToast(context, '当前模型不支持思考参数。');
                                          return;
                                        }
                                        widget.onOpenReasoning();
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  _CompactToggle(
                                    icon: Icons.auto_awesome_outlined,
                                    label: imageMode ? '生图中' : '生图',
                                    selected: imageMode,
                                    onTap: _toggleImageMode,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _SendButton(
                            busy: session.busy,
                            enabled: canSend,
                            imageMode: imageMode,
                            onTap: () {
                              if (session.busy) {
                                session.stop();
                              } else {
                                _send();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.selection.provider.demo) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.primarySoft,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '演示',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: c.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      imageMode
                          ? '图片由所选模型生成 · 请遵守内容政策'
                          : 'Lumen 也会犯错，请核实重要信息',
                      textAlign: TextAlign.center,
                      style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingAttachmentTile extends StatelessWidget {
  const _PendingAttachmentTile({required this.attachment, required this.onRemove});

  final Attachment attachment;
  final VoidCallback onRemove;

  IconData get _icon {
    final name = attachment.name.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.docx')) return Icons.description_outlined;
    if (name.endsWith('.xlsx')) return Icons.table_chart_outlined;
    if (name.endsWith('.pptx')) return Icons.slideshow_outlined;
    if (name.endsWith('.md') || name.endsWith('.txt')) return Icons.article_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (attachment.isImage) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          AttachmentImage(
            attachment: attachment,
            width: 66,
            height: 66,
            radius: 11,
            onTap: () => openImageViewer(context, attachment),
          ),
          _removeButton(c),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => showFilePreviewDialog(context, attachment),
          child: Container(
            width: 196,
            height: 66,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(_icon, size: 22, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        attachment.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: c.textPrimary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatFileSize(attachment.sizeBytes)} · ${attachment.extractedText.length} 字',
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
        ),
        _removeButton(c),
      ],
    );
  }

  Widget _removeButton(LumenColors c) {
    return Positioned(
      right: -5,
      top: -5,
      child: GestureDetector(
        onTap: onRemove,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: c.textPrimary,
            shape: BoxShape.circle,
            border: Border.all(color: c.surface, width: 2),
          ),
          child: Icon(Icons.close_rounded, size: 12, color: c.background),
        ),
      ),
    );
  }
}

class _AspectChip extends StatelessWidget {
  const _AspectChip({required this.label, required this.selected, required this.onTap});

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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? c.primary.withValues(alpha: 0.4) : c.border),
        ),
        child: Text(
          label,
          style: context.text.labelSmall?.copyWith(
            color: selected ? c.primary : c.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CompactToggle extends StatelessWidget {
  const _CompactToggle({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: enabled ? label : '当前模型不支持该能力',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: selected ? c.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14.5, color: selected ? c.primary : c.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: context.text.labelSmall?.copyWith(
                      color: selected ? c.primary : c.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final child = Material(
      color: c.surfaceAlt,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 19, color: onTap == null ? c.textTertiary : c.textSecondary),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.busy,
    required this.enabled,
    required this.imageMode,
    required this.onTap,
  });

  final bool busy;
  final bool enabled;
  final bool imageMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = busy || enabled;
    return Tooltip(
      message: busy ? '停止生成' : (imageMode ? '生成图片' : '发送'),
      child: GestureDetector(
        onTap: active ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: busy
                ? c.textPrimary
                : (enabled ? c.primary : c.surfaceAlt),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            busy
                ? Icons.stop_rounded
                : (imageMode ? Icons.auto_awesome_rounded : Icons.arrow_upward_rounded),
            size: 20,
            color: busy
                ? c.background
                : (enabled ? c.onPrimary : c.textTertiary),
          ),
        ),
      ),
    );
  }
}
