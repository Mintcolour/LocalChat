import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/models/transfer_views.dart';
import 'package:localchat/services/file_store.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/security_service.dart';
import 'package:localchat/services/transport_service.dart';

class _TestFileStore extends FileStore {
  _TestFileStore(this.root);
  final Directory root;
  @override
  Future<Directory> receiveDirectory() async {
    final dir = Directory('${root.path}${Platform.pathSeparator}incoming');
    await dir.create(recursive: true);
    return dir;
  }
  @override
  Future<SavedFile> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    required String conversationFolder,
    required DateTime at,
    String? relativePath,
    bool moveSource = false,
  }) async {
    return SavedFile(path: sourcePath, actualFileName: fileName);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('transfer cancel compatibility and grouping', () {
    late AppDatabase dbA;
    late AppDatabase dbB;
    late TransportService transportA;
    late TransportService transportB;
    late Directory rootA;
    late Directory rootB;

    setUp(() async {
      dbA = AppDatabase(NativeDatabase.memory());
      dbB = AppDatabase(NativeDatabase.memory());
      rootA = await Directory.systemTemp.createTemp('localchat-cancel-a');
      rootB = await Directory.systemTemp.createTemp('localchat-cancel-b');
      final identityA = IdentityService(dbA);
      final identityB = IdentityService(dbB);
      transportA = TransportService(
        dbA,
        identityA,
        SecurityService(identityA),
        _TestFileStore(rootA),
      );
      transportB = TransportService(
        dbB,
        identityB,
        SecurityService(identityB),
        _TestFileStore(rootB),
      );
      await identityA.load();
      await identityB.load();
      await transportA.start();
      await transportB.start();
      final localB = await identityB.load();
      // A 视角下 B 是旧版本接收端：不支持 cancel（A 发送时无法主动取消）。
      await dbA.trustDevice(
        id: localB.deviceId,
        displayName: localB.displayName,
        platform: localB.platform,
        host: '127.0.0.1',
        port: transportB.port,
        signingPublicKey: localB.signingPublicKey,
        exchangePublicKey: localB.exchangePublicKey,
        fingerprint: localB.fingerprint,
        avatarSeed: localB.avatarSeed,
        avatarColor: localB.avatarColor,
        capabilities: const ['text', 'files', 'encrypted_chunks'],
      );
      final localA = await identityA.load();
      await dbB.trustDevice(
        id: localA.deviceId,
        displayName: localA.displayName,
        platform: localA.platform,
        host: '127.0.0.1',
        port: transportA.port,
        signingPublicKey: localA.signingPublicKey,
        exchangePublicKey: localA.exchangePublicKey,
        fingerprint: localA.fingerprint,
        avatarSeed: localA.avatarSeed,
        avatarColor: localA.avatarColor,
        capabilities: const ['text', 'files', 'encrypted_chunks', 'transfer_cancel_v1'],
      );
    });

    tearDown(() async {
      await transportA.stop();
      await transportB.stop();
      await dbA.close();
      await dbB.close();
      await rootA.delete(recursive: true);
      await rootB.delete(recursive: true);
    });

    test('cancel request is denied when peer lacks transfer_cancel_v1', () async {
      final localB = await IdentityService(dbB).load();
      final peerB = (await dbA.getDevice(localB.deviceId))!;
      // A 视角下 B 不支持取消（capabilities 未含 transfer_cancel_v1）。
      expect(dbA.deviceCapabilities(peerB), isNot(contains(transferCancelCapability)));
      expect(transportA.deviceSupportsCancel(peerB), isFalse);
      expect(peerSupportsCancel(const ['text', 'files']), isFalse);
      // requestRemoteCancel 应在能力检查处返回 false，不发起网络请求。
      final ok = await transportA.requestRemoteCancel(peerB, 'nonexistent');
      expect(ok, isFalse);
    });

    test('folder group cancel removes all queued tasks in the group', () async {
      final localB = await IdentityService(dbB).load();
      final peerB = (await dbA.getDevice(localB.deviceId))!;
      // 入队一个文件夹（3 个文件），共享同一 groupId。
      final files = <File>[];
      for (var i = 0; i < 3; i++) {
        final f = File('${rootA.path}${Platform.pathSeparator}g$i.txt');
        await f.writeAsString('group $i');
        files.add(f);
      }
      // 用一个大文件占住活动槽，让 3 个小文件排队。
      final blocker = File('${rootA.path}${Platform.pathSeparator}blocker.bin');
      final sink = blocker.openWrite();
      sink.add(List<int>.filled(6 * 1024 * 1024, 66));
      await sink.close();
      await transportA.sendFiles(peerB, [blocker.path]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await transportA.sendFiles(peerB, files.map((f) => f.path).toList());
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // 排队的 3 个文件应共享同一 groupId。
      final queued = await dbA.select(dbA.transfers).get();
      final groupIds = queued
          .where((t) => t.fileName.startsWith('g') && t.fileName.endsWith('.txt'))
          .map((t) => t.groupId)
          .toSet();
      expect(groupIds.length, 1);
      final groupId = groupIds.single!;
      final canceled = await transportA.cancelOutboundGroup(groupId);
      expect(canceled, greaterThanOrEqualTo(1));

      // 等待 blocker 结束，避免 tearDown 时在途传输。
      final blockerTransfer = queued.firstWhere((t) => t.fileName == 'blocker.bin');
      for (var i = 0; i < 60; i++) {
        final cur = (await dbA.listTransfersByIds([blockerTransfer.id])).single;
        if (const ['sent', 'failed', 'canceled'].contains(cur.status)) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
  });

  test('transfer group view aggregates progress across tasks', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 6, 22);
    await db.batch((batch) {
      batch.insertAll(db.transfers, [
        TransfersCompanion.insert(
          id: 'g1a', peerDeviceId: 'peer-1', direction: 'out', fileName: 'a.bin',
          fileSize: 100, status: 'sent', groupId: const Value('group-1'),
          receivedBytes: const Value(100), createdAt: now, updatedAt: now,
        ),
        TransfersCompanion.insert(
          id: 'g1b', peerDeviceId: 'peer-1', direction: 'out', fileName: 'b.bin',
          fileSize: 200, status: 'sending', groupId: const Value('group-1'),
          receivedBytes: const Value(50), createdAt: now, updatedAt: now,
        ),
      ]);
    });
    await db.trustDevice(
      id: 'peer-1', displayName: 'Phone', platform: 'android', host: '1.1.1.1',
      port: 1, signingPublicKey: 's', exchangePublicKey: 'e', fingerprint: 'f',
      avatarSeed: 'seed', avatarColor: '#000',
    );
    final identity = IdentityService(db);
    final transport = TransportService(db, identity, SecurityService(identity), FileStore());
    final groups = await transport.buildTransferGroupViews();
    final group = groups.firstWhere((g) => g.groupId == 'group-1');
    expect(group.tasks.length, 2);
    expect(group.totalBytes, 300);
    expect(group.sentBytes, 150);
    expect(group.groupKind, TransferGroupKind.active);
  });
}
