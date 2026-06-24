import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/file_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'changing storage root without migration keeps old files and DB paths',
    () async {
      if (!Platform.isWindows) return;
      final oldRoot = await Directory.systemTemp.createTemp('localchat-old');
      final newRoot = await Directory.systemTemp.createTemp('localchat-new');
      addTearDown(() => oldRoot.delete(recursive: true));
      addTearDown(() => newRoot.delete(recursive: true));
      final source = File(
        p.join(oldRoot.path, 'Peer', '26', '06', 'Documents', 'report.txt'),
      );
      await source.parent.create(recursive: true);
      await source.writeAsString('old');

      final db = AppDatabase(NativeDatabase.memory());
      final controller = AppController(database: db);
      addTearDown(controller.dispose);
      await controller.settings.setStorageRootPath(oldRoot.path);
      controller.fileStore.setStorageRootPath(oldRoot.path);
      controller.storageRootPath = oldRoot.path;
      await _insertReceivedFile(
        db,
        transferId: 'transfer-1',
        messageId: 'message-1',
        path: source.path,
        fileName: 'report.txt',
      );

      await controller.setStorageRootPath(
        newRoot.path,
        migrateIndexedFiles: false,
      );

      final transfer = (await db.listTransfersByIds(['transfer-1'])).single;
      expect(await source.exists(), isTrue);
      expect(
        await File(
          p.join(newRoot.path, 'Peer', '26', '06', 'Documents', 'report.txt'),
        ).exists(),
        isFalse,
      );
      expect(FileStore.isSamePath(transfer.savedPath!, source.path), isTrue);
      expect(
        FileStore.isSamePath(controller.storageRootPath, newRoot.path),
        isTrue,
      );
    },
  );

  test(
    'migration moves indexed files, skips missing files, and leaves unknown files',
    () async {
      if (!Platform.isWindows) return;
      final oldRoot = await Directory.systemTemp.createTemp('localchat-old');
      final newRoot = await Directory.systemTemp.createTemp('localchat-new');
      addTearDown(() => oldRoot.delete(recursive: true));
      addTearDown(() => newRoot.delete(recursive: true));
      final source = File(
        p.join(oldRoot.path, 'Peer', '26', '06', 'Documents', 'report.txt'),
      );
      await source.parent.create(recursive: true);
      await source.writeAsString('old');
      final conflict = File(
        p.join(newRoot.path, 'Peer', '26', '06', 'Documents', 'report.txt'),
      );
      await conflict.parent.create(recursive: true);
      await conflict.writeAsString('existing');
      final unknown = File(p.join(oldRoot.path, 'unknown.txt'));
      await unknown.writeAsString('unknown');
      final missingPath = p.join(
        oldRoot.path,
        'Peer',
        '26',
        '06',
        'Documents',
        'missing.txt',
      );

      final db = AppDatabase(NativeDatabase.memory());
      final controller = AppController(database: db);
      addTearDown(controller.dispose);
      await controller.settings.setStorageRootPath(oldRoot.path);
      controller.fileStore.setStorageRootPath(oldRoot.path);
      controller.storageRootPath = oldRoot.path;
      await _insertReceivedFile(
        db,
        transferId: 'transfer-1',
        messageId: 'message-1',
        path: source.path,
        fileName: 'report.txt',
      );
      await _insertReceivedFile(
        db,
        transferId: 'transfer-2',
        messageId: 'message-2',
        path: missingPath,
        fileName: 'missing.txt',
      );

      await controller.setStorageRootPath(
        newRoot.path,
        migrateIndexedFiles: true,
      );

      final moved = (await db.listTransfersByIds(['transfer-1'])).single;
      final skipped = (await db.listTransfersByIds(['transfer-2'])).single;
      final messages = await db.listMessages('peer:peer-1');
      final movedMessage = messages.singleWhere(
        (message) => message.id == 'message-1',
      );
      final movedPath = p.join(
        newRoot.path,
        'Peer',
        '26',
        '06',
        'Documents',
        'report (1).txt',
      );
      expect(await File(movedPath).exists(), isTrue);
      expect(await source.exists(), isFalse);
      expect(await unknown.exists(), isTrue);
      expect(FileStore.isSamePath(moved.savedPath!, movedPath), isTrue);
      expect(FileStore.isSamePath(moved.filePath!, movedPath), isTrue);
      expect(FileStore.isSamePath(movedMessage.filePath!, movedPath), isTrue);
      expect(moved.fileName, 'report (1).txt');
      expect(movedMessage.fileName, 'report (1).txt');
      expect(FileStore.isSamePath(skipped.savedPath!, missingPath), isTrue);
      expect(controller.status, contains('已移动 1 个文件，跳过 1 个'));
    },
  );
}

Future<void> _insertReceivedFile(
  AppDatabase db, {
  required String transferId,
  required String messageId,
  required String path,
  required String fileName,
}) async {
  final now = DateTime.utc(2026, 6, 24);
  await db
      .into(db.chatMessages)
      .insert(
        ChatMessagesCompanion.insert(
          id: messageId,
          conversationId: 'peer:peer-1',
          peerDeviceId: 'peer-1',
          direction: 'in',
          kind: 'file',
          fileName: Value(fileName),
          filePath: Value(path),
          status: 'received',
          transferId: Value(transferId),
          createdAt: now,
        ),
      );
  await db
      .into(db.transfers)
      .insert(
        TransfersCompanion.insert(
          id: transferId,
          peerDeviceId: 'peer-1',
          direction: 'in',
          fileName: fileName,
          filePath: Value(path),
          fileSize: 3,
          savedPath: Value(path),
          status: 'received',
          createdAt: now,
          updatedAt: now,
        ),
      );
}
