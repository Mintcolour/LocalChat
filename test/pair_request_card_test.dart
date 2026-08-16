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

  testWidgets('SAS pair request requires entering the derived code', (
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
        // 明文传输的 code 可能被中间人篡改，展示与比对都必须用派生码。
        code: '000000',
        createdAt: now,
        sasCode: '492817',
      ),
    );

    // 卡片含输入框后更高，放大测试视口避免聊天栏溢出。
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(LocalChatApp(controller: controller));
    await tester.pump();

    // 展示派生码而非明文 code。
    expect(find.text('492 817'), findsOneWidget);
    expect(find.text('000 000'), findsNothing);
    expect(find.text(controller.text.pairSasPrompt), findsOneWidget);

    FilledButton allowButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, controller.text.allow),
        );
    Finder codeField() => find.widgetWithText(
          TextField,
          controller.text.pairCodeInputHint,
        );

    // 未输入时允许按钮禁用。
    expect(allowButton().onPressed, isNull);

    // 输入错误校验码仍禁用。
    await tester.enterText(codeField(), '123456');
    await tester.pump();
    expect(allowButton().onPressed, isNull);

    // 输入正确派生码后才能允许。
    await tester.enterText(codeField(), '492817');
    await tester.pump();
    expect(allowButton().onPressed, isNotNull);
    await tester.tap(find.text(controller.text.allow));
    await tester.pumpAndSettle();

    expect(find.text(controller.text.securePairRequest), findsNothing);
    expect(
      find.text(controller.text.trustedChannelEstablished),
      findsOneWidget,
    );
  });
}
