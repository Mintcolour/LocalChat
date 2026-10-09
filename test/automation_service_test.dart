import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/automation_service.dart';
import 'package:localchat/services/file_store.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/security_service.dart';
import 'package:localchat/services/transport_service.dart';

class _TestFileStore extends FileStore {
  _TestFileStore(this.root);
  final Directory root;

  @override
  Future<Directory> receiveDirectory() async =>
      Directory('${root.path}/incoming')..createSync(recursive: true);

  @override
  Future<SavedFile> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    required String conversationFolder,
    required DateTime at,
    String? relativePath,
    bool moveSource = false,
  }) async => SavedFile(path: sourcePath, actualFileName: fileName);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late AppDatabase dbA;
  late AppDatabase dbB;
  late AppController controller;
  late TransportService receiver;
  late AutomationDispatcher dispatcher;
  late String target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('localchat-automation-');
    dbA = AppDatabase(NativeDatabase.memory());
    dbB = AppDatabase(NativeDatabase.memory());
    controller = AppController(database: dbA, fileStore: _TestFileStore(root));
    final identityB = IdentityService(dbB);
    receiver = TransportService(
      dbB,
      identityB,
      SecurityService(identityB),
      _TestFileStore(root),
    )..autoCopyReceivedText = false;
    final a = await controller.identityService.load();
    final b = await identityB.load();
    await controller.transportService.start();
    await receiver.start();
    target = b.deviceId;
    await dbA.trustDevice(
      id: b.deviceId,
      displayName: '我的手机',
      platform: b.platform,
      host: '127.0.0.1',
      port: receiver.port,
      signingPublicKey: b.signingPublicKey,
      exchangePublicKey: b.exchangePublicKey,
      fingerprint: b.fingerprint,
      avatarSeed: b.avatarSeed,
      avatarColor: b.avatarColor,
      capabilities: const ['text', 'files', 'encrypted_chunks', 'folders_v1'],
    );
    await dbB.trustDevice(
      id: a.deviceId,
      displayName: a.displayName,
      platform: a.platform,
      host: '127.0.0.1',
      port: controller.transportService.port,
      signingPublicKey: a.signingPublicKey,
      exchangePublicKey: a.exchangePublicKey,
      fingerprint: a.fingerprint,
      avatarSeed: a.avatarSeed,
      avatarColor: a.avatarColor,
      capabilities: const ['text', 'files', 'encrypted_chunks', 'folders_v1'],
    );
    dispatcher = AutomationDispatcher(dbA, controller.transportService);
  });

  tearDown(() async {
    // Let the registered jobs finish before disposing the DB / deleting files.
    await controller.transportService.stop();
    await receiver.stop();
    controller.dispose();
    await dbB.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, Object?>> finish(String id) async {
    final timer = Stopwatch()..start();
    while (timer.elapsed < const Duration(seconds: 10)) {
      final result = await dispatcher.job(id);
      if (result['terminal'] == true) return result;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('Job did not finish: $id');
  }

  test(
    'multiline Unicode text reaches peer without changing selected chat',
    () async {
      final selected = (await dbA.getDevice(
        target,
      ))!.copyWith(id: 'other-chat');
      controller.selectedDevice = selected;
      controller.selectedConversation = await dbA.ensureConversation(selected);
      final conversation = controller.selectedConversation;
      const body = '  已完成：中文总结\r\n第二行 🌙\nhttps://example.com\n';
      final result = await dispatcher.send({'target': target, 'text': body});
      final job = await finish(result['jobId'] as String);
      expect(job['status'], 'sent');
      expect(job['messageIds'], hasLength(1));
      expect(controller.selectedDevice, same(selected));
      expect(controller.selectedConversation, same(conversation));
      final received = await dbB.select(dbB.chatMessages).get();
      expect(received.single.body, body);
    },
  );

  test(
    'device listing and target lookup use the visible conversation name',
    () async {
      final peer = (await dbA.getDevice(target))!;
      final conversation = await dbA.ensureConversation(peer);
      await dbA.renameConversation(conversation.id, '工作手机');
      final devices = await dispatcher.devices();
      expect(devices['devices'], contains(containsPair('name', '工作手机')));
      final result = await dispatcher.send({
        'target': '工作手机',
        'text': 'by alias',
      });
      expect((await finish(result['jobId'] as String))['status'], 'sent');
    },
  );

  test(
    'concurrent sends get independent jobs without changing selection',
    () async {
      controller.selectedDevice = (await dbA.getDevice(
        target,
      ))!.copyWith(id: 'other');
      final results = await Future.wait([
        dispatcher.send({'target': target, 'text': 'first'}),
        dispatcher.send({'target': target, 'text': 'second'}),
      ]);
      expect(results.map((item) => item['jobId']).toSet(), hasLength(2));
      for (final result in results) {
        expect((await finish(result['jobId'] as String))['status'], 'sent');
      }
      expect(controller.selectedDevice!.id, 'other');
      expect(
        (await dbB.select(dbB.chatMessages).get()).map((item) => item.body),
        unorderedEquals(['first', 'second']),
      );
    },
  );

  test(
    'compiled CLI sends through the real automation and encrypted transport without SDK on PATH',
    () async {
      final executable = File(
        '${Directory.current.path}/build/cli/localchat-cli.exe',
      );
      final directory = await Directory('${root.path}/LocalChat').create();
      final descriptor = File('${directory.path}/automation.json');
      final service = AutomationService(
        dispatcher: dispatcher,
        publishDescriptor: (contents) async {
          await descriptor.writeAsString(contents);
          return descriptor.path;
        },
        removeDescriptor: () async {
          if (await descriptor.exists()) await descriptor.delete();
        },
      );
      addTearDown(service.stop);
      await service.start();
      final environment = {
        'LOCALAPPDATA': root.path,
        'SystemRoot': Platform.environment['SystemRoot']!,
        'PATH': '',
        'http_proxy': 'http://127.0.0.1:1',
        'https_proxy': 'http://127.0.0.1:1',
        'no_proxy': '',
      };
      final listing = await Process.run(
        executable.path,
        ['devices', '--json'],
        includeParentEnvironment: false,
        environment: environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(listing.exitCode, 0);
      final listed =
          jsonDecode(listing.stdout as String) as Map<String, dynamic>;
      expect(listed['devices'], contains(containsPair('id', target)));
      final send = await Process.run(
        executable.path,
        ['send', '--to', target, '--text', '独立 EXE\n验收', '--json'],
        includeParentEnvironment: false,
        environment: environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(send.exitCode, 0, reason: send.stdout as String);
      expect(
        (jsonDecode(send.stdout as String) as Map<String, dynamic>)['status'],
        'sent',
      );
      expect(
        (await dbB.select(dbB.chatMessages).get()).single.body,
        '独立 EXE\n验收',
      );
      final file = await File('${root.path}/CLI 空 文件.txt').writeAsBytes([]);
      final image = await File(
        '${root.path}/CLI 图片.png',
      ).writeAsBytes([1, 2, 3]);
      final files = await Process.run(
        executable.path,
        [
          'send',
          '--to',
          target,
          '--file',
          file.path,
          '--file',
          image.path,
          '--json',
        ],
        includeParentEnvironment: false,
        environment: environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(files.exitCode, 0, reason: files.stdout as String);
      final sentFiles =
          jsonDecode(files.stdout as String) as Map<String, dynamic>;
      expect(sentFiles['status'], 'sent');
      expect(sentFiles['transferIds'], hasLength(2));
      final folder = await Directory(
        '${root.path}/CLI 目录/sub',
      ).create(recursive: true);
      await File('${folder.path}/nested.txt').writeAsString('nested');
      final queued = await Process.run(
        executable.path,
        [
          'send',
          '--to',
          target,
          '--folder',
          folder.parent.path,
          '--no-wait',
          '--json',
        ],
        includeParentEnvironment: false,
        environment: environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(queued.exitCode, 0, reason: queued.stdout as String);
      final queuedJob =
          jsonDecode(queued.stdout as String) as Map<String, dynamic>;
      final jobId = queuedJob['jobId'] as String;
      expect((await finish(jobId))['status'], 'sent');
      final status = await Process.run(
        executable.path,
        ['status', '--job', jobId, '--json'],
        includeParentEnvironment: false,
        environment: environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(status.exitCode, 0, reason: status.stdout as String);
      expect(
        (jsonDecode(status.stdout as String) as Map<String, dynamic>)['status'],
        'sent',
      );
    },
    skip:
        !Platform.isWindows ||
        !File(
          '${Directory.current.path}/build/cli/localchat-cli.exe',
        ).existsSync(),
  );

  test(
    'zero-byte and Unicode files are persisted as one complete group',
    () async {
      final empty = await File('${root.path}/空 文件.txt').writeAsBytes([]);
      final report = await File('${root.path}/报告.pdf').writeAsString('report');
      final result = await dispatcher.send({
        'target': target,
        'files': [empty.path, report.path],
      });
      expect(result['transferIds'], hasLength(2));
      expect(result['messageIds'], hasLength(2));
      final job = await finish(result['jobId'] as String);
      expect(job['status'], 'sent');
      expect(job['progress'], containsPair('completedItems', 2));
      final received = await dbB.select(dbB.transfers).get();
      expect(received.map((item) => item.fileSize), containsAll([0, 6]));
    },
  );

  test(
    'nested folder preserves relative paths and ignores symbolic links',
    () async {
      final folder = await Directory(
        '${root.path}/输出 目录/sub',
      ).create(recursive: true);
      await File('${folder.parent.path}/根.txt').writeAsString('root');
      await File('${folder.path}/内层.txt').writeAsString('nested');
      if (!Platform.isWindows) {
        await Link('${folder.path}/outside').create(root.path);
      }
      final result = await dispatcher.send({
        'target': target,
        'folder': folder.parent.path,
      });
      final job = await finish(result['jobId'] as String);
      expect(job['status'], 'sent');
      final received = await dbB.select(dbB.transfers).get();
      expect(
        received.map((item) => item.relativePath),
        unorderedEquals(['输出 目录/根.txt', '输出 目录/sub/内层.txt']),
      );
    },
  );

  test('invalid later file prevents the whole batch from enqueueing', () async {
    final file = await File('${root.path}/valid.txt').writeAsString('valid');
    await expectLater(
      dispatcher.send({
        'target': target,
        'files': [file.path, '${root.path}/missing.txt'],
      }),
      throwsA(
        isA<AutomationFailure>().having((e) => e.code, 'code', 'invalid_path'),
      ),
    );
    expect(await dbA.select(dbA.transfers).get(), isEmpty);
    expect(await dbA.select(dbA.chatMessages).get(), isEmpty);
  });

  test(
    'empty folders, conflicting sources and unpaired targets fail clearly',
    () async {
      final empty = await Directory('${root.path}/empty').create();
      await expectLater(
        dispatcher.send({'target': target, 'folder': empty.path}),
        throwsA(
          isA<AutomationFailure>().having(
            (e) => e.code,
            'code',
            'folder_empty',
          ),
        ),
      );
      await expectLater(
        dispatcher.send({'target': target, 'text': 'x', 'files': []}),
        throwsA(isA<AutomationFailure>().having((e) => e.exitCode, 'exit', 2)),
      );
      await (dbA.update(dbA.devices)..where((row) => row.id.equals(target)))
          .write(const DevicesCompanion(trusted: Value(false)));
      await expectLater(
        dispatcher.send({'target': target, 'text': 'x'}),
        throwsA(
          isA<AutomationFailure>().having(
            (e) => e.code,
            'code',
            'target_unpaired',
          ),
        ),
      );
    },
  );

  test('duplicate names return candidate IDs, exact ID wins', () async {
    final peer = (await dbA.getDevice(target))!;
    await dbA.trustDevice(
      id: 'duplicate',
      displayName: peer.displayName,
      platform: peer.platform,
      host: peer.host!,
      port: peer.port!,
      signingPublicKey: peer.signingPublicKey,
      exchangePublicKey: peer.exchangePublicKey,
      fingerprint: peer.fingerprint,
      avatarSeed: peer.avatarSeed,
      avatarColor: peer.avatarColor,
    );
    await expectLater(
      dispatcher.send({'target': peer.displayName, 'text': 'x'}),
      throwsA(
        isA<AutomationFailure>()
            .having((e) => e.code, 'code', 'ambiguous_target')
            .having((e) => e.details['candidates'], 'candidates', hasLength(2)),
      ),
    );
    final result = await dispatcher.send({'target': target, 'text': 'x'});
    expect((await finish(result['jobId'] as String))['status'], 'sent');
  });

  test(
    'identity changes and unreachable peers never create messages',
    () async {
      await (dbA.update(dbA.devices)..where((row) => row.id.equals(target)))
          .write(const DevicesCompanion(identityChanged: Value(true)));
      await expectLater(
        dispatcher.send({'target': target, 'text': 'x'}),
        throwsA(
          isA<AutomationFailure>().having(
            (e) => e.code,
            'code',
            'peer_identity_changed',
          ),
        ),
      );
      await (dbA.update(
        dbA.devices,
      )..where((row) => row.id.equals(target))).write(
        const DevicesCompanion(identityChanged: Value(false), port: Value(1)),
      );
      await expectLater(
        dispatcher.send({'target': target, 'text': 'x'}),
        throwsA(
          isA<AutomationFailure>().having(
            (e) => e.code,
            'code',
            'target_offline',
          ),
        ),
      );
      expect(await dbA.select(dbA.chatMessages).get(), isEmpty);
    },
  );

  test(
    'partial results and restart interruption are derived from persisted records',
    () async {
      final file = await File('${root.path}/one.txt').writeAsString('one');
      final second = await File('${root.path}/two.txt').writeAsString('two');
      final result = await dispatcher.send({
        'target': target,
        'files': [file.path, second.path],
      });
      final id = result['jobId'] as String;
      await finish(id);
      final ids = result['transferIds'] as List<String>;
      await (dbA.update(
        dbA.transfers,
      )..where((row) => row.id.equals(ids.last))).write(
        const TransfersCompanion(
          status: Value('failed'),
          errorCode: Value('connection_lost'),
        ),
      );
      final partial = await dispatcher.job(id);
      expect(partial['status'], 'partial_failure');
      expect(partial['exitCode'], 5);
      expect(
        partial['items'],
        contains(containsPair('errorCode', 'connection_lost')),
      );
      await (dbA.update(dbA.transfers)..where((row) => row.id.isIn(ids))).write(
        const TransfersCompanion(status: Value('queued')),
      );
      await controller.transportService.stop();
      await controller.transportService.start();
      final restarted = AutomationDispatcher(dbA, controller.transportService);
      expect((await restarted.job(id))['status'], 'interrupted');
    },
  );

  test(
    'server is loopback-only, authenticated, rejects browser origins, rotates token',
    () async {
      final descriptor = File('${root.path}/automation.json');
      final service = AutomationService(
        dispatcher: dispatcher,
        publishDescriptor: (contents) async {
          await descriptor.writeAsString(contents);
          return descriptor.path;
        },
        removeDescriptor: () async {
          if (await descriptor.exists()) await descriptor.delete();
        },
      );
      addTearDown(service.stop);
      await service.start();
      final first =
          jsonDecode(await descriptor.readAsString()) as Map<String, dynamic>;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<HttpClientResponse> request({
        String? token,
        String? origin,
        String path = '/v1/devices',
      }) async {
        final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${service.port}$path'),
        );
        if (token != null) req.headers.set('authorization', 'Bearer $token');
        if (origin != null) req.headers.set('origin', origin);
        return req.close();
      }

      final denied = await request(token: 'wrong');
      expect(denied.statusCode, 401);
      await denied.drain<void>();
      final browser = await request(
        token: first['token'] as String,
        origin: 'https://example.com',
      );
      expect(browser.statusCode, 401);
      await browser.drain<void>();
      final allowed = await request(token: first['token'] as String);
      expect(allowed.statusCode, 200);
      final body =
          jsonDecode(await utf8.decoder.bind(allowed).join())
              as Map<String, dynamic>;
      expect(body['devices'], hasLength(1));
      // The actual bound socket is loopback: connecting through a LAN address fails.
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      if (interfaces.isNotEmpty) {
        await expectLater(
          Socket.connect(
            interfaces.first.addresses.first,
            service.port!,
            timeout: const Duration(seconds: 1),
          ),
          throwsA(isA<SocketException>()),
        );
      }
      await service.stop();
      expect(await descriptor.exists(), isFalse);
      await service.start();
      final second =
          jsonDecode(await descriptor.readAsString()) as Map<String, dynamic>;
      expect(second['token'], isNot(first['token']));
    },
  );
}
