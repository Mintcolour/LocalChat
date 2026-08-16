import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/core/formatters.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/security_service.dart';

Device _peerDevice(LocalIdentity local) => Device(
      id: local.deviceId,
      displayName: local.displayName,
      platform: local.platform,
      host: '127.0.0.1',
      port: 12345,
      signingPublicKey: local.signingPublicKey,
      exchangePublicKey: local.exchangePublicKey,
      fingerprint: local.fingerprint,
      avatarSeed: local.avatarSeed,
      avatarColor: local.avatarColor,
      trusted: true,
      endpointSource: 'auto',
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('nonce 登记必须发生在验签之后', () {
    late AppDatabase dbA;
    late AppDatabase dbB;
    late SecurityService securityA;
    late SecurityService securityB;
    late LocalIdentity localA;
    late LocalIdentity localB;
    late Device peerA;
    late Device peerB;

    setUp(() async {
      dbA = AppDatabase(NativeDatabase.memory());
      dbB = AppDatabase(NativeDatabase.memory());
      final identityA = IdentityService(dbA);
      final identityB = IdentityService(dbB);
      securityA = SecurityService(identityA);
      securityB = SecurityService(identityB);
      localA = await identityA.load();
      localB = await identityB.load();
      peerA = _peerDevice(localA);
      peerB = _peerDevice(localB);
    });

    tearDown(() async {
      await dbA.close();
      await dbB.close();
    });

    test('验签失败的信封不占用 nonce 槽位', () async {
      final sealed = await securityA.seal(peerB, {
        'kind': 'text',
        'text': 'hi',
      });
      // 攻击者伪造携带同一 nonce、签名无效的信封。
      final tampered = {...sealed, 'signature': b64(List<int>.filled(64, 1))};
      await expectLater(
        securityB.open(peerA, tampered),
        throwsA(isA<FormatException>()),
      );
      // 同一 nonce 的合法信封仍可正常打开：证明垃圾信封没有污染缓存。
      final opened = await securityB.open(peerA, sealed);
      expect(opened['text'], 'hi');
    });

    test('合法信封的重放仍被拒绝', () async {
      final sealed = await securityA.seal(peerB, {
        'kind': 'text',
        'text': 'hi',
      });
      await securityB.open(peerA, sealed);
      await expectLater(
        securityB.open(peerA, sealed),
        throwsA(isA<FormatException>()),
      );
    });

    test('验签失败的流鉴权头不占用 nonce 槽位', () async {
      final headers = await securityA.streamAuthHeaders(peerB, 'transfer-1');
      final timestamp = int.parse(headers['x-localchat-timestamp']!);
      final nonce = headers['x-localchat-nonce']!;
      await expectLater(
        securityB.verifyStreamAuth(
          peer: peerA,
          recipientDeviceId: localB.deviceId,
          transferId: 'transfer-1',
          timestamp: timestamp,
          nonce: nonce,
          signature: b64(List<int>.filled(64, 2)),
        ),
        throwsA(isA<FormatException>()),
      );
      // 同一 nonce 的合法签名应通过验证。
      await securityB.verifyStreamAuth(
        peer: peerA,
        recipientDeviceId: localB.deviceId,
        transferId: 'transfer-1',
        timestamp: timestamp,
        nonce: nonce,
        signature: headers['x-localchat-signature']!,
      );
    });

    test('合法流鉴权头的重放仍被拒绝', () async {
      final headers = await securityA.streamAuthHeaders(peerB, 'transfer-2');
      Future<void> verify() => securityB.verifyStreamAuth(
            peer: peerA,
            recipientDeviceId: localB.deviceId,
            transferId: 'transfer-2',
            timestamp: int.parse(headers['x-localchat-timestamp']!),
            nonce: headers['x-localchat-nonce']!,
            signature: headers['x-localchat-signature']!,
          );
      await verify();
      await expectLater(verify(), throwsA(isA<FormatException>()));
    });
  });
}
