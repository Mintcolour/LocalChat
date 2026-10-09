import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'diagnostic_log_service.dart';

/// Only for device-to-device traffic. Internet services keep their own clients.
Dio createPeerHttpClient(DiagnosticLogger logger) {
  final client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 75),
    ),
  );
  client.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..idleTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT',
  );
  final timers = Expando<Stopwatch>();
  Map<String, Object?> fields(RequestOptions request, int? status) => {
    'method': request.method,
    'host': request.uri.host,
    'port': request.uri.port,
    'path': request.uri.path,
    'routing': 'direct',
    'elapsedMs': timers[request]?.elapsedMilliseconds,
    'httpStatus': ?status,
  };
  client.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        timers[request] = Stopwatch()..start();
        handler.next(request);
      },
      onResponse: (response, handler) {
        logger.info(
          'transport.request_succeeded',
          fields(response.requestOptions, response.statusCode),
        );
        handler.next(response);
      },
      onError: (error, handler) {
        // Never log envelopes, headers, response bodies or query parameters.
        logger.warning('transport.request_failed', {
          ...fields(error.requestOptions, error.response?.statusCode),
          'type': error.type.name,
          if (error.error case SocketException socket)
            'errno': socket.osError?.errorCode,
        });
        handler.next(error);
      },
    ),
  );
  return client;
}
