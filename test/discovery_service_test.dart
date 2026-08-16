import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/network_health.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/services/discovery_service.dart';
import 'package:localchat/services/identity_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<List<int>> freeUdpPorts(int count) async {
    final sockets = <RawDatagramSocket>[];
    try {
      for (var index = 0; index < count; index++) {
        sockets.add(
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
        );
      }
      return sockets.map((socket) => socket.port).toList();
    } finally {
      for (final socket in sockets) {
        socket.close();
      }
    }
  }

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

  test('reply targets the source discovery port', () async {
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
      InternetAddress('192.168.1.53'),
      listenPort: 45880,
      sourcePort: 45874,
    );

    expect(sent.single.port, 45874);
  });

  test('falls back when the preferred discovery port cannot bind', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final identityService = IdentityService(db);
    await identityService.load();
    final ports = await freeUdpPorts(2);
    final firstPort = ports[0];
    final fallbackPort = ports[1];
    final service = DiscoveryService(
      db,
      identityService,
      candidatePorts: [firstPort, fallbackPort],
      interfaceLoader: () async => const [],
      socketBinder: (address, port) {
        if (port == firstPort) {
          throw const SocketException(
            'Permission denied',
            osError: OSError('Permission denied', 10013),
          );
        }
        return RawDatagramSocket.bind(address, port, reuseAddress: true);
      },
    );
    addTearDown(service.stop);

    final health = await service.start(listenPort: 40123);

    expect(health.availability, DiscoveryAvailability.degraded);
    expect(health.boundPort, fallbackPort);
    expect(health.bindFailures.single.errorCode, 10013);
  });

  test(
    'all bind failures leave discovery unavailable without throwing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final identityService = IdentityService(db);
      await identityService.load();
      final service = DiscoveryService(
        db,
        identityService,
        candidatePorts: const [45871, 45872],
        interfaceLoader: () async => const [],
        socketBinder: (address, port) {
          throw const SocketException(
            'Permission denied',
            osError: OSError('Permission denied', 10013),
          );
        },
      );

      final health = await service.start(listenPort: 40123);

      expect(health.availability, DiscoveryAvailability.unavailable);
      expect(health.boundPort, isNull);
      expect(health.bindFailures, hasLength(2));
    },
  );

  test('announcement targets every compatible discovery port', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final identityService = IdentityService(db);
    await identityService.load();
    final ports = await freeUdpPorts(2);
    final firstPort = ports[0];
    final secondPort = ports[1];
    final sentPorts = <int>[];
    final service = DiscoveryService(
      db,
      identityService,
      candidatePorts: [firstPort, secondPort],
      interfaceLoader: () async => const [],
      sendObserver: (address, port, data) => sentPorts.add(port),
    );
    addTearDown(service.stop);
    await service.start(listenPort: 40123);
    sentPorts.clear();

    await service.announce();

    expect(sentPorts.toSet(), {firstPort, secondPort});
  });
}
