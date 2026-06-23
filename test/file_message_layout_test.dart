import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';

void main() {
  testWidgets(
    'long file names wrap above actions and failed sends show retry',
    (tester) async {
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
        id: 'peer-1',
        displayName: 'Phone',
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
      const longName =
          'app-arm64-v8a-release-with-a-very-long-descriptive-file-name.apk';
      final message = ChatMessage(
        id: 'message-1',
        conversationId: 'peer:peer-1',
        peerDeviceId: peer.id,
        direction: 'out',
        kind: 'file',
        fileName: longName,
        filePath: r'C:\temp\app.apk',
        fileSize: 22000000,
        mimeType: 'application/vnd.android.package-archive',
        status: 'failed',
        transferId: 'transfer-1',
        createdAt: now,
      );
      final transfer = Transfer(
        id: 'transfer-1',
        peerDeviceId: peer.id,
        direction: 'out',
        fileName: longName,
        filePath: message.filePath,
        fileSize: message.fileSize!,
        mimeType: message.mimeType,
        status: 'failed',
        receivedBytes: 0,
        totalChunks: 1,
        createdAt: now,
        updatedAt: now,
      );
      controller.devices = [peer];
      controller.selectedDevice = peer;
      controller.messages = [message];
      controller.transfersById = {transfer.id: transfer};

      await tester.pumpWidget(LocalChatApp(controller: controller));
      await tester.pump();

      final nameFinder = find.text(longName);
      final retryFinder = find.byIcon(Icons.refresh);
      final openFinder = find.byIcon(Icons.open_in_new);
      expect(nameFinder, findsOneWidget);
      expect(retryFinder, findsOneWidget);
      final onPrimary = Theme.of(
        tester.element(nameFinder),
      ).colorScheme.onPrimary;
      expect(tester.widget<Text>(nameFinder).style?.color, onPrimary);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.open_in_new),
            )
            .color,
        onPrimary,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(openFinder).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(nameFinder).dy),
      );
    },
  );
}
