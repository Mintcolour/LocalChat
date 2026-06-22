import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/pending_attachment.dart';
import 'package:localchat/ui/attachment_preview.dart';

void main() {
  testWidgets('image batches show one review page with an edit action', (
    tester,
  ) async {
    final image = (await tester.runAsync<File>(() async {
      final dir = await Directory.systemTemp.createTemp(
        'localchat-preview-test',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}photo.png');
      await file.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      return file;
    }))!;
    final controller = AppController(
      database: AppDatabase(NativeDatabase.memory()),
    );
    addTearDown(controller.dispose);
    final batch = PendingAttachmentBatch(
      id: 1,
      items: [PendingAttachment.fromPath(image.path)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AttachmentPreviewPage(controller: controller, batch: batch),
      ),
    );
    await tester.pump();

    expect(find.text('预览附件'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.byIcon(Icons.crop_rotate), findsOneWidget);
    expect(find.text('发送 1 个附件'), findsOneWidget);
  });
}
