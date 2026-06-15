import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/core/peer_status.dart';
import 'package:localchat/data/app_database.dart';

void main() {
  test('peer is online only within the freshness window', () {
    final now = DateTime.utc(2026, 6, 15, 10);
    final online = _device(lastSeen: now.subtract(const Duration(seconds: 4)));
    final offline = _device(
      lastSeen: now.subtract(peerOnlineWindow + const Duration(seconds: 1)),
    );
    final neverSeen = _device(neverSeen: true);

    expect(isPeerOnline(online, now: now), isTrue);
    expect(isPeerOnline(offline, now: now), isFalse);
    expect(isPeerOnline(neverSeen, now: now), isFalse);
    expect(peerStatusLabel(online, now: now), '在线');
    expect(peerStatusLabel(offline, now: now), '离线，等待重新上线');
  });

  test(
    'conversation rename persists independently from device display name',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final device = _device();
      await db.upsertDiscoveredDevice(
        id: device.id,
        displayName: device.displayName,
        platform: device.platform,
        host: device.host!,
        port: device.port!,
        signingPublicKey: device.signingPublicKey,
        exchangePublicKey: device.exchangePublicKey,
        fingerprint: device.fingerprint,
      );
      await db.trustDevice(
        id: device.id,
        displayName: device.displayName,
        platform: device.platform,
        host: device.host!,
        port: device.port!,
        signingPublicKey: device.signingPublicKey,
        exchangePublicKey: device.exchangePublicKey,
        fingerprint: device.fingerprint,
      );

      final conversation = await db.ensureConversation(device);
      await db.renameConversation(conversation.id, '客厅电脑');

      final renamed = await db.getConversationForDevice(device.id);
      final storedDevice = await db.getDevice(device.id);
      expect(renamed!.title, '客厅电脑');
      expect(storedDevice!.displayName, 'Office PC');
    },
  );

  test('endpoint updates and offline marker support reconnect flow', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final device = _device(lastSeen: DateTime.utc(2026));
    await db.trustDevice(
      id: device.id,
      displayName: device.displayName,
      platform: device.platform,
      host: device.host!,
      port: device.port!,
      signingPublicKey: device.signingPublicKey,
      exchangePublicKey: device.exchangePublicKey,
      fingerprint: device.fingerprint,
    );

    await db.markDeviceOffline(device.id);
    expect((await db.getDevice(device.id))!.lastSeen, isNull);

    await db.updateDeviceEndpoint(
      id: device.id,
      host: '192.168.1.99',
      port: 50123,
    );
    final updated = await db.getDevice(device.id);
    expect(updated!.host, '192.168.1.99');
    expect(updated.port, 50123);
    expect(updated.lastSeen, isNotNull);
  });
}

Device _device({DateTime? lastSeen, bool neverSeen = false}) {
  return Device(
    id: 'device-1',
    displayName: 'Office PC',
    platform: 'windows',
    host: '192.168.1.20',
    port: 40123,
    signingPublicKey: 'signing',
    exchangePublicKey: 'exchange',
    fingerprint: 'abcdef0123456789',
    trusted: true,
    lastSeen: neverSeen ? null : lastSeen ?? DateTime.now(),
    createdAt: DateTime.utc(2026),
  );
}
