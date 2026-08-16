import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'incoming manual pairing request switches to the requesting device',
    () async {
      final dbA = AppDatabase(NativeDatabase.memory());
      final dbB = AppDatabase(NativeDatabase.memory());
      final controllerA = AppController(database: dbA);
      final controllerB = AppController(database: dbB);
      addTearDown(controllerA.dispose);
      addTearDown(controllerB.dispose);

      await controllerB.initialize();
      await controllerA.initialize();

      await dbB.upsertDiscoveredDevice(
        id: 'other-peer',
        displayName: 'Other peer',
        platform: 'windows',
        host: '127.0.0.1',
        port: 40000,
        signingPublicKey: 'other-signing',
        exchangePublicKey: 'other-exchange',
        fingerprint: 'other-fingerprint',
        avatarSeed: 'other-seed',
        avatarColor: '#64748B',
      );
      await controllerB.selectDevice((await dbB.getDevice('other-peer'))!);
      expect(controllerB.selectedDevice?.id, 'other-peer');

      final peerB = await controllerA.addPeerManually(
        '127.0.0.1',
        controllerB.localListenPort,
      );
      expect(peerB, isNotNull);

      final pairFuture = controllerA.pair(peerB!).catchError((_) {});
      await expectLater(
        _waitUntil(() => controllerB.pendingPairRequests.isNotEmpty),
        completes,
      );

      final requesterId = controllerA.identity!.deviceId;
      expect(controllerB.selectedDevice?.id, requesterId);
      expect(controllerB.pendingPairRequestForDevice(requesterId), isNotNull);

      await controllerB.rejectPendingPair();
      await pairFuture.timeout(const Duration(seconds: 5));
    },
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('condition not met before timeout');
}
