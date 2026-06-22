import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/app/settings_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/window_service.dart';

class _NoopWindowService extends WindowService {
  const _NoopWindowService();
  @override
  bool get isSupported => false;
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

    expect(settings.languageCode, 'en');
    expect(settings.themeModeCode, 'dark');
    expect(settings.autoCopyReceivedText, isFalse);

    // 重新载入应从数据库恢复。
    final reloaded = SettingsController(
      db: db,
      windowService: const _NoopWindowService(),
    );
    await reloaded.load();
    expect(reloaded.languageCode, 'en');
    expect(reloaded.themeModeCode, 'dark');
    expect(reloaded.autoCopyReceivedText, isFalse);
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
