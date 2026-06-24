import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/services/discovery_service.dart';
import 'package:localchat/services/identity_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<LocalIdentity> identityFor(AppDatabase db) {
    return IdentityService(db).load();
  }

  DiscoveredPeer peerFromIdentity(LocalIdentity identity) {
    return DiscoveredPeer(
      deviceId: identity.deviceId,
      displayName: identity.displayName,
      platform: identity.platform,
      host: '',
      port: 40123,
      signingPublicKey: identity.signingPublicKey,
      exchangePublicKey: identity.exchangePublicKey,
      fingerprint: identity.fingerprint,
      avatarSeed: identity.avatarSeed,
      avatarColor: identity.avatarColor,
      lastSeen: DateTime.now(),
    );
  }

  test(
    'valid discovery datagram is stored and answered with unicast reply',
    () async {
      final localDb = AppDatabase(NativeDatabase.memory());
      final remoteDb = AppDatabase(NativeDatabase.memory());
      addTearDown(localDb.close);
      addTearDown(remoteDb.close);
      final localIdentityService = IdentityService(localDb);
      await localIdentityService.load();
      final remote = await identityFor(remoteDb);
      final sent = <({InternetAddress address, int port, List<int> data})>[];
      final service = DiscoveryService(
        localDb,
        localIdentityService,
        sendObserver: (address, port, data) {
          sent.add((address: address, port: port, data: data));
        },
      );

      await service.handleDatagramForTest(
        utf8.encode(jsonEncode(peerFromIdentity(remote).toJson())),
        InternetAddress('192.168.1.50'),
        listenPort: 45880,
      );

      final device = await localDb.getDevice(remote.deviceId);
      expect(device?.host, '192.168.1.50');
      expect(sent, hasLength(1));
      expect(sent.single.address.address, '192.168.1.50');
      expect(sent.single.port, discoveryPort);
      final reply = jsonDecode(utf8.decode(sent.single.data)) as Map;
      expect(reply['discovery_reply'], isTrue);
      expect(reply['device_id'], localIdentityService.identity.deviceId);
    },
  );

  test('invalid discovery identity is ignored and not answered', () async {
    final localDb = AppDatabase(NativeDatabase.memory());
    final remoteDb = AppDatabase(NativeDatabase.memory());
    addTearDown(localDb.close);
    addTearDown(remoteDb.close);
    final localIdentityService = IdentityService(localDb);
    await localIdentityService.load();
    final remote = await identityFor(remoteDb);
    final sent = <({InternetAddress address, int port, List<int> data})>[];
    final service = DiscoveryService(
      localDb,
      localIdentityService,
      sendObserver: (address, port, data) {
        sent.add((address: address, port: port, data: data));
      },
    );
    final invalid = peerFromIdentity(remote).toJson()
      ..['device_id'] = 'invalid-device-id';

    await service.handleDatagramForTest(
      utf8.encode(jsonEncode(invalid)),
      InternetAddress('192.168.1.51'),
      listenPort: 45880,
    );

    expect(sent, isEmpty);
    expect(await localDb.listDevices(), isEmpty);
  });

  test('discovery reply packets are stored without ping-pong reply', () async {
    final localDb = AppDatabase(NativeDatabase.memory());
    final remoteDb = AppDatabase(NativeDatabase.memory());
    addTearDown(localDb.close);
    addTearDown(remoteDb.close);
    final localIdentityService = IdentityService(localDb);
    await localIdentityService.load();
    final remote = await identityFor(remoteDb);
    final sent = <({InternetAddress address, int port, List<int> data})>[];
    final service = DiscoveryService(
      localDb,
      localIdentityService,
      sendObserver: (address, port, data) {
        sent.add((address: address, port: port, data: data));
      },
    );
    final reply = peerFromIdentity(remote).toJson()..['discovery_reply'] = true;

    await service.handleDatagramForTest(
      utf8.encode(jsonEncode(reply)),
      InternetAddress('192.168.1.52'),
      listenPort: 45880,
    );

    expect(await localDb.getDevice(remote.deviceId), isNotNull);
    expect(sent, isEmpty);
  });
}
