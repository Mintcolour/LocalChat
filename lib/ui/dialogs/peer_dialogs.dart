import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/file_store.dart';

Future<void> showRenameDialog(
  BuildContext context,
  AppController controller,
  Device peer,
) async {
  var input = controller.titleFor(peer);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.renameConversation),
      content: TextFormField(
        initialValue: input,
        autofocus: true,
        decoration: InputDecoration(
          labelText: controller.text.conversationName,
        ),
        onChanged: (value) => input = value,
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(input),
          child: Text(controller.text.save),
        ),
      ],
    ),
  );
  if (value != null) {
    await controller.renameSelectedConversation(value);
  }
}

Future<void> confirmDeleteConversation(
  BuildContext context,
  AppController controller,
) async {
  final peer = controller.selectedDevice;
  if (peer == null) return;
  final title = controller.titleFor(peer);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.deleteConversationTitle),
      content: Text(controller.text.deleteConversationBody(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(controller.text.delete),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.deleteSelectedConversation();
  }
}

Future<bool> confirmDanger(
  BuildContext context,
  AppController controller,
  String title,
  String body,
) async {
  final text = controller.text;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(text.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(text.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showLocalRenameDialog(
  BuildContext context,
  AppController controller,
) async {
  var input = controller.identity?.displayName ?? 'LocalChat';
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.editLocalNickname),
      content: TextFormField(
        initialValue: input,
        autofocus: true,
        decoration: InputDecoration(
          labelText: controller.text.deviceNameVisible,
        ),
        onChanged: (value) => input = value,
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(input),
          child: Text(controller.text.save),
        ),
      ],
    ),
  );
  if (value != null) {
    await controller.renameLocalDevice(value);
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
