import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/notification_event.dart';
import '../models/protocol.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'localchat_messages';
  static const _channelName = 'LocalChat messages';
  static const _channelDescription =
      'Incoming LocalChat messages and pairing requests';

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _permissionDenied = false;
  int _nextId = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  Stream<String> get notificationTapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    try {
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_localchat'),
        windows: WindowsInitializationSettings(
          appName: 'LocalChat',
          appUserModelId: 'com.localchat.localchat',
          guid: '9f837d52-7c52-4f3d-90fd-8e5a8b7392ad',
        ),
      );
      await _plugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      _initialized = true;
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final payload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        scheduleMicrotask(() => _tapController.add(payload));
      }
    } on MissingPluginException {
      _initialized = false;
    } on PlatformException {
      _initialized = false;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<bool> requestPermissionIfNeeded() async {
    if (!isSupported || _permissionDenied) return false;
    await initialize();
    if (!_initialized) return false;
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      _permissionDenied = granted == false;
      return granted ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showMessageNotification(
    AppNotificationEvent event, {
    required bool includePreview,
  }) async {
    await _show(
      title: event.title,
      body: event.body(includePreview: includePreview),
      payload: event.payload,
    );
  }

  Future<void> showPairRequestNotification(
    PendingPairRequest request, {
    required String title,
    required String body,
  }) async {
    await _show(
      title: title,
      body: body,
      payload: AppNotificationEvent(
        type: AppNotificationType.pairRequest,
        title: title,
        privateBody: body,
        deviceId: request.deviceId,
        requestId: request.id,
      ).payload,
    );
  }

  Future<void> _show({
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!isSupported || _permissionDenied) return;
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: _nextNotificationId(),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
          windows: WindowsNotificationDetails(
            duration: WindowsNotificationDuration.short,
          ),
        ),
      );
    } on MissingPluginException {
      _initialized = false;
    } on PlatformException {
      // 权限、系统策略或平台插件错误都不应影响 LocalChat 主流程。
    } catch (_) {
      // ignore
    }
  }

  bool get isSupported => Platform.isAndroid || Platform.isWindows;

  int _nextNotificationId() {
    _nextId = (_nextId + 1) & 0x7fffffff;
    return _nextId;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _tapController.add(payload);
  }

  void dispose() {
    _tapController.close();
  }
}
