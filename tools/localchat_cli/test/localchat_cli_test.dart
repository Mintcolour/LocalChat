import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localchat_cli/localchat_cli.dart';
import 'package:test/test.dart';

typedef _Reply =
    FutureOr<Map<String, Object?>> Function(
      HttpRequest request,
      Map<String, Object?>? payload,
    );

void main() {
  late Directory root;
  late File descriptor;
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late List<String> output;
  late List<Map<String, Object?>> submissions;
  late _Reply reply;
  late int queries;
  late int launches;
  final token = base64UrlEncode(List.filled(32, 7));

  Map<String, Object?> queued() => {
    'ok': true,
    'status': 'queued',
    'terminal': false,
    'exitCode': 0,
    'targetDeviceId': 'phone',
    'jobId': 'message:example',
    'messageIds': ['example'],
    'transferIds': <String>[],
    'items': <Object?>[],
  };

  Future<void> publish() => descriptor
      .writeAsString(
        jsonEncode({
          'protocolVersion': 1,
          'port': server.port,
          'token': token,
          'pid': pid,
        }),
      )
      .then((_) {});

  LocalChatCli cli({Future<String> Function()? input}) => LocalChatCli(
    descriptorFile: descriptor,
    output: output.add,
    input: input,
    pollInterval: const Duration(milliseconds: 5),
    startupTimeout: const Duration(milliseconds: 200),
    launchApplication: () async {
      launches++;
      await publish();
    },
  );

  Map<String, Object?> result() =>
      jsonDecode(output.last) as Map<String, Object?>;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('localchat-cli-test-');
    descriptor = File('${root.path}/automation.json');
    output = [];
    submissions = [];
    queries = 0;
    launches = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    reply = (request, payload) async {
      if (request.uri.path == '/v1/devices') {
        return {
          'ok': true,
          'exitCode': 0,
          'devices': [
            {'id': 'phone', 'name': '我的手机'},
          ],
        };
      }
      if (request.method == 'POST') return queued();
      return {...queued(), 'status': 'sent', 'terminal': true};
    };
    subscription = server.listen((request) async {
      expect(request.headers.value('authorization'), 'Bearer $token');
      Map<String, Object?> value;
      if (request.uri.path == '/v1/health') {
        value = {'ok': true, 'application': 'LocalChat', 'protocolVersion': 1};
      } else {
        Map<String, Object?>? payload;
        if (request.method == 'POST') {
          payload =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, Object?>;
          submissions.add(payload);
        }
        if (request.uri.path.startsWith('/v1/jobs/')) queries++;
        value = await reply(request, payload);
      }
      if (value['__close'] == true) {
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(value));
      await request.response.close();
    });
    await publish();
  });

  tearDown(() async {
    await server.close(force: true);
    await subscription.cancel();
    await root.delete(recursive: true);
  });

  test('help and invalid arguments never start the application', () async {
    await descriptor.delete();
    expect(await cli().run(['--help']), 0);
    expect(launches, 0);
    expect(await cli().run(['send', '--text', 'x', '--json']), 2);
    expect(result()['errorCode'], 'invalid_target');
    expect(
      await cli().run([
        'send',
        '--to',
        'phone',
        '--text',
        'x',
        '--folder',
        'y',
        '--json',
      ]),
      2,
    );
    expect(result()['errorCode'], 'invalid_source');
    expect(await cli().run(['status', '--json']), 2);
    expect(
      await cli().run([
        'send',
        '--to',
        'phone',
        '--text',
        'x',
        '--timeout',
        '0',
        '--json',
      ]),
      2,
    );
    expect(await cli().run(['devices', '--unknown', '--json']), 2);
    expect(launches, 0);
  });

  test('devices prints a single JSON object without the credential', () async {
    expect(await cli().run(['devices', '--json']), 0);
    expect(output, hasLength(1));
    expect(result()['devices'], contains(containsPair('name', '我的手机')));
    expect(output.single, isNot(contains(token)));
    expect(launches, 0);
  });

  test('text waits for receipt and keeps Unicode and newlines', () async {
    const text = '  中文 🌙\r\n第二行\n';
    expect(
      await cli().run(['send', '--to', 'phone', '--text', text, '--json']),
      0,
    );
    expect(submissions.single['text'], text);
    expect(result()['status'], 'sent');
    expect(queries, 1);
    expect(output, hasLength(1));
  });

  test('UTF-8 file and stdin support long text', () async {
    const text = '第一行\n第二行\n';
    final file = await File('${root.path}/长 文本.txt').writeAsString(text);
    expect(
      await cli().run([
        'send',
        '--to',
        'phone',
        '--text-file',
        file.path,
        '--json',
      ]),
      0,
    );
    expect(submissions.last['text'], text);
    expect(
      await cli(
        input: () async => text,
      ).run(['send', '--to', 'phone', '--stdin', '--json']),
      0,
    );
    expect(submissions.last['text'], text);
  });

  test(
    'repeatable file arguments preserve commas and resolve relative paths',
    () async {
      expect(
        await cli().run([
          'send',
          '--to',
          'phone',
          '--file',
          'a,b.txt',
          '--file',
          '有 空格.png',
          '--no-wait',
          '--json',
        ]),
        0,
      );
      expect(submissions.single['files'], [
        File('a,b.txt').absolute.path,
        File('有 空格.png').absolute.path,
      ]);
      expect(queries, 0);
      expect(result()['status'], 'queued');
      expect(
        await cli().run([
          'send',
          '--to',
          'phone',
          '--folder',
          '输出',
          '--no-wait',
          '--json',
        ]),
        0,
      );
      expect(submissions.last['folder'], Directory('输出').absolute.path);
    },
  );

  test(
    'timeout retains the job ID and does not repeat or cancel submission',
    () async {
      reply = (_, _) => queued();
      expect(
        await cli().run([
          'send',
          '--to',
          'phone',
          '--text',
          'x',
          '--timeout',
          '1',
          '--json',
        ]),
        6,
      );
      expect(submissions, hasLength(1));
      expect(result()['jobId'], 'message:example');
      expect(result()['status'], 'queued');
      expect(result()['errorCode'], 'wait_timeout');
    },
  );

  test(
    'target errors and partial failures preserve server exit codes',
    () async {
      reply = (_, _) => {
        'ok': false,
        'exitCode': 4,
        'errorCode': 'ambiguous_target',
        'candidates': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      };
      expect(
        await cli().run(['send', '--to', 'phone', '--text', 'x', '--json']),
        4,
      );
      expect(result()['candidates'], hasLength(2));
      expect(queries, 0);
      reply = (_, _) => {
        ...queued(),
        'ok': false,
        'exitCode': 5,
        'terminal': true,
        'status': 'partial_failure',
      };
      expect(await cli().run(['status', '--job', 'group:test', '--json']), 5);
      expect(result()['status'], 'partial_failure');
    },
  );

  test(
    'missing/stale descriptor starts once; version mismatch fails without launch',
    () async {
      await descriptor.writeAsString('{incomplete');
      expect(await cli().run(['devices', '--json']), 0);
      expect(launches, 1);
      await descriptor.writeAsString(jsonEncode({'protocolVersion': 999}));
      expect(await cli().run(['devices', '--json']), 3);
      expect(result()['errorCode'], 'incompatible_version');
      expect(launches, 1);
    },
  );

  test('lost submission response never retries the POST', () async {
    reply = (_, _) => {'__close': true};
    expect(
      await cli().run(['send', '--to', 'phone', '--text', 'x', '--json']),
      3,
    );
    expect(result()['errorCode'], 'submission_unknown');
    expect(submissions, hasLength(1));
  });

  test(
    'lost status response keeps the job receipt for later queries',
    () async {
      reply = (request, _) async {
        if (request.method == 'POST') return queued();
        return {'__close': true};
      };
      expect(
        await cli().run(['send', '--to', 'phone', '--text', 'x', '--json']),
        3,
      );
      expect(result()['jobId'], 'message:example');
      expect(submissions, hasLength(1));
    },
  );
}
