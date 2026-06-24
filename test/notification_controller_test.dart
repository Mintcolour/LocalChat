import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/notification_event.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/services/notification_service.dart';

class FakeNotificationService extends NotificationService {
  final messageEvents = <AppNotificationEvent>[];
  final previewFlags = <bool>[];
  final pairRequests = <PendingPairRequest>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissionIfNeeded() async => true;

  @override
  Future<void> showMessageNotification(
    AppNotificationEvent event, {
    required bool includePreview,
  }) async {
    messageEvents.add(event);
    previewFlags.add(includePreview);
  }

  @override
  Future<void> showPairRequestNotification(
    PendingPairRequest request, {
    required String title,
    required String body,
  }) async {
    pairRequests.add(request);
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'message notifications are suppressed in foreground and shown in background',
    () async {
      final fakeNotifications = FakeNotificationService();
      final controller = AppController(
        database: AppDatabase(NativeDatabase.memory()),
        notificationService: fakeNotifications,
      );
      addTearDown(controller.dispose);
      final event = const AppNotificationEvent(
        type: AppNotificationType.message,
        title: 'Phone',
        privateBody: '收到一条新消息',
        previewBody: 'hello',
        deviceId: 'peer-1',
        conversationId: 'peer:peer-1',
      );

      controller.setAppForeground(true);
      await controller.handleNotificationEvent(event);
      expect(fakeNotifications.messageEvents, isEmpty);

      controller.setAppForeground(false);
      await controller.handleNotificationEvent(event);
      expect(fakeNotifications.messageEvents, [event]);
      expect(fakeNotifications.previewFlags, [false]);

      controller.settings.notificationPreviewEnabled = true;
      await controller.handleNotificationEvent(event);
      expect(fakeNotifications.messageEvents, [event, event]);
      expect(fakeNotifications.previewFlags, [false, true]);
    },
  );

  test('notification payload selects the target device conversation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final controller = AppController(
      database: db,
      notificationService: FakeNotificationService(),
    );
    addTearDown(controller.dispose);
    await db.upsertDiscoveredDevice(
      id: 'peer-1',
      displayName: 'Phone',
      platform: 'android',
      host: '192.168.1.23',
      port: 40123,
      signingPublicKey: 'signing-key',
      exchangePublicKey: 'exchange-key',
      fingerprint: 'fingerprint',
      avatarSeed: 'seed',
      avatarColor: '#2563EB',
    );
    final payload = const AppNotificationEvent(
      type: AppNotificationType.message,
      title: 'Phone',
      privateBody: '收到一条新消息',
      deviceId: 'peer-1',
      conversationId: 'peer:peer-1',
    ).payload;

    await controller.handleNotificationPayload(payload);

    expect(controller.selectedDevice?.id, 'peer-1');
    expect(controller.selectedConversation?.peerDeviceId, 'peer-1');
  });
}
