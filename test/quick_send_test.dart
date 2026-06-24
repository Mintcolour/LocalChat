import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
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

  test(
    'quick send devices include online trusted peers with selected first',
    () {
      final controller = AppController(
        database: AppDatabase(NativeDatabase.memory()),
      );
      addTearDown(controller.dispose);
      final now = DateTime.utc(2026, 6, 24, 12);
      final selected = _device(
        id: 'selected',
        displayName: 'Selected PC',
        lastSeen: now.subtract(const Duration(seconds: 8)),
      );
      final recent = _device(
        id: 'recent',
        displayName: 'Recent Phone',
        platform: 'android',
        lastSeen: now.subtract(const Duration(seconds: 1)),
      );
      final offline = _device(
        id: 'offline',
        displayName: 'Offline PC',
        lastSeen: now.subtract(const Duration(seconds: 30)),
      );
      final untrusted = _device(
        id: 'untrusted',
        displayName: 'Nearby',
        trusted: false,
        lastSeen: now,
      );

      controller.selectedDevice = selected;
      controller.devices = [recent, offline, untrusted, selected];

      final views = controller.quickSendDeviceViews(now: now);

      expect(views.map((view) => view.id), ['selected', 'recent']);
      expect(views.first.selected, isTrue);
      expect(views.first.displayName, 'Selected PC');
      expect(views.last.platform, 'android');
    },
  );

  test('quick send rejects offline targets before sending', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final controller = AppController(database: db);
    addTearDown(controller.dispose);
    final peer = _device(id: 'peer', displayName: 'Peer PC');
    await db.trustDevice(
      id: peer.id,
      displayName: peer.displayName,
      platform: peer.platform,
      host: peer.host!,
      port: peer.port!,
      signingPublicKey: peer.signingPublicKey,
      exchangePublicKey: peer.exchangePublicKey,
      fingerprint: peer.fingerprint,
      avatarSeed: peer.avatarSeed,
      avatarColor: peer.avatarColor,
    );
    await db.markDeviceOffline(peer.id);
    final file = await File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}quick-offline.txt',
    ).writeAsString('payload');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    await controller.handleQuickDropFiles(peer.id, [file.path]);

    expect(controller.status, controller.text.quickSendTargetUnavailable);
    expect(await db.select(db.transfers).get(), isEmpty);
  });

  test(
    'quick send queues files for target peer without switching chat',
    () async {
      final dbA = AppDatabase(NativeDatabase.memory());
      final dbB = AppDatabase(NativeDatabase.memory());
      final rootA = await Directory.systemTemp.createTemp('localchat-quick-a');
      final rootB = await Directory.systemTemp.createTemp('localchat-quick-b');
      final controllerA = AppController(
        database: dbA,
        fileStore: _TestFileStore(rootA),
      );
      final identityB = IdentityService(dbB);
      final transportB = TransportService(
        dbB,
        identityB,
        SecurityService(identityB),
        _TestFileStore(rootB),
      );
      addTearDown(() async {
        await controllerA.transportService.stop();
        await transportB.stop();
        controllerA.dispose();
        await dbB.close();
        await rootA.delete(recursive: true);
        await rootB.delete(recursive: true);
      });

      final localA = await controllerA.identityService.load();
      final localB = await identityB.load();
      await controllerA.transportService.start();
      await transportB.start();
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
      await dbB.trustDevice(
        id: localA.deviceId,
        displayName: localA.displayName,
        platform: localA.platform,
        host: '127.0.0.1',
        port: controllerA.transportService.port,
        signingPublicKey: localA.signingPublicKey,
        exchangePublicKey: localA.exchangePublicKey,
        fingerprint: localA.fingerprint,
        avatarSeed: localA.avatarSeed,
        avatarColor: localA.avatarColor,
        capabilities: const ['text', 'files', 'encrypted_chunks'],
      );
      await dbA.trustDevice(
        id: 'other-peer',
        displayName: 'Other Peer',
        platform: 'windows',
        host: '127.0.0.1',
        port: 9,
        signingPublicKey: 'other-signing',
        exchangePublicKey: 'other-exchange',
        fingerprint: 'other-fingerprint',
        avatarSeed: 'other-seed',
        avatarColor: '#334155',
      );
      final otherPeer = (await dbA.getDevice('other-peer'))!;
      controllerA.selectedDevice = otherPeer;
      controllerA.selectedConversation = await dbA.ensureConversation(
        otherPeer,
      );
      final file = File('${rootA.path}${Platform.pathSeparator}quick.txt');
      await file.writeAsString('quick payload');

      await controllerA.handleQuickDropFiles(localB.deviceId, [file.path]);

      expect(controllerA.selectedDevice?.id, 'other-peer');
      final transfers = await dbA.select(dbA.transfers).get();
      expect(
        transfers.map((transfer) => transfer.fileName),
        contains('quick.txt'),
      );
      expect(controllerA.status, contains('1'));
      expect(controllerA.status, contains(localB.displayName));
    },
  );
}

Device _device({
  required String id,
  required String displayName,
  String platform = 'windows',
  bool trusted = true,
  DateTime? lastSeen,
}) {
  return Device(
    id: id,
    displayName: displayName,
    platform: platform,
    host: '127.0.0.1',
    port: 40123,
    signingPublicKey: 'signing-$id',
    exchangePublicKey: 'exchange-$id',
    fingerprint: 'fingerprint-$id',
    avatarSeed: 'seed-$id',
    avatarColor: '#2563EB',
    trusted: trusted,
    endpointSource: 'auto',
    lastSeen: lastSeen ?? DateTime.now(),
    createdAt: DateTime.utc(2026),
  );
}
