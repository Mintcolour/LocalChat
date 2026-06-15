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
  return visible.replaceAllMapped(RegExp(r'.{4}'), (match) => '${match[0]} ').trim();
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
