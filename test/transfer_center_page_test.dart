import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/ui/transfer_center_page.dart';

void main() {
  testWidgets(
    'transfer center renders sections for active and completed transfers',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final controller = AppController(database: db);
      addTearDown(controller.dispose);
      final now = DateTime(2026, 6, 22, 10);

      // 一条已完成入站传输。
      await db
          .into(db.transfers)
          .insert(
            TransfersCompanion.insert(
              id: 't-done',
              peerDeviceId: 'peer-1',
              direction: 'in',
              fileName: 'photo.png',
              fileSize: 1024,
              status: 'received',
              savedPath: const Value(r'C:\Downloads\LocalChat\photo.png'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      // 一条已完成出站传输：可打开源文件，但不能重命名源文件。
      await db
          .into(db.transfers)
          .insert(
            TransfersCompanion.insert(
              id: 't-sent',
              peerDeviceId: 'peer-1',
              direction: 'out',
              fileName: 'sent.apk',
              fileSize: 4096,
              status: 'sent',
              filePath: const Value(r'C:\temp\sent.apk'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      // 一条排队出站传输。
      await db
          .into(db.transfers)
          .insert(
            TransfersCompanion.insert(
              id: 't-queued',
              peerDeviceId: 'peer-1',
              direction: 'out',
              fileName: 'doc.pdf',
              fileSize: 2048,
              status: 'queued',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.trustDevice(
        id: 'peer-1',
        displayName: 'Phone',
        platform: 'android',
        host: '127.0.0.1',
        port: 1,
        signingPublicKey: 's',
        exchangePublicKey: 'e',
        fingerprint: 'f',
        avatarSeed: 'seed',
        avatarColor: '#2563EB',
      );

      await tester.pumpWidget(
        MaterialApp(home: TransferCenterPage(controller: controller)),
      );
      // 首帧为 loading，等待异步加载完成。
      await tester.pumpAndSettle();

      // 单文件组：文件名同时出现在组标题与任务行；批量场景同理。
      expect(find.text('photo.png'), findsWidgets);
      expect(find.text('doc.pdf'), findsWidgets);
      expect(find.text('sent.apk'), findsWidgets);
      // 分组标题出现。
      expect(find.textContaining('进行中'), findsOneWidget);
      expect(find.textContaining('已完成'), findsOneWidget);
      expect(find.byTooltip(controller.text.open), findsNWidgets(2));
      expect(find.byTooltip(controller.text.openFolder), findsNWidgets(2));
      expect(find.byTooltip(controller.text.renameFile), findsOneWidget);
    },
  );
}
