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

  /// 将设备显示名清洗为可用作目录名的会话文件夹名，空名回退到设备 ID。
  static String conversationFolder(String displayName, String deviceId) {
    final cleaned = displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isEmpty) {
      return deviceId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    return cleaned;
  }

  /// 按年月生成 `yy/mm` 相对子路径。
  static String yearMonthSubpath(DateTime at) {
    final yy = (at.year % 100).toString().padLeft(2, '0');
    final mm = at.month.toString().padLeft(2, '0');
    return p.join(yy, mm);
  }

  /// 将文件夹递归传输的相对路径清洗为安全的目录段列表。
  /// 输入按 POSIX `/` 拆分，逐段清洗非法字符，剔除 `.`、`..`、空段，防止目录穿越。
  static List<String> sanitizeRelativeDirs(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return const [];
    final segments = <String>[];
    for (final raw in relativePath.split('/')) {
      final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') continue;
      segments.add(cleaned);
    }
    // 丢弃末尾的文件名段：相对路径形如 "root/sub/file.txt"，
    // 目录段只取到倒数第二段，文件名由调用方单独传入 fileName。
    if (segments.isNotEmpty) {
      segments.removeLast();
    }
    return segments;
  }

  Future<Directory> receiveDirectory() async {
    if (Platform.isWindows) {
      return _downloadsDirectory();
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'LocalChat'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> createReceiveFile(
    String fileName, {
    required String conversationFolder,
    required DateTime at,
    String? relativePath,
  }) async {
    final base = await receiveDirectory();
    final dirSegments = <String>[
      base.path,
      conversationFolder,
      yearMonthSubpath(at),
      ...sanitizeRelativeDirs(relativePath),
    ];
    final dir = Directory(p.joinAll(dirSegments));
    await dir.create(recursive: true);
    return _uniqueFile(dir, fileName);
  }

  Future<SavedFile> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    required String conversationFolder,
    required DateTime at,
    String? relativePath,
  }) async {
    final relativeDirs = sanitizeRelativeDirs(relativePath);
    final subpath = p.joinAll([
      conversationFolder,
      yearMonthSubpath(at),
      ...relativeDirs,
    ]);
    if (Platform.isAndroid) {
      final result = await _downloadsChannel
          .invokeMapMethod<String, Object?>('saveFile', {
            'sourcePath': sourcePath,
            'fileName': fileName,
            'mimeType': mimeType ?? 'application/octet-stream',
            'subpath': subpath,
          });
      return SavedFile(
        path: result?['path'] as String?,
        uri: result?['uri'] as String?,
      );
    }
    final source = File(sourcePath);
    final base = await _downloadsDirectory();
    final dir = Directory(p.join(base.path, subpath));
    await dir.create(recursive: true);
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
