import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/app_database.dart';
import '../models/protocol.dart';
import 'identity_service.dart';

class DiscoveryService {
  DiscoveryService(this._db, this._identityService);

  final AppDatabase _db;
  final IdentityService _identityService;
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
    final data = utf8.encode(jsonEncode(peer.toJson()));
    for (final socket in _sockets) {
      socket.send(data, InternetAddress('255.255.255.255'), discoveryPort);
    }
  }

  Future<void> _handleEvent(RawSocketEvent event) async {
    if (event != RawSocketEvent.read) {
      return;
    }
    for (final socket in _sockets) {
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final peer = DiscoveredPeer.fromDatagram(
          datagram!.data,
          datagram.address.address,
        );
        if (peer == null ||
            peer.deviceId == _identityService.identity.deviceId) {
          continue;
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
        );
        _peers.add(peer);
      }
    }
  }
}
