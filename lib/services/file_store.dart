import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/file_types.dart';

class SavedFile {
  const SavedFile({this.path, this.uri, this.actualFileName});

  final String? path;
  final String? uri;
  final String? actualFileName;
}

class RenamedFile extends SavedFile {
  const RenamedFile({
    required this.fileName,
    required this.mimeType,
    required this.relativePath,
    super.path,
    super.uri,
  });

  final String fileName;
  final String? mimeType;
  final String? relativePath;
}

class FileStore {
  static const _downloadsChannel = MethodChannel('localchat/downloads');

  static String conversationFolder(String displayName, String deviceId) {
    final cleaned = displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isEmpty) {
      return deviceId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    return cleaned;
  }

  static String yearMonthSubpath(DateTime at) {
    final yy = (at.year % 100).toString().padLeft(2, '0');
    final mm = at.month.toString().padLeft(2, '0');
    return p.join(yy, mm);
  }

  static List<String> sanitizeRelativeDirs(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return const [];
    final segments = <String>[];
    for (final raw in relativePath.split('/')) {
      final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') continue;
      segments.add(cleaned);
    }
    if (segments.isNotEmpty) {
      segments.removeLast();
    }
    return segments;
  }

  static String? validateFileName(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'empty';
    if (name == '.' || name == '..') return 'dot';
    if (name.length > 255) return 'too_long';
    if (RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(name)) return 'invalid';
    if (name.endsWith('.') || name.endsWith(' ')) return 'trailing';
    final stem = p.basenameWithoutExtension(name).toUpperCase();
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
      return 'reserved';
    }
    return null;
  }

  static String replaceRelativeFileName(String relativePath, String fileName) {
    final segments = relativePath.split('/');
    if (segments.isEmpty) return fileName;
    segments[segments.length - 1] = fileName;
    return segments.join('/');
  }

  static String destinationSubpath({
    required String conversationFolder,
    required DateTime at,
    required String fileName,
    String? mimeType,
    String? relativePath,
  }) {
    final category = relativePath == null
        ? fileCategoryFor(mimeType: mimeType, fileName: fileName)
        : FileCategory.others;
    return p.joinAll([
      conversationFolder,
      yearMonthSubpath(at),
      category.folderName,
      ...sanitizeRelativeDirs(relativePath),
    ]);
  }

  Future<Directory> receiveDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'LocalChat', 'incoming'));
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
    final transferDir = Directory(
      p.join(base.path, DateTime.now().microsecondsSinceEpoch.toString()),
    );
    await transferDir.create(recursive: true);
    return _uniqueFile(transferDir, fileName);
  }

  Future<File> createManagedEditedFile(
    String sourcePath, {
    required String extension,
  }) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(
      p.join(
        base.path,
        'LocalChat',
        'edited',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await dir.create(recursive: true);
    final sourceName = p.basenameWithoutExtension(sourcePath);
    return File(p.join(dir.path, '$sourceName$extension'));
  }

  Future<void> deleteManagedEditedFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } catch (_) {
      // Best-effort cleanup for cancelled drafts.
    }
  }

  Future<void> deleteManagedEditedFiles(Iterable<String?> paths) async {
    final base = await getApplicationSupportDirectory();
    final root = p.normalize(p.join(base.path, 'LocalChat', 'edited'));
    for (final value in paths.whereType<String>()) {
      final path = p.normalize(value);
      if (p.isWithin(root, path)) {
        await deleteManagedEditedFile(path);
      }
    }
  }

  Future<void> clearManagedEditedFiles() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'LocalChat', 'edited'));
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // History clearing must not fail because a preview file is locked.
    }
  }

  Future<void> deleteIncomingFiles(Iterable<String?> paths) async {
    final root = p.normalize((await receiveDirectory()).path);
    for (final value in paths.whereType<String>()) {
      final path = p.normalize(value);
      if (!p.isWithin(root, path)) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        final parent = file.parent;
        if (await parent.exists() && await parent.list().isEmpty) {
          await parent.delete();
        }
      } catch (_) {
        // Best-effort cleanup for app-private receive previews.
      }
    }
  }

  Future<void> clearIncomingFiles() async {
    final dir = await receiveDirectory();
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // A file can still be open by an in-progress transfer.
    }
  }

  Future<SavedFile> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    required String conversationFolder,
    required DateTime at,
    String? relativePath,
    bool moveSource = false,
  }) async {
    final subpath = destinationSubpath(
      conversationFolder: conversationFolder,
      at: at,
      fileName: fileName,
      mimeType: mimeType,
      relativePath: relativePath,
    );
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
        actualFileName: result?['fileName'] as String?,
      );
    }
    final source = File(sourcePath);
    final base = await _downloadsDirectory();
    final dir = Directory(p.join(base.path, subpath));
    await dir.create(recursive: true);
    if (p.normalize(p.dirname(source.path)).toLowerCase() ==
        p.normalize(dir.path).toLowerCase()) {
      return SavedFile(
        path: source.path,
        actualFileName: p.basename(source.path),
      );
    }
    final target = await _uniqueFile(dir, fileName);
    if (moveSource) {
      try {
        await source.rename(target.path);
      } on FileSystemException {
        await source.copy(target.path);
        await source.delete();
      }
    } else {
      await source.copy(target.path);
    }
    return SavedFile(
      path: target.path,
      actualFileName: p.basename(target.path),
    );
  }

  Future<RenamedFile> renameSavedFile({
    required String currentPath,
    String? currentUri,
    required String newFileName,
    required String conversationFolder,
    required DateTime at,
    String? relativePath,
  }) async {
    final validation = validateFileName(newFileName);
    if (validation != null) {
      throw FormatException('invalid_file_name:$validation');
    }
    final cleanName = newFileName.trim();
    final newMimeType = lookupMimeType(cleanName);
    final newRelativePath = relativePath == null
        ? null
        : replaceRelativeFileName(relativePath, cleanName);
    final subpath = destinationSubpath(
      conversationFolder: conversationFolder,
      at: at,
      fileName: cleanName,
      mimeType: newMimeType,
      relativePath: newRelativePath,
    );

    if (Platform.isAndroid) {
      final result = await _downloadsChannel
          .invokeMapMethod<String, Object?>('renameFile', {
            'currentPath': currentPath,
            'currentUri': currentUri,
            'fileName': cleanName,
            'mimeType': newMimeType ?? 'application/octet-stream',
            'subpath': subpath,
          });
      final actualName = result?['fileName'] as String? ?? cleanName;
      return RenamedFile(
        fileName: actualName,
        mimeType: newMimeType,
        relativePath: newRelativePath == null
            ? null
            : replaceRelativeFileName(newRelativePath, actualName),
        path: result?['path'] as String?,
        uri: result?['uri'] as String?,
      );
    }

    final source = File(currentPath);
    if (!await source.exists()) {
      throw FileSystemException('Saved file does not exist', currentPath);
    }
    final base = await _downloadsDirectory();
    final targetDir = Directory(p.join(base.path, subpath));
    await targetDir.create(recursive: true);
    if (p.basename(source.path) == cleanName &&
        p.normalize(source.parent.path).toLowerCase() ==
            p.normalize(targetDir.path).toLowerCase()) {
      return RenamedFile(
        fileName: cleanName,
        mimeType: newMimeType,
        relativePath: newRelativePath,
        path: source.path,
      );
    }
    final target = await _uniqueFile(targetDir, cleanName);
    File renamed;
    try {
      renamed = await source.rename(target.path);
    } on FileSystemException {
      renamed = await source.copy(target.path);
      await source.delete();
    }
    return RenamedFile(
      fileName: p.basename(renamed.path),
      mimeType: lookupMimeType(renamed.path),
      relativePath: newRelativePath == null
          ? null
          : replaceRelativeFileName(newRelativePath, p.basename(renamed.path)),
      path: renamed.path,
    );
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
