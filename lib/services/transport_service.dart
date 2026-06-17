import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:drift/drift.dart' hide JsonKey;
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
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

const _streamFrameMagic = 0x4C434632; // LCF2
const _streamFrameHeaderLength = 24;
const _progressPersistInterval = Duration(milliseconds: 300);

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
    dio.BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 75),
    ),
  );
  final _uuid = const Uuid();
  final _updates = StreamController<void>.broadcast();
  final _notifications = StreamController<String>.broadcast();
  final _pairRequests = StreamController<PendingPairRequest>.broadcast();
  final Map<String, Completer<bool>> _pendingPairApprovals = {};
  final Map<String, DateTime> _lastProgressPersistedAt = {};
  final Map<String, int> _lastProgressBytes = {};
  HttpServer? _server;
  int _port = 0;
  Future<Device?> Function(String deviceId)? reconnectPeer;
  bool autoCopyReceivedText = true;

  int get port => _port;
  Stream<void> get updates => _updates.stream;
  Stream<String> get notifications => _notifications.stream;
  Stream<PendingPairRequest> get pairRequests => _pairRequests.stream;

  Future<int> start() async {
    if (_server != null) return _port;
    final router = Router()
      ..get('/v1/hello', _hello)
      ..post('/v1/pair/request', _pairRequest)
      ..post('/v1/pair/confirm', _pairConfirm)
      ..post('/v1/messages', _receiveMessage)
      ..post('/v1/transfers', _receiveTransferStart)
      ..post('/v1/transfers/<id>/stream', _receiveTransferStream)
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
    for (final completer in _pendingPairApprovals.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _pendingPairApprovals.clear();
    _server = null;
    _port = 0;
  }

  void approvePairRequest(String requestId) {
    final completer = _pendingPairApprovals[requestId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  void rejectPairRequest(String requestId) {
    final completer = _pendingPairApprovals[requestId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
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
      'nickname': identity.displayName,
      'avatar_seed': identity.avatarSeed,
      'avatar_color': identity.avatarColor,
      'capabilities': [
        'text',
        'files',
        'pairing',
        'encrypted_chunks',
        encryptedStreamCapability,
      ],
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
    final displayName = _string(
      body['nickname'],
      _string(body['display_name'], 'Unknown'),
    );
    final fingerprint = _string(body['public_key_fingerprint'], '');
    final avatarSeed = _string(body['avatar_seed'], fingerprint);
    final avatarColor = _string(body['avatar_color'], '#2563EB');
    await _db.upsertDiscoveredDevice(
      id: deviceId,
      displayName: displayName,
      platform: _string(body['platform'], 'unknown'),
      host: host,
      port: port,
      signingPublicKey: _string(body['signing_public_key'], ''),
      exchangePublicKey: _string(body['exchange_public_key'], ''),
      fingerprint: fingerprint,
      avatarSeed: avatarSeed,
      avatarColor: avatarColor,
    );
    final existing = await _db.getDevice(deviceId);
    var approved = existing?.trusted == true;
    if (!approved) {
      final requestId = _uuid.v4();
      final completer = Completer<bool>();
      _pendingPairApprovals[requestId] = completer;
      _pairRequests.add(
        PendingPairRequest(
          id: requestId,
          deviceId: deviceId,
          displayName: displayName,
          platform: _string(body['platform'], 'unknown'),
          host: host,
          port: port,
          signingPublicKey: _string(body['signing_public_key'], ''),
          exchangePublicKey: _string(body['exchange_public_key'], ''),
          fingerprint: fingerprint,
          avatarSeed: avatarSeed,
          avatarColor: avatarColor,
          code: code,
          createdAt: DateTime.now(),
        ),
      );
      _updates.add(null);
      try {
        approved = await completer.future.timeout(const Duration(seconds: 60));
      } on TimeoutException {
        approved = false;
      } finally {
        _pendingPairApprovals.remove(requestId);
      }
    }
    if (!approved) {
      return _json({'accepted': false, 'reason': 'rejected_or_timeout'});
    }
    await _db.trustDevice(
      id: deviceId,
      displayName: displayName,
      platform: _string(body['platform'], 'unknown'),
      host: host,
      port: port,
      signingPublicKey: _string(body['signing_public_key'], ''),
      exchangePublicKey: _string(body['exchange_public_key'], ''),
      fingerprint: fingerprint,
      avatarSeed: avatarSeed,
      avatarColor: avatarColor,
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
      'nickname': identity.displayName,
      'avatar_seed': identity.avatarSeed,
      'avatar_color': identity.avatarColor,
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
        'nickname': identity.displayName,
        'avatar_seed': identity.avatarSeed,
        'avatar_color': identity.avatarColor,
        'code': code,
      },
    );
    final data = response.data;
    if (data == null || data['accepted'] != true || data['code'] != code) {
      throw StateError('Pairing was rejected or the code did not match.');
    }
    final fingerprint = _string(
      data['public_key_fingerprint'],
      peer.fingerprint,
    );
    final avatarSeed = _string(data['avatar_seed'], fingerprint);
    await _db.trustDevice(
      id: _string(data['device_id'], peer.id),
      displayName: _string(
        data['nickname'],
        _string(data['display_name'], peer.displayName),
      ),
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
      fingerprint: fingerprint,
      avatarSeed: avatarSeed,
      avatarColor: _string(data['avatar_color'], peer.avatarColor),
    );
    _updates.add(null);
  }

  Future<bool> checkPeer(Device peer) async {
    final current = await _freshPeer(peer);
    if (!current.trusted || current.host == null || current.port == null) {
      return false;
    }
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        Uri.parse('http://${current.host}:${current.port}/v1/hello'),
      );
      final data = response.data;
      if (data == null || data['device_id'] != current.id) {
        await _db.markDeviceOffline(current.id);
        _updates.add(null);
        return false;
      }
      final fingerprint = _string(
        data['public_key_fingerprint'],
        current.fingerprint,
      );
      await _db.trustDevice(
        id: current.id,
        displayName: _string(
          data['nickname'],
          _string(data['display_name'], current.displayName),
        ),
        platform: _string(data['platform'], current.platform),
        host: current.host!,
        port: _int(data['listen_port']) > 0
            ? _int(data['listen_port'])
            : current.port!,
        signingPublicKey: _string(
          data['signing_public_key'],
          current.signingPublicKey,
        ),
        exchangePublicKey: _string(
          data['exchange_public_key'],
          current.exchangePublicKey,
        ),
        fingerprint: fingerprint,
        avatarSeed: _string(data['avatar_seed'], current.avatarSeed),
        avatarColor: _string(data['avatar_color'], current.avatarColor),
      );
      _updates.add(null);
      return true;
    } catch (_) {
      await _db.markDeviceOffline(current.id);
      _updates.add(null);
      return false;
    }
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
    final mimeType = lookupMimeType(file.path);
    final totalChunks = length == 0
        ? 1
        : (length + encryptedStreamChunkSize - 1) ~/ encryptedStreamChunkSize;
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
            mimeType: Value(mimeType),
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
        mimeType: Value(mimeType),
        status: 'sending',
        transferId: Value(transferId),
        createdAt: DateTime.now(),
      ),
    );
    _updates.add(null);
    try {
      var targetPeer = currentPeer;
      try {
        await _sendFileAttempt(
          targetPeer,
          file,
          transferId,
          name,
          length,
          mimeType,
          totalChunks,
        );
      } catch (error) {
        if (!_isConnectionError(error)) {
          rethrow;
        }
        await _db.markDeviceOffline(targetPeer.id);
        _updates.add(null);
        final resolved = await reconnectPeer?.call(targetPeer.id);
        if (resolved == null) {
          rethrow;
        }
        targetPeer = resolved;
        await _markTransferProgress(transferId, 0, force: true);
        await _sendFileAttempt(
          targetPeer,
          file,
          transferId,
          name,
          length,
          mimeType,
          totalChunks,
        );
      }
      await _markTransferStatus(transferId, 'sent', length);
    } catch (_) {
      await _markTransferStatus(transferId, 'failed', 0);
      rethrow;
    } finally {
      _updates.add(null);
    }
  }

  Future<void> _sendFileAttempt(
    Device peer,
    File file,
    String transferId,
    String name,
    int length,
    String? mimeType,
    int totalChunks,
  ) async {
    await _postSecure(peer, '/v1/transfers', {
      'id': transferId,
      'file_name': name,
      'file_size': length,
      'mime_type': mimeType,
      'total_chunks': totalChunks,
      'chunk_size': encryptedStreamChunkSize,
      'stream_version': encryptedStreamVersion,
    });
    final freshPeer = await _freshPeer(peer);
    final usedStream = await _trySendEncryptedStream(
      freshPeer,
      file,
      transferId,
    );
    if (!usedStream) {
      await _sendLegacyChunks(freshPeer, file, transferId, length);
    }
    final sha = await _sha256File(file);
    await (_db.update(
      _db.transfers,
    )..where((tbl) => tbl.id.equals(transferId))).write(
      TransfersCompanion(sha256: Value(sha), updatedAt: Value(DateTime.now())),
    );
    await _postSecure(freshPeer, '/v1/transfers/$transferId/complete', {
      'id': transferId,
      'sha256': sha,
    });
  }

  Future<bool> _trySendEncryptedStream(
    Device peer,
    File file,
    String transferId,
  ) async {
    if (peer.host == null || peer.port == null) {
      throw StateError('Peer endpoint is not known.');
    }
    final uri = Uri.parse(
      'http://${peer.host}:${peer.port}/v1/transfers/$transferId/stream',
    );
    final headers = await _securityService.streamAuthHeaders(peer, transferId);
    try {
      await _dio.postUri<void>(
        uri,
        data: _encryptedFileStream(peer, file, transferId),
        options: dio.Options(
          headers: headers,
          contentType: 'application/octet-stream',
          responseType: dio.ResponseType.plain,
        ),
      );
      await _db.updateDeviceEndpoint(
        id: peer.id,
        host: peer.host!,
        port: peer.port!,
      );
      return true;
    } on dio.DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 404 || status == 405 || status == 415 || status == 501) {
        return false;
      }
      rethrow;
    }
  }

  Stream<List<int>> _encryptedFileStream(
    Device peer,
    File file,
    String transferId,
  ) async* {
    final length = await file.length();
    var buffer = BytesBuilder(copy: false);
    var index = 0;
    var sent = 0;
    await for (final part in file.openRead()) {
      buffer.add(part);
      while (buffer.length >= encryptedStreamChunkSize) {
        final bytes = buffer.takeBytes();
        final chunk = Uint8List.fromList(
          bytes.take(encryptedStreamChunkSize).toList(),
        );
        final rest = bytes.skip(encryptedStreamChunkSize).toList();
        if (rest.isNotEmpty) {
          buffer.add(rest);
        }
        final encrypted = await _securityService.encryptFileChunk(
          peer,
          index,
          chunk,
        );
        yield _encodeFrame(encrypted);
        index++;
        sent += chunk.length;
        await _markTransferProgress(transferId, sent.clamp(0, length));
      }
    }
    final tail = buffer.takeBytes();
    if (tail.isNotEmpty || length == 0) {
      final encrypted = await _securityService.encryptFileChunk(
        peer,
        index,
        tail,
      );
      yield _encodeFrame(encrypted);
      sent += tail.length;
      await _markTransferProgress(
        transferId,
        sent.clamp(0, length),
        force: true,
      );
    }
  }

  Future<void> _sendLegacyChunks(
    Device peer,
    File file,
    String transferId,
    int length,
  ) async {
    final stream = file.openRead();
    var buffer = BytesBuilder(copy: false);
    var index = 0;
    var sent = 0;
    await for (final part in stream) {
      buffer.add(part);
      while (buffer.length >= legacyTransferChunkSize) {
        final chunk = buffer.takeBytes();
        await _sendChunk(
          peer,
          transferId,
          index,
          Uint8List.fromList(chunk.take(legacyTransferChunkSize).toList()),
        );
        final rest = chunk.skip(legacyTransferChunkSize).toList();
        if (rest.isNotEmpty) {
          buffer.add(rest);
        }
        index++;
        sent += legacyTransferChunkSize;
        await _markTransferProgress(transferId, sent.clamp(0, length));
      }
    }
    final tail = buffer.takeBytes();
    if (tail.isNotEmpty || length == 0) {
      await _sendChunk(peer, transferId, index, tail);
      sent += tail.length;
      await _markTransferProgress(
        transferId,
        sent.clamp(0, length),
        force: true,
      );
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

  Uint8List _encodeFrame(EncryptedFileChunk chunk) {
    final output = BytesBuilder(copy: false);
    final header = ByteData(_streamFrameHeaderLength)
      ..setUint32(0, _streamFrameMagic)
      ..setUint32(4, chunk.index)
      ..setUint32(8, chunk.plainLength)
      ..setUint32(12, chunk.nonce.length)
      ..setUint32(16, chunk.mac.length)
      ..setUint32(20, chunk.cipherText.length);
    output
      ..add(header.buffer.asUint8List())
      ..add(chunk.nonce)
      ..add(chunk.mac)
      ..add(chunk.cipherText);
    return output.takeBytes();
  }

  Future<Response> _receiveMessage(Request request) =>
      _withTrustedEnvelope(request, (peer, payload) async {
        final conversation = await _db.ensureConversation(peer);
        final kind = _string(payload['kind'], 'text');
        final body = _string(payload['body'], '');
        await _db.addMessage(
          ChatMessagesCompanion.insert(
            id: _string(payload['id'], _uuid.v4()),
            conversationId: conversation.id,
            peerDeviceId: peer.id,
            direction: 'in',
            kind: kind,
            body: Value(body),
            status: 'received',
            createdAt:
                DateTime.tryParse(_string(payload['created_at'], '')) ??
                DateTime.now(),
          ),
        );
        if ((kind == 'text' || kind == 'link') &&
            body.isNotEmpty &&
            autoCopyReceivedText) {
          try {
            await Clipboard.setData(ClipboardData(text: body));
            _notifications.add('收到 ${peer.displayName} 的文字，已复制到剪贴板');
          } catch (_) {
            _notifications.add('收到 ${peer.displayName} 的文字');
          }
        } else if ((kind == 'text' || kind == 'link') && body.isNotEmpty) {
          _notifications.add('收到 ${peer.displayName} 的文字');
        } else {
          _notifications.add('收到 ${peer.displayName} 的消息');
        }
        _updates.add(null);
        return _json({'ok': true});
      });

  Future<Response> _receiveTransferStart(Request request) =>
      _withTrustedEnvelope(request, (peer, payload) async {
        final conversation = await _db.ensureConversation(peer);
        final at = DateTime.now();
        final file = await _fileStore.createReceiveFile(
          _string(payload['file_name'], 'received.bin'),
          conversationFolder: FileStore.conversationFolder(
            peer.displayName,
            peer.id,
          ),
          at: at,
        );
        final id = _string(payload['id'], _uuid.v4());
        final fileName = _string(payload['file_name'], p.basename(file.path));
        await _db
            .into(_db.transfers)
            .insertOnConflictUpdate(
              TransfersCompanion.insert(
                id: id,
                peerDeviceId: peer.id,
                direction: 'in',
                fileName: fileName,
                filePath: Value(file.path),
                fileSize: _int(payload['file_size']),
                sha256: Value(_nullableString(payload['sha256'])),
                mimeType: Value(_nullableString(payload['mime_type'])),
                status: 'receiving',
                totalChunks: Value(_int(payload['total_chunks'])),
                createdAt: at,
                updatedAt: at,
              ),
            );
        await _db.addMessage(
          ChatMessagesCompanion.insert(
            id: _uuid.v4(),
            conversationId: conversation.id,
            peerDeviceId: peer.id,
            direction: 'in',
            kind: 'file',
            fileName: Value(fileName),
            filePath: Value(file.path),
            fileSize: Value(_int(payload['file_size'])),
            mimeType: Value(_nullableString(payload['mime_type'])),
            status: 'receiving',
            transferId: Value(id),
            createdAt: DateTime.now(),
          ),
        );
        _notifications.add('收到 ${peer.displayName} 的文件：$fileName');
        _updates.add(null);
        return _json({'ok': true, 'path': file.path});
      });

  Future<Response> _receiveTransferStream(Request request, String id) async {
    final sender = request.headers['x-localchat-sender'];
    final recipient = request.headers['x-localchat-recipient'];
    final transferHeader = request.headers['x-localchat-transfer-id'];
    final timestamp = int.tryParse(
      request.headers['x-localchat-timestamp'] ?? '',
    );
    final nonce = request.headers['x-localchat-nonce'];
    final signature = request.headers['x-localchat-signature'];
    if (sender == null ||
        recipient == null ||
        transferHeader != id ||
        timestamp == null ||
        nonce == null ||
        signature == null) {
      return Response.forbidden('Missing stream authentication');
    }
    if (recipient != _identityService.identity.deviceId) {
      return Response.forbidden('Stream recipient does not match this device');
    }
    final peer = await _db.getDevice(sender);
    if (peer == null || !peer.trusted) {
      return Response.forbidden('Peer is not trusted');
    }
    try {
      await _securityService.verifyStreamAuth(
        peer: peer,
        recipientDeviceId: recipient,
        transferId: id,
        timestamp: timestamp,
        nonce: nonce,
        signature: signature,
      );
    } catch (error) {
      return Response.forbidden('$error');
    }
    final transfer = await (_db.select(
      _db.transfers,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (transfer == null || transfer.filePath == null) {
      return Response.notFound('Transfer not found');
    }
    final reader = _FrameReader(request.read());
    final file = File(transfer.filePath!);
    final sink = file.openWrite(mode: FileMode.write);
    var expectedIndex = 0;
    var received = 0;
    try {
      while (true) {
        final frame = await reader.next();
        if (frame == null) break;
        if (frame.index != expectedIndex) {
          throw const FormatException('Unexpected frame index');
        }
        final clear = await _securityService.decryptFileChunk(peer, frame);
        if (clear.length != frame.plainLength) {
          throw const FormatException('Frame length mismatch');
        }
        sink.add(clear);
        received += clear.length;
        expectedIndex++;
        await _markTransferProgress(id, received);
      }
      await sink.close();
    } catch (error) {
      await sink.close();
      await _markTransferStatus(id, 'failed', received);
      return Response(400, body: '$error');
    }
    _updates.add(null);
    return _json({'ok': true, 'received_bytes': received});
  }

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

  Future<Response> _receiveTransferComplete(
    Request request,
    String id,
  ) => _withTrustedEnvelope(request, (peer, payload) async {
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
    try {
      final saved = await _fileStore.saveToDownloads(
        sourcePath: transfer.filePath!,
        fileName: transfer.fileName,
        mimeType: transfer.mimeType,
        conversationFolder: FileStore.conversationFolder(
          peer.displayName,
          peer.id,
        ),
        at: transfer.createdAt,
      );
      await _db.markTransferSaved(
        transferId: id,
        savedPath: saved.path,
        savedUri: saved.uri,
      );
    } catch (_) {
      // The verified temp file remains available even if the public save fails.
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

  Future<void> _markTransferProgress(
    String id,
    int receivedBytes, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final lastBytes = _lastProgressBytes[id];
    final lastAt = _lastProgressPersistedAt[id];
    if (!force &&
        lastBytes != null &&
        receivedBytes <= lastBytes &&
        lastAt != null) {
      return;
    }
    if (!force &&
        lastAt != null &&
        now.difference(lastAt) < _progressPersistInterval) {
      _lastProgressBytes[id] = receivedBytes;
      return;
    }
    await (_db.update(_db.transfers)..where((tbl) => tbl.id.equals(id))).write(
      TransfersCompanion(
        receivedBytes: Value(receivedBytes),
        updatedAt: Value(now),
      ),
    );
    _lastProgressPersistedAt[id] = now;
    _lastProgressBytes[id] = receivedBytes;
    _updates.add(null);
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
    _lastProgressPersistedAt.remove(id);
    _lastProgressBytes.remove(id);
    await (_db.update(_db.chatMessages)
          ..where((tbl) => tbl.transferId.equals(id)))
        .write(ChatMessagesCompanion(status: Value(status)));
    _updates.add(null);
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

class _FrameReader {
  _FrameReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;
  var _done = false;

  Future<EncryptedFileChunk?> next() async {
    final header = await _readExact(_streamFrameHeaderLength);
    if (header == null) return null;
    final data = ByteData.sublistView(header);
    if (data.getUint32(0) != _streamFrameMagic) {
      throw const FormatException('Invalid stream frame magic.');
    }
    final index = data.getUint32(4);
    final plainLength = data.getUint32(8);
    final nonceLength = data.getUint32(12);
    final macLength = data.getUint32(16);
    final cipherLength = data.getUint32(20);
    final nonce = await _readRequired(nonceLength);
    final mac = await _readRequired(macLength);
    final cipherText = await _readRequired(cipherLength);
    return EncryptedFileChunk(
      index: index,
      plainLength: plainLength,
      nonce: nonce,
      mac: mac,
      cipherText: cipherText,
    );
  }

  Future<Uint8List> _readRequired(int length) async {
    final bytes = await _readExact(length);
    if (bytes == null) {
      throw const FormatException('Unexpected end of stream.');
    }
    return bytes;
  }

  Future<Uint8List?> _readExact(int length) async {
    final output = BytesBuilder(copy: false);
    while (output.length < length) {
      final available = _buffer.length - _offset;
      if (available > 0) {
        final needed = length - output.length;
        final take = available < needed ? available : needed;
        output.add(Uint8List.sublistView(_buffer, _offset, _offset + take));
        _offset += take;
        if (_offset == _buffer.length) {
          _buffer = Uint8List(0);
          _offset = 0;
        }
      } else {
        if (_done) {
          if (output.length == 0) return null;
          throw const FormatException('Unexpected partial stream frame.');
        }
        if (await _iterator.moveNext()) {
          _buffer = Uint8List.fromList(_iterator.current);
          _offset = 0;
        } else {
          _done = true;
        }
      }
    }
    return output.takeBytes();
  }
}
