import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/core/file_types.dart';
import 'package:localchat/core/formatters.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/file_store.dart';
import 'package:localchat/ui/device_pane.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.controller,
    required this.message,
  });

  final AppController controller;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == 'out';
    final scheme = Theme.of(context).colorScheme;
    // 出站：绿色气泡；入站：白色/暗色表面气泡（微信式左右分列）。
    final bubbleColor = outgoing
        ? scheme.primary
        : (Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : scheme.surfaceContainerHighest);
    final textColor = outgoing ? scheme.onPrimary : scheme.onSurface;
    final align = outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final peer = outgoing ? null : controller.selectedDevice;
    final identity = controller.identity;
    final avatar = outgoing
        ? (identity == null
              ? null
              : DeviceAvatar(
                  name: identity.displayName,
                  platform: identity.platform,
                  avatarSeed: identity.avatarSeed,
                  avatarColor: identity.avatarColor,
                  radius: 16,
                ))
        : (peer == null
              ? null
              : DeviceAvatar(
                  name: controller.titleFor(peer),
                  platform: peer.platform,
                  avatarSeed: peer.avatarSeed,
                  avatarColor: peer.avatarColor,
                  radius: 16,
                ));
    final bubble = Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(outgoing ? 14 : 4),
              bottomRight: Radius.circular(outgoing ? 4 : 14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: textColor),
            child: message.kind == 'file'
                ? _FileMessage(
                    controller: controller,
                    message: message,
                    transfer: message.transferId == null
                        ? null
                        : controller.transfersById[message.transferId!],
                  )
                : _TextMessage(controller: controller, message: message),
          ),
        ),
        if (outgoing && message.status == 'failed' && message.kind != 'file')
          TextButton.icon(
            onPressed: controller.busy
                ? null
                : () => controller.retryMessage(message),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(controller.text.retry),
          ),
        const SizedBox(height: 3),
        Text(
          '${controller.text.messageStatus(message.status)} ${formatMessageTimestamp(message.createdAt)}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: outgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!outgoing && avatar != null) ...[
            avatar,
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
          if (outgoing && avatar != null) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }
}

class _TextMessage extends StatelessWidget {
  const _TextMessage({required this.controller, required this.message});

  final AppController controller;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final body = message.body ?? '';
    final links = extractLinks(body);
    if (links.isEmpty) {
      return SelectableText(body);
    }
    // 含链接时用富文本渲染，链接可点击打开（保留文本选择）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(body),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final link in links)
              ActionChip(
                avatar: const Icon(Icons.link, size: 16),
                label: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: () => controller.openUrl(link),
              ),
          ],
        ),
      ],
    );
  }
}

class _FileMessage extends StatelessWidget {
  const _FileMessage({
    required this.controller,
    required this.message,
    required this.transfer,
  });

  final AppController controller;
  final ChatMessage message;
  final Transfer? transfer;

  @override
  Widget build(BuildContext context) {
    final fileSize = transfer?.fileSize ?? message.fileSize ?? 0;
    final receivedBytes =
        transfer?.receivedBytes ??
        (message.status == 'sent' || message.status == 'received'
            ? fileSize
            : 0);
    final progress = fileSize <= 0
        ? null
        : (receivedBytes / fileSize).clamp(0.0, 1.0);
    final mimeType = transfer?.mimeType ?? message.mimeType;
    final openTarget =
        transfer?.savedUri ?? transfer?.savedPath ?? message.filePath;
    final saved = transfer?.savedPath != null || transfer?.savedUri != null;
    final folderTarget = transfer?.savedUri != null && Platform.isAndroid
        ? null
        : transfer?.savedPath ?? message.filePath;
    final canRename = controller.canRenameMessageFile(message, transfer);
    final canRetry =
        message.direction == 'out' &&
        message.status == 'failed' &&
        transfer != null;
    final showProgress =
        progress != null &&
        progress < 1 &&
        (message.status == 'sending' || message.status == 'receiving');
    final isQueued = message.status == 'queued';
    final isTerminalFailed =
        message.status == 'failed' ||
        message.status == 'canceled' ||
        message.status == 'interrupted';
    final outgoing = message.direction == 'out';
    final scheme = Theme.of(context).colorScheme;
    final panelColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.14)
        : scheme.surfaceContainerHigh;
    final panelBorderColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.22)
        : scheme.outlineVariant;
    final primaryTextColor = outgoing ? scheme.onPrimary : scheme.onSurface;
    final secondaryTextColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.82)
        : scheme.onSurfaceVariant;
    final disabledActionColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.36)
        : scheme.onSurface.withValues(alpha: 0.34);
    final failureTextColor = outgoing ? scheme.onPrimary : scheme.error;
    final fileName =
        message.relativePath ?? message.fileName ?? controller.text.file;
    final smallTextStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: secondaryTextColor);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: panelBorderColor),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: primaryTextColor),
        child: IconTheme.merge(
          data: IconThemeData(color: primaryTextColor),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilePreview(message: message, mimeType: mimeType),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: primaryTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (fileSize > 0)
                          Text(formatBytes(fileSize), style: smallTextStyle),
                        if (saved)
                          Text(
                            controller.text.savedLocal,
                            style: smallTextStyle,
                          ),
                        if (isQueued || isTerminalFailed)
                          Text(
                            messageStatusLabel(message.status),
                            style: smallTextStyle?.copyWith(
                              color: isTerminalFailed
                                  ? failureTextColor
                                  : secondaryTextColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  color: primaryTextColor,
                  backgroundColor: primaryTextColor.withValues(alpha: 0.22),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatBytes(receivedBytes)} / ${formatBytes(fileSize)} · ${(progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: secondaryTextColor),
                ),
              ],
              if (isQueued) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  color: primaryTextColor,
                  backgroundColor: primaryTextColor.withValues(alpha: 0.22),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  alignment: WrapAlignment.end,
                  children: [
                    if (canRetry)
                      _fileActionButton(
                        tooltip: controller.text.retry,
                        onPressed: controller.busy
                            ? null
                            : () => controller.retryMessage(message),
                        icon: Icons.refresh,
                        color: primaryTextColor,
                        disabledColor: disabledActionColor,
                      ),
                    _fileActionButton(
                      tooltip: controller.text.open,
                      onPressed: openTarget == null
                          ? null
                          : () => controller.openPath(openTarget),
                      icon: Icons.open_in_new,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
                    ),
                    _fileActionButton(
                      tooltip: controller.text.openFolder,
                      onPressed: folderTarget == null
                          ? null
                          : () => controller.openFolder(folderTarget),
                      icon: Icons.folder_open,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
                    ),
                    if (canRename)
                      _fileActionButton(
                        tooltip: controller.text.renameFile,
                        onPressed: controller.busy
                            ? null
                            : () => showRenameFileDialog(
                                context,
                                controller,
                                message,
                                transfer!,
                              ),
                        icon: Icons.drive_file_rename_outline,
                        color: primaryTextColor,
                        disabledColor: disabledActionColor,
                      ),
                    _fileActionButton(
                      tooltip: controller.text.saveLocal,
                      onPressed: saved
                          ? null
                          : () => controller.saveMessageFile(message),
                      icon: Icons.save_alt,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
                    ),
                    _fileActionButton(
                      tooltip: controller.text.delete,
                      onPressed: () => showDeleteFileMessageDialog(
                        context,
                        controller,
                        message,
                        transfer,
                      ),
                      icon: Icons.delete_outline,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
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

  Widget _fileActionButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
    required Color color,
    required Color disabledColor,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: color,
      disabledColor: disabledColor,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

Future<void> showRenameFileDialog(
  BuildContext context,
  AppController controller,
  ChatMessage message,
  Transfer transfer,
) async {
  final formKey = GlobalKey<FormState>();
  final initial = transfer.fileName;
  final dot = initial.lastIndexOf('.');
  final cursorOffset = dot > 0 ? dot : initial.length; // 放在扩展名前面（无扩展名时置于末尾）
  final textController = TextEditingController(text: initial)
    ..selection = TextSelection.collapsed(offset: cursorOffset);
  var value = initial;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.renameFile),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(labelText: controller.text.fileName),
          onChanged: (text) => value = text,
          validator: (text) => FileStore.validateFileName(text ?? '') == null
              ? null
              : controller.text.invalidFileName,
          onFieldSubmitted: (_) {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(value);
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(value);
            }
          },
          child: Text(controller.text.save),
        ),
      ],
    ),
  );
  if (result != null) {
    await controller.renameMessageFile(message, transfer, result);
  }
  textController.dispose();
}

Future<void> showDeleteFileMessageDialog(
  BuildContext context,
  AppController controller,
  ChatMessage message,
  Transfer? transfer,
) async {
  final filePath = transfer?.savedPath ?? message.filePath;
  final hasLocalFile =
      filePath != null &&
      filePath.isNotEmpty &&
      (File(filePath).existsSync() || Directory(filePath).existsSync());

  await showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(controller.text.deleteFileConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(controller.text.deleteFileMessageConfirmBody),
            const SizedBox(height: 16),
            Text(
              controller.text.localFilePath,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SelectableText(
                filePath != null && filePath.isNotEmpty
                    ? filePath
                    : controller.text.localFileNotExist,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: filePath != null && filePath.isNotEmpty
                      ? scheme.onSurface
                      : scheme.error,
                ),
              ),
            ),
            if (filePath != null && filePath.isNotEmpty && !hasLocalFile) ...[
              const SizedBox(height: 8),
              Text(
                controller.text.localFileNotExist,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(controller.text.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              controller.deleteFileMessage(message, false);
            },
            child: Text(controller.text.deleteRecordOnly),
          ),
          FilledButton(
            onPressed: hasLocalFile
                ? () {
                    Navigator.of(context).pop();
                    controller.deleteFileMessage(message, true);
                  }
                : null,
            child: Text(controller.text.deleteFileAndRecord),
          ),
        ],
      );
    },
  );
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.message, required this.mimeType});

  final ChatMessage message;
  final String? mimeType;

  @override
  Widget build(BuildContext context) {
    final path = message.filePath;
    if (path != null &&
        isImageFile(
          mimeType: mimeType,
          fileName: message.fileName,
          path: path,
        )) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.image_not_supported),
          ),
        ),
      );
    }
    return const Icon(Icons.insert_drive_file);
  }
}
