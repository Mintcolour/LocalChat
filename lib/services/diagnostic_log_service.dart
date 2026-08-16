import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class DiagnosticLogger {
  void info(String event, [Map<String, Object?> fields = const {}]);
  void warning(String event, [Map<String, Object?> fields = const {}]);
  void error(String event, Object error, [StackTrace? stackTrace]);
}

class NoopDiagnosticLogger implements DiagnosticLogger {
  const NoopDiagnosticLogger();

  @override
  void error(String event, Object error, [StackTrace? stackTrace]) {}

  @override
  void info(String event, [Map<String, Object?> fields = const {}]) {}

  @override
  void warning(String event, [Map<String, Object?> fields = const {}]) {}
}

class DiagnosticLogService implements DiagnosticLogger {
  DiagnosticLogService({
    Future<Directory> Function()? directoryProvider,
    this.maxFileBytes = 2 * 1024 * 1024,
    this.retainedFileCount = 7,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final Future<Directory> Function() _directoryProvider;
  final int maxFileBytes;
  final int retainedFileCount;
  Future<void> _writeChain = Future<void>.value();
  Directory? _directory;
  bool _initialized = false;

  String? get directoryPath => _directory?.path;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      _directory = directory;
      _initialized = true;
      info('log.initialized', {'directory': directory.path});
      await flush();
    } catch (_) {
      _directory = null;
      _initialized = false;
    }
  }

  @override
  void info(String event, [Map<String, Object?> fields = const {}]) {
    _enqueue('INFO', event, fields);
  }

  @override
  void warning(String event, [Map<String, Object?> fields = const {}]) {
    _enqueue('WARN', event, fields);
  }

  @override
  void error(String event, Object error, [StackTrace? stackTrace]) {
    _enqueue('ERROR', event, {
      'error': '$error',
      if (stackTrace != null) 'stack': '$stackTrace',
    });
  }

  Future<void> flush() => _writeChain;

  Future<String> buildExport(String summary) async {
    await flush();
    final buffer = StringBuffer()
      ..writeln('LocalChat diagnostic report')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln(summary.trim())
      ..writeln()
      ..writeln('--- logs ---');
    final directory = _directory;
    if (directory == null || !await directory.exists()) {
      buffer.writeln('Logging is unavailable.');
      return buffer.toString();
    }
    final files = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              p.basename(entry.path).startsWith('localchat.log'),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => _logOrder(a.path).compareTo(_logOrder(b.path)));
    for (final file in files.reversed) {
      buffer
        ..writeln()
        ..writeln('--- ${p.basename(file.path)} ---');
      try {
        buffer.write(await file.readAsString());
      } catch (error) {
        buffer.writeln('Unable to read log: $error');
      }
    }
    return buffer.toString();
  }

  Future<void> dispose() async {
    await flush();
  }

  void _enqueue(String level, String event, Map<String, Object?> fields) {
    if (!_initialized || _directory == null) return;
    final entry = <String, Object?>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'event': event,
      'fields': _sanitize(fields),
    };
    final line = '${jsonEncode(entry)}\n';
    _writeChain = _writeChain.then((_) => _writeLine(line)).catchError((_) {});
  }

  Future<void> _writeLine(String line) async {
    final directory = _directory;
    if (directory == null) return;
    final file = File(p.join(directory.path, 'localchat.log'));
    if (await file.exists() &&
        await file.length() + utf8.encode(line).length > maxFileBytes) {
      await _rotate(directory);
    }
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  Future<void> _rotate(Directory directory) async {
    for (var index = retainedFileCount - 1; index >= 1; index--) {
      final source = File(
        p.join(
          directory.path,
          index == 1 ? 'localchat.log' : 'localchat.log.${index - 1}',
        ),
      );
      if (!await source.exists()) continue;
      final target = File(p.join(directory.path, 'localchat.log.$index'));
      if (await target.exists()) await target.delete();
      await source.rename(target.path);
    }
  }

  Map<String, Object?> _sanitize(Map<String, Object?> fields) {
    final result = <String, Object?>{};
    for (final entry in fields.entries) {
      final key = entry.key;
      final lower = key.toLowerCase();
      if (lower.contains('private') ||
          lower.contains('token') ||
          lower.contains('paircode') ||
          lower == 'body' ||
          lower == 'message' ||
          lower == 'text' ||
          lower.contains('content')) {
        result[key] = '<redacted>';
        continue;
      }
      final value = entry.value;
      result[key] = value is String && value.length > 200
          ? '${value.substring(0, 200)}...'
          : value;
    }
    return result;
  }

  static int _logOrder(String path) {
    final name = p.basename(path);
    if (name == 'localchat.log') return 0;
    return int.tryParse(name.split('.').last) ?? retainedSortFallback;
  }

  static const retainedSortFallback = 999;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'LocalChat', 'logs'));
  }
}
