import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';

void main() {
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
}
