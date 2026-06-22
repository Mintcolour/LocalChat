import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
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

  test('pairing waits for receiver approval before trusting devices', () async {
    final dbA = AppDatabase(NativeDatabase.memory());
    final dbB = AppDatabase(NativeDatabase.memory());
    final identityA = IdentityService(dbA);
    final identityB = IdentityService(dbB);
    final rootA = await Directory.systemTemp.createTemp('localchat-retry-a');
    final rootB = await Directory.systemTemp.createTemp('localchat-retry-b');
    final transportA = TransportService(
      dbA,
      identityA,
      SecurityService(identityA),
      _TestFileStore(rootA),
    );
    final transportB = TransportService(
      dbB,
      identityB,
      SecurityService(identityB),
      _TestFileStore(rootB),
    );
    addTearDown(() async {
      await transportA.stop();
      await transportB.stop();
      await dbA.close();
      await dbB.close();
      await rootA.delete(recursive: true);
      await rootB.delete(recursive: true);
    });

    final localA = await identityA.load();
    final localB = await identityB.load();
    await transportA.start();
    final portB = await transportB.start();
    final peerB = Device(
      id: localB.deviceId,
      displayName: localB.displayName,
      platform: localB.platform,
      host: '127.0.0.1',
      port: portB,
      signingPublicKey: localB.signingPublicKey,
      exchangePublicKey: localB.exchangePublicKey,
      fingerprint: localB.fingerprint,
      avatarSeed: localB.avatarSeed,
      avatarColor: localB.avatarColor,
      trusted: false,
      endpointSource: 'auto',
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
    );

    var completed = false;
    final pairFuture = transportA.pairWith(peerB, '123456').whenComplete(() {
      completed = true;
    });
    final request = await transportB.pairRequests.first.timeout(
      const Duration(seconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(completed, isFalse);
    expect((await dbB.getDevice(localA.deviceId))!.trusted, isFalse);

    transportB.approvePairRequest(request.id);
    await pairFuture.timeout(const Duration(seconds: 5));

    expect((await dbA.getDevice(localB.deviceId))!.trusted, isTrue);
    expect((await dbB.getDevice(localA.deviceId))!.trusted, isTrue);
    final trustedPeerB = (await dbA.getDevice(localB.deviceId))!;
    final conversationA = await dbA.ensureConversation(trustedPeerB);
    final source = File('${rootA.path}${Platform.pathSeparator}retry.txt');
    await source.writeAsString('retry payload');
    final now = DateTime.now();
    await dbA
        .into(dbA.transfers)
        .insert(
          TransfersCompanion.insert(
            id: 'failed-transfer',
            peerDeviceId: trustedPeerB.id,
            direction: 'out',
            fileName: 'retry.txt',
            filePath: Value(source.path),
            fileSize: await source.length(),
            mimeType: const Value('text/plain'),
            status: 'failed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await dbA.addMessage(
      ChatMessagesCompanion.insert(
        id: 'failed-message',
        conversationId: conversationA.id,
        peerDeviceId: trustedPeerB.id,
        direction: 'out',
        kind: 'file',
        fileName: const Value('retry.txt'),
        filePath: Value(source.path),
        fileSize: Value(await source.length()),
        mimeType: const Value('text/plain'),
        status: 'failed',
        transferId: const Value('failed-transfer'),
        createdAt: now,
      ),
    );
    final failedMessage = (await dbA.listMessages(
      conversationA.id,
    )).singleWhere((message) => message.id == 'failed-message');
    final failedTransfer = (await dbA.listTransfersByIds([
      'failed-transfer',
    ])).single;

    await transportA.retryFile(trustedPeerB, failedMessage, failedTransfer);

    final retriedMessage = (await dbA.listMessages(
      conversationA.id,
    )).singleWhere((message) => message.id == 'failed-message');
    expect(retriedMessage.status, 'sent');
    expect(retriedMessage.transferId, isNot('failed-transfer'));
    expect(await dbA.listTransfersByIds(['failed-transfer']), isEmpty);
  });
}
