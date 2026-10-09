import 'package:dio/dio.dart';

import '../core/app_failure.dart';

AppFailure peerRequestFailure(
  Object error, {
  required String operation,
  required String target,
  required String languageCode,
}) {
  if (error is AppFailure) return error;
  final english = languageCode == 'en';
  String detail;
  String code;
  if (error is DioException && error.response?.statusCode != null) {
    final status = error.response!.statusCode!;
    detail = english
        ? 'the peer request returned HTTP $status'
        : '对端请求返回 HTTP $status';
    code = 'peer_http_$status';
  } else if (error is DioException && error.type.name.endsWith('Timeout')) {
    detail = english ? 'connection timed out' : '连接超时，请检查对方网络';
    code = 'peer_timeout';
  } else {
    detail = english ? 'unable to reach the peer' : '无法连接对方，请检查网络和地址';
    code = 'peer_connection';
  }
  return AppFailure(
    code: code,
    userMessage: english
        ? '$operation to $target failed: $detail'
        : '$operation到 $target 失败：$detail',
    cause: error,
  );
}
