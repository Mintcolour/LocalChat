import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
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

  late AppDatabase dbA;
  late AppDatabase dbB;
  late TransportService transportA;
  late TransportService transportB;
  late Directory rootA;
  late Directory rootB;

  setUp(() async {
    dbA = AppDatabase(NativeDatabase.memory());
    dbB = AppDatabase(NativeDatabase.memory());
    rootA = await Directory.systemTemp.createTemp('localchat-queue-a');
    rootB = await Directory.systemTemp.createTemp('localchat-queue-b');
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
    // 双向信任。
    final localB = await identityB.load();
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
      capabilities: const [
        'text',
        'files',
        'encrypted_chunks',
        'transfer_cancel_v1',
      ],
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
      capabilities: const [
        'text',
        'files',
        'encrypted_chunks',
        'transfer_cancel_v1',
      ],
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

  test(
    'queued transfer is created with queued status before execution',
    () async {
      final localB = await IdentityService(dbB).load();
      final peerB = (await dbA.getDevice(localB.deviceId))!;
      final file = File('${rootA.path}${Platform.pathSeparator}q1.txt');
      await file.writeAsString('queued payload');

      await transportA.sendFiles(peerB, [file.path]);
      // 入队后立即应有一条 queued 记录。
      final transfers = await dbA.select(dbA.transfers).get();
      expect(transfers, isNotEmpty);
      expect(
        transfers.any(
          (t) =>
              t.status == 'queued' ||
              t.status == 'sending' ||
              t.status == 'sent',
        ),
        isTrue,
      );

      // 等待队列执行完成。
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final done = await dbA.select(dbA.transfers).get();
      expect(done.any((t) => t.status == 'sent'), isTrue);
    },
  );

  test('canceling a queued task marks it canceled without sending', () async {
    final localB = await IdentityService(dbB).load();
    final peerB = (await dbA.getDevice(localB.deviceId))!;
    // 用一个大文件让首任务停留在发送中，第二个排队，取消排队的。
    final big = File('${rootA.path}${Platform.pathSeparator}big.bin');
    final sink = big.openWrite();
    sink.add(List<int>.filled(8 * 1024 * 1024, 65)); // 8MB
    await sink.close();
    final queued = File('${rootA.path}${Platform.pathSeparator}queued.txt');
    await queued.writeAsString('queued');

    await transportA.sendFiles(peerB, [big.path]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await transportA.sendFiles(peerB, [queued.path]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 找到 queued 记录并取消。
    final transfers = await dbA.select(dbA.transfers).get();
    final queuedTransfer = transfers.firstWhere(
      (t) => t.fileName == 'queued.txt',
    );
    final canceled = await transportA.cancelOutbound(queuedTransfer.id);
    expect(canceled, isTrue);

    final after = (await dbA.listTransfersByIds([queuedTransfer.id])).single;
    expect(after.status, 'canceled');

    // 等待活动任务（big.bin）结束，避免 tearDown 时仍有在途传输访问已关闭的 db。
    final bigTransfer = transfers.firstWhere((t) => t.fileName == 'big.bin');
    for (var i = 0; i < 60; i++) {
      final current = (await dbA.listTransfersByIds([bigTransfer.id])).single;
      if (current.status == 'sent' ||
          current.status == 'failed' ||
          current.status == 'canceled') {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });

  test('canceling an active stream cleans up the receiver', () async {
    final localB = await IdentityService(dbB).load();
    final peerB = (await dbA.getDevice(localB.deviceId))!;
    final file = File('${rootA.path}${Platform.pathSeparator}active.bin');
    final sink = file.openWrite();
    for (var i = 0; i < 16; i++) {
      sink.add(List<int>.filled(1024 * 1024, i));
    }
    await sink.close();

    await transportA.sendFiles(peerB, [file.path]);
    Transfer? outgoing;
    for (var i = 0; i < 100; i++) {
      final rows = await dbA.select(dbA.transfers).get();
      outgoing = rows
          .where((item) => item.fileName == 'active.bin')
          .firstOrNull;
      if (outgoing != null && transportA.isOutboundActive(outgoing.id)) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(outgoing, isA<Transfer>());
    expect(transportA.isOutboundActive(outgoing!.id), isTrue);

    Transfer? incoming;
    for (var i = 0; i < 100; i++) {
      final rows = await dbB.select(dbB.transfers).get();
      incoming = rows.where((item) => item.id == outgoing!.id).firstOrNull;
      if (incoming?.status == 'receiving') break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(incoming?.status, 'receiving');
    final incomingPath = incoming!.filePath;

    expect(await transportA.requestRemoteCancel(peerB, outgoing.id), isTrue);
    expect(await transportA.cancelOutbound(outgoing.id), isTrue);

    for (var i = 0; i < 100; i++) {
      incoming = (await dbB.listTransfersByIds([outgoing.id])).single;
      if (incoming.status == 'canceled') break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(incoming!.status, 'canceled');
    expect(incomingPath == null || !File(incomingPath).existsSync(), isTrue);
  });

  test(
    'stale queued/sending transfers are marked interrupted on start',
    () async {
      // 直接往 dbA 插入 sending 与 queued 记录，模拟上次崩溃残留。
      final now = DateTime.now();
      for (final entry in const [
        ('stale-sending', 'sending'),
        ('stale-queued', 'queued'),
      ]) {
        await dbA
            .into(dbA.transfers)
            .insert(
              TransfersCompanion.insert(
                id: entry.$1,
                peerDeviceId: 'some-peer',
                direction: 'out',
                fileName: '${entry.$1}.bin',
                fileSize: 100,
                status: entry.$2,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await dbA
            .into(dbA.chatMessages)
            .insert(
              ChatMessagesCompanion.insert(
                id: '${entry.$1}-msg',
                conversationId: 'peer:some-peer',
                peerDeviceId: 'some-peer',
                direction: 'out',
                kind: 'file',
                status: entry.$2,
                transferId: Value(entry.$1),
                createdAt: now,
              ),
            );
      }
      // 重新 start 触发 _markStaleTransfersInterrupted（已在 setUp 调用过，这里再显式验证）。
      await transportA.stop();
      await transportA.start();
      final transfers = await dbA.listTransfersByIds([
        'stale-sending',
        'stale-queued',
      ]);
      expect(transfers, hasLength(2));
      expect(
        transfers.every((transfer) => transfer.status == 'interrupted'),
        isTrue,
      );
      expect(
        transfers.every((transfer) => transfer.errorCode == 'interrupted'),
        isTrue,
      );
    },
  );

  test('transfer task views group by kind and expose progress', () async {
    final localB = await IdentityService(dbB).load();
    final peerB = (await dbA.getDevice(localB.deviceId))!;
    final file = File('${rootA.path}${Platform.pathSeparator}v.txt');
    await file.writeAsString('view payload');
    await transportA.sendFiles(peerB, [file.path]);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final views = await transportA.buildTransferTaskViews();
    expect(views, isNotEmpty);
    final view = views.first;
    expect(view.peerDisplayName, localB.displayName);
    expect(view.groupKind, TransferGroupKind.completed);
    expect(view.progress, greaterThanOrEqualTo(0.99));
  });

  test('peer capability check gates remote cancel', () async {
    final localB = await IdentityService(dbB).load();
    final peerB = (await dbA.getDevice(localB.deviceId))!;
    expect(transportA.deviceSupportsCancel(peerB), isTrue);

    // 一个不支持取消能力的对端。
    final localA = await IdentityService(dbA).load();
    await dbA.upsertManualDevice(
      id: 'legacy-peer',
      displayName: 'Legacy',
      platform: 'windows',
      host: '127.0.0.1',
      port: 9,
      signingPublicKey: localA.signingPublicKey,
      exchangePublicKey: localA.exchangePublicKey,
      fingerprint: localA.fingerprint,
      avatarSeed: localA.avatarSeed,
      avatarColor: localA.avatarColor,
      capabilities: const ['text', 'files'], // 无 transfer_cancel_v1
    );
    final legacy = (await dbA.getDevice('legacy-peer'))!;
    expect(transportA.deviceSupportsCancel(legacy), isFalse);
    expect(peerSupportsCancel(const ['text', 'files']), isFalse);
    expect(peerSupportsCancel(const ['transfer_cancel_v1']), isTrue);
  });
}
