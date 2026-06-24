import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../services/window_service.dart';

const _autoCopyReceivedTextKey = 'auto_copy_received_text';
const _languageCodeKey = 'language_code';
const _themeModeKey = 'theme_mode';
const _trayEnabledKey = 'tray_enabled';
const _autostartEnabledKey = 'autostart_enabled';
const _notificationsEnabledKey = 'notifications_enabled';
const _notificationPreviewEnabledKey = 'notification_preview_enabled';
const _keepAliveEnabledKey = 'android_keep_alive_enabled';
const _storageRootPathKey = 'storage_root_path';

/// 设置子控制器：负责语言、外观、自动复制、托盘、开机自启偏好的持久化与原生同步。
///
/// 作为 AppCoordinator 拆分的一部分（计划 P1：AppController 职责过重）。本类只持有
/// 设置相关状态与读写逻辑；UI 通知仍由 AppController 统一广播（设置项变更通常伴随
/// 状态文案与全量刷新），避免引入多 notifier 跨模块协调的复杂度。AppController
/// 持有本实例并把对外的设置字段/方法委托到这里，公共 API 保持不变。
class SettingsController extends ChangeNotifier {
  SettingsController({required this.db, required this.windowService});

  final AppDatabase db;
  final WindowService windowService;

  bool autoCopyReceivedText = true;
  bool trayEnabled = true;
  bool autostartEnabled = false;
  bool notificationsEnabled = true;
  bool notificationPreviewEnabled = false;
  bool keepAliveEnabled = Platform.isAndroid;
  String languageCode = 'zh';
  String themeModeCode = 'system';
  String? storageRootPath;

  /// 从数据库与原生状态载入设置。
  Future<void> load() async {
    languageCode = await db.getSetting(_languageCodeKey) ?? 'zh';
    final storedThemeMode = await db.getSetting(_themeModeKey);
    themeModeCode = const {'system', 'light', 'dark'}.contains(storedThemeMode)
        ? storedThemeMode!
        : 'system';
    autoCopyReceivedText =
        await db.getSetting(_autoCopyReceivedTextKey) != 'false';
    notificationsEnabled =
        await db.getSetting(_notificationsEnabledKey) != 'false';
    notificationPreviewEnabled =
        await db.getSetting(_notificationPreviewEnabledKey) == 'true';
    final keepAliveRaw = await db.getSetting(_keepAliveEnabledKey);
    keepAliveEnabled = keepAliveRaw == null
        ? Platform.isAndroid
        : keepAliveRaw != 'false';
    final storedStorageRoot = await db.getSetting(_storageRootPathKey);
    final cleanStorageRoot = storedStorageRoot?.trim();
    storageRootPath = cleanStorageRoot == null || cleanStorageRoot.isEmpty
        ? null
        : cleanStorageRoot;
    await _loadWindowPreferences();
  }

  Future<void> setLanguageCode(String value) async {
    if (value != 'zh' && value != 'en') return;
    languageCode = value;
    await db.setSetting(_languageCodeKey, value);
  }

  Future<void> setThemeModeCode(String value) async {
    if (!const {'system', 'light', 'dark'}.contains(value)) return;
    themeModeCode = value;
    await db.setSetting(_themeModeKey, value);
  }

  Future<void> setAutoCopyReceivedText(bool value) async {
    autoCopyReceivedText = value;
    await db.setSetting(_autoCopyReceivedTextKey, value ? 'true' : 'false');
  }

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    await db.setSetting(_notificationsEnabledKey, value ? 'true' : 'false');
  }

  Future<void> setNotificationPreviewEnabled(bool value) async {
    notificationPreviewEnabled = value;
    await db.setSetting(
      _notificationPreviewEnabledKey,
      value ? 'true' : 'false',
    );
  }

  Future<void> setKeepAliveEnabled(bool value) async {
    keepAliveEnabled = value;
    await db.setSetting(_keepAliveEnabledKey, value ? 'true' : 'false');
  }

  Future<void> setStorageRootPath(String value) async {
    final cleanPath = value.trim();
    if (cleanPath.isEmpty) return;
    storageRootPath = cleanPath;
    await db.setSetting(_storageRootPathKey, cleanPath);
  }

  Future<void> resetStorageRootPath() async {
    storageRootPath = null;
    await db.setSetting(_storageRootPathKey, '');
  }

  Future<void> setTrayEnabled(bool value) async {
    trayEnabled = value;
    await db.setSetting(_trayEnabledKey, value ? 'true' : 'false');
    await windowService.setTrayEnabled(value);
  }

  Future<void> setAutostartEnabled(bool value) async {
    autostartEnabled = value;
    await db.setSetting(_autostartEnabledKey, value ? 'true' : 'false');
    await windowService.setAutostartEnabled(value);
  }

  /// 读取托盘/开机自启偏好，并与原生状态同步。仅 Windows 生效。
  Future<void> _loadWindowPreferences() async {
    if (!windowService.isSupported) return;
    final storedTray = await db.getSetting(_trayEnabledKey);
    trayEnabled = storedTray != 'false';
    final storedAutostart = await db.getSetting(_autostartEnabledKey);
    // 优先信任原生实际状态（用户可能在系统设置里改动过）。
    final nativeAutostart = await windowService.isAutostartEnabled();
    autostartEnabled = storedAutostart == 'true' || nativeAutostart;
    if (autostartEnabled != nativeAutostart) {
      await windowService.setAutostartEnabled(autostartEnabled);
    }
    await windowService.setTrayEnabled(trayEnabled);
  }
}
