import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:drift/drift.dart' hide JsonKey;
import 'package:crypto/crypto.dart' as crypto;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/protocol.dart';
import 'file_store.dart';
import 'identity_service.dart';
import 'security_service.dart';

class TransportService {
  TransportService(
    this._db,
    this._identityService,
    this._securityService,
    this._fileStore,
  );

  final AppDatabase _db;
  final IdentityService _identityService;
  final SecurityService _securityService;
  final FileStore _fileStore;
  final _dio = dio.Dio(
    dio.BaseOptions(connectTimeout: const Duration(seconds: 5)),
  );
  final _uuid = const Uuid();
  final _updates = StreamController<void>.broadcast();
  HttpServer? _server;
  int _port = 0;
  Future<Device?> Function(String deviceId)? reconnectPeer;

  int get port => _port;
  Stream<void> get updates => _updates.stream;

  Future<int> start() async {
    if (_server != null) return _port;
    final router = Router()
      ..get('/v1/hello', _hello)
      ..post('/v1/pair/request', _pairRequest)
      ..post('/v1/pair/confirm', _pairConfirm)
      ..post('/v1/messages', _receiveMessage)
      ..post('/v1/transfers', _receiveTransferStart)
      ..put('/v1/transfers/<id>/chunks/<index>', _receiveTransferChunk)
      ..post('/v1/transfers/<id>/complete', _receiveTransferComplete);
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    _port = _server!.port;
    return _port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  Future<Response> _hello(Request request) async {
    final identity = _identityService.identity;
    return _json({
      'protocol_version': protocolVersion,
      'device_id': identity.deviceId,
      'display_name': identity.displayName,
      'platform': identity.platform,
      'listen_port': _port,
      'signing_public_key': identity.signingPublicKey,
      'exchange_public_key': identity.exchangePublicKey,
      'public_key_fingerprint': identity.fingerprint,
    });
  }

  Future<Response> _pairRequest(Request request) async {
    final body = await _readJson(request);
    final deviceId = body['device_id'];
    final code = body['code'];
    if (deviceId is! String || code is! String) {
      return Response.badRequest(body: 'Invalid pair request');
    }
    final host = _remoteHost(request) ?? request.requestedUri.host;
    final port = body['listen_port'] is int ? body['listen_port'] as int : 0;
    await _db.trustDevice(
      id: deviceId,
      displayName: _string(body['display_name'], 'Unknown'),
      platform: _string(body['platform'], 'unknown'),
      host: host,
      port: port,
      signingPublicKey: _string(body['signing_public_key'], ''),
      exchangePublicKey: _string(body['exchange_public_key'], ''),
      fingerprint: _string(body['public_key_fingerprint'], ''),
    );
    final identity = _identityService.identity;
    _updates.add(null);
    return _json({
      'accepted': true,
      'code': code,
      'device_id': identity.deviceId,
      'display_name': identity.displayName,
      'platform': identity.platform,
      'listen_port': _port,
      'signing_public_key': identity.signingPublicKey,
      'exchange_public_key': identity.exchangePublicKey,
      'public_key_fingerprint': identity.fingerprint,
    });
  }

  Future<Response> _pairConfirm(Request request) async {
    return _json({'accepted': true});
  }

  Future<void> pairWith(Device peer, String code) async {
    if (peer.host == null || peer.port == null) {
      throw StateError('Peer endpoint is not known.');
    }
    final identity = _identityService.identity;
    final response = await _dio.postUri<Map<String, dynamic>>(
      Uri.parse('http://${peer.host}:${peer.port}/v1/pair/request'),
      data: {
        'device_id': identity.deviceId,
        'display_name': identity.displayName,
        'platform': identity.platform,
        'listen_port': _port,
        'signing_public_key': identity.signingPublicKey,
        'exchange_public_key': identity.exchangePublicKey,
        'public_key_fingerprint': identity.fingerprint,
        'code': code,
      },
    );
    final data = response.data;
    if (data == null || data['accepted'] != true || data['code'] != code) {
      throw StateError('Pairing was rejected or the code did not match.');
    }
    await _db.trustDevice(
      id: _string(data['device_id'], peer.id),
      displayName: _string(data['display_name'], peer.displayName),
      platform: _string(data['platform'], peer.platform),
      host: peer.host!,
      port: peer.port!,
      signingPublicKey: _string(
        data['signing_public_key'],
        peer.signingPublicKey,
      ),
      exchangePublicKey: _string(
        data['exchange_public_key'],
        peer.exchangePublicKey,
      ),
      fingerprint: _string(data['public_key_fingerprint'], peer.fingerprint),
    );
    _updates.add(null);
  }

  Future<void> sendText(Device peer, String text) async {
    final currentPeer = await _freshPeer(peer);
    final conversation = await _db.ensureConversation(currentPeer);
    final messageId = _uuid.v4();
    await _db.addMessage(
      ChatMessagesCompanion.insert(
        id: messageId,
        conversationId: conversation.id,
        peerDeviceId: currentPeer.id,
        direction: 'out',
        kind: Uri.tryParse(text)?.hasAbsolutePath == true ? 'link' : 'text',
        body: Value(text),
        status: 'sending',
        createdAt: DateTime.now(),
      ),
    );
    _updates.add(null);
    try {
      await _postSecure(currentPeer, '/v1/messages', {
        'id': messageId,
        'kind': 'text',
        'body': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _db.addMessage(
        ChatMessagesCompanion.insert(
          id: messageId,
          conversationId: conversation.id,
          peerDeviceId: currentPeer.id,
          direction: 'out',
          kind: 'text',
          body: Value(text),
          status: 'sent',
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      await _db.addMessage(
        ChatMessagesCompanion.insert(
          id: messageId,
          conversationId: conversation.id,
          peerDeviceId: currentPeer.id,
          direction: 'out',
          kind: 'text',
          body: Value(text),
          status: 'failed',
          createdAt: DateTime.now(),
        ),
      );
      rethrow;
    } finally {
      _updates.add(null);
    }
  }

  Future<void> sendFiles(Device peer, List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      await _sendFile(peer, file);
    }
  }

  Future<void> _sendFile(Device peer, File file) async {
    final currentPeer = await _freshPeer(peer);
    final length = await file.length();
    final transferId = _uuid.v4();
    final conversation = await _db.ensureConversation(currentPeer);
    final name = p.basename(file.path);
    final sha = await _sha256File(file);
    final totalChunks = (length / defaultTransferChunkSize).ceil();
    await _db
        .into(_db.transfers)
        .insertOnConflictUpdate(
          TransfersCompanion.insert(
            id: transferId,
            peerDeviceId: currentPeer.id,
            direction: 'out',
            fileName: name,
            fileSize: length,
            filePath: Value(file.path),
            sha256: Value(sha),
            status: 'sending',
            totalChunks: Value(totalChunks),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    await _db.addMessage(
      ChatMessagesCompanion.insert(
        id: _uuid.v4(),
        conversationId: conversation.id,
        peerDeviceId: currentPeer.id,
        direction: 'out',
        kind: 'file',
        fileName: Value(name),
        filePath: Value(file.path),
        fileSize: Value(length),
        status: 'sending',
        transferId: Value(transferId),
        createdAt: DateTime.now(),
      ),
    );
    _updates.add(null);
    try {
      await _postSecure(currentPeer, '/v1/transfers', {
        'id': transferId,
        'file_name': name,
        'file_size': length,
        'sha256': sha,
        'mime_type': lookupMimeType(file.path),
        'total_chunks': totalChunks,
      });
      final stream = file.openRead();
      var buffer = BytesBuilder(copy: false);
      var index = 0;
      var sent = 0;
      await for (final part in stream) {
        buffer.add(part);
        while (buffer.length >= defaultTransferChunkSize) {
          final chunk = buffer.takeBytes();
          await _sendChunk(
            currentPeer,
            transferId,
            index,
            Uint8List.fromList(chunk.take(defaultTransferChunkSize).toList()),
          );
          final rest = chunk.skip(defaultTransferChunkSize).toList();
          if (rest.isNotEmpty) {
            buffer.add(rest);
          }
          index++;
          sent += defaultTransferChunkSize;
          await _markTransferProgress(transferId, sent.clamp(0, length));
        }
      }
      final tail = buffer.takeBytes();
      if (tail.isNotEmpty || length == 0) {
        await _sendChunk(currentPeer, transferId, index, tail);
      }
      await _postSecure(currentPeer, '/v1/transfers/$transferId/complete', {
        'id': transferId,
        'sha256': sha,
      });
      await _markTransferStatus(transferId, 'sent', length);
    } catch (_) {
      await _markTransferStatus(transferId, 'failed', 0);
      rethrow;
    } finally {
      _updates.add(null);
    }
  }

  Future<void> _sendChunk(
    Device peer,
    String transferId,
    int index,
    List<int> bytes,
  ) async {
    await _postSecure(peer, '/v1/transfers/$transferId/chunks/$index', {
      'transfer_id': transferId,
      'index': index,
      'bytes': b64(bytes),
      'length': bytes.length,
    }, method: 'put');
  }

  Future<Response> _receiveMessage(Request request) =>
      _withTrustedEnvelope(request, (peer, payload) async {
        final conversation = await _db.ensureConversation(peer);
        await _db.addMessage(
          ChatMessagesCompanion.insert(
            id: _string(payload['id'], _uuid.v4()),
            conversationId: conversation.id,
            peerDeviceId: peer.id,
            direction: 'in',
            kind: _string(payload['kind'], 'text'),
            body: Value(_string(payload['body'], '')),
            status: 'received',
            createdAt:
                DateTime.tryParse(_string(payload['created_at'], '')) ??
                DateTime.now(),
          ),
        );
        _updates.add(null);
        return _json({'ok': true});
      });

  Future<Response> _receiveTransferStart(Request request) =>
      _withTrustedEnvelope(request, (peer, payload) async {
        final file = await _fileStore.createReceiveFile(
          _string(payload['file_name'], 'received.bin'),
        );
        final id = _string(payload['id'], _uuid.v4());
        await _db
            .into(_db.transfers)
            .insertOnConflictUpdate(
              TransfersCompanion.insert(
                id: id,
                peerDeviceId: peer.id,
                direction: 'in',
                fileName: _string(payload['file_name'], p.basename(file.path)),
                filePath: Value(file.path),
                fileSize: _int(payload['file_size']),
                sha256: Value(_nullableString(payload['sha256'])),
                status: 'receiving',
                totalChunks: Value(_int(payload['total_chunks'])),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        final conversation = await _db.ensureConversation(peer);
        await _db.addMessage(
          ChatMessagesCompanion.insert(
            id: _uuid.v4(),
            conversationId: conversation.id,
            peerDeviceId: peer.id,
            direction: 'in',
            kind: 'file',
            fileName: Value(
              _string(payload['file_name'], p.basename(file.path)),
            ),
            filePath: Value(file.path),
            fileSize: Value(_int(payload['file_size'])),
            status: 'receiving',
            transferId: Value(id),
            createdAt: DateTime.now(),
          ),
        );
        _updates.add(null);
        return _json({'ok': true, 'path': file.path});
      });

  Future<Response> _receiveTransferChunk(
    Request request,
    String id,
    String index,
  ) => _withTrustedEnvelope(request, (peer, payload) async {
    final transfer = await (_db.select(
      _db.transfers,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (transfer == null || transfer.filePath == null) {
      return Response.notFound('Transfer not found');
    }
    final bytes = unb64(_string(payload['bytes'], ''));
    final sink = File(transfer.filePath!).openWrite(mode: FileMode.append);
    sink.add(bytes);
    await sink.close();
    final received = transfer.receivedBytes + bytes.length;
    await _markTransferProgress(id, received);
    _updates.add(null);
    return _json({'ok': true, 'received_bytes': received});
  });

  Future<Response> _receiveTransferComplete(Request request, String id) =>
      _withTrustedEnvelope(request, (peer, payload) async {
        final transfer = await (_db.select(
          _db.transfers,
        )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
        if (transfer == null || transfer.filePath == null) {
          return Response.notFound('Transfer not found');
        }
        final actual = await _sha256File(File(transfer.filePath!));
        final expected = _nullableString(payload['sha256']) ?? transfer.sha256;
        if (expected != null && expected != actual) {
          await _markTransferStatus(id, 'failed', transfer.receivedBytes);
          return Response(409, body: 'SHA-256 mismatch');
        }
        await _markTransferStatus(id, 'received', transfer.fileSize);
        _updates.add(null);
        return _json({'ok': true, 'sha256': actual});
      });

  Future<Response> _withTrustedEnvelope(
    Request request,
    Future<Response> Function(Device peer, Map<String, Object?> payload) body,
  ) async {
    final json = await _readJson(request);
    final sender = json['sender_device_id'];
    if (sender is! String) {
      return Response.forbidden('Missing sender');
    }
    final peer = await _db.getDevice(sender);
    if (peer == null || !peer.trusted) {
      return Response.forbidden('Peer is not trusted');
    }
    final payload = await _securityService.open(peer, json);
    final host = _remoteHost(request);
    final listenPort = _int(payload['sender_listen_port']);
    if (host != null && listenPort > 0) {
      await _db.updateDeviceEndpoint(id: peer.id, host: host, port: listenPort);
    }
    return body(peer, payload);
  }

  Future<void> _postSecure(
    Device peer,
    String path,
    Map<String, Object?> payload, {
    String method = 'post',
  }) async {
    final current = await _freshPeer(peer);
    try {
      await _postSecureOnce(current, path, payload, method: method);
    } catch (error) {
      if (!_isConnectionError(error)) {
        rethrow;
      }
      await _db.markDeviceOffline(current.id);
      _updates.add(null);
      final resolved = await reconnectPeer?.call(current.id);
      if (resolved == null) {
        rethrow;
      }
      await _postSecureOnce(resolved, path, payload, method: method);
    }
  }

  Future<void> _postSecureOnce(
    Device peer,
    String path,
    Map<String, Object?> payload, {
    String method = 'post',
  }) async {
    if (peer.host == null || peer.port == null) {
      throw StateError('Peer endpoint is not known.');
    }
    final envelope = await _securityService.seal(peer, {
      ...payload,
      'sender_listen_port': _port,
    });
    final uri = Uri.parse('http://${peer.host}:${peer.port}$path');
    if (method == 'put') {
      await _dio.putUri(uri, data: envelope);
    } else {
      await _dio.postUri(uri, data: envelope);
    }
    await _db.updateDeviceEndpoint(
      id: peer.id,
      host: peer.host!,
      port: peer.port!,
    );
  }

  Future<Device> _freshPeer(Device peer) async {
    return await _db.getDevice(peer.id) ?? peer;
  }

  String? _remoteHost(Request request) {
    final connectionInfo = request.context['shelf.io.connection_info'];
    if (connectionInfo is HttpConnectionInfo) {
      return connectionInfo.remoteAddress.address;
    }
    return null;
  }

  bool _isConnectionError(Object error) {
    if (error is StateError) {
      return true;
    }
    if (error is dio.DioException) {
      return error.type == dio.DioExceptionType.connectionError ||
          error.type == dio.DioExceptionType.connectionTimeout ||
          error.type == dio.DioExceptionType.receiveTimeout ||
          error.type == dio.DioExceptionType.sendTimeout;
    }
    return false;
  }

  Future<Map<String, Object?>> _readJson(Request request) async {
    final raw = await request.readAsString();
    final decoded = jsonDecode(raw.isEmpty ? '{}' : raw);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    throw const FormatException('Expected JSON object');
  }

  Response _json(Map<String, Object?> value) => Response.ok(
    jsonEncode(value),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<void> _markTransferProgress(String id, int receivedBytes) async {
    await (_db.update(_db.transfers)..where((tbl) => tbl.id.equals(id))).write(
      TransfersCompanion(
        receivedBytes: Value(receivedBytes),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _markTransferStatus(
    String id,
    String status,
    int receivedBytes,
  ) async {
    await (_db.update(_db.transfers)..where((tbl) => tbl.id.equals(id))).write(
      TransfersCompanion(
        status: Value(status),
        receivedBytes: Value(receivedBytes),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<String> _sha256File(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _string(Object? value, String fallback) =>
      value is String && value.isNotEmpty ? value : fallback;
  String? _nullableString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
}
