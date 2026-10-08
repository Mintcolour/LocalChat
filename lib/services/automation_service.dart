import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../core/app_failure.dart';
import '../core/peer_status.dart';
import '../data/app_database.dart';
import 'transport_service.dart';
import 'window_service.dart';

const automationProtocolVersion = 1;
const _maxRequestBytes = 2 * 1024 * 1024;

class AutomationFailure implements Exception {
  const AutomationFailure(
    this.code,
    this.message,
    this.exitCode, {
    this.details = const {},
  });

  final String code;
  final String message;
  final int exitCode;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => {
    'ok': false,
    'status': 'failed',
    'errorCode': code,
    'message': message,
    'exitCode': exitCode,
    ...details,
  };
}

/// The same persisted messages/transfers used by the UI back automation jobs.
/// This dispatcher has no dependency on the selected conversation.
class AutomationDispatcher {
  AutomationDispatcher(this.db, this.transport);

  final AppDatabase db;
  final TransportService transport;

  Future<Map<String, String>> _deviceNames() async => {
    for (final conversation in await db.listConversations())
      conversation.peerDeviceId: conversation.title,
  };

  Future<Map<String, Object?>> devices() async {
    final names = await _deviceNames();
    return {
      'ok': true,
      'exitCode': 0,
      'devices': [
        for (final device in await db.listDevices())
          {
            'id': device.id,
            'name': names[device.id] ?? device.displayName,
            'deviceName': device.displayName,
            'platform': device.platform,
            'trusted': device.trusted,
            'online': isPeerOnline(device),
            'identityChanged': device.identityChanged == true,
          },
      ],
    };
  }

  Future<Device> _resolveTarget(Object? value) async {
    if (value is! String || value.trim().isEmpty) {
      throw const AutomationFailure('invalid_target', 'Specify --to.', 2);
    }
    final byId = await db.getDevice(value);
    if (byId != null) return byId;
    final names = await _deviceNames();
    final matches = (await db.listDevices())
        .where(
          (device) => device.displayName == value || names[device.id] == value,
        )
        .toList();
    if (matches.isEmpty) {
      throw const AutomationFailure('target_not_found', 'Device not found.', 4);
    }
    if (matches.length > 1) {
      throw AutomationFailure(
        'ambiguous_target',
        'Several devices have this name. Specify a device ID.',
        4,
        details: {
          'candidates': [
            for (final device in matches)
              {'id': device.id, 'name': names[device.id] ?? device.displayName},
          ],
        },
      );
    }
    return matches.single;
  }

  void _requireTrusted(Device peer) {
    if (!peer.trusted) {
      throw const AutomationFailure(
        'target_unpaired',
        'Pair the device in LocalChat first.',
        4,
      );
    }
    if (peer.identityChanged == true) {
      throw const AutomationFailure(
        'peer_identity_changed',
        'Device identity changed. Pair it again in LocalChat.',
        4,
      );
    }
  }

  Future<Map<String, Object?>> send(Map<String, Object?> request) async {
    final kinds = [
      'text',
      'files',
      'folder',
    ].where(request.containsKey).toList();
    if (kinds.length != 1) {
      throw const AutomationFailure(
        'invalid_source',
        'Specify exactly one of text, files or folder.',
        2,
      );
    }
    var peer = await _resolveTarget(request['target']);
    _requireTrusted(peer);
    final entries = <({String absolute, String? relative})>[];
    String? text;
    try {
      switch (kinds.single) {
        case 'text':
          final value = request['text'];
          if (value is! String || value.trim().isEmpty) {
            throw const AutomationFailure(
              'invalid_text',
              'Text must not be empty.',
              2,
            );
          }
          text = value;
        case 'files':
          final files = request['files'];
          if (files is! List || files.isEmpty) {
            throw const AutomationFailure('invalid_files', 'Specify files.', 2);
          }
          for (final file in files) {
            final absolute = await _readableFile(file);
            entries.add((absolute: absolute, relative: null));
          }
        case 'folder':
          final folder = request['folder'];
          if (folder is! String || !p.isAbsolute(folder)) {
            throw const AutomationFailure(
              'invalid_folder',
              'Folder path must be absolute.',
              2,
            );
          }
          if (await FileSystemEntity.type(folder, followLinks: false) !=
              FileSystemEntityType.directory) {
            throw const AutomationFailure(
              'invalid_folder',
              'Folder does not exist or is a symbolic link.',
              5,
            );
          }
          final root = p.basename(p.normalize(folder));
          if (root.isEmpty || p.equals(folder, p.dirname(folder))) {
            throw const AutomationFailure(
              'invalid_folder',
              'Select a folder below the filesystem root.',
              2,
            );
          }
          await for (final entity in Directory(
            folder,
          ).list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final absolute = await _readableFile(entity.path);
              entries.add((
                absolute: absolute,
                relative: p
                    .join(root, p.relative(entity.path, from: folder))
                    .replaceAll(r'\', '/'),
              ));
            }
          }
          if (entries.isEmpty) {
            throw const AutomationFailure(
              'folder_empty',
              'Folder contains no regular files.',
              5,
            );
          }
          entries.sort((a, b) => a.relative!.compareTo(b.relative!));
      }
    } on FileSystemException {
      throw const AutomationFailure(
        'source_unreadable',
        'Cannot read a source file or directory.',
        5,
      );
    }

    // Probe even if lastSeen is stale: autostart has not necessarily received a
    // discovery broadcast yet. checkPeer also verifies the pinned identity.
    final reachable = await transport.checkPeer(peer);
    final updated = await db.getDevice(peer.id);
    if (updated == null) {
      throw const AutomationFailure(
        'target_not_found',
        'Device was removed.',
        4,
      );
    }
    peer = updated;
    _requireTrusted(peer);
    if (!reachable) {
      throw AutomationFailure(
        'target_offline',
        'Device is offline. Retry later.',
        4,
        details: {'targetDeviceId': peer.id},
      );
    }
    try {
      final receipt = text != null
          ? await transport.enqueueTextWithReceipt(peer, text)
          : await transport.sendPreparedFilesWithReceipt(peer, entries);
      return await job(receipt.jobId);
    } on AppFailure catch (error) {
      throw AutomationFailure(error.code, error.userMessage, 4);
    } on FileSystemException {
      throw const AutomationFailure(
        'source_unreadable',
        'A source file became unavailable before enqueueing.',
        5,
      );
    }
  }

  Future<String> _readableFile(Object? path) async {
    if (path is! String || !p.isAbsolute(path)) {
      throw const AutomationFailure(
        'invalid_path',
        'File paths must be absolute.',
        2,
      );
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const AutomationFailure(
        'invalid_path',
        'Source is missing, not a regular file, or a symbolic link.',
        5,
      );
    }
    final handle = await File(path).open(mode: FileMode.read);
    await handle.close();
    return p.normalize(path);
  }

  Future<Map<String, Object?>> job(String jobId) async {
    if (jobId.startsWith('message:')) {
      final id = jobId.substring('message:'.length);
      final message =
          await (db.select(db.chatMessages)..where(
                (row) => row.id.equals(id) & row.direction.equals('out'),
              ))
              .getSingleOrNull();
      if (message == null) throw _unknownJob;
      return _snapshot(
        jobId,
        message.peerDeviceId,
        [
          {
            'messageId': message.id,
            'status': message.status,
            if (message.status == 'failed') 'errorCode': 'send_failed',
          },
        ],
        messageIds: [message.id],
      );
    }
    if (jobId.startsWith('group:')) {
      final group = jobId.substring('group:'.length);
      final transfers =
          await (db.select(db.transfers)
                ..where(
                  (row) =>
                      row.groupId.equals(group) & row.direction.equals('out'),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
              .get();
      if (transfers.isEmpty) throw _unknownJob;
      final ids = transfers.map((item) => item.id).toList();
      final messages =
          await (db.select(db.chatMessages)..where(
                (row) => row.transferId.isIn(ids) & row.direction.equals('out'),
              ))
              .get();
      return _snapshot(
        jobId,
        transfers.first.peerDeviceId,
        [
          for (final item in transfers)
            {
              'transferId': item.id,
              'fileName': item.fileName,
              'relativePath': item.relativePath,
              'status': item.status,
              'totalBytes': item.fileSize,
              'completedBytes': item.receivedBytes,
              if (item.errorCode != null) 'errorCode': item.errorCode,
            },
        ],
        messageIds: messages.map((item) => item.id).toList(),
        transferIds: ids,
        groupId: group,
      );
    }
    throw _unknownJob;
  }

  static const _unknownJob = AutomationFailure(
    'job_not_found',
    'Job not found.',
    2,
  );

  Map<String, Object?> _snapshot(
    String jobId,
    String target,
    List<Map<String, Object?>> items, {
    required List<String> messageIds,
    List<String> transferIds = const [],
    String? groupId,
  }) {
    final states = items.map((item) => item['status']).toList();
    const activeStates = {'queued', 'preparing', 'sending', 'receiving'};
    final terminal = !states.any(activeStates.contains);
    final sent = states.where((state) => state == 'sent').length;
    final String status;
    if (!terminal) {
      status = states.every((state) => state == 'queued')
          ? 'queued'
          : 'sending';
    } else if (sent == states.length) {
      status = 'sent';
    } else if (sent > 0) {
      status = 'partial_failure';
    } else if (states.every((state) => state == 'interrupted')) {
      status = 'interrupted';
    } else if (states.every((state) => state == 'canceled')) {
      status = 'canceled';
    } else {
      status = 'failed';
    }
    final ok = !terminal || status == 'sent';
    return {
      'ok': ok,
      'status': status,
      'terminal': terminal,
      'exitCode': ok ? 0 : 5,
      'jobId': jobId,
      'targetDeviceId': target,
      'messageIds': messageIds,
      'transferIds': transferIds,
      'groupId': groupId,
      if (!ok) 'errorCode': status == 'failed' ? 'send_failed' : status,
      'progress': {
        'totalItems': items.length,
        'completedItems': sent,
        'totalBytes': items.fold<int>(
          0,
          (sum, item) => sum + (item['totalBytes'] as int? ?? 0),
        ),
        'completedBytes': items.fold<int>(
          0,
          (sum, item) => sum + (item['completedBytes'] as int? ?? 0),
        ),
      },
      'items': items,
    };
  }
}

/// Separate from the LAN transport: loopback only, bearer authenticated, no
/// browser origins, and no request logging of credentials or content.
class AutomationService {
  AutomationService({
    required this.dispatcher,
    Future<String> Function(String)? publishDescriptor,
    Future<void> Function()? removeDescriptor,
  }) : _publishDescriptor =
           publishDescriptor ??
           const WindowService().publishAutomationDescriptor,
       _removeDescriptor =
           removeDescriptor ?? const WindowService().removeAutomationDescriptor;

  final AutomationDispatcher dispatcher;
  final Future<String> Function(String) _publishDescriptor;
  final Future<void> Function() _removeDescriptor;
  HttpServer? _server;
  bool _published = false;
  String? _token;

  int? get port => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    final random = Random.secure();
    _token = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
    try {
      await _publishDescriptor(
        jsonEncode({
          'protocolVersion': automationProtocolVersion,
          'port': server.port,
          'token': _token,
          'pid': pid,
        }),
      );
      _published = true;
    } catch (_) {
      await server.close(force: true);
      _server = null;
      _token = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    await server?.close(force: true);
    if (_published) {
      _published = false;
      await _removeDescriptor();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    Map<String, Object?> result;
    var status = HttpStatus.ok;
    try {
      if (_token == null ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $_token' ||
          request.headers.value('origin') != null) {
        status = HttpStatus.unauthorized;
        throw const AutomationFailure('unauthorized', 'Access denied.', 3);
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/health') {
        result = {
          'ok': true,
          'application': 'LocalChat',
          'protocolVersion': automationProtocolVersion,
          'exitCode': 0,
        };
      } else if (request.method == 'GET' && path == '/v1/devices') {
        result = await dispatcher.devices();
      } else if (request.method == 'GET' && path.startsWith('/v1/jobs/')) {
        result = await dispatcher.job(
          Uri.decodeComponent(path.substring('/v1/jobs/'.length)),
        );
      } else if (request.method == 'POST' && path == '/v1/send') {
        final builder = BytesBuilder();
        await for (final chunk in request.timeout(
          const Duration(seconds: 15),
        )) {
          if (builder.length + chunk.length > _maxRequestBytes) {
            throw const AutomationFailure(
              'request_too_large',
              'Request exceeds the 2 MiB limit.',
              2,
            );
          }
          builder.add(chunk);
        }
        final payload = jsonDecode(utf8.decode(builder.takeBytes()));
        if (payload is! Map<String, dynamic>) {
          throw const FormatException();
        }
        result = await dispatcher.send(payload);
      } else {
        status = HttpStatus.notFound;
        throw const AutomationFailure('not_found', 'Unknown endpoint.', 2);
      }
    } on AutomationFailure catch (error) {
      if (status == HttpStatus.ok) status = HttpStatus.badRequest;
      result = error.toJson();
    } on FormatException {
      status = HttpStatus.badRequest;
      result = const AutomationFailure(
        'invalid_json',
        'Invalid request JSON.',
        2,
      ).toJson();
    } catch (_) {
      status = HttpStatus.internalServerError;
      result = const AutomationFailure(
        'automation_failed',
        'LocalChat could not complete the operation.',
        5,
      ).toJson();
    }
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(jsonEncode(result));
      await request.response.close();
    } on IOException {
      // A CLI timeout/disconnect must not cancel a registered send.
    }
  }
}
