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

import '../core/app_failure.dart';
import '../core/formatters.dart';
import '../core/device_profile.dart';
import '../data/app_database.dart';
import '../models/protocol.dart';
import '../models/transfer_views.dart';
import 'file_store.dart';
import 'identity_service.dart';
import 'security_service.dart';

const _streamFrameMagic = 0x4C434632; // LCF2
const _streamFrameHeaderLength = 24;
const _progressPersistInterval = Duration(milliseconds: 300);
const _speedSampleInterval = Duration(milliseconds: 500);

/// 出站传输被用户取消时抛出，用于在传输链路中中断流生成与 dio 请求。
class _OutboundCancelled implements Exception {
  const _OutboundCancelled();
}

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
  // 出站单活动任务队列：同一时刻只跑一个出站传输，其余排队等待。
  final List<_OutboundTask> _outboundQueue = [];
  _OutboundTask? _activeOutbound;
  bool _pumping = false;
  // 实时传输统计（发送字节数与瞬时速度），仅存内存，避免高频写库。
  final Map<String, _LiveTransferStat> _liveStats = {};
  // 正在接收的入站传输取消信号：transferId → 取消标志，供对端 cancel 接口触发。
  final Map<String, _InboundCancel> _inboundCancels = {};
  HttpServer? _server;
  int _port = 0;
  Future<Device?> Function(String deviceId)? reconnectPeer;
  bool autoCopyReceivedText = true;
  String languageCode = 'zh';

  int get port => _port;
  Stream<void> get updates => _updates.stream;
  Stream<String> get notifications => _notifications.stream;
  Stream<PendingPairRequest> get pairRequests => _pairRequests.stream;

  bool isOutboundActive(String transferId) =>
      _activeOutbound?.transferId == transferId;

  String? activeOutboundTransferIdForGroup(String groupId) {
    final active = _activeOutbound;
    return active != null && active.groupId == groupId
        ? active.transferId
        : null;
  }

  Future<int> start() async {
    if (_server != null) return _port;
    await _markStaleTransfersInterrupted();
    final router = Router()
      ..get('/v1/hello', _hello)
      ..post('/v1/pair/request', _pairRequest)
      ..post('/v1/pair/confirm', _pairConfirm)
      ..post('/v1/messages', _receiveMessage)
      ..post('/v1/transfers', _receiveTransferStart)
      ..post('/v1/transfers/<id>/stream', _receiveTransferStream)
      ..put('/v1/transfers/<id>/chunks/<index>', _receiveTransferChunk)
      ..post('/v1/transfers/<id>/complete', _receiveTransferComplete)
      ..post('/v1/transfers/<id>/cancel', _receiveTransferCancel);
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

  /// 应用重启时把遗留的 queued/preparing/sending/receiving 传输标记为
  /// interrupted。队列只存在于内存中，因此 queued 也必须处理。
  Future<void> _markStaleTransfersInterrupted() async {
    await (_db.update(_db.transfers)..where(
          (tbl) => tbl.status.isIn(const [
            'queued',
            'preparing',
            'sending',
            'receiving',
          ]),
        ))
        .write(
          TransfersCompanion(
            status: const Value('interrupted'),
            errorCode: const Value('interrupted'),
            updatedAt: Value(DateTime.now()),
          ),
        );
    await (_db.update(_db.chatMessages)
          ..where((tbl) => tbl.transferId.isNotNull())
          ..where(
            (tbl) => tbl.status.isIn(const [
              'queued',
              'preparing',
              'sending',
              'receiving',
            ]),
          ))
        .write(const ChatMessagesCompanion(status: Value('interrupted')));
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
        folderCapability,
        transferCancelCapability,
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
    final signingPublicKey = _string(body['signing_public_key'], '');
    final exchangePublicKey = _string(body['exchange_public_key'], '');
    // 摄入对端身份前校验自洽：拒绝设备 ID / 公钥 / 指纹不一致的配对请求。
    try {
      validatePeerIdentity(
        deviceId: deviceId,
        signingPublicKey: signingPublicKey,
        fingerprint: fingerprint,
      );
    } catch (_) {
      return Response.badRequest(body: 'Inconsistent peer identity');
    }
    await _db.upsertDiscoveredDevice(
      id: deviceId,
      displayName: displayName,
      platform: _string(body['platform'], 'unknown'),
      host: host,
      port: port,
      signingPublicKey: signingPublicKey,
      exchangePublicKey: exchangePublicKey,
      fingerprint: fingerprint,
      avatarSeed: avatarSeed,
      avatarColor: avatarColor,
      capabilities: _capabilitiesFrom(body['capabilities']),
    );
    final existing = await _db.getDevice(deviceId);
    // 已信任设备若身份公钥发生变化，拒绝继续配对，要求删除后重新配对（P0）。
    if (existing?.trusted == true && existing?.identityChanged == true) {
      return _json({'accepted': false, 'reason': 'identity_changed'});
    }
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
      signingPublicKey: signingPublicKey,
      exchangePublicKey: exchangePublicKey,
      fingerprint: fingerprint,
      avatarSeed: avatarSeed,
      avatarColor: avatarColor,
      capabilities: _capabilitiesFrom(body['capabilities']),
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
      'capabilities': [
        'text',
        'files',
        'pairing',
        'encrypted_chunks',
        encryptedStreamCapability,
        folderCapability,
        transferCancelCapability,
      ],
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
    final trustedDeviceId = _string(data['device_id'], peer.id);
    final trustedSigningKey = _string(
      data['signing_public_key'],
      peer.signingPublicKey,
    );
    final trustedExchangeKey = _string(
      data['exchange_public_key'],
      peer.exchangePublicKey,
    );
    // 配对响应里若带齐身份三元组则校验自洽，拒绝不一致的对端。
    if (trustedSigningKey.isNotEmpty &&
        trustedExchangeKey.isNotEmpty &&
        fingerprint.isNotEmpty &&
        data['device_id'] is String) {
      try {
        validatePeerIdentity(
          deviceId: trustedDeviceId,
          signingPublicKey: trustedSigningKey,
          fingerprint: fingerprint,
        );
      } catch (_) {
        throw StateError('Pairing response identity is inconsistent.');
      }
    }
    await _db.trustDevice(
      id: trustedDeviceId,
      displayName: _string(
        data['nickname'],
        _string(data['display_name'], peer.displayName),
      ),
      platform: _string(data['platform'], peer.platform),
      host: peer.host!,
      port: peer.port!,
      signingPublicKey: trustedSigningKey,
      exchangePublicKey: trustedExchangeKey,
      fingerprint: fingerprint,
      avatarSeed: avatarSeed,
      avatarColor: _string(data['avatar_color'], peer.avatarColor),
      capabilities: _capabilitiesFrom(data['capabilities']),
    );
    _updates.add(null);
  }

  /// 跨网段手动加好友：按用户输入的 host:port 探测对端身份。
  /// 命中 /v1/hello 后以 endpointSource='manual' 落库（未信任，等待配对确认）。
  /// 返回落库后的设备；连接失败或非本协议返回 null。
  Future<Device?> fetchPeerIdentity(String host, int port) async {
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        Uri.parse('http://$host:$port/v1/hello'),
      );
      final data = response.data;
      if (data == null || data['protocol_version'] != protocolVersion) {
        return null;
      }
      final deviceId = data['device_id'];
      if (deviceId is! String || deviceId.isEmpty) return null;
      final listenPort = data['listen_port'] is int
          ? data['listen_port'] as int
          : port;
      final fingerprint = _string(data['public_key_fingerprint'], '');
      final avatarSeed = _string(data['avatar_seed'], fingerprint);
      final signingPublicKey = _string(data['signing_public_key'], '');
      final exchangePublicKey = _string(data['exchange_public_key'], '');
      // 校验对端身份自洽：拒绝 ID / 公钥 / 指纹不一致的设备。
      try {
        validatePeerIdentity(
          deviceId: deviceId,
          signingPublicKey: signingPublicKey,
          fingerprint: fingerprint,
        );
      } catch (_) {
        return null;
      }
      await _db.upsertManualDevice(
        id: deviceId,
        displayName: _string(
          data['nickname'],
          _string(data['display_name'], 'Unknown'),
        ),
        platform: _string(data['platform'], 'unknown'),
        host: host,
        port: listenPort > 0 ? listenPort : port,
        signingPublicKey: signingPublicKey,
        exchangePublicKey: exchangePublicKey,
        fingerprint: fingerprint,
        avatarSeed: avatarSeed,
        avatarColor: _string(data['avatar_color'], avatarColorFor(avatarSeed)),
        capabilities: _capabilitiesFrom(data['capabilities']),
      );
      _updates.add(null);
      return _db.getDevice(deviceId);
    } catch (_) {
      return null;
    }
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
      final signingPublicKey = _string(
        data['signing_public_key'],
        current.signingPublicKey,
      );
      final exchangePublicKey = _string(
        data['exchange_public_key'],
        current.exchangePublicKey,
      );
      // 已信任设备：用 upsertDiscoveredDevice 而非 trustDevice 刷新，确保签名/交换
      // 公钥与指纹被固定、不被 /v1/hello 静默覆盖；公钥变化时由 DB 标记
      // identity_changed（P0）。仅当 hello 自报的三元组完整时才做自洽校验。
      if (signingPublicKey.isNotEmpty &&
          exchangePublicKey.isNotEmpty &&
          fingerprint.isNotEmpty &&
          data['device_id'] is String) {
        try {
          validatePeerIdentity(
            deviceId: data['device_id'] as String,
            signingPublicKey: signingPublicKey,
            fingerprint: fingerprint,
          );
        } catch (_) {
          await _db.markDeviceOffline(current.id);
          _updates.add(null);
          return false;
        }
      }
      await _db.upsertDiscoveredDevice(
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
        signingPublicKey: signingPublicKey,
        exchangePublicKey: exchangePublicKey,
        fingerprint: fingerprint,
        avatarSeed: _string(data['avatar_seed'], current.avatarSeed),
        avatarColor: _string(data['avatar_color'], current.avatarColor),
        capabilities: _capabilitiesFrom(data['capabilities']),
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
    _requireIdentityUnchanged(currentPeer);
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

  Future<void> retryText(Device peer, ChatMessage message) async {
    final body = message.body;
    if (message.direction != 'out' || body == null || body.isEmpty) return;
    var targetPeer = await _freshPeer(peer);
    _requireIdentityUnchanged(targetPeer);
    await _setMessageStatus(message.id, 'sending');
    _updates.add(null);
    try {
      try {
        await _postSecure(targetPeer, '/v1/messages', {
          'id': message.id,
          'kind': 'text',
          'body': body,
          'created_at': message.createdAt.toIso8601String(),
        });
      } catch (error) {
        if (!_isConnectionError(error)) rethrow;
        await _db.markDeviceOffline(targetPeer.id);
        _updates.add(null);
        final resolved = await reconnectPeer?.call(targetPeer.id);
        if (resolved == null) rethrow;
        targetPeer = resolved;
        await _postSecure(targetPeer, '/v1/messages', {
          'id': message.id,
          'kind': 'text',
          'body': body,
          'created_at': message.createdAt.toIso8601String(),
        });
      }
      await _setMessageStatus(message.id, 'sent');
    } catch (_) {
      await _setMessageStatus(message.id, 'failed');
      rethrow;
    } finally {
      _updates.add(null);
    }
  }

  Future<void> retryFile(
    Device peer,
    ChatMessage message,
    Transfer transfer,
  ) async {
    final path = transfer.filePath ?? message.filePath;
    if (message.direction != 'out' || path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Source file no longer exists', path);
    }
    final currentPeer = await _freshPeer(peer);
    _requireIdentityUnchanged(currentPeer);
    final length = await file.length();
    final retryTransferId = _uuid.v4();
    final totalChunks = length == 0
        ? 1
        : (length + encryptedStreamChunkSize - 1) ~/ encryptedStreamChunkSize;
    final name = transfer.fileName;
    final mimeType = transfer.mimeType ?? lookupMimeType(path);
    final groupId = _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.transfers)
          .insert(
            TransfersCompanion.insert(
              id: retryTransferId,
              peerDeviceId: currentPeer.id,
              direction: 'out',
              fileName: name,
              fileSize: length,
              filePath: Value(path),
              mimeType: Value(mimeType),
              status: 'queued',
              totalChunks: Value(totalChunks),
              relativePath: Value(transfer.relativePath),
              groupId: Value(groupId),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await (_db.update(
        _db.chatMessages,
      )..where((tbl) => tbl.id.equals(message.id))).write(
        ChatMessagesCompanion(
          status: const Value('queued'),
          transferId: Value(retryTransferId),
          filePath: Value(path),
          fileSize: Value(length),
        ),
      );
      await (_db.delete(
        _db.transfers,
      )..where((tbl) => tbl.id.equals(transfer.id))).go();
    });
    final completion = Completer<void>();
    _liveStats[retryTransferId] = _LiveTransferStat(totalBytes: length);
    _outboundQueue.add(
      _OutboundTask(
        transferId: retryTransferId,
        peerId: currentPeer.id,
        file: file,
        name: name,
        length: length,
        mimeType: mimeType,
        totalChunks: totalChunks,
        groupId: groupId,
        relativePath: transfer.relativePath,
        completion: completion,
      ),
    );
    _updates.add(null);
    _pumpOutbound();
    await completion.future;
  }

  Future<void> _setMessageStatus(String messageId, String status) async {
    await (_db.update(_db.chatMessages)
          ..where((tbl) => tbl.id.equals(messageId)))
        .write(ChatMessagesCompanion(status: Value(status)));
  }

  Future<void> sendFiles(Device peer, List<String> paths) async {
    final groupId = _uuid.v4();
    for (final path in paths) {
      await _enqueueFile(peer, File(path), groupId: groupId);
    }
  }

  /// 递归发送一个文件夹。entries 为 (绝对路径, 相对根目录的路径) 列表，
  /// relative 已 POSIX 化并以根目录名开头（如 "mydir/sub/f.txt"）。
  /// 始终在协议里携带 relative_path：支持 folders_v1 的对端按相对路径镜像落盘，
  /// 旧版本对端会忽略该未知字段并按平铺文件名接收（行为不变）。
  Future<void> sendFolder(
    Device peer,
    String rootName,
    List<({String absolute, String relative})> entries,
  ) async {
    final groupId = _uuid.v4();
    for (final entry in entries) {
      await _enqueueFile(
        peer,
        File(entry.absolute),
        groupId: groupId,
        relativePath: entry.relative,
      );
    }
  }

  /// 把单个文件入队为排队传输（status='queued'），立即返回，不阻塞调用方。
  /// 队列单活动串行执行，支持取消排队任务与当前活动任务。
  Future<void> _enqueueFile(
    Device peer,
    File file, {
    required String groupId,
    String? relativePath,
  }) async {
    if (!await file.exists()) return;
    final currentPeer = await _freshPeer(peer);
    _requireIdentityUnchanged(currentPeer);
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
            status: 'queued',
            totalChunks: Value(totalChunks),
            relativePath: Value(relativePath),
            groupId: Value(groupId),
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
        status: 'queued',
        transferId: Value(transferId),
        relativePath: Value(relativePath),
        createdAt: DateTime.now(),
      ),
    );
    _liveStats[transferId] = _LiveTransferStat(totalBytes: length);
    _outboundQueue.add(
      _OutboundTask(
        transferId: transferId,
        peerId: currentPeer.id,
        file: file,
        name: name,
        length: length,
        mimeType: mimeType,
        totalChunks: totalChunks,
        groupId: groupId,
        relativePath: relativePath,
      ),
    );
    _updates.add(null);
    _pumpOutbound();
  }

  /// 单活动出站调度：同一时刻只跑一个出站任务，完成后处理下一个。
  Future<void> _pumpOutbound() async {
    if (_pumping) return;
    if (_activeOutbound != null) return;
    if (_outboundQueue.isEmpty) return;
    _pumping = true;
    try {
      final task = _outboundQueue.removeAt(0);
      _activeOutbound = task;
      await _runOutboundTask(task);
    } finally {
      _activeOutbound = null;
      _pumping = false;
      if (_outboundQueue.isNotEmpty) {
        _pumpOutbound();
      }
    }
  }

  Future<void> _runOutboundTask(_OutboundTask task) async {
    if (task.canceled) {
      await _markTransferStatus(task.transferId, 'canceled', 0);
      task.completeError(const _OutboundCancelled());
      return;
    }
    final stored = await _db.getDevice(task.peerId);
    if (stored == null) {
      await _markTransferFailed(task.transferId, 'peer_removed');
      task.completeError(StateError('Peer was removed.'));
      return;
    }
    try {
      _requireIdentityUnchanged(stored);
    } on AppFailure catch (error) {
      await _markTransferFailed(task.transferId, error.code);
      task.completeError(error);
      return;
    }
    await _markTransferStatus(task.transferId, 'sending', 0);
    _updates.add(null);
    try {
      await _transmitFile(
        stored,
        task.file,
        task.transferId,
        task.name,
        task.length,
        task.mimeType,
        task.totalChunks,
        relativePath: task.relativePath,
        task: task,
      );
      await _markTransferStatus(task.transferId, 'sent', task.length);
      task.complete();
    } on _OutboundCancelled {
      await _markTransferStatus(task.transferId, 'canceled', 0);
      task.completeError(const _OutboundCancelled());
    } catch (error) {
      final code = error is AppFailure
          ? error.code
          : (_isConnectionError(error) ? 'connection_lost' : 'unknown');
      await _markTransferFailed(task.transferId, code);
      task.completeError(error);
    } finally {
      _liveStats.remove(task.transferId);
      _updates.add(null);
    }
  }

  /// 取消一个出站传输。排队中的任务直接移除并标记 canceled；活动任务通过
  /// dio CancelToken 与流中断标志中断。返回是否成功取消。
  Future<bool> cancelOutbound(String transferId) async {
    final queuedIndex = _outboundQueue.indexWhere(
      (task) => task.transferId == transferId,
    );
    if (queuedIndex >= 0) {
      final task = _outboundQueue.removeAt(queuedIndex);
      task.canceled = true;
      await _markTransferStatus(transferId, 'canceled', 0);
      return true;
    }
    final active = _activeOutbound;
    if (active != null && active.transferId == transferId) {
      active.canceled = true;
      if (!active.cancelToken.isCancelled) {
        active.cancelToken.cancel('user_canceled');
      }
      return true;
    }
    return false;
  }

  /// 整组取消：取消同 groupId 下所有仍在排队或活动中的出站任务。
  Future<int> cancelOutboundGroup(String groupId) async {
    var count = 0;
    final ids = _outboundQueue
        .where((task) => task.groupId == groupId)
        .map((task) => task.transferId)
        .toList();
    for (final id in ids) {
      if (await cancelOutbound(id)) count++;
    }
    final active = _activeOutbound;
    if (active != null && active.groupId == groupId && !active.canceled) {
      if (await cancelOutbound(active.transferId)) count++;
    }
    return count;
  }

  Future<void> _markTransferFailed(String transferId, String errorCode) async {
    await (_db.update(
      _db.transfers,
    )..where((tbl) => tbl.id.equals(transferId))).write(
      TransfersCompanion(
        status: const Value('failed'),
        errorCode: Value(errorCode),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await (_db.update(_db.chatMessages)
          ..where((tbl) => tbl.transferId.equals(transferId)))
        .write(const ChatMessagesCompanion(status: Value('failed')));
    _updates.add(null);
  }

  Future<void> _transmitFile(
    Device peer,
    File file,
    String transferId,
    String name,
    int length,
    String? mimeType,
    int totalChunks, {
    String? relativePath,
    _OutboundTask? task,
  }) async {
    try {
      var targetPeer = peer;
      try {
        await _sendFileAttempt(
          targetPeer,
          file,
          transferId,
          name,
          length,
          mimeType,
          totalChunks,
          relativePath: relativePath,
          task: task,
        );
      } catch (error) {
        if (task?.canceled == true) throw const _OutboundCancelled();
        if (!_isConnectionError(error)) rethrow;
        await _db.markDeviceOffline(targetPeer.id);
        _updates.add(null);
        final resolved = await reconnectPeer?.call(targetPeer.id);
        if (resolved == null) rethrow;
        if (task?.canceled == true) throw const _OutboundCancelled();
        targetPeer = resolved;
        await _markTransferProgress(transferId, 0, force: true, task: task);
        await _sendFileAttempt(
          targetPeer,
          file,
          transferId,
          name,
          length,
          mimeType,
          totalChunks,
          relativePath: relativePath,
          task: task,
        );
      }
    } catch (_) {
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
    int totalChunks, {
    String? relativePath,
    _OutboundTask? task,
  }) async {
    if (task?.canceled == true) throw const _OutboundCancelled();
    final startBody = <String, Object?>{
      'id': transferId,
      'file_name': name,
      'file_size': length,
      'mime_type': mimeType,
      'total_chunks': totalChunks,
      'chunk_size': encryptedStreamChunkSize,
      'stream_version': encryptedStreamVersion,
    };
    if (relativePath != null && relativePath.isNotEmpty) {
      startBody['relative_path'] = relativePath;
    }
    await _postSecure(peer, '/v1/transfers', startBody, task: task);
    if (task?.canceled == true) throw const _OutboundCancelled();
    final freshPeer = await _freshPeer(peer);
    final usedStream = await _trySendEncryptedStream(
      freshPeer,
      file,
      transferId,
      task: task,
    );
    if (task?.canceled == true) throw const _OutboundCancelled();
    if (!usedStream) {
      await _sendLegacyChunks(freshPeer, file, transferId, length, task: task);
    }
    if (task?.canceled == true) throw const _OutboundCancelled();
    final sha = await _sha256File(file);
    await (_db.update(
      _db.transfers,
    )..where((tbl) => tbl.id.equals(transferId))).write(
      TransfersCompanion(sha256: Value(sha), updatedAt: Value(DateTime.now())),
    );
    await _postSecure(freshPeer, '/v1/transfers/$transferId/complete', {
      'id': transferId,
      'sha256': sha,
    }, task: task);
  }

  Future<bool> _trySendEncryptedStream(
    Device peer,
    File file,
    String transferId, {
    _OutboundTask? task,
  }) async {
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
        data: _encryptedFileStream(peer, file, transferId, task: task),
        cancelToken: task?.cancelToken,
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
      if (task?.canceled == true || error.type == dio.DioExceptionType.cancel) {
        throw const _OutboundCancelled();
      }
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
    String transferId, {
    _OutboundTask? task,
  }) async* {
    final length = await file.length();
    var buffer = BytesBuilder(copy: false);
    var index = 0;
    var sent = 0;
    await for (final part in file.openRead()) {
      if (task?.canceled == true) return;
      buffer.add(part);
      while (buffer.length >= encryptedStreamChunkSize) {
        if (task?.canceled == true) return;
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
        await _markTransferProgress(
          transferId,
          sent.clamp(0, length),
          task: task,
        );
      }
    }
    if (task?.canceled == true) return;
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
        task: task,
      );
    }
  }

  Future<void> _sendLegacyChunks(
    Device peer,
    File file,
    String transferId,
    int length, {
    _OutboundTask? task,
  }) async {
    final stream = file.openRead();
    var buffer = BytesBuilder(copy: false);
    var index = 0;
    var sent = 0;
    await for (final part in stream) {
      if (task?.canceled == true) throw const _OutboundCancelled();
      buffer.add(part);
      while (buffer.length >= legacyTransferChunkSize) {
        if (task?.canceled == true) throw const _OutboundCancelled();
        final chunk = buffer.takeBytes();
        await _sendChunk(
          peer,
          transferId,
          index,
          Uint8List.fromList(chunk.take(legacyTransferChunkSize).toList()),
          task: task,
        );
        final rest = chunk.skip(legacyTransferChunkSize).toList();
        if (rest.isNotEmpty) {
          buffer.add(rest);
        }
        index++;
        sent += legacyTransferChunkSize;
        await _markTransferProgress(
          transferId,
          sent.clamp(0, length),
          task: task,
        );
      }
    }
    final tail = buffer.takeBytes();
    if (tail.isNotEmpty || length == 0) {
      await _sendChunk(peer, transferId, index, tail, task: task);
      sent += tail.length;
      await _markTransferProgress(
        transferId,
        sent.clamp(0, length),
        force: true,
        task: task,
      );
    }
  }

  Future<void> _sendChunk(
    Device peer,
    String transferId,
    int index,
    List<int> bytes, {
    _OutboundTask? task,
  }) async {
    await _postSecure(
      peer,
      '/v1/transfers/$transferId/chunks/$index',
      {
        'transfer_id': transferId,
        'index': index,
        'bytes': b64(bytes),
        'length': bytes.length,
      },
      method: 'put',
      task: task,
    );
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

  Future<Response> _receiveMessage(Request request) => _withTrustedEnvelope(
    request,
    (peer, payload) async {
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
          _notifications.add(
            languageCode == 'en'
                ? 'Received text from ${peer.displayName}, copied to clipboard'
                : '收到 ${peer.displayName} 的文字，已复制到剪贴板',
          );
        } catch (_) {
          _notifications.add(
            languageCode == 'en'
                ? 'Received text from ${peer.displayName}'
                : '收到 ${peer.displayName} 的文字',
          );
        }
      } else if ((kind == 'text' || kind == 'link') && body.isNotEmpty) {
        _notifications.add(
          languageCode == 'en'
              ? 'Received text from ${peer.displayName}'
              : '收到 ${peer.displayName} 的文字',
        );
      } else {
        _notifications.add(
          languageCode == 'en'
              ? 'Received a message from ${peer.displayName}'
              : '收到 ${peer.displayName} 的消息',
        );
      }
      _updates.add(null);
      return _json({'ok': true});
    },
  );

  Future<Response> _receiveTransferStart(Request request) =>
      _withTrustedEnvelope(request, (peer, payload) async {
        final conversation = await _db.ensureConversation(peer);
        final at = DateTime.now();
        final relativePath = _nullableString(payload['relative_path']);
        final file = await _fileStore.createReceiveFile(
          _string(payload['file_name'], 'received.bin'),
          conversationFolder: FileStore.conversationFolder(
            peer.displayName,
            peer.id,
          ),
          at: at,
          relativePath: relativePath,
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
                relativePath: Value(relativePath),
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
            relativePath: Value(relativePath),
            createdAt: DateTime.now(),
          ),
        );
        _notifications.add(
          languageCode == 'en'
              ? relativePath != null
                    ? 'Received ${peer.displayName}: $relativePath'
                    : 'Received file from ${peer.displayName}: $fileName'
              : relativePath != null
              ? '收到 ${peer.displayName}：$relativePath'
              : '收到 ${peer.displayName} 的文件：$fileName',
        );
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
    final cancel = _inboundCancels[id] = _InboundCancel();
    var expectedIndex = 0;
    var received = 0;
    try {
      while (true) {
        if (cancel.canceled) {
          throw const _OutboundCancelled();
        }
        final frame = await reader.next();
        // cancel 请求可能在等待下一帧时到达；流关闭后仍需再次检查标志，
        // 否则 EOF 会被当成正常结束并留下 receiving 记录。
        if (cancel.canceled) {
          throw const _OutboundCancelled();
        }
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
    } on _OutboundCancelled {
      await sink.close();
      await _abortInboundTransfer(id, received);
      return _json({'ok': true, 'canceled': true});
    } catch (error) {
      await sink.close();
      await _markTransferStatus(id, 'failed', received);
      _inboundCancels.remove(id);
      return Response(400, body: '$error');
    }
    _inboundCancels.remove(id);
    _updates.add(null);
    return _json({'ok': true, 'received_bytes': received});
  }

  /// 接收端被对端取消：关闭流、标记 canceled、删除临时文件。
  Future<void> _abortInboundTransfer(String id, int received) async {
    final transfer = await (_db.select(
      _db.transfers,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    final tempPath = transfer?.filePath;
    await (_db.update(_db.transfers)..where((tbl) => tbl.id.equals(id))).write(
      TransfersCompanion(
        status: const Value('canceled'),
        errorCode: const Value('remote_canceled'),
        receivedBytes: Value(received),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await (_db.update(_db.chatMessages)
          ..where((tbl) => tbl.transferId.equals(id)))
        .write(const ChatMessagesCompanion(status: Value('canceled')));
    if (tempPath != null) {
      final file = File(tempPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    _inboundCancels.remove(id);
    _updates.add(null);
  }

  Future<Response> _receiveTransferCancel(Request request, String id) =>
      _withTrustedEnvelope(request, (peer, payload) async {
        final transferId = _string(payload['transfer_id'], id);
        final transfer = await (_db.select(
          _db.transfers,
        )..where((tbl) => tbl.id.equals(transferId))).getSingleOrNull();
        if (transfer == null) {
          return _json({'ok': false, 'reason': 'not_found'});
        }
        if (transfer.peerDeviceId != peer.id) {
          return Response.forbidden('Transfer does not belong to peer');
        }
        if (transfer.direction != 'in' || transfer.status != 'receiving') {
          // 已完成或非接收中的传输无法取消。
          return _json({'ok': false, 'reason': 'already_done'});
        }
        final cancel = _inboundCancels[transferId];
        if (cancel != null) {
          cancel.canceled = true;
        } else {
          // 没有活动流（例如旧版分块路径），直接中止落盘记录。
          await _abortInboundTransfer(transferId, transfer.receivedBytes);
        }
        return _json({'ok': true, 'canceled': true});
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
        relativePath: transfer.relativePath,
        moveSource: Platform.isWindows,
      );
      await _db.markTransferSaved(
        transferId: id,
        savedPath: saved.path,
        savedUri: saved.uri,
        fileName: saved.actualFileName,
        localFilePath: saved.uri == null ? saved.path : null,
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
    _OutboundTask? task,
  }) async {
    final current = await _freshPeer(peer);
    try {
      await _postSecureOnce(current, path, payload, method: method, task: task);
    } catch (error) {
      if (task?.canceled == true) throw const _OutboundCancelled();
      if (!_isConnectionError(error)) {
        rethrow;
      }
      await _db.markDeviceOffline(current.id);
      _updates.add(null);
      final resolved = await reconnectPeer?.call(current.id);
      if (resolved == null) {
        rethrow;
      }
      if (task?.canceled == true) throw const _OutboundCancelled();
      await _postSecureOnce(
        resolved,
        path,
        payload,
        method: method,
        task: task,
      );
    }
  }

  Future<void> _postSecureOnce(
    Device peer,
    String path,
    Map<String, Object?> payload, {
    String method = 'post',
    _OutboundTask? task,
  }) async {
    if (peer.host == null || peer.port == null) {
      throw StateError('Peer endpoint is not known.');
    }
    final envelope = await _securityService.seal(peer, {
      ...payload,
      'sender_listen_port': _port,
    });
    final uri = Uri.parse('http://${peer.host}:${peer.port}$path');
    try {
      if (method == 'put') {
        await _dio.putUri(uri, data: envelope, cancelToken: task?.cancelToken);
      } else {
        await _dio.postUri(uri, data: envelope, cancelToken: task?.cancelToken);
      }
    } on dio.DioException catch (error) {
      if (task?.canceled == true || error.type == dio.DioExceptionType.cancel) {
        throw const _OutboundCancelled();
      }
      rethrow;
    }
    await _db.updateDeviceEndpoint(
      id: peer.id,
      host: peer.host!,
      port: peer.port!,
    );
  }

  /// 安全信封 POST 并返回解析后的响应体（供需要读取对端应答的接口使用，如取消）。
  Future<Map<String, Object?>> _postSecureExpect(
    Device peer,
    String path,
    Map<String, Object?> payload,
  ) async {
    if (peer.host == null || peer.port == null) {
      throw StateError('Peer endpoint is not known.');
    }
    final envelope = await _securityService.seal(peer, {
      ...payload,
      'sender_listen_port': _port,
    });
    final uri = Uri.parse('http://${peer.host}:${peer.port}$path');
    final response = await _dio.postUri<Map<String, dynamic>>(
      uri,
      data: envelope,
    );
    final data = response.data;
    if (data != null) return Map<String, Object?>.from(data);
    return const <String, Object?>{};
  }

  Future<Device> _freshPeer(Device peer) async {
    return await _db.getDevice(peer.id) ?? peer;
  }

  /// 构建传输中心所需的全部任务视图（合并 DB 持久化进度与内存实时速度）。
  Future<List<TransferTaskView>> buildTransferTaskViews() async {
    final transfers = await (_db.select(
      _db.transfers,
    )..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])).get();
    final peers = <String, Device>{};
    for (final transfer in transfers) {
      if (!peers.containsKey(transfer.peerDeviceId)) {
        peers[transfer.peerDeviceId] =
            await _db.getDevice(transfer.peerDeviceId) ??
            Device(
              id: transfer.peerDeviceId,
              displayName: transfer.peerDeviceId,
              platform: 'unknown',
              signingPublicKey: '',
              exchangePublicKey: '',
              fingerprint: '',
              avatarSeed: '',
              avatarColor: '#2563EB',
              trusted: false,
              endpointSource: 'auto',
              createdAt: DateTime.now(),
            );
      }
    }
    return transfers.map((transfer) {
      final stat = _liveStats[transfer.id];
      final sentBytes = transfer.direction == 'out'
          ? (stat?.sentBytes ?? transfer.receivedBytes)
          : transfer.receivedBytes;
      return TransferTaskView(
        transfer: transfer,
        peerDisplayName:
            peers[transfer.peerDeviceId]?.displayName ?? transfer.peerDeviceId,
        sentBytes: sentBytes,
        totalBytes: transfer.fileSize,
        bytesPerSecond: stat?.bytesPerSecond ?? 0,
        errorCode: transfer.errorCode,
        groupId: transfer.groupId,
      );
    }).toList();
  }

  /// 按 groupId 聚合任务视图为组视图；无 groupId 的任务各成独立单元素组。
  Future<List<TransferGroupView>> buildTransferGroupViews() async {
    final tasks = await buildTransferTaskViews();
    final byGroup = <String, List<TransferTaskView>>{};
    for (final task in tasks) {
      final key = task.groupId ?? task.transfer.id;
      byGroup.putIfAbsent(key, () => []).add(task);
    }
    return byGroup.entries.map((entry) {
      // 组内按更新时间排序，保证展示稳定。
      entry.value.sort(
        (a, b) => b.transfer.updatedAt.compareTo(a.transfer.updatedAt),
      );
      return TransferGroupView(
        groupId: entry.key,
        peerDisplayName: entry.value.first.peerDisplayName,
        tasks: entry.value,
      );
    }).toList();
  }

  /// 判断已存储的对端设备是否支持主动取消传输。
  bool deviceSupportsCancel(Device peer) =>
      peerSupportsCancel(_db.deviceCapabilities(peer));

  /// 请求对端取消一个出站传输（要求对端支持 transfer_cancel_v1）。
  /// 返回是否被对端接受；对端不支持能力时返回 false（调用方应据此禁用并提示）。
  Future<bool> requestRemoteCancel(Device peer, String transferId) async {
    if (!deviceSupportsCancel(peer)) return false;
    try {
      final response = await _postSecureExpect(
        peer,
        '/v1/transfers/$transferId/cancel',
        {'transfer_id': transferId},
      ).timeout(const Duration(seconds: 3));
      return response['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 发送前置守卫：已信任设备的身份公钥/指纹发生变化（identity_changed）时禁止
  /// 发送，要求用户删除后重新配对（计划 P0）。在所有出站发送路径调用。
  void _requireIdentityUnchanged(Device peer) {
    if (peer.identityChanged == true) {
      throw AppFailure(
        code: 'peer_identity_changed',
        userMessage: languageCode == 'en'
            ? "This device's identity has changed. Delete it and re-pair to continue."
            : '该设备身份已变化，请删除后重新配对后再发送',
      );
    }
  }

  /// 从 hello / pair 响应体里解析对端能力列表。
  List<String> _capabilitiesFrom(Object? raw) {
    if (raw is List) return raw.whereType<String>().toList();
    return const <String>[];
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
    _OutboundTask? task,
  }) async {
    final now = DateTime.now();
    // 实时统计：更新内存速度（发送字节数与瞬时速率），供传输中心展示。
    final stat = _liveStats[id];
    if (stat != null) {
      stat.sentBytes = receivedBytes;
      final lastAt = stat.lastSampleAt;
      if (lastAt == null || now.difference(lastAt) >= _speedSampleInterval) {
        final delta = receivedBytes - stat.lastSampledBytes;
        final elapsed = lastAt == null
            ? _speedSampleInterval
            : now.difference(lastAt);
        if (elapsed.inMilliseconds > 0) {
          stat.bytesPerSecond = delta * 1000 / elapsed.inMilliseconds;
        }
        stat.lastSampleAt = now;
        stat.lastSampledBytes = receivedBytes;
      }
    }
    final lastBytes = _lastProgressBytes[id];
    final lastAt = _lastProgressPersistedAt[id];
    if (!force &&
        lastBytes != null &&
        receivedBytes <= lastBytes &&
        lastAt != null) {
      _updates.add(null);
      return;
    }
    if (!force &&
        lastAt != null &&
        now.difference(lastAt) < _progressPersistInterval) {
      _lastProgressBytes[id] = receivedBytes;
      _updates.add(null);
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

/// 一个排队或正在执行的单文件出站传输任务。
class _OutboundTask {
  _OutboundTask({
    required this.transferId,
    required this.peerId,
    required this.file,
    required this.name,
    required this.length,
    required this.mimeType,
    required this.totalChunks,
    required this.groupId,
    this.relativePath,
    this.completion,
  });

  final String transferId;
  final String peerId;
  final File file;
  final String name;
  final int length;
  final String? mimeType;
  final int totalChunks;
  final String groupId;
  final String? relativePath;
  final Completer<void>? completion;

  /// 运行期取消控制：dio 请求取消令牌 + 流生成中断标志。
  final dio.CancelToken cancelToken = dio.CancelToken();
  bool canceled = false;

  void complete() {
    final value = completion;
    if (value != null && !value.isCompleted) value.complete();
  }

  void completeError(Object error) {
    final value = completion;
    if (value != null && !value.isCompleted) value.completeError(error);
  }
}

/// 传输实时统计（内存态）：发送字节数 + 瞬时速度。
class _LiveTransferStat {
  _LiveTransferStat({required this.totalBytes});
  final int totalBytes;
  int sentBytes = 0;
  double bytesPerSecond = 0;
  DateTime? lastSampleAt;
  int lastSampledBytes = 0;
}

/// 入站接收取消信号：被对端 cancel 接口触发后中断流读取循环。
class _InboundCancel {
  bool canceled = false;
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
