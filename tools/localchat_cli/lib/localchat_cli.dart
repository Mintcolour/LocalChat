import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

const _protocolVersion = 1;

class _CliFailure implements Exception {
  const _CliFailure(this.code, this.message, this.exitCode);

  final String code;
  final String message;
  final int exitCode;

  Map<String, Object?> toJson() => {
    'ok': false,
    'status': 'failed',
    'errorCode': code,
    'message': message,
    'exitCode': exitCode,
  };
}

class _Connection {
  const _Connection(this.port, this.token);
  final int port;
  final String token;
}

/// Pure Dart client: no Flutter, SQLite, identity keys or GUI automation.
class LocalChatCli {
  LocalChatCli({
    File? descriptorFile,
    File? applicationFile,
    Future<void> Function()? launchApplication,
    void Function(String)? output,
    Future<String> Function()? input,
    this.startupTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 250),
  }) : _descriptorFile = descriptorFile,
       _applicationFile = applicationFile,
       _launchApplication = launchApplication,
       _output = output ?? stdout.writeln,
       _input = input ?? (() => stdin.transform(utf8.decoder).join());

  final File? _descriptorFile;
  final File? _applicationFile;
  final Future<void> Function()? _launchApplication;
  final void Function(String) _output;
  final Future<String> Function() _input;
  final Duration startupTimeout;
  final Duration pollInterval;

  static ArgParser _parser() {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('json', negatable: false);
    ArgParser command() => ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('json', negatable: false);
    parser.addCommand('devices', command());
    parser.addCommand(
      'send',
      command()
        ..addOption('to')
        ..addOption('text')
        ..addOption('text-file')
        ..addFlag('stdin', negatable: false)
        ..addMultiOption('file', splitCommas: false)
        ..addOption('folder')
        ..addOption('timeout', defaultsTo: '120')
        ..addFlag('no-wait', negatable: false),
    );
    parser.addCommand('status', command()..addOption('job'));
    return parser;
  }

  Future<int> run(List<String> arguments) async {
    var json = arguments.contains('--json');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final parsed = _parser().parse(arguments);
      final command = parsed.command;
      json = parsed['json'] == true || command?['json'] == true;
      if (parsed['help'] == true || command?['help'] == true) {
        _output(json ? jsonEncode({'ok': true, 'help': _help}) : _help);
        return 0;
      }
      if (command == null ||
          parsed.rest.isNotEmpty ||
          command.rest.isNotEmpty) {
        throw const _CliFailure(
          'invalid_arguments',
          'Use devices, send or status. See --help.',
          2,
        );
      }

      Map<String, Object?>? payload;
      String? jobId;
      var timeoutSeconds = 120;
      if (command.name == 'send') {
        final target = command['to'] as String?;
        if (target == null || target.trim().isEmpty) {
          throw const _CliFailure('invalid_target', 'Specify --to.', 2);
        }
        final files = command['file'] as List<String>;
        final sourceCount = [
          command.wasParsed('text'),
          command.wasParsed('text-file'),
          command['stdin'] == true,
          files.isNotEmpty,
          command.wasParsed('folder'),
        ].where((value) => value).length;
        if (sourceCount != 1) {
          throw const _CliFailure(
            'invalid_source',
            'Choose one: --text, --text-file, --stdin, --file or --folder.',
            2,
          );
        }
        timeoutSeconds = int.tryParse(command['timeout'] as String) ?? 0;
        if (timeoutSeconds < 1 || timeoutSeconds > 86400) {
          throw const _CliFailure(
            'invalid_timeout',
            '--timeout must be an integer from 1 to 86400 seconds.',
            2,
          );
        }
        payload = {'target': target};
        if (command.wasParsed('text')) {
          payload['text'] = command['text'] as String;
        } else if (command.wasParsed('text-file')) {
          try {
            payload['text'] = await File(
              command['text-file'] as String,
            ).readAsString(encoding: utf8);
          } on FileSystemException {
            throw const _CliFailure(
              'source_unreadable',
              'Cannot read --text-file.',
              5,
            );
          } on FormatException {
            throw const _CliFailure(
              'invalid_text_encoding',
              '--text-file must contain UTF-8 text.',
              2,
            );
          }
        } else if (command['stdin'] == true) {
          payload['text'] = await _input();
        } else if (files.isNotEmpty) {
          payload['files'] = files
              .map((path) => File(path).absolute.path)
              .toList();
        } else {
          payload['folder'] = Directory(
            command['folder'] as String,
          ).absolute.path;
        }
        if (payload.containsKey('text') &&
            (payload['text'] as String).trim().isEmpty) {
          throw const _CliFailure('invalid_text', 'Text must not be empty.', 2);
        }
        if (utf8.encode(jsonEncode(payload)).length > 2 * 1024 * 1024) {
          throw const _CliFailure(
            'request_too_large',
            'Text and request metadata must fit within 2 MiB.',
            2,
          );
        }
      } else if (command.name == 'status') {
        jobId = command['job'] as String?;
        if (jobId == null || jobId.isEmpty) {
          throw const _CliFailure('invalid_job', 'Specify --job.', 2);
        }
      }

      final connection = await _connect(client);
      Map<String, Object?> result;
      if (command.name == 'devices') {
        result = await _request(client, connection, 'GET', '/v1/devices');
      } else if (command.name == 'status') {
        result = await _request(
          client,
          connection,
          'GET',
          '/v1/jobs/${Uri.encodeComponent(jobId!)}',
        );
      } else {
        try {
          result = await _request(
            client,
            connection,
            'POST',
            '/v1/send',
            payload: payload,
            timeout: const Duration(seconds: 120),
          );
        } on _CliFailure {
          // Never retry a POST: the reply may have been lost after enqueueing.
          throw const _CliFailure(
            'submission_unknown',
            'No submission response. Check LocalChat before sending again.',
            3,
          );
        }
        if (result['ok'] == true && command['no-wait'] != true) {
          final submittedJobId = result['jobId'];
          if (submittedJobId is! String) throw _invalidResponse;
          final timer = Stopwatch()..start();
          while (result['terminal'] != true) {
            final remaining = Duration(seconds: timeoutSeconds) - timer.elapsed;
            if (remaining <= Duration.zero) {
              result = _timedOut(result);
              break;
            }
            await Future<void>.delayed(
              remaining < pollInterval ? remaining : pollInterval,
            );
            final requestRemaining =
                Duration(seconds: timeoutSeconds) - timer.elapsed;
            if (requestRemaining <= Duration.zero) {
              result = _timedOut(result);
              break;
            }
            try {
              final next = await _request(
                client,
                connection,
                'GET',
                '/v1/jobs/${Uri.encodeComponent(submittedJobId)}',
                timeout: requestRemaining < const Duration(seconds: 10)
                    ? requestRemaining
                    : const Duration(seconds: 10),
              );
              if (next['jobId'] != submittedJobId) {
                result = {...result, ...next, 'jobId': submittedJobId};
                break;
              }
              result = next;
            } on _CliFailure catch (error) {
              result = {
                ...result,
                'ok': false,
                'errorCode': error.code,
                'message':
                    'Cannot query delivery. Keep the job ID; do not resend.',
                'exitCode': 3,
              };
              if (timer.elapsed >= Duration(seconds: timeoutSeconds)) {
                result = _timedOut(result);
              }
              break;
            }
          }
        }
      }
      _emit(result, json);
      return result['exitCode'] as int? ?? (result['ok'] == true ? 0 : 5);
    } on ArgParserException catch (error) {
      final failure = _CliFailure('invalid_arguments', error.message, 2);
      _emit(failure.toJson(), json);
      return failure.exitCode;
    } on _CliFailure catch (error) {
      _emit(error.toJson(), json);
      return error.exitCode;
    } catch (_) {
      _emit(
        const _CliFailure(
          'client_unavailable',
          'LocalChat CLI could not complete the operation.',
          3,
        ).toJson(),
        json,
      );
      return 3;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _timedOut(Map<String, Object?> result) => {
    ...result,
    'ok': false,
    'errorCode': 'wait_timeout',
    'message': 'Delivery is still pending. Query --job; the send continues.',
    'exitCode': 6,
  };

  void _emit(Map<String, Object?> result, bool json) => _output(
    json
        ? jsonEncode(result)
        : const JsonEncoder.withIndent('  ').convert(result),
  );

  File _descriptor() {
    if (_descriptorFile != null) return _descriptorFile;
    final appData = Platform.environment['LOCALAPPDATA'];
    if (appData == null || appData.isEmpty) {
      throw const _CliFailure(
        'client_unavailable',
        'LOCALAPPDATA is unavailable. Run as the LocalChat Windows user.',
        3,
      );
    }
    return File(
      '$appData${Platform.pathSeparator}LocalChat'
      '${Platform.pathSeparator}automation.json',
    );
  }

  Future<_Connection?> _readConnection(HttpClient client) async {
    try {
      final data = jsonDecode(await _descriptor().readAsString());
      if (data is! Map<String, dynamic>) return null;
      if (data['protocolVersion'] != _protocolVersion) {
        throw const _CliFailure(
          'incompatible_version',
          'Update LocalChat and its CLI together.',
          3,
        );
      }
      final port = data['port'];
      final token = data['token'];
      if (port is! int ||
          port < 1 ||
          port > 65535 ||
          token is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(token)) {
        return null;
      }
      final connection = _Connection(port, token);
      final health = await _request(
        client,
        connection,
        'GET',
        '/v1/health',
        timeout: const Duration(milliseconds: 750),
      );
      if (health['ok'] != true || health['application'] != 'LocalChat')
        return null;
      if (health['protocolVersion'] != _protocolVersion) {
        throw const _CliFailure(
          'incompatible_version',
          'Update LocalChat and its CLI together.',
          3,
        );
      }
      return connection;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on _CliFailure catch (error) {
      if (error.code == 'incompatible_version') rethrow;
      return null;
    }
  }

  Future<_Connection> _connect(HttpClient client) async {
    final existing = await _readConnection(client);
    if (existing != null) return existing;
    final timer = Stopwatch()..start();
    try {
      if (_launchApplication != null) {
        await _launchApplication();
      } else {
        final app =
            _applicationFile ??
            File(
              '${File(Platform.resolvedExecutable).parent.path}'
              '${Platform.pathSeparator}localchat.exe',
            );
        if (!await app.exists()) {
          throw const _CliFailure(
            'client_not_found',
            'Place localchat-cli.exe beside localchat.exe.',
            3,
          );
        }
        await Process.start(
          app.absolute.path,
          ['--automation-start'],
          workingDirectory: app.parent.absolute.path,
          mode: ProcessStartMode.detached,
        );
      }
    } on ProcessException {
      throw const _CliFailure(
        'client_start_failed',
        'Cannot start LocalChat.',
        3,
      );
    }
    while (timer.elapsed < startupTimeout) {
      final connection = await _readConnection(client);
      if (connection != null) return connection;
      await Future<void>.delayed(pollInterval);
    }
    throw const _CliFailure(
      'client_start_timeout',
      'LocalChat did not become ready within the startup timeout.',
      3,
    );
  }

  static const _invalidResponse = _CliFailure(
    'invalid_response',
    'LocalChat returned an invalid response.',
    3,
  );

  Future<Map<String, Object?>> _request(
    HttpClient client,
    _Connection connection,
    String method,
    String path, {
    Map<String, Object?>? payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    HttpClientRequest? pending;
    var expired = false;
    Future<Map<String, Object?>> perform() async {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${connection.port}$path'),
      );
      pending = request;
      if (expired) {
        request.abort();
        throw TimeoutException('Request expired');
      }
      request
        ..followRedirects = false
        ..headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${connection.token}',
        );
      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(payload)));
      }
      final response = await request.close();
      final result = jsonDecode(await utf8.decoder.bind(response).join());
      if (result is! Map<String, dynamic> || result['ok'] is! bool) {
        throw _invalidResponse;
      }
      return result;
    }

    try {
      return await perform().timeout(
        timeout,
        onTimeout: () {
          expired = true;
          pending?.abort();
          throw TimeoutException('Request expired');
        },
      );
    } on _CliFailure {
      rethrow;
    } catch (_) {
      throw const _CliFailure(
        'client_unavailable',
        'Cannot reach the local LocalChat automation service.',
        3,
      );
    }
  }
}

const _help = '''LocalChat CLI
  devices [--json]
  send --to <name-or-id> <source> [--timeout <seconds>] [--no-wait] [--json]
  status --job <job-id> [--json]

Sources (choose one):
  --text <text>          Text or link
  --text-file <path>     UTF-8 text file
  --stdin               UTF-8 text from standard input
  --file <path>          File or image; repeat for multiple files
  --folder <path>        Recursive directory, without following symbolic links

Delivery wait defaults to 120 seconds; --timeout accepts 1..86400 seconds.
--no-wait returns after enqueueing. A wait timeout does not cancel the send.
LocalChat starts automatically from the CLI directory when needed (20s limit).
JSON output is one object, including failures. Help never starts LocalChat.
Exit codes: 0 success/queued, 2 arguments, 3 client, 4 target, 5 send, 6 wait timeout.
''';
