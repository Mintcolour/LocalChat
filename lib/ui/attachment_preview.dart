import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pro_image_editor/pro_image_editor.dart';

import '../app/app_controller.dart';
import '../core/formatters.dart';
import '../models/pending_attachment.dart';

class AttachmentPreviewPage extends StatefulWidget {
  const AttachmentPreviewPage({
    super.key,
    required this.controller,
    required this.batch,
  });

  final AppController controller;
  final PendingAttachmentBatch batch;

  @override
  State<AttachmentPreviewPage> createState() => _AttachmentPreviewPageState();
}

class _AttachmentPreviewPageState extends State<AttachmentPreviewPage> {
  late List<PendingAttachment> _items;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.batch.items);
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    await widget.controller.cancelAttachmentBatch(widget.batch.id, _items);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _send() async {
    if (_closing || _items.isEmpty) return;
    _closing = true;
    Navigator.of(context).pop();
    unawaited(
      widget.controller.completeAttachmentBatch(widget.batch.id, _items),
    );
  }

  Future<void> _edit(int index) async {
    final item = _items[index];
    if (!item.isEditableImage) return;
    final edited = await Navigator.of(context).push<PendingAttachment>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            _LocalImageEditor(controller: widget.controller, attachment: item),
      ),
    );
    if (edited == null || !mounted) return;
    if (item.edited && item.path != edited.path) {
      await widget.controller.fileStore.deleteManagedEditedFile(item.path);
    }
    setState(() => _items[index] = edited);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancel());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close),
            tooltip: text.cancel,
          ),
          title: Text(text.attachmentPreview),
        ),
        body: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = _items[index];
            final size = File(item.path).lengthSync();
            return Card(
              child: ListTile(
                leading: item.isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(item.path),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 64,
                            height: 64,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      )
                    : const SizedBox(
                        width: 64,
                        height: 64,
                        child: Icon(Icons.insert_drive_file_outlined),
                      ),
                title: Text(item.fileName),
                subtitle: Text(
                  '${formatBytes(size)}${item.edited ? ' · ${text.edited}' : ''}',
                ),
                trailing: item.isEditableImage
                    ? IconButton(
                        onPressed: () => _edit(index),
                        tooltip: text.editImage,
                        icon: const Icon(Icons.crop_rotate),
                      )
                    : item.isImage
                    ? Tooltip(
                        message: text.animatedImageOriginalOnly,
                        child: const Icon(Icons.lock_outline),
                      )
                    : null,
              ),
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _items.isEmpty ? null : _send,
            icon: const Icon(Icons.send),
            label: Text(text.confirmSend(_items.length)),
          ),
        ),
      ),
    );
  }
}

class _LocalImageEditor extends StatefulWidget {
  const _LocalImageEditor({required this.controller, required this.attachment});

  final AppController controller;
  final PendingAttachment attachment;

  @override
  State<_LocalImageEditor> createState() => _LocalImageEditorState();
}

class _LocalImageEditorState extends State<_LocalImageEditor> {
  ui.Size? _sourceSize;
  Object? _error;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _decodeSize();
  }

  Future<void> _decodeSize() async {
    try {
      final bytes = await File(widget.attachment.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (!mounted) return;
      setState(
        () => _sourceSize = ui.Size(
          image.width.toDouble(),
          image.height.toDouble(),
        ),
      );
      image.dispose();
      codec.dispose();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.controller.text.editImage)),
        body: Center(child: Text(widget.controller.text.imageNotSupported)),
      );
    }
    final sourceSize = _sourceSize;
    if (sourceSize == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final extension = p.extension(widget.attachment.path).toLowerCase();
    final jpeg = extension == '.jpg' || extension == '.jpeg';
    final outputExtension = jpeg ? extension : '.png';
    final outputFormat = jpeg ? OutputFormat.jpg : OutputFormat.png;
    final zh = !widget.controller.text.en;

    return ProImageEditor.file(
      File(widget.attachment.path),
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) async {
          if (_completed) return;
          _completed = true;
          final target = await widget.controller.fileStore
              .createManagedEditedFile(
                widget.attachment.originalPath,
                extension: outputExtension,
              );
          await target.writeAsBytes(bytes, flush: true);
          if (!mounted) {
            await widget.controller.fileStore.deleteManagedEditedFile(
              target.path,
            );
            return;
          }
          Navigator.of(
            this.context,
          ).pop(widget.attachment.withEditedPath(target.path));
        },
        onCloseEditor: (_) {
          if (!_completed && mounted) Navigator.of(context).pop();
        },
      ),
      configs: ProImageEditorConfigs(
        mainEditor: const MainEditorConfigs(
          tools: [SubEditorMode.cropRotate, SubEditorMode.text],
        ),
        imageGeneration: ImageGenerationConfigs(
          outputFormat: outputFormat,
          jpegQuality: 95,
          pngLevel: 6,
          captureImageByteFormat: ui.ImageByteFormat.rawStraightRgba,
          enableUseOriginalBytes: false,
          maxOutputSize: sourceSize,
        ),
        i18n: zh
            ? const I18n(
                cancel: '取消',
                undo: '撤销',
                redo: '重做',
                done: '完成',
                remove: '删除',
                doneLoadingMsg: '正在生成图片',
                textEditor: I18nTextEditor(
                  inputHintText: '输入文字',
                  bottomNavigationBarText: '文字',
                  back: '返回',
                  done: '完成',
                  textAlign: '文字对齐',
                  fontScale: '文字大小',
                  backgroundMode: '背景样式',
                  smallScreenMoreTooltip: '更多',
                ),
                cropRotateEditor: I18nCropRotateEditor(
                  bottomNavigationBarText: '裁切/旋转',
                  rotate: '旋转',
                  flip: '翻转',
                  ratio: '比例',
                  back: '返回',
                  done: '完成',
                  cancel: '取消',
                  undo: '撤销',
                  redo: '重做',
                  reset: '重置',
                  smallScreenMoreTooltip: '更多',
                ),
                various: I18nVarious(
                  loadingDialogMsg: '请稍候…',
                  closeEditorWarningTitle: '关闭图片编辑器？',
                  closeEditorWarningMessage: '未保存的修改将会丢失。',
                  closeEditorWarningConfirmBtn: '关闭',
                  closeEditorWarningCancelBtn: '取消',
                ),
              )
            : const I18n(),
      ),
    );
  }
}
