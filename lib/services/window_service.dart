import 'dart:io';

import 'package:flutter/services.dart';

import '../models/quick_send_device.dart';

typedef QuickDropFilesHandler =
    Future<void> Function(String deviceId, List<String> paths);

/// 封装 Windows 原生窗口/托盘/开机自启能力（method channel: localchat/window）。
///
/// 仅 Windows 平台实例化。Android/iOS 无对应原生实现，调用为空操作。
class WindowService {
  const WindowService();

  static const _channel = MethodChannel('localchat/window');

  bool get isSupported => Platform.isWindows;

  /// 注册 Windows 快捷拖拽投递回调。原生层只负责采集目标设备与路径；
  /// 实际信任/在线校验和发送仍由 Dart 控制器完成。
  Future<void> setQuickDropFilesHandler(
    QuickDropFilesHandler? handler, {
    void Function()? onHide,
  }) async {
    if (!isSupported) return;
    try {
      if (handler == null) {
        _channel.setMethodCallHandler(null);
        return;
      }
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'quickDropFiles') {
          final args = call.arguments;
          if (args is! Map) return null;
          final deviceId = args['deviceId'];
          final rawPaths = args['paths'];
          if (deviceId is! String || rawPaths is! List) return null;
          final paths = rawPaths.whereType<String>().toList();
          await handler(deviceId, paths);
        } else if (call.method == 'quickDropShelfHidden') {
          if (onHide != null) {
            onHide();
          }
        }
        return null;
      });
    } catch (_) {
      // Unit tests may run on Windows without a Flutter binary messenger.
    }
  }

  /// 最小化到系统托盘（隐藏主窗口）。
  Future<void> minimizeToTray() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('minimizeToTray');
    } on MissingPluginException {
      // 测试或非原生 runner 环境。
    } on PlatformException {
      // 原生尚未实现时静默忽略。
    } catch (_) {
      // ignore
    }
  }

  /// 显示并前置主窗口（托盘双击/菜单触发）。
  Future<void> show() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('show');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// 查询 Windows 主窗口是否可见且位于前台。
  Future<bool?> isForeground() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<bool>('isForeground');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 真正退出应用（移除托盘图标并结束进程）。
  Future<void> quit() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('quit');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// 查询开机自启是否已启用。
  Future<bool> isAutostartEnabled() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAutostartEnabled');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 设置开机自启开关。
  Future<void> setAutostartEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setAutostartEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// 设置托盘模式开关：true 时关窗隐藏到托盘并显示图标；false 时关窗退出。
  Future<void> setTrayEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setTrayEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// 设置桌面底部快捷拖拽发送开关。
  Future<void> setQuickSendEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setQuickSendEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// 设置贴边是否自动隐藏成条形。
  Future<void> setQuickSendAutoHide(bool autoHide) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setQuickSendAutoHide', {
        'autoHide': autoHide,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// 同步原生快捷拖拽浮层要展示的在线可信设备。
  Future<void> updateQuickSendDevices(List<QuickSendDeviceView> devices) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('updateQuickSendDevices', {
        'devices': devices.map((device) => device.toNativeMap()).toList(),
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }
}
