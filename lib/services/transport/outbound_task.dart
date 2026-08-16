import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' as dio;

/// 出站传输被用户取消时抛出，用于在传输链路中中断流生成与 dio 请求。
class OutboundCancelled implements Exception {
  const OutboundCancelled();
}

/// 出站传输任务：单个文件的队列条目与运行期控制。
class OutboundTask {
  OutboundTask({
    required this.transferId,
    required this.peerId,
    required this.file,
    required this.name,
    required this.length,
    required this.mimeType,
    required this.totalChunks,
    required this.groupId,
    this.relativePath,
    this.completion,
  });

  final String transferId;
  final String peerId;
  final File file;
  final String name;
  final int length;
  final String? mimeType;
  final int totalChunks;
  final String groupId;
  final String? relativePath;
  final Completer<void>? completion;

  /// 运行期取消控制：dio 请求取消令牌 + 流生成中断标志。
  final dio.CancelToken cancelToken = dio.CancelToken();
  bool canceled = false;

  void complete() {
    final value = completion;
    if (value != null && !value.isCompleted) value.complete();
  }

  void completeError(Object error) {
    final value = completion;
    if (value != null && !value.isCompleted) value.completeError(error);
  }
}

/// 传输实时统计（内存态）：发送字节数 + 瞬时速度。
class LiveTransferStat {
  LiveTransferStat({required this.totalBytes});
  final int totalBytes;
  int sentBytes = 0;
  double bytesPerSecond = 0;
  DateTime? lastSampleAt;
  int lastSampledBytes = 0;
}

/// 入站接收取消信号：被对端 cancel 接口触发后中断流读取循环。
class InboundCancel {
  bool canceled = false;
}
