import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/core/app_failure.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/protocol.dart';
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
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('peer identity validation', () {
    test('fingerprint derives from signing key and identity is self-consistent',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final identity = IdentityService(db);
      final local = await identity.load();

      expect(fingerprintFromSigningKey(local.signingPublicKey), local.fingerprint);
      expect(local.deviceId, local.fingerprint.substring(0, 20));

      // 自洽的三元组通过校验。
      validatePeerIdentity(
        deviceId: local.deviceId,
        signingPublicKey: local.signingPublicKey,
        fingerprint: local.fingerprint,
      );

      // 篡改指纹 → 拒绝。
      expect(
        () => validatePeerIdentity(
          deviceId: local.deviceId,
          signingPublicKey: local.signingPublicKey,
          fingerprint: 'tampered',
        ),
        throwsA(isA<PeerIdentityMismatch>()),
      );
      // 篡改 deviceId → 拒绝。
      expect(
        () => validatePeerIdentity(
          deviceId: 'wrong-device-id',
          signingPublicKey: local.signingPublicKey,
          fingerprint: local.fingerprint,
        ),
        throwsA(isA<PeerIdentityMismatch>()),
      );
      // 空值 → 拒绝。
      expect(
        () => validatePeerIdentity(
          deviceId: '',
          signingPublicKey: local.signingPublicKey,
          fingerprint: local.fingerprint,
        ),
        throwsA(isA<PeerIdentityMismatch>()),
      );
    });
  });

  group('trusted device public key pinning', () {
    test('discovery cannot overwrite pinned keys and flags identity change',
        () async {
      final dbA = AppDatabase(NativeDatabase.memory());
      addTearDown(dbA.close);
      // 真实对端身份 B。
      final dbB = AppDatabase(NativeDatabase.memory());
      addTearDown(dbB.close);
      final identityB = IdentityService(dbB);
      final localB = await identityB.load();

      final peerB = Device(
        id: localB.deviceId,
        displayName: localB.displayName,
        platform: localB.platform,
        host: '127.0.0.1',
        port: 12345,
        signingPublicKey: localB.signingPublicKey,
        exchangePublicKey: localB.exchangePublicKey,
        fingerprint: localB.fingerprint,
        avatarSeed: localB.avatarSeed,
        avatarColor: localB.avatarColor,
        trusted: true,
        endpointSource: 'auto',
        lastSeen: DateTime.now(),
        createdAt: DateTime.now(),
      );
      await dbA.trustDevice(
        id: peerB.id,
        displayName: peerB.displayName,
        platform: peerB.platform,
        host: peerB.host!,
        port: peerB.port!,
        signingPublicKey: peerB.signingPublicKey,
        exchangePublicKey: peerB.exchangePublicKey,
        fingerprint: peerB.fingerprint,
        avatarSeed: peerB.avatarSeed,
        avatarColor: peerB.avatarColor,
        capabilities: const ['text', 'files'],
      );

      // 模拟恶意/漂移的发现包：同一 deviceId 但签名公钥不同。
      await dbA.upsertDiscoveredDevice(
        id: peerB.id,
        displayName: peerB.displayName,
        platform: peerB.platform,
        host: peerB.host!,
        port: peerB.port!,
        signingPublicKey: 'attacker-signing-key',
        exchangePublicKey: peerB.exchangePublicKey,
        fingerprint: peerB.fingerprint,
        avatarSeed: peerB.avatarSeed,
        avatarColor: peerB.avatarColor,
      );

      final stored = await dbA.getDevice(peerB.id);
      expect(stored!.identityChanged, isTrue);
      // 固定的签名公钥未被覆盖。
      expect(stored.signingPublicKey, localB.signingPublicKey);
      // 能力列表被持久化。
      expect(dbA.deviceCapabilities(stored), containsAll(const ['text', 'files']));
    });

    test('send is blocked when identity has changed', () async {
      final dbA = AppDatabase(NativeDatabase.memory());
      final rootA = await Directory.systemTemp.createTemp('localchat-pinning');
      addTearDown(() async {
        await dbA.close();
        await rootA.delete(recursive: true);
      });
      final identityA = IdentityService(dbA);
      final transportA = TransportService(
        dbA,
        identityA,
        SecurityService(identityA),
        _TestFileStore(rootA),
      );
      await identityA.load();

      final dbB = AppDatabase(NativeDatabase.memory());
      addTearDown(dbB.close);
      final identityB = IdentityService(dbB);
      final localB = await identityB.load();

      await dbA.trustDevice(
        id: localB.deviceId,
        displayName: localB.displayName,
        platform: localB.platform,
        host: '127.0.0.1',
        port: 12345,
        signingPublicKey: localB.signingPublicKey,
        exchangePublicKey: localB.exchangePublicKey,
        fingerprint: localB.fingerprint,
        avatarSeed: localB.avatarSeed,
        avatarColor: localB.avatarColor,
      );
      // 触发身份变化标记。
      await dbA.upsertDiscoveredDevice(
        id: localB.deviceId,
        displayName: localB.displayName,
        platform: localB.platform,
        host: '127.0.0.1',
        port: 12345,
        signingPublicKey: 'attacker-signing-key',
        exchangePublicKey: localB.exchangePublicKey,
        fingerprint: localB.fingerprint,
        avatarSeed: localB.avatarSeed,
        avatarColor: localB.avatarColor,
      );

      final peerB = Device(
        id: localB.deviceId,
        displayName: localB.displayName,
        platform: localB.platform,
        host: '127.0.0.1',
        port: 12345,
        signingPublicKey: localB.signingPublicKey,
        exchangePublicKey: localB.exchangePublicKey,
        fingerprint: localB.fingerprint,
        avatarSeed: localB.avatarSeed,
        avatarColor: localB.avatarColor,
        trusted: true,
        endpointSource: 'auto',
        lastSeen: DateTime.now(),
        createdAt: DateTime.now(),
      );
      // 发送应被身份变化守卫拦截，抛出结构化 AppFailure。
      await expectLater(
        transportA.sendText(peerB, 'hi'),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'peer_identity_changed',
          ),
        ),
      );
    });

    test('re-pairing after trust resets the identity changed flag', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final identity = IdentityService(db);
      final local = await identity.load();
      await db.trustDevice(
        id: local.deviceId,
        displayName: local.displayName,
        platform: local.platform,
        host: '127.0.0.1',
        port: 1,
        signingPublicKey: local.signingPublicKey,
        exchangePublicKey: local.exchangePublicKey,
        fingerprint: local.fingerprint,
        avatarSeed: local.avatarSeed,
        avatarColor: local.avatarColor,
      );
      await db.upsertDiscoveredDevice(
        id: local.deviceId,
        displayName: local.displayName,
        platform: local.platform,
        host: '127.0.0.1',
        port: 1,
        signingPublicKey: 'changed',
        exchangePublicKey: local.exchangePublicKey,
        fingerprint: local.fingerprint,
        avatarSeed: local.avatarSeed,
        avatarColor: local.avatarColor,
      );
      expect((await db.getDevice(local.deviceId))!.identityChanged, isTrue);
      // 重新配对（trustDevice）清除标记并重新固定公钥。
      await db.trustDevice(
        id: local.deviceId,
        displayName: local.displayName,
        platform: local.platform,
        host: '127.0.0.1',
        port: 1,
        signingPublicKey: local.signingPublicKey,
        exchangePublicKey: local.exchangePublicKey,
        fingerprint: local.fingerprint,
        avatarSeed: local.avatarSeed,
        avatarColor: local.avatarColor,
      );
      final restored = await db.getDevice(local.deviceId);
      expect(restored!.identityChanged, isFalse);
      expect(restored.signingPublicKey, local.signingPublicKey);
    });
  });
}
