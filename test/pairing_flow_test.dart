import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/file_store.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/security_service.dart';
import 'package:localchat/services/transport_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('pairing waits for receiver approval before trusting devices', () async {
    final dbA = AppDatabase(NativeDatabase.memory());
    final dbB = AppDatabase(NativeDatabase.memory());
    final identityA = IdentityService(dbA);
    final identityB = IdentityService(dbB);
    final transportA = TransportService(
      dbA,
      identityA,
      SecurityService(identityA),
      FileStore(),
    );
    final transportB = TransportService(
      dbB,
      identityB,
      SecurityService(identityB),
      FileStore(),
    );
    addTearDown(() async {
      await transportA.stop();
      await transportB.stop();
      await dbA.close();
      await dbB.close();
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
  });
}
