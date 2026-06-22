import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/core/device_profile.dart';
import 'package:localchat/core/file_types.dart';
import 'package:localchat/data/app_database.dart';

void main() {
  test('default nickname is stable and platform specific', () {
    expect(defaultDeviceNickname('windows', 'abcdef012345'), 'Windows电脑-ABCD');
    expect(defaultDeviceNickname('android', '1234ef'), 'Android手机-1234');
  });

  test('avatar seed and color are stable for a device', () {
    final seed = avatarSeedFor('device-1', 'abcdef0123456789');
    expect(seed, avatarSeedFor('device-1', 'abcdef0123456789'));
    expect(avatarColorFor(seed), avatarColorFor(seed));
    expect(avatarColorFor(seed), startsWith('#'));
  });

  test('image files can be detected by mime type or extension', () {
    expect(isImageFile(mimeType: 'image/png', fileName: 'a.bin'), isTrue);
    expect(isImageFile(fileName: 'photo.webp'), isTrue);
    expect(isImageFile(fileName: 'package.apk'), isFalse);
  });

  test('files are mapped to stable automatic categories', () {
    expect(fileCategoryFor(fileName: 'photo.webp'), FileCategory.images);
    expect(fileCategoryFor(fileName: 'manual.pdf'), FileCategory.documents);
    expect(fileCategoryFor(fileName: 'bundle.7z'), FileCategory.archives);
    expect(fileCategoryFor(fileName: 'setup.msi'), FileCategory.apps);
    expect(fileCategoryFor(fileName: 'unknown.bin'), FileCategory.others);
  });

  test('transfer saved location is persisted', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.transfers)
        .insert(
          TransfersCompanion.insert(
            id: 'transfer-1',
            peerDeviceId: 'peer-1',
            direction: 'in',
            fileName: 'app.apk',
            fileSize: 1024,
            status: 'received',
            mimeType: const Value('application/vnd.android.package-archive'),
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

    await db.markTransferSaved(
      transferId: 'transfer-1',
      savedPath: r'C:\Users\me\Downloads\LocalChat\app.apk',
      savedUri: null,
    );

    final transfer = (await db.listTransfersByIds(['transfer-1'])).single;
    expect(transfer.savedPath, contains('Downloads'));
    expect(transfer.mimeType, 'application/vnd.android.package-archive');
  });

  test('received file rename updates transfer and message atomically', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 6, 22);
    await db
        .into(db.chatMessages)
        .insert(
          ChatMessagesCompanion.insert(
            id: 'message-1',
            conversationId: 'peer:peer-1',
            peerDeviceId: 'peer-1',
            direction: 'in',
            kind: 'file',
            fileName: const Value('old.pdf'),
            mimeType: const Value('application/pdf'),
            status: 'received',
            transferId: const Value('transfer-1'),
            createdAt: now,
          ),
        );
    await db
        .into(db.transfers)
        .insert(
          TransfersCompanion.insert(
            id: 'transfer-1',
            peerDeviceId: 'peer-1',
            direction: 'in',
            fileName: 'old.pdf',
            fileSize: 10,
            status: 'received',
            savedPath: const Value(r'C:\Downloads\old.pdf'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.renameReceivedTransfer(
      transferId: 'transfer-1',
      fileName: 'new.docx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      savedPath: r'C:\Downloads\Documents\new.docx',
      savedUri: null,
      relativePath: null,
    );

    final transfer = (await db.listTransfersByIds(['transfer-1'])).single;
    final message = (await db.listMessages('peer:peer-1')).single;
    expect(transfer.fileName, 'new.docx');
    expect(message.fileName, 'new.docx');
    expect(transfer.savedPath, contains('Documents'));
  });

  test(
    'migration repairs a database whose column exists before version 4',
    () async {
      final dir = await Directory.systemTemp.createTemp('localchat-migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}localchat.sqlite');

      final original = AppDatabase(NativeDatabase(file));
      await original.customSelect('SELECT 1').get();
      await original.customStatement('PRAGMA user_version = 3');
      await original.close();

      final repaired = AppDatabase(NativeDatabase(file));
      addTearDown(repaired.close);
      await repaired.listDevices();

      final version = await repaired
          .customSelect('PRAGMA user_version')
          .getSingle();
      final columns = await repaired
          .customSelect('PRAGMA table_info("devices")')
          .get();
      expect(version.read<int>('user_version'), 5);
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('endpoint_source'),
      );
      expect(
        columns.map((row) => row.read<String>('name')),
        containsAll(<String>['capabilities', 'identity_changed']),
      );
      final transferColumns = await repaired
          .customSelect('PRAGMA table_info("transfers")')
          .get();
      expect(
        transferColumns.map((row) => row.read<String>('name')),
        containsAll(<String>['group_id', 'error_code']),
      );
      final conversationColumns = await repaired
          .customSelect('PRAGMA table_info("conversations")')
          .get();
      expect(
        conversationColumns.map((row) => row.read<String>('name')),
        contains('last_read_at'),
      );
    },
  );

  test('v5 indexes are created on fresh databases', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.listDevices();
    final indexes = await db
        .customSelect('PRAGMA index_list("chat_messages")')
        .get();
    expect(
      indexes.map((row) => row.read<String>('name')),
      contains('idx_chat_messages_conversation_created'),
    );
  });

  test('theme mode preference is persisted', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final controller = AppController(database: db);
    addTearDown(controller.dispose);

    await controller.setThemeModeCode('dark');

    expect(controller.themeModeCode, 'dark');
    expect(await db.getSetting('theme_mode'), 'dark');
  });
}
