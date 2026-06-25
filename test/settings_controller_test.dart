import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/app/settings_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/android_keep_alive_service.dart';
import 'package:localchat/services/window_service.dart';

class _NoopWindowService extends WindowService {
  const _NoopWindowService();
  @override
  bool get isSupported => false;
}

class _FakeKeepAliveService extends AndroidKeepAliveService {
  _FakeKeepAliveService();

  int startCalls = 0;
  int stopCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> start() async {
    startCalls++;
    return true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  test('SettingsController persists and reloads preferences', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsController(
      db: db,
      windowService: const _NoopWindowService(),
    );

    await settings.setLanguageCode('en');
    await settings.setThemeModeCode('dark');
    await settings.setAutoCopyReceivedText(false);
    await settings.setNotificationsEnabled(false);
    await settings.setNotificationPreviewEnabled(true);
    await settings.setKeepAliveEnabled(true);
    await settings.setQuickSendEnabled(true);
    await settings.setQuickSendAutoHide(false);
    await settings.setStorageRootPath(r'C:\LocalChatStore');

    expect(settings.languageCode, 'en');
    expect(settings.themeModeCode, 'dark');
    expect(settings.autoCopyReceivedText, isFalse);
    expect(settings.notificationsEnabled, isFalse);
    expect(settings.notificationPreviewEnabled, isTrue);
    expect(settings.keepAliveEnabled, isTrue);
    expect(settings.quickSendEnabled, isTrue);
    expect(settings.quickSendAutoHide, isFalse);
    expect(settings.storageRootPath, r'C:\LocalChatStore');

    // 重新载入应从数据库恢复。
    final reloaded = SettingsController(
      db: db,
      windowService: const _NoopWindowService(),
    );
    await reloaded.load();
    expect(reloaded.languageCode, 'en');
    expect(reloaded.themeModeCode, 'dark');
    expect(reloaded.autoCopyReceivedText, isFalse);
    expect(reloaded.notificationsEnabled, isFalse);
    expect(reloaded.notificationPreviewEnabled, isTrue);
    expect(reloaded.keepAliveEnabled, isTrue);
    expect(reloaded.quickSendEnabled, isTrue);
    expect(reloaded.quickSendAutoHide, isFalse);
    expect(reloaded.storageRootPath, r'C:\LocalChatStore');

    await reloaded.resetStorageRootPath();
    expect(reloaded.storageRootPath, isNull);
    expect(await db.getSetting('storage_root_path'), '');
  });

  test('AppController delegates settings getters and setters', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = AppController(database: db);
    addTearDown(controller.dispose);

    // 通过 AppController 对外 API 改外观（委托到 SettingsController）。
    await controller.setThemeModeCode('dark');
    expect(controller.themeModeCode, 'dark');
    expect(await db.getSetting('theme_mode'), 'dark');

    // 直接赋值兼容旧用法（mobile_back_navigation_test 依赖）。
    controller.themeModeCode = 'light';
    expect(controller.themeModeCode, 'light');
  });

  test('AppController starts and stops Android keep-alive setting', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final keepAlive = _FakeKeepAliveService();
    final controller = AppController(database: db, keepAliveService: keepAlive);
    addTearDown(controller.dispose);

    await controller.setKeepAliveEnabled(true);
    expect(controller.keepAliveEnabled, isTrue);
    expect(keepAlive.startCalls, 1);
    expect(keepAlive.stopCalls, 0);
    expect(await db.getSetting('android_keep_alive_enabled'), 'true');

    await controller.setKeepAliveEnabled(false);
    expect(controller.keepAliveEnabled, isFalse);
    expect(keepAlive.startCalls, 1);
    expect(keepAlive.stopCalls, 1);
    expect(await db.getSetting('android_keep_alive_enabled'), 'false');
  });

  test('operation tracker gates the composer without global busy', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = AppController(database: db);
    addTearDown(controller.dispose);

    expect(controller.anyOperationActive, isFalse);
    expect(controller.isOperationActive('sendText:peer-1'), isFalse);
    // busy 仅在启动时为 true，操作状态独立于 busy。
    expect(controller.busy, isFalse);
  });
}
