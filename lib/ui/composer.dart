import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.textController,
    required this.peer,
  });

  final AppController controller;
  final TextEditingController textController;
  final Device peer;

  @override
  Widget build(BuildContext context) {
    // 文件传输已入队异步执行，不再用全局 busy 禁用输入框；仅当当前会话正在
    // 发送文本时短暂禁用，避免重复提交（计划 P1：传输期间仍可输入和发送）。
    final enabled =
        peer.trusted && !controller.isOperationActive('sendText:${peer.id}');
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (enabled) {
            _pasteFromClipboard();
          }
        },
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: controller.text.chooseFile,
              onPressed: enabled ? controller.pickAndSendFiles : null,
              icon: const Icon(Icons.attach_file),
            ),
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
              IconButton(
                tooltip: controller.text.chooseFolder,
                onPressed: enabled ? controller.pickAndSendFolder : null,
                icon: const Icon(Icons.folder_outlined),
              ),
            IconButton(
              tooltip: controller.text.pasteFileOrImage,
              onPressed: enabled ? _pasteFromClipboard : null,
              icon: const Icon(Icons.content_paste),
            ),
            Expanded(
              child: TextField(
                controller: textController,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: peer.trusted
                      ? controller.text.inputHint
                      : controller.text.pairBeforeSend,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: enabled ? _send : null,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final text = textController.text;
    textController.clear();
    controller.sendText(text);
  }

  Future<void> _pasteFromClipboard() async {
    final sentFiles = await controller.pasteAndSendClipboardFiles();
    if (sentFiles) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final value = textController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final newText = value.text.replaceRange(start, end, text);
    final offset = start + text.length;
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
