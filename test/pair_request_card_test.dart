import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';
import 'package:localchat/models/protocol.dart';

void main() {
  testWidgets('pair request is shown inline in chat instead of a dialog', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final controller = AppController(database: db);
    addTearDown(controller.dispose);
    final now = DateTime.now();
    await db.upsertDiscoveredDevice(
      id: 'peer-1',
      displayName: 'Galaxy S24',
      platform: 'android',
      host: '192.168.1.23',
      port: 40123,
      signingPublicKey: 'signing-key',
      exchangePublicKey: 'exchange-key',
      fingerprint: 'fingerprint-1234567890',
      avatarSeed: 'seed',
      avatarColor: '#2563EB',
    );
    final peer = (await db.getDevice('peer-1'))!;
    controller.devices = [peer];
    controller.selectedDevice = peer;
    controller.selectedConversation = await db.ensureConversation(peer);
    controller.pendingPairRequests.add(
      PendingPairRequest(
        id: 'request-1',
        deviceId: peer.id,
        displayName: peer.displayName,
        platform: peer.platform,
        host: peer.host ?? '',
        port: peer.port ?? 0,
        signingPublicKey: peer.signingPublicKey,
        exchangePublicKey: peer.exchangePublicKey,
        fingerprint: peer.fingerprint,
        avatarSeed: peer.avatarSeed,
        avatarColor: peer.avatarColor,
        code: '492817',
        createdAt: now,
      ),
    );

    await tester.pumpWidget(LocalChatApp(controller: controller));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(controller.text.securePairRequest), findsOneWidget);
    expect(find.text('492 817'), findsOneWidget);
    expect(
      find.text(controller.text.firstConnectionConfirmCode),
      findsOneWidget,
    );

    await tester.tap(find.text(controller.text.allow));
    await tester.pumpAndSettle();

    expect(find.text(controller.text.securePairRequest), findsNothing);
    expect(
      find.text(controller.text.trustedChannelEstablished),
      findsOneWidget,
    );
  });
}
