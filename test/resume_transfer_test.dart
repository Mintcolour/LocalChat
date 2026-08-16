import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/services/file_store.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/security_service.dart';
import 'package:localchat/services/transport_service.dart';
import 'package:localchat/services/transport/frame_codec.dart';

class _TestFileStore extends FileStore {
  _TestFileStore(this.root);

  final Directory root;

  @override
  Future<Directory> receiveDirectory() async {
    final dir = Directory('${root.path}${Platform.pathSeparator}incoming');
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<SavedFile> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    required String conversationFolder,
    required DateTime at,
    String? relativePath,
    bool moveSource = false,
  }) async {
    return SavedFile(path: sourcePath, actualFileName: fileName);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase dbA;
  late AppDatabase dbB;
  late IdentityService identityA;
  late IdentityService identityB;
  late SecurityService securityA;
  late TransportService transportA;
  late TransportService transportB;
  late Directory rootA;
  late Directory rootB;
  late Device peerA;
  late Device peerB;
  late dio.Dio client;

  setUp(() async {
    dbA = AppDatabase(NativeDatabase.memory());
    dbB = AppDatabase(NativeDatabase.memory());
    identityA = IdentityService(dbA);
    identityB = IdentityService(dbB);
    securityA = SecurityService(identityA);
    rootA = await Directory.systemTemp.createTemp('localchat-resume-a');
    rootB = await Directory.systemTemp.createTemp('localchat-resume-b');
    transportA = TransportService(
      dbA,
      identityA,
      SecurityService(identityA),
      _TestFileStore(rootA),
    );
    transportB = TransportService(
      dbB,
      identityB,
      SecurityService(identityB),
      _TestFileStore(rootB),
    );
    final localA = await identityA.load();
    final localB = await identityB.load();
    final portA = await transportA.start();
    final portB = await transportB.start();
    Device deviceOf(LocalIdentity local, int port) => Device(
          id: local.deviceId,
          displayName: local.displayName,
          platform: local.platform,
          host: '127.0.0.1',
          port: port,
          signingPublicKey: local.signingPublicKey,
          exchangePublicKey: local.exchangePublicKey,
          fingerprint: local.fingerprint,
          avatarSeed: local.avatarSeed,
          avatarColor: local.avatarColor,
          trusted: true,
          endpointSource: 'auto',
          lastSeen: DateTime.now(),
          createdAt: DateTime.now(),
        );
    peerA = deviceOf(localA, portA);
    peerB = deviceOf(localB, portB);
    for (final entry in {dbA: peerB, dbB: peerA}.entries) {
      await entry.key.trustDevice(
        id: entry.value.id,
        displayName: entry.value.displayName,
        platform: entry.value.platform,
        host: entry.value.host!,
        port: entry.value.port!,
        signingPublicKey: entry.value.signingPublicKey,
        exchangePublicKey: entry.value.exchangePublicKey,
        fingerprint: entry.value.fingerprint,
        avatarSeed: entry.value.avatarSeed,
        avatarColor: entry.value.avatarColor,
      );
    }
    client = dio.Dio();
  });

  tearDown(() async {
    await transportA.stop();
    await transportB.stop();
    await dbA.close();
    await dbB.close();
    await rootA.delete(recursive: true);
    await rootB.delete(recursive: true);
  });

  /// 以 A 的身份发送安全信封请求到 B，返回解析后的响应体。
  Future<Map<String, Object?>> postSecure(
    String path,
    Map<String, Object?> payload,
  ) async {
    final envelope = await securityA.seal(peerB, {
      ...payload,
      'sender_listen_port': transportA.port,
    });
    final response = await client.post<Map<String, dynamic>>(
      'http://127.0.0.1:${transportB.port}$path',
      data: envelope,
    );
    return Map<String, Object?>.from(response.data!);
  }

  test('start 协商 resume_offset 且 stream 按偏移追加续写', () async {
    final chunkSize = encryptedStreamChunkSize;
    final payload = List<int>.generate(10 * 1024 * 1024, (i) => i % 251);
    final temp = File('${rootB.path}${Platform.pathSeparator}resume-t1.tmp');
    await temp.writeAsBytes(payload.sublist(0, chunkSize));
    final now = DateTime.now();
    await dbB.into(dbB.transfers).insert(
          TransfersCompanion.insert(
            id: 'resume-t1',
            peerDeviceId: peerA.id,
            direction: 'in',
            fileName: 'resume-src.bin',
            filePath: Value(temp.path),
            fileSize: payload.length,
            status: 'failed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await (dbB.update(
      dbB.transfers,
    )..where((tbl) => tbl.id.equals('resume-t1'))).write(
      TransfersCompanion(receivedBytes: Value(chunkSize)),
    );

    // 同 id 重新 start：应回报 resume_offset = 已收 4MB，且不新增消息。
    final start = await postSecure('/v1/transfers', {
      'id': 'resume-t1',
      'file_name': 'resume-src.bin',
      'file_size': payload.length,
      'total_chunks': 3,
      'chunk_size': chunkSize,
      'stream_version': encryptedStreamVersion,
    });
    expect(start['resume_offset'], chunkSize);
    expect((start['capabilities'] as List).contains(resumeCapability), isTrue);
    expect(
      await (dbB.select(
        dbB.chatMessages,
      )..where((tbl) => tbl.transferId.equals('resume-t1'))).get(),
      isEmpty,
      reason: '续传 start 不应重复生成消息',
    );

    // 偏移与临时文件不符 → 409。
    final badHeaders = await securityA.streamAuthHeaders(peerB, 'resume-t1');
    final badResponse = await client.postUri(
      Uri.parse(
        'http://127.0.0.1:${transportB.port}'
        '/v1/transfers/resume-t1/stream?offset=${chunkSize + 123}',
      ),
      data: <int>[],
      options: dio.Options(
        headers: badHeaders,
        contentType: 'application/octet-stream',
        validateStatus: (status) => true,
      ),
    );
    expect(badResponse.statusCode, 409);

    // 从 4MB 偏移续传剩余两个分块。
    final headers = await securityA.streamAuthHeaders(peerB, 'resume-t1');
    final midChunk = await securityA.encryptFileChunk(
      peerB,
      1,
      payload.sublist(chunkSize, chunkSize * 2),
    );
    final tailChunk = await securityA.encryptFileChunk(
      peerB,
      2,
      payload.sublist(chunkSize * 2),
    );
    final body = BytesBuilder()
      ..add(encodeFrame(midChunk))
      ..add(encodeFrame(tailChunk));
    final streamResponse = await client.postUri<Map<String, dynamic>>(
      Uri.parse(
        'http://127.0.0.1:${transportB.port}'
        '/v1/transfers/resume-t1/stream?offset=$chunkSize',
      ),
      data: body.takeBytes(),
      options: dio.Options(
        headers: headers,
        contentType: 'application/octet-stream',
      ),
    );
    expect(streamResponse.statusCode, 200);
    expect(streamResponse.data!['received_bytes'], payload.length);
    expect(await temp.length(), payload.length);
    expect(await temp.readAsBytes(), payload);

    // complete 校验整体 SHA-256 通过后标记 received。
    final digest = crypto.sha256.convert(payload).toString();
    final complete = await postSecure('/v1/transfers/resume-t1/complete', {
      'id': 'resume-t1',
      'sha256': digest,
    });
    expect(complete['ok'], isTrue);
    final row = await (dbB.select(
      dbB.transfers,
    )..where((tbl) => tbl.id.equals('resume-t1'))).getSingle();
    expect(row.status, 'received');
    expect(row.receivedBytes, payload.length);
  });

  test('retryFile 复用 transfer id 并端到端续传', () async {
    final payload = List<int>.generate(10 * 1024 * 1024, (i) => (i * 7) % 256);
    final source = File('${rootA.path}${Platform.pathSeparator}resume-e2e.bin');
    await source.writeAsBytes(payload);
    await transportA.sendFiles(peerB, [source.path]);
    final transferId = await _waitFor(() async {
      final rows = await dbA.select(dbA.transfers).get();
      return rows.isNotEmpty ? rows.first.id : null;
    });
    await _waitFor(() async {
      final row = await (dbA.select(
        dbA.transfers,
      )..where((tbl) => tbl.id.equals(transferId))).getSingle();
      return row.status == 'sent' ? row.status : null;
    });

    // 模拟接收端传输中断：行状态 failed、只保留首个 4MB 分块。
    final chunkSize = encryptedStreamChunkSize;
    final tempRow = await (dbB.select(
      dbB.transfers,
    )..where((tbl) => tbl.id.equals(transferId))).getSingle();
    final tempFile = File(tempRow.filePath!);
    expect(await tempFile.length(), payload.length);
    await tempFile.writeAsBytes(payload.sublist(0, chunkSize));
    await (dbB.update(
      dbB.transfers,
    )..where((tbl) => tbl.id.equals(transferId))).write(
      TransfersCompanion(
        status: const Value('failed'),
        receivedBytes: Value(chunkSize),
      ),
    );

    // 发送端重试：应复用同 id，从接收端 4MB 处继续。
    final message = (await (dbA.select(
      dbA.chatMessages,
    )..where((tbl) => tbl.transferId.equals(transferId))).get()).single;
    final transfer = (await (dbA.select(
      dbA.transfers,
    )..where((tbl) => tbl.id.equals(transferId))).get()).single;
    await transportA.retryFile(peerB, message, transfer);

    final retriedMessage = (await (dbA.select(
      dbA.chatMessages,
    )..where((tbl) => tbl.id.equals(message.id))).get()).single;
    expect(retriedMessage.status, 'sent');
    expect(retriedMessage.transferId, transferId, reason: '重试应复用原 id');
    expect(await tempFile.length(), payload.length);
    expect(await tempFile.readAsBytes(), payload);

    // 续传不重复生成接收消息。
    final bMessages = await (dbB.select(
      dbB.chatMessages,
    )..where((tbl) => tbl.transferId.equals(transferId))).get();
    expect(bMessages, hasLength(1));
    final bRow = await (dbB.select(
      dbB.transfers,
    )..where((tbl) => tbl.id.equals(transferId))).getSingle();
    expect(bRow.status, 'received');
  });
}

Future<T> _waitFor<T>(
  Future<T?> Function() probe, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final value = await probe();
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('condition not met before timeout');
}
