import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../models/protocol.dart';
import 'identity_service.dart';

class DiscoveryService {
  DiscoveryService(
    this._db,
    this._identityService, {
    void Function(InternetAddress address, int port, List<int> data)?
    sendObserver,
    // ignore: prefer_initializing_formals
  }) : _sendObserver = sendObserver;

  final AppDatabase _db;
  final IdentityService _identityService;
  final void Function(InternetAddress address, int port, List<int> data)?
  _sendObserver;
  final _peers = StreamController<DiscoveredPeer>.broadcast();
  final List<RawDatagramSocket> _sockets = [];
  Timer? _timer;
  int _listenPort = 0;

  Stream<DiscoveredPeer> get peers => _peers.stream;

  Future<void> start({required int listenPort}) async {
    _listenPort = listenPort;
    await stop();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    socket.listen(_handleEvent);
    _sockets.add(socket);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => announce());
    await announce();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
  }

  Future<void> announce() async {
    if (_listenPort <= 0 || _sockets.isEmpty) {
      return;
    }
    final data = _discoveryPayload();
    _sendPayloadTo(InternetAddress('255.255.255.255'), data);
    final devices = await _db.listDevices();
    for (final device in devices) {
      final host = device.host;
      if (host == null || host.isEmpty) continue;
      final address = InternetAddress.tryParse(host);
      if (address == null || address.type != InternetAddressType.IPv4) {
        continue;
      }
      _sendPayloadTo(address, data);
    }
  }

  Future<void> announceTo(
    InternetAddress address, {
    bool isReply = false,
  }) async {
    if (_listenPort <= 0) return;
    _sendPayloadTo(address, _discoveryPayload(isReply: isReply));
  }

  Future<void> _handleEvent(RawSocketEvent event) async {
    if (event != RawSocketEvent.read) {
      return;
    }
    for (final socket in _sockets) {
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        await _handleDatagram(datagram!.data, datagram.address);
      }
    }
  }

  @visibleForTesting
  Future<void> handleDatagramForTest(
    List<int> data,
    InternetAddress address, {
    required int listenPort,
  }) async {
    final previousPort = _listenPort;
    _listenPort = listenPort;
    try {
      await _handleDatagram(data, address);
    } finally {
      _listenPort = previousPort;
    }
  }

  Future<void> _handleDatagram(List<int> data, InternetAddress address) async {
    final peer = DiscoveredPeer.fromDatagram(data, address.address);
    if (peer == null || peer.deviceId == _identityService.identity.deviceId) {
      return;
    }
    // 摄入对端身份前先校验设备 ID / 公钥 / 指纹自洽，拒绝不一致的发现包。
    try {
      validatePeerIdentity(
        deviceId: peer.deviceId,
        signingPublicKey: peer.signingPublicKey,
        fingerprint: peer.fingerprint,
      );
    } catch (_) {
      return;
    }
    await _db.upsertDiscoveredDevice(
      id: peer.deviceId,
      displayName: peer.displayName,
      platform: peer.platform,
      host: peer.host,
      port: peer.port,
      signingPublicKey: peer.signingPublicKey,
      exchangePublicKey: peer.exchangePublicKey,
      fingerprint: peer.fingerprint,
      avatarSeed: peer.avatarSeed,
      avatarColor: peer.avatarColor,
      capabilities: peer.capabilities,
    );
    _peers.add(peer);
    if (!_isReplyPacket(data)) {
      await announceTo(address, isReply: true);
    }
  }

  List<int> _discoveryPayload({bool isReply = false}) {
    final identity = _identityService.identity;
    final peer = DiscoveredPeer(
      deviceId: identity.deviceId,
      displayName: identity.displayName,
      platform: identity.platform,
      host: '',
      port: _listenPort,
      signingPublicKey: identity.signingPublicKey,
      exchangePublicKey: identity.exchangePublicKey,
      fingerprint: identity.fingerprint,
      avatarSeed: identity.avatarSeed,
      avatarColor: identity.avatarColor,
      lastSeen: DateTime.now(),
    );
    final json = peer.toJson();
    if (isReply) {
      json['discovery_reply'] = true;
    }
    return utf8.encode(jsonEncode(json));
  }

  void _sendPayloadTo(InternetAddress address, List<int> data) {
    if (_sockets.isEmpty) {
      _sendObserver?.call(address, discoveryPort, data);
      return;
    }
    for (final socket in _sockets) {
      _sendObserver?.call(address, discoveryPort, data);
      socket.send(data, address, discoveryPort);
    }
  }

  bool _isReplyPacket(List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map<String, Object?>) {
        return decoded['discovery_reply'] == true;
      }
      if (decoded is Map) {
        return decoded['discovery_reply'] == true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
