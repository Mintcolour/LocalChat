import 'dart:io';

import 'package:flutter/services.dart';

/// 封装 Windows 原生窗口/托盘/开机自启能力（method channel: localchat/window）。
///
/// 仅 Windows 平台实例化。Android/iOS 无对应原生实现，调用为空操作。
class WindowService {
  const WindowService();

  static const _channel = MethodChannel('localchat/window');

  bool get isSupported => Platform.isWindows;

  /// 最小化到系统托盘（隐藏主窗口）。
  Future<void> minimizeToTray() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('minimizeToTray');
    } on MissingPluginException {
      // 测试或非原生 runner 环境。
    } on PlatformException {
      // 原生尚未实现时静默忽略。
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
    }
  }
}
