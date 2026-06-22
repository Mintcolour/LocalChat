import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

String b64(List<int> bytes) => base64UrlEncode(bytes);

List<int> unb64(String value) => base64Url.decode(value);

String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

String randomCode([int digits = 6]) {
  final random = Random.secure();
  final max = pow(10, digits).toInt();
  return random.nextInt(max).toString().padLeft(digits, '0');
}

String randomNonce([int bytes = 16]) {
  final random = Random.secure();
  return b64(List<int>.generate(bytes, (_) => random.nextInt(256)));
}

String shortFingerprint(String value) {
  final clean = value.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toUpperCase();
  final visible = clean.length >= 16 ? clean.substring(0, 16) : clean;
  return visible
      .replaceAllMapped(RegExp(r'.{4}'), (match) => '${match[0]} ')
      .trim();
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024.0;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
}

String displayHost(String? host, int? port) {
  if (host == null || host.isEmpty || port == null || port <= 0) return '未连接';
  return '$host:$port';
}

String formatMessageTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.year % 100)}/${_two(local.month)}/${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

/// 日期分隔标题：今天/昨天/本周内显示星期、更早显示完整日期。
String formatChatDateSeparator(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final that = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(that).inDays;
  if (diffDays == 0) return '今天';
  if (diffDays == 1) return '昨天';
  if (diffDays < 7) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[that.weekday - 1];
  }
  return '${local.year}年${local.month}月${local.day}日';
}

/// 消息中可点击链接的正则（http/https）。
final linkRegExp = RegExp(
  r'https?://[^\s<>()]+',
  caseSensitive: false,
);

/// 提取消息文本中的全部链接。
List<String> extractLinks(String text) =>
    linkRegExp.allMatches(text).map((m) => m.group(0)!).toList();

String messageStatusLabel(String status) {
  return switch (status) {
    'queued' => '排队中',
    'sending' => '发送中',
    'sent' => '已发送',
    'failed' => '发送失败',
    'receiving' => '接收中',
    'received' => '已接收',
    'canceled' => '已取消',
    'interrupted' => '已中断',
    _ => status,
  };
}

String _two(int value) => value.toString().padLeft(2, '0');
