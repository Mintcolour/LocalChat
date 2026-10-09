import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/core/peer_status.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/services/diagnostic_log_service.dart';
import 'package:localchat/services/file_store.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/peer_http_client.dart';
import 'package:localchat/services/peer_presence_monitor.dart';
import 'package:localchat/services/security_service.dart';
import 'package:localchat/services/transport_service.dart';
import 'package:localchat/ui/banners.dart';

class _Store extends FileStore {
  _Store(this.root);
  final Directory root;
  @override
  Future<Directory> receiveDirectory() async => root;
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

class _Logger implements DiagnosticLogger {
  final events = <({String event, Map<String, Object?> fields})>[];
  @override
  void info(String event, [Map<String, Object?> fields = const {}]) =>
      events.add((event: event, fields: fields));
  @override
  void warning(String event, [Map<String, Object?> fields = const {}]) =>
      info(event, fields);
  @override
  void error(String event, Object error, [StackTrace? stackTrace]) =>
      info(event, {'error': '$error'});
}

class _ProxyOverride extends HttpOverrides {
  _ProxyOverride(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase dbA, dbB;
  late TransportService sender, receiver;
  late LocalIdentity a, b;
  late Directory root;
  late _Logger logger;
  late DateTime now;

  setUp(() async {
    // The widget binding's fake HTTP client would hide real TCP regressions.
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('localchat-connectivity-');
    dbA = AppDatabase(NativeDatabase.memory());
    dbB = AppDatabase(NativeDatabase.memory());
    final identityA = IdentityService(dbA);
    final identityB = IdentityService(dbB);
    a = await identityA.load();
    b = await identityB.load();
    now = DateTime.now();
    logger = _Logger();
    sender = TransportService(
      dbA,
      identityA,
      SecurityService(identityA),
      _Store(root),
      logger: logger,
      now: () => now,
      probeTimeout: const Duration(milliseconds: 250),
    );
    receiver = TransportService(
      dbB,
      identityB,
      SecurityService(identityB),
      _Store(root),
    );
    sender.autoCopyReceivedText = receiver.autoCopyReceivedText = false;
    await sender.start();
    await receiver.start();
    Future<void> trust(AppDatabase db, LocalIdentity identity, int port) =>
        db.trustDevice(
          id: identity.deviceId,
          displayName: identity.displayName,
          platform: identity.platform,
          host: '127.0.0.1',
          port: port,
          signingPublicKey: identity.signingPublicKey,
          exchangePublicKey: identity.exchangePublicKey,
          fingerprint: identity.fingerprint,
          avatarSeed: identity.avatarSeed,
          avatarColor: identity.avatarColor,
          capabilities: ['text', 'files', encryptedStreamCapability],
        );
    await trust(dbA, b, receiver.port);
    await trust(dbB, a, sender.port);
  });
  tearDown(() async {
    await sender.stop();
    await receiver.stop();
    await dbA.close();
    await dbB.close();
    // This directory was created for this test, with no user data.
    await root.delete(recursive: true);
  });
  Future<Device> target() async => (await dbA.getDevice(b.deviceId))!;
  Future<HttpServer> serverWith(
    Future<void> Function(HttpRequest) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    addTearDown(() => server.close(force: true));
    await dbA.updateDeviceEndpoint(
      id: b.deviceId,
      host: '127.0.0.1',
      port: server.port,
    );
    return server;
  }

  Future<void> stale() async {
    await (dbA.update(
      dbA.devices,
    )..where((t) => t.id.equals(b.deviceId))).write(
      DevicesCompanion(
        lastSeen: Value(now.subtract(const Duration(minutes: 1))),
      ),
    );
  }

  test(
    'peer client bypasses a failing proxy and logs no payload or credentials',
    () async {
      var proxyRequests = 0;
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      proxy.listen((request) async {
        proxyRequests++;
        request.response.statusCode = 502;
        await request.response.close();
      });
      addTearDown(() => proxy.close(force: true));
      await HttpOverrides.runWithHttpOverrides(() async {
        final defaultClient = HttpClient();
        final baseline = await (await defaultClient.getUrl(
          Uri.parse('http://127.0.0.1:${receiver.port}/v1/hello'),
        )).close();
        expect(baseline.statusCode, 502);
        await baseline.drain<void>();
        defaultClient.close(force: true);
        final peerClient = createPeerHttpClient(logger);
        addTearDown(() => peerClient.close(force: true));
        final response = await peerClient.get(
          'http://127.0.0.1:${receiver.port}/v1/hello?private=secret',
          options: Options(headers: {'Authorization': 'secret'}),
        );
        expect(response.statusCode, 200);
      }, _ProxyOverride(proxy.port));
      expect(proxyRequests, 1);
      final serialized = jsonEncode(
        logger.events.map((e) => {'event': e.event, ...e.fields}).toList(),
      );
      expect(serialized, isNot(contains('secret')));
      expect(serialized, isNot(contains('signing_public_key')));
      expect(logger.events.last.fields['routing'], 'direct');
      expect(logger.events.last.fields['elapsedMs'], isA<int>());
    },
  );

  test(
    'ordinary 502 does not immediately mark a recently active peer offline',
    () async {
      await serverWith((request) async {
        request.response.statusCode = 502;
        await request.response.close();
      });
      final peer = await target();
      expect(await sender.checkPeer(peer), isFalse);
      expect(isPeerOnline(await target(), now: now), isTrue);
      now = now.add(const Duration(seconds: 20));
      await sender.checkPeer(await target());
      await sender.checkPeer(await target());
      expect(isPeerOnline(await target(), now: now), isTrue);
      expect((await target()).lastSeen, isNotNull);
      expect(
        logger.events.any(
          (e) =>
              e.event == 'transport.request_failed' &&
              e.fields['httpStatus'] == 502 &&
              e.fields['path'] == '/v1/hello',
        ),
        isTrue,
      );
    },
  );

  test(
    'three failed probes expire a stale peer and success resets the failure count',
    () async {
      var failHello = true;
      await serverWith((request) async {
        request.response.statusCode = failHello ? 502 : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'device_id': b.deviceId,
            'public_key_fingerprint': b.fingerprint,
            'signing_public_key': b.signingPublicKey,
            'exchange_public_key': b.exchangePublicKey,
          }),
        );
        await request.response.close();
      });
      await stale();
      await sender.checkPeer(await target());
      await sender.checkPeer(await target());
      expect((await target()).lastSeen, isNotNull);
      failHello = false;
      expect(await sender.checkPeer(await target()), isTrue);
      failHello = true;
      now = now.add(const Duration(minutes: 1));
      await sender.checkPeer(await target());
      await sender.checkPeer(await target());
      expect((await target()).lastSeen, isNotNull);
      await sender.checkPeer(await target());
      expect((await target()).lastSeen, isNull);
    },
  );

  test(
    'late probe failure cannot erase a newer encrypted inbound message',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      await serverWith((request) async {
        entered.complete();
        await release.future;
        request.response.statusCode = 502;
        await request.response.close();
      });
      await stale();
      final pending = sender.checkPeer(await target());
      await entered.future;
      await receiver.sendText(
        (await dbB.getDevice(a.deviceId))!,
        'new activity',
      );
      final revision = dbA.peerActivityRevision(b.deviceId);
      release.complete();
      expect(await pending, isFalse);
      expect(dbA.peerActivityRevision(b.deviceId), revision);
      expect(isPeerOnline(await target(), now: DateTime.now()), isTrue);
      expect((await target()).port, receiver.port);
      expect(
        logger.events.where((e) => e.event == 'presence.probe_failed'),
        isEmpty,
      );
    },
  );

  test('stalled hello uses the short probe timeout', () async {
    await serverWith((request) async {});
    final stopwatch = Stopwatch()..start();
    expect(await sender.checkPeer(await target()), isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(isPeerOnline(await target(), now: now), isTrue);
  });

  test('changed public keys block online status and sending', () async {
    final otherDb = AppDatabase(NativeDatabase.memory());
    addTearDown(otherDb.close);
    final other = await IdentityService(otherDb).load();
    await serverWith((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'device_id': b.deviceId,
          'public_key_fingerprint': b.fingerprint,
          'signing_public_key': b.signingPublicKey,
          'exchange_public_key': other.exchangePublicKey,
        }),
      );
      await request.response.close();
    });
    expect(await sender.checkPeer(await target()), isFalse);
    expect((await target()).identityChanged, isTrue);
    expect(isPeerOnline(await target(), now: now), isFalse);
    await expectLater(
      sender.sendText(await target(), 'blocked'),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'manual endpoints refresh activity without changing the user address',
    () async {
      final peer = await target();
      await (dbA.update(dbA.devices)..where((t) => t.id.equals(peer.id))).write(
        const DevicesCompanion(endpointSource: Value('manual')),
      );
      await dbA.markDeviceOffline(peer.id);
      await dbA.updateDeviceEndpoint(
        id: peer.id,
        host: '10.10.10.10',
        port: 54321,
      );
      final updated = await target();
      expect(updated.host, peer.host);
      expect(updated.port, peer.port);
      expect(updated.lastSeen, isNotNull);
      await sender.sendText(updated, 'manual outbound');
      await receiver.sendText(
        (await dbB.getDevice(a.deviceId))!,
        'manual inbound',
      );
      expect((await target()).host, peer.host);
      expect(isPeerOnline(await target()), isTrue);
    },
  );

  test(
    'invalid hello identity is pinned as changed and cannot be revived by discovery',
    () async {
      await serverWith((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'device_id': b.deviceId,
            'public_key_fingerprint': b.fingerprint,
            'signing_public_key': 'invalid-signing-key',
            'exchange_public_key': b.exchangePublicKey,
          }),
        );
        await request.response.close();
      });
      expect(await sender.checkPeer(await target()), isFalse);
      expect((await target()).identityChanged, isTrue);
      await dbA.upsertDiscoveredDevice(
        id: b.deviceId,
        displayName: b.displayName,
        platform: b.platform,
        host: '127.0.0.1',
        port: receiver.port,
        signingPublicKey: b.signingPublicKey,
        exchangePublicKey: b.exchangePublicKey,
        fingerprint: b.fingerprint,
        avatarSeed: b.avatarSeed,
        avatarColor: b.avatarColor,
      );
      expect(isPeerOnline(await target()), isFalse);
      expect((await target()).signingPublicKey, b.signingPublicKey);
      await expectLater(
        sender.sendText(await target(), 'blocked'),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    'alternate UDP addresses do not replace a recently verified endpoint',
    () async {
      expect(await sender.checkPeer(await target()), isTrue);
      Future<void> discover() => dbA.upsertDiscoveredDevice(
        id: b.deviceId,
        displayName: b.displayName,
        platform: b.platform,
        host: '192.168.145.8',
        port: 45678,
        signingPublicKey: b.signingPublicKey,
        exchangePublicKey: b.exchangePublicKey,
        fingerprint: b.fingerprint,
        avatarSeed: b.avatarSeed,
        avatarColor: b.avatarColor,
        seenAt: now,
      );
      await discover();
      expect((await target()).host, '127.0.0.1');
      now = now.add(const Duration(seconds: 31));
      await discover();
      expect((await target()).host, '192.168.145.8');
    },
  );

  test(
    'multi-chunk encrypted file and bidirectional Unicode text reach the peer',
    () async {
      await sender.sendText(await target(), '中文 🌙\nsecond line');
      await receiver.sendText((await dbB.getDevice(a.deviceId))!, '回复');
      final file = File('${root.path}/large.bin');
      final size = int.parse(
        Platform.environment['LOCALCHAT_TEST_FILE_BYTES'] ??
            '${12 * 1024 * 1024 + 73}',
      );
      final bytes = Uint8List(size);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i % 251;
      }
      await file.writeAsBytes(bytes);
      final receipt = await sender.sendPreparedFilesWithReceipt(
        await target(),
        [(absolute: file.path, relative: null)],
      );
      final timer = Stopwatch()..start();
      Transfer? sent;
      while (timer.elapsed < const Duration(minutes: 2)) {
        sent = (await dbA.listTransfersByIds(receipt.transferIds)).single;
        if (sent.status == 'sent' || sent.status == 'failed') break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(sent?.status, 'sent');
      final received = (await dbB.listTransfersByIds(
        receipt.transferIds,
      )).single;
      final receivedHash = await crypto.sha256
          .bind(File(received.savedPath!).openRead())
          .first;
      final sentHash = await crypto.sha256.bind(file.openRead()).first;
      expect(receivedHash, sentHash);
      expect(await File(received.savedPath!).length(), size);
      expect(isPeerOnline(await target()), isTrue);
      final eventText = jsonEncode(logger.events.map((e) => e.fields).toList());
      expect(eventText, isNot(contains('中文')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('failed queued file retains the HTTP status for its own task', () async {
    await serverWith((request) async {
      request.response.statusCode = 502;
      await request.response.close();
    });
    final file = File('${root.path}/not-sent.bin');
    await file.writeAsBytes([1, 2, 3]);
    final receipt = await sender.sendPreparedFilesWithReceipt(await target(), [
      (absolute: file.path, relative: null),
    ]);
    final timer = Stopwatch()..start();
    Transfer? task;
    while (timer.elapsed < const Duration(seconds: 5)) {
      task = (await dbA.listTransfersByIds(receipt.transferIds)).single;
      if (task.status == 'failed') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(task?.status, 'failed');
    expect(task?.errorCode, 'peer_http_502');
    expect(isPeerOnline(await target(), now: now), isTrue);
  });

  test(
    'bounded presence workers reach healthy peers while others are pending and never overlap',
    () async {
      final monitor = PeerPresenceMonitor();
      final peers = [
        for (var i = 0; i < 8; i++) (await target()).copyWith(id: '$i'),
      ];
      final gate = Completer<void>();
      var active = 0, maximum = 0, rounds = 0;
      final started = <String>[];
      Future<bool> check(Device peer) async {
        active++;
        if (active > maximum) maximum = active;
        started.add(peer.id);
        if (int.parse(peer.id) < 3) await gate.future;
        active--;
        return true;
      }

      Future<void> run() => monitor.refresh(
        loadPeers: () async => peers,
        checkPeer: check,
        onComplete: () async {
          rounds++;
        },
      );
      final pending = run();
      await Future<void>.delayed(Duration.zero);
      expect(started, containsAll(['3', '4', '5', '6', '7']));
      await run();
      expect(started, hasLength(8));
      expect(maximum, 4);
      gate.complete();
      await pending;
      expect(rounds, 1);
      monitor.stop();
      await run();
      expect(rounds, 1);
    },
  );

  testWidgets(
    '502 send failure is scoped and a later successful result hides the old error',
    (tester) async {
      final controller = AppController(database: dbA, fileStore: _Store(root));
      // The fixture owns dbA; avoid disposing a second database owner here.
      await tester.runAsync(() async {
        await serverWith((request) async {
          request.response.statusCode = 502;
          await request.response.close();
        });
        await controller.identityService.load();
        controller.selectedDevice = await target();
        controller.selectedConversation = await dbA.ensureConversation(
          await target(),
        );
        await controller.sendText('not delivered');
        expect(controller.status, contains('HTTP 502'));
        expect(controller.status, isNot(contains('DioException')));
        await dbA.updateDeviceEndpoint(
          id: b.deviceId,
          host: '127.0.0.1',
          port: receiver.port,
        );
        await controller.sendText('delivered');
      });
      expect(controller.status, contains('已发送'));
      expect(controller.lastError, isNull);
      controller.lastError = 'old failure';
      controller.status = '收到文字，已复制到剪贴板';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StatusBar(controller: controller)),
        ),
      );
      expect(find.text('收到文字，已复制到剪贴板'), findsOneWidget);
      expect(find.textContaining('old failure'), findsNothing);
    },
  );
}
