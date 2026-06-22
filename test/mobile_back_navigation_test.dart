import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';

void main() {
  testWidgets('dark theme is applied from the controller preference', (
    tester,
  ) async {
    final controller = AppController(
      database: AppDatabase(NativeDatabase.memory()),
    );
    addTearDown(controller.dispose);
    controller.themeModeCode = 'dark';

    await tester.pumpWidget(LocalChatApp(controller: controller));

    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('system back returns from a mobile chat to the device list', (
    tester,
  ) async {
    final controller = AppController(
      database: AppDatabase(NativeDatabase.memory()),
    );
    addTearDown(controller.dispose);
    final peer = Device(
      id: 'peer-1',
      displayName: 'Android phone',
      platform: 'android',
      signingPublicKey: 'signing-key',
      exchangePublicKey: 'exchange-key',
      fingerprint: 'fingerprint',
      avatarSeed: 'seed',
      avatarColor: '#2563EB',
      trusted: true,
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
      endpointSource: 'auto',
    );
    controller.devices = [peer];
    controller.selectedDevice = peer;

    await tester.pumpWidget(
      MaterialApp(home: LocalChatHome(controller: controller)),
    );
    expect(find.text('Android phone'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(controller.selectedDevice, isNull);
    expect(find.textContaining('已信任设备'), findsOneWidget);
  });

  testWidgets('opening a mobile conversation animates the chat into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController(
      database: AppDatabase(NativeDatabase.memory()),
    );
    addTearDown(controller.dispose);
    final now = DateTime(2026, 6, 22, 10);
    final peer = Device(
      id: 'peer-animated',
      displayName: 'Animated phone',
      platform: 'android',
      signingPublicKey: 'signing-key',
      exchangePublicKey: 'exchange-key',
      fingerprint: 'fingerprint',
      avatarSeed: 'seed',
      avatarColor: '#2563EB',
      trusted: true,
      lastSeen: now,
      createdAt: now,
      endpointSource: 'auto',
    );
    controller.devices = [peer];

    await tester.pumpWidget(LocalChatApp(controller: controller));
    await tester.tap(find.text('Animated phone'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile-page-transition')),
      findsOneWidget,
    );
    final conversation = find.byKey(
      const ValueKey('mobile-conversation-peer-animated'),
    );
    expect(conversation, findsOneWidget);
    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(of: conversation, matching: find.byType(FadeTransition)),
    );
    expect(fades.any((fade) => fade.opacity.value < 1), isTrue);

    await tester.pumpAndSettle();
    expect(find.text('Animated phone'), findsOneWidget);
  });
}
