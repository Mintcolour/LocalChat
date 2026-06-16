import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SavedFile {
  const SavedFile({this.path, this.uri});

  final String? path;
  final String? uri;
}

class FileStore {
  static const _downloadsChannel = MethodChannel('localchat/downloads');

  Future<Directory> receiveDirectory() async {
    if (Platform.isWindows) {
      return _downloadsDirectory();
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'LocalChat'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> createReceiveFile(String fileName) async {
    final dir = await receiveDirectory();
    return _uniqueFile(dir, fileName);
  }

  Future<SavedFile> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
  }) async {
    if (Platform.isAndroid) {
      final result = await _downloadsChannel
          .invokeMapMethod<String, Object?>('saveFile', {
            'sourcePath': sourcePath,
            'fileName': fileName,
            'mimeType': mimeType ?? 'application/octet-stream',
          });
      return SavedFile(
        path: result?['path'] as String?,
        uri: result?['uri'] as String?,
      );
    }
    final source = File(sourcePath);
    final dir = await _downloadsDirectory();
    if (p.normalize(p.dirname(source.path)).toLowerCase() ==
        p.normalize(dir.path).toLowerCase()) {
      return SavedFile(path: source.path);
    }
    final target = await _uniqueFile(dir, fileName);
    await source.copy(target.path);
    return SavedFile(path: target.path);
  }

  Future<Directory> _downloadsDirectory() async {
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        final dir = Directory(p.join(profile, 'Downloads', 'LocalChat'));
        await dir.create(recursive: true);
        return dir;
      }
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      final dir = Directory(p.join(downloads.path, 'LocalChat'));
      await dir.create(recursive: true);
      return dir;
    }
    return receiveDirectory();
  }

  Future<File> _uniqueFile(Directory dir, String fileName) async {
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var candidate = File(p.join(dir.path, safeName));
    if (!await candidate.exists()) return candidate;
    final extension = p.extension(safeName);
    final stem = p.basenameWithoutExtension(safeName);
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(dir.path, '$stem ($index)$extension'));
      index++;
    }
    return candidate;
  }
}
