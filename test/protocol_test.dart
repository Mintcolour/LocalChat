import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/core/formatters.dart';
import 'package:localchat/models/protocol.dart';

void main() {
  test('discovery packet round trips', () {
    final peer = DiscoveredPeer(
      deviceId: 'device-1',
      displayName: 'Office PC',
      platform: 'windows',
      host: '',
      port: 40123,
      signingPublicKey: 'signing',
      exchangePublicKey: 'exchange',
      fingerprint: 'abcdef0123456789',
      avatarSeed: 'abcdef0123456789',
      avatarColor: '#2563EB',
      lastSeen: DateTime.utc(2026),
    );

    final parsed = DiscoveredPeer.fromDatagram(
      utf8.encode(jsonEncode(peer.toJson())),
      '192.168.1.20',
    );

    expect(parsed, isNotNull);
    expect(parsed!.deviceId, 'device-1');
    expect(parsed.host, '192.168.1.20');
    expect(parsed.port, 40123);
  });

  test('pairing code is always six digits', () {
    for (var i = 0; i < 100; i++) {
      expect(randomCode(), matches(RegExp(r'^\d{6}$')));
    }
  });

  test('pair SAS code is symmetric, deterministic and key-dependent', () {
    final fpA = 'a' * 64;
    final fpB = 'b' * 64;
    // 双方各自计算结果一致，与角色无关。
    expect(pairSasCode(fpA, fpB), pairSasCode(fpB, fpA));
    // 确定性：同一对指纹反复派生得到同一数字。
    expect(pairSasCode(fpA, fpB), pairSasCode(fpA, fpB));
    expect(pairSasCode(fpA, fpB), matches(RegExp(r'^\d{6}$')));
    // 中间人持有不同密钥 → 双方屏幕必然显示不同校验码。
    final fpMitm = 'c' * 64;
    expect(pairSasCode(fpA, fpB), isNot(pairSasCode(fpA, fpMitm)));
    expect(pairSasCode(fpA, fpB), isNot(pairSasCode(fpMitm, fpB)));
  });

  test('message timestamp uses compact local chat format', () {
    expect(
      formatMessageTimestamp(DateTime(2026, 6, 16, 9, 5, 3)),
      '26/06/16 09:05:03',
    );
    expect(messageStatusLabel('received'), '已接收');
  });

  test('secure envelope preserves signed payload fields', () {
    final envelope = SecureEnvelope(
      senderDeviceId: 'a',
      recipientDeviceId: 'b',
      timestamp: 123,
      nonce: 'nonce',
      cipherNonce: 'cn',
      cipherText: 'ct',
      cipherMac: 'cm',
      signature: 'sig',
    );

    expect(envelope.toSignedPayload().containsKey('signature'), isFalse);
    expect(SecureEnvelope.fromJson(envelope.toJson()).signature, 'sig');
  });

  test('folder capability is advertised and round trips through discovery', () {
    final peer = DiscoveredPeer(
      deviceId: 'device-1',
      displayName: 'Office PC',
      platform: 'windows',
      host: '',
      port: 40123,
      signingPublicKey: 'signing',
      exchangePublicKey: 'exchange',
      fingerprint: 'abcdef0123456789',
      avatarSeed: 'abcdef0123456789',
      avatarColor: '#2563EB',
      lastSeen: DateTime.utc(2026),
    );
    expect(peer.capabilities, contains(folderCapability));

    final parsed = DiscoveredPeer.fromDatagram(
      utf8.encode(jsonEncode(peer.toJson())),
      '192.168.1.20',
    );
    expect(parsed, isNotNull);
    expect(parsed!.capabilities, contains(folderCapability));
  });
}
