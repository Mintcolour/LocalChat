/// 存储根迁移结果：成功搬移与跳过（不存在/非文件/搬移失败）的文件数。
class StorageMigrationResult {
  const StorageMigrationResult({required this.moved, required this.skipped});

  final int moved;
  final int skipped;
}
