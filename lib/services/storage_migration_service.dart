import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/app_database.dart';
import '../models/storage_migration.dart';
import 'file_store.dart';

/// 存储根迁移：把索引内已接收的文件搬到新存储根目录并回写索引。
///
/// 纯文件与数据库操作，不含 UI 状态——状态文案与刷新广播由 AppController
/// 负责（见 SettingsController 顶注的 P1 拆分约定）。搬移失败或索引回写
/// 失败时计入 skipped 并回滚已搬移文件，保证索引与磁盘一致。
class StorageMigrationService {
  const StorageMigrationService(this._db, this._fileStore);

  final AppDatabase _db;
  final FileStore _fileStore;

  Future<StorageMigrationResult> migrateIndexedFiles({
    required String oldRoot,
    required String newRoot,
  }) async {
    final transfers = await _db.listReceivedTransfersForStorageMigration();
    var movedCount = 0;
    var skippedCount = 0;

    for (final transfer in transfers) {
      final sourcePath = transfer.savedPath ?? transfer.filePath;
      if (sourcePath == null || sourcePath.isEmpty) continue;
      if (!FileStore.isSameOrWithin(oldRoot, sourcePath)) continue;

      final sourceType = await FileSystemEntity.type(
        sourcePath,
        followLinks: true,
      );
      if (sourceType != FileSystemEntityType.file) {
        skippedCount++;
        continue;
      }

      final relativePath = p.relative(sourcePath, from: oldRoot);
      if (p.isAbsolute(relativePath) || relativePath.startsWith('..')) {
        skippedCount++;
        continue;
      }

      final targetDir = Directory(
        p.normalize(p.join(newRoot, p.dirname(relativePath))),
      );
      try {
        await targetDir.create(recursive: true);
      } catch (_) {
        skippedCount++;
        continue;
      }

      final target = await _fileStore.uniqueFileInDirectory(
        targetDir,
        p.basename(sourcePath),
      );
      final moved = await _moveFile(File(sourcePath), target);
      if (moved == null) {
        skippedCount++;
        continue;
      }

      final actualName = p.basename(moved.path);
      final migratedRelativePath = transfer.relativePath == null
          ? null
          : FileStore.replaceRelativeFileName(
              transfer.relativePath!,
              actualName,
            );
      try {
        await _db.renameReceivedTransfer(
          transferId: transfer.id,
          fileName: actualName,
          mimeType: transfer.mimeType,
          savedPath: moved.path,
          savedUri: null,
          relativePath: migratedRelativePath,
        );
        movedCount++;
      } catch (_) {
        await _rollbackMovedFile(moved.path, sourcePath);
        skippedCount++;
      }
    }

    await _fileStore.deleteEmptyDirectoriesUnder(oldRoot);
    return StorageMigrationResult(moved: movedCount, skipped: skippedCount);
  }

  /// 优先 rename，跨盘回退 copy+delete；任一步失败则清理目标并返回 null。
  Future<File?> _moveFile(File source, File target) async {
    try {
      return await source.rename(target.path);
    } on FileSystemException {
      try {
        final copied = await source.copy(target.path);
        try {
          await source.delete();
        } catch (_) {
          try {
            if (await copied.exists()) await copied.delete();
          } catch (_) {}
          return null;
        }
        return copied;
      } catch (_) {
        try {
          if (await target.exists()) await target.delete();
        } catch (_) {}
        return null;
      }
    }
  }

  Future<void> _rollbackMovedFile(String movedPath, String originalPath) async {
    final moved = File(movedPath);
    if (!await moved.exists() || await File(originalPath).exists()) return;
    try {
      await File(originalPath).parent.create(recursive: true);
      try {
        await moved.rename(originalPath);
      } on FileSystemException {
        await moved.copy(originalPath);
        await moved.delete();
      }
    } catch (_) {
      // Best effort: if rollback fails, the next refresh will still show status.
    }
  }
}
