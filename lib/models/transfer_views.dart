import '../data/app_database.dart';
import '../models/protocol.dart';

/// 单个传输任务的 UI 投影：聚合 [Transfer] 与实时进度、速度、剩余时间。
///
/// 传输中心据此分组渲染。进度与速度由传输服务在传输过程中刷新，DB 只持久化
/// receivedBytes / fileSize（避免高频写库）。
class TransferTaskView {
  const TransferTaskView({
    required this.transfer,
    required this.peerDisplayName,
    required this.sentBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.errorCode,
    this.groupId,
  });

  final Transfer transfer;
  final String peerDisplayName;
  final int sentBytes;
  final int totalBytes;
  final double bytesPerSecond;
  final String? groupId;
  final String? errorCode;

  bool get isOutbound => transfer.direction == 'out';
  bool get isInbound => transfer.direction == 'in';

  /// 归一化状态分组：进行中 / 已完成 / 失败（含取消、中断）。
  TransferGroupKind get groupKind {
    switch (transfer.status) {
      case 'queued':
      case 'preparing':
      case 'sending':
      case 'receiving':
        return TransferGroupKind.active;
      case 'sent':
      case 'received':
        return TransferGroupKind.completed;
      case 'failed':
      case 'canceled':
      case 'interrupted':
        return TransferGroupKind.failed;
      default:
        return TransferGroupKind.active;
    }
  }

  double get progress {
    if (totalBytes <= 0) return 0;
    return (sentBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// 预计剩余秒数；速度未知或为 0 时返回 null。
  int? get etaSeconds {
    if (bytesPerSecond <= 0) return null;
    final remaining = totalBytes - sentBytes;
    if (remaining <= 0) return 0;
    return (remaining / bytesPerSecond).ceil();
  }
}

/// 一组传输（文件夹或批量附件）的聚合视图，用于整组进度与整组取消。
class TransferGroupView {
  const TransferGroupView({
    required this.groupId,
    required this.peerDisplayName,
    required this.tasks,
  });

  final String groupId;
  final String peerDisplayName;
  final List<TransferTaskView> tasks;

  int get totalBytes => tasks.fold(0, (sum, task) => sum + task.totalBytes);
  int get sentBytes => tasks.fold(0, (sum, task) => sum + task.sentBytes);

  double get progress {
    if (totalBytes <= 0) return 0;
    return (sentBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// 整组完成时为 true（便于从列表折叠）。
  bool get isTerminal =>
      tasks.every((task) => task.groupKind != TransferGroupKind.active);

  TransferGroupKind get groupKind {
    if (tasks.any((task) => task.groupKind == TransferGroupKind.active)) {
      return TransferGroupKind.active;
    }
    if (tasks.every((task) => task.groupKind == TransferGroupKind.completed)) {
      return TransferGroupKind.completed;
    }
    return TransferGroupKind.failed;
  }
}

/// 传输在传输中心的分组类别。
enum TransferGroupKind { active, completed, failed }

/// 对一个出站传输的取消句柄。
///
/// - 若任务仍在队列等待：取消会将其移出队列并标记 canceled。
/// - 若任务正在发送：取消会中断底层 dio 请求与加密流生成。
/// 返回 true 表示成功取消，false 表示任务已结束（完成/失败/已取消）无法再取消。
typedef TransferCancellationHandle = Future<bool> Function(String transferId);

/// 判断对端是否支持主动取消（双方都需广播 [transferCancelCapability]）。
bool peerSupportsCancel(List<String> capabilities) =>
    capabilities.contains(transferCancelCapability);
