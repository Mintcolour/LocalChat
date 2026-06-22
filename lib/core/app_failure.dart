import 'dart:async';

import 'package:flutter/foundation.dart';

/// 结构化失败信息。界面只展示 [userMessage]，[code] 与 [cause] 仅供诊断与日志。
///
/// 用以替代把原始异常字符串直接塞进底部状态栏的做法（计划 P1：错误信息集中且
/// 包含原始异常）。本类型在阶段 A 引入，阶段 D 起在控制器层全面替换裸 `$error`。
@immutable
class AppFailure implements Exception {
  const AppFailure({
    required this.code,
    required this.userMessage,
    this.cause,
  });

  /// 稳定错误码，用于测试断言与跨模块识别（如 `peer_identity_changed`）。
  final String code;

  /// 面向用户的可读文案（已按语言确定，调用方负责本地化）。
  final String userMessage;

  /// 原始异常或上下文对象，仅用于诊断，不展示给用户。
  final Object? cause;

  /// 把任意异常归一为 [AppFailure]。已知 [code] 时优先使用，否则按异常类型推断
  /// 一个保守的通用码，并把原始异常挂在 [cause] 上。
  factory AppFailure.from(
    Object error, {
    String? userMessage,
    String? code,
  }) {
    if (error is AppFailure) {
      return error;
    }
    return AppFailure(
      code: code ?? _inferCode(error),
      userMessage: userMessage ?? _inferMessage(error),
      cause: error,
    );
  }

  @override
  String toString() => 'AppFailure($code): $userMessage';
}

String _inferCode(Object error) {
  if (error is TimeoutException) return 'timeout';
  if (error is FormatException) return 'format';
  return 'unknown';
}

String _inferMessage(Object error) {
  if (error is TimeoutException) return '操作超时，请稍后重试';
  if (error is FormatException) return '数据格式无效';
  return '操作失败，请重试';
}
