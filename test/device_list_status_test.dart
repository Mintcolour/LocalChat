import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';

void main() {
  testWidgets('device status badge remains visible when preview shows text', (
    tester,
  ) async {
    final controller = AppController(
      database: AppDatabase(NativeDatabase.memory()),
    );
    addTearDown(controller.dispose);
    final now = DateTime.now();
    final peer = Device(
      id: 'peer-1',
      displayName: 'Android手机-E8B4',
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
    final conversation = Conversation(
      id: 'peer:peer-1',
      peerDeviceId: peer.id,
      title: peer.displayName,
      updatedAt: now,
    );
    controller.devices = [peer];
    controller.conversations = [conversation];
    controller.lastMessages = {
      conversation.id: ChatMessage(
        id: 'message-1',
        conversationId: conversation.id,
        peerDeviceId: peer.id,
        direction: 'in',
        kind: 'text',
        body: '15264452556',
        status: 'received',
        createdAt: now,
      ),
    };

    await tester.pumpWidget(LocalChatApp(controller: controller));
    await tester.pump();

    expect(find.text('15264452556'), findsOneWidget);
    expect(find.byTooltip('在线'), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
  });
}
