import 'dart:io';

import 'package:flutter/services.dart';

class ClipboardImportService {
  static const _channel = MethodChannel('localchat/clipboard');

  Future<List<String>> readFilePaths() async {
    if (!(Platform.isWindows || Platform.isAndroid)) {
      return const <String>[];
    }
    final result = await _channel.invokeMethod<List<Object?>>('getFiles');
    if (result == null) return const <String>[];
    return result.whereType<String>().where((path) => path.isNotEmpty).toList();
  }
}
