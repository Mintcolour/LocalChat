import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/services/diagnostic_log_service.dart';

void main() {
  test('diagnostic logs redact sensitive fields and rotate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'localchat-diagnostic-log',
    );
    addTearDown(() => directory.delete(recursive: true));
    final logger = DiagnosticLogService(
      directoryProvider: () async => directory,
      maxFileBytes: 180,
      retainedFileCount: 3,
    );
    await logger.initialize();

    for (var index = 0; index < 20; index++) {
      logger.info('network.event', {
        'index': index,
        'token': 'secret-token',
        'message': 'private chat message',
        'port': 45871,
      });
    }
    await logger.flush();
    final report = await logger.buildExport('summary');

    expect(report, contains('summary'));
    expect(report, contains('<redacted>'));
    expect(report, isNot(contains('secret-token')));
    expect(report, isNot(contains('private chat message')));
    final files = await directory
        .list()
        .where((entry) => entry is File)
        .toList();
    expect(files.length, lessThanOrEqualTo(3));
  });
}
