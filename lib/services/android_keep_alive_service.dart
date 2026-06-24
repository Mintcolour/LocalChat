import 'dart:io';

import 'package:flutter/services.dart';

class AndroidKeepAliveService {
  const AndroidKeepAliveService();

  static const MethodChannel _channel = MethodChannel('localchat/keep_alive');

  bool get isSupported => Platform.isAndroid;

  Future<bool> start() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<bool> isRunning() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
