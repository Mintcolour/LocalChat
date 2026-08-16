import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../models/network_health.dart';
import '../models/protocol.dart';
import 'diagnostic_log_service.dart';
import 'identity_service.dart';

typedef DiscoverySocketBinder =
    Future<RawDatagramSocket> Function(InternetAddress address, int port);
typedef DiscoveryInterfaceLoader =
    Future<List<DiscoveryInterfaceAddress>> Function();

class DiscoveryInterfaceAddress {
  const DiscoveryInterfaceAddress({required this.name, required this.address});

  final String name;
  final InternetAddress address;
}

class DiscoveryService {
  DiscoveryService(
    this._db,
    this._identityService, {
    this._logger = const NoopDiagnosticLogger(),
    DiscoverySocketBinder? socketBinder,
    DiscoveryInterfaceLoader? interfaceLoader,
    List<int> candidatePorts = discoveryPorts,
    this._sendObserver,
  }) : _socketBinder = socketBinder ?? _bindSocket,
       _interfaceLoader = interfaceLoader ?? _loadInterfaces,
       _candidatePorts = List<int>.unmodifiable(candidatePorts);

  final AppDatabase _db;
  final IdentityService _identityService;
  final DiagnosticLogger _logger;
  final DiscoverySocketBinder _socketBinder;
  final DiscoveryInterfaceLoader _interfaceLoader;
  final List<int> _candidatePorts;
  final void Function(InternetAddress address, int port, List<int> data)?
  _sendObserver;
  final _peers = StreamController<DiscoveredPeer>.broadcast();
  final List<StreamSubscription<RawSocketEvent>> _socketSubscriptions = [];
  final Map<String, RawDatagramSocket> _interfaceSockets = {};
  RawDatagramSocket? _listenerSocket;
  Timer? _timer;
  Timer? _interfaceTimer;
  int _transportPort = 0;
  DiscoveryHealth _health = const DiscoveryHealth.notStarted();

  Stream<DiscoveredPeer> get peers => _peers.stream;
  DiscoveryHealth get health => _health;

  Future<DiscoveryHealth> start({required int listenPort}) async {
    await stop();
    _transportPort = listenPort;
    final failures = <DiscoveryBindFailure>[];
    for (final port in _candidatePorts) {
      try {
        final socket = await _socketBinder(InternetAddress.anyIPv4, port);
        socket.broadcastEnabled = true;
        _listenerSocket = socket;
        _listen(socket);
        _logger.info('discovery.bind_success', {'port': socket.port});
        break;
      } on SocketException catch (error) {
        final failure = DiscoveryBindFailure(
          port: port,
          errorCode: error.osError?.errorCode,
          message: error.message,
        );
        failures.add(failure);
        _logger.warning('discovery.bind_failed', {
          'port': port,
          'errno': failure.errorCode,
          'error': failure.message,
        });
      } catch (error, stackTrace) {
        failures.add(DiscoveryBindFailure(port: port, message: '$error'));
        _logger.error('discovery.bind_failed', error, stackTrace);
      }
    }

    final listener = _listenerSocket;
    if (listener == null) {
      _health = DiscoveryHealth(
        availability: DiscoveryAvailability.unavailable,
        bindFailures: failures,
      );
      return _health;
    }

    await _refreshInterfaceSockets();
    _health = DiscoveryHealth(
      availability: listener.port == _candidatePorts.first
          ? DiscoveryAvailability.active
          : DiscoveryAvailability.degraded,
      boundPort: listener.port,
      bindFailures: failures,
      interfaceAddresses: _interfaceSockets.keys.toList()..sort(),
    );
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(announce()),
    );
    _interfaceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshInterfaceSockets()),
    );
    await announce();
    return _health;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _interfaceTimer?.cancel();
    _interfaceTimer = null;
    for (final subscription in _socketSubscriptions) {
      await subscription.cancel();
    }
    _socketSubscriptions.clear();
    _listenerSocket?.close();
    _listenerSocket = null;
    for (final socket in _interfaceSockets.values) {
      socket.close();
    }
    _interfaceSockets.clear();
  }

  Future<void> announce() async {
    if (_transportPort <= 0 || _listenerSocket == null) return;
    final data = _discoveryPayload();
    final senders = _interfaceSockets.values.isEmpty
        ? <RawDatagramSocket>[_listenerSocket!]
        : _interfaceSockets.values.toList();
    for (final socket in senders) {
      for (final port in _candidatePorts) {
        _sendPayloadTo(
          InternetAddress('255.255.255.255'),
          port,
          data,
          socket: socket,
        );
      }
    }
    final devices = await _db.listDevices();
    for (final device in devices) {
      final host = device.host;
      if (host == null || host.isEmpty) continue;
      final address = InternetAddress.tryParse(host);
      if (address == null || address.type != InternetAddressType.IPv4) {
        continue;
      }
      for (final port in _candidatePorts) {
        for (final socket in senders) {
          _sendPayloadTo(address, port, data, socket: socket);
        }
      }
    }
    _logger.info('discovery.announce', {
      'ports': _candidatePorts.join(','),
      'interfaces': senders.length,
      'knownPeers': devices.length,
    });
  }

  Future<void> announceTo(
    InternetAddress address, {
    required int destinationPort,
    bool isReply = false,
    RawDatagramSocket? socket,
  }) async {
    if (_transportPort <= 0) return;
    _sendPayloadTo(
      address,
      destinationPort,
      _discoveryPayload(isReply: isReply),
      socket: socket ?? _listenerSocket,
    );
  }

  void _listen(RawDatagramSocket socket) {
    _socketSubscriptions.add(
      socket.listen(
        (event) => _handleEvent(socket, event),
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning('discovery.socket_error', {'error': '$error'});
        },
      ),
    );
  }

  Future<void> _handleEvent(
    RawDatagramSocket socket,
    RawSocketEvent event,
  ) async {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      await _handleDatagram(
        datagram!.data,
        datagram.address,
        datagram.port,
        replySocket: socket,
      );
    }
  }

  @visibleForTesting
  Future<void> handleDatagramForTest(
    List<int> data,
    InternetAddress address, {
    required int listenPort,
    int sourcePort = discoveryPort,
  }) async {
    final previousPort = _transportPort;
    _transportPort = listenPort;
    try {
      await _handleDatagram(data, address, sourcePort);
    } finally {
      _transportPort = previousPort;
    }
  }

  Future<void> _handleDatagram(
    List<int> data,
    InternetAddress address,
    int sourcePort, {
    RawDatagramSocket? replySocket,
  }) async {
    final peer = DiscoveredPeer.fromDatagram(data, address.address);
    if (peer == null || peer.deviceId == _identityService.identity.deviceId) {
      return;
    }
    try {
      validatePeerIdentity(
        deviceId: peer.deviceId,
        signingPublicKey: peer.signingPublicKey,
        fingerprint: peer.fingerprint,
      );
    } catch (_) {
      _logger.warning('discovery.invalid_identity', {
        'host': address.address,
        'deviceId': _shortId(peer.deviceId),
      });
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
    _logger.info('discovery.peer_received', {
      'host': address.address,
      'sourcePort': sourcePort,
      'transportPort': peer.port,
      'deviceId': _shortId(peer.deviceId),
    });
    if (!_isReplyPacket(data)) {
      await announceTo(
        address,
        destinationPort: sourcePort,
        isReply: true,
        socket: replySocket,
      );
    }
  }

  Future<void> _refreshInterfaceSockets() async {
    if (_listenerSocket == null) return;
    List<DiscoveryInterfaceAddress> interfaces;
    try {
      interfaces = await _interfaceLoader();
    } catch (error, stackTrace) {
      _logger.error('discovery.interfaces_failed', error, stackTrace);
      return;
    }
    final privateInterfaces = interfaces
        .where((item) => _isPrivateIpv4(item.address))
        .toList();
    final selected = privateInterfaces.isEmpty ? interfaces : privateInterfaces;
    final desired = <String, DiscoveryInterfaceAddress>{
      for (final item in selected)
        if (!item.address.isLoopback &&
            !item.address.address.startsWith('169.254.'))
          item.address.address: item,
    };

    for (final address in _interfaceSockets.keys.toList()) {
      if (desired.containsKey(address)) continue;
      _interfaceSockets.remove(address)?.close();
      _logger.info('discovery.interface_removed', {'address': address});
    }
    for (final entry in desired.entries) {
      if (_interfaceSockets.containsKey(entry.key)) continue;
      try {
        final socket = await _socketBinder(entry.value.address, 0);
        socket.broadcastEnabled = true;
        _interfaceSockets[entry.key] = socket;
        _listen(socket);
        _logger.info('discovery.interface_added', {
          'name': entry.value.name,
          'address': entry.key,
          'sourcePort': socket.port,
        });
      } catch (error, stackTrace) {
        _logger.error('discovery.interface_bind_failed', error, stackTrace);
      }
    }
    _health = DiscoveryHealth(
      availability: _health.availability,
      boundPort: _listenerSocket?.port,
      bindFailures: _health.bindFailures,
      interfaceAddresses: _interfaceSockets.keys.toList()..sort(),
    );
  }

  List<int> _discoveryPayload({bool isReply = false}) {
    final identity = _identityService.identity;
    final peer = DiscoveredPeer(
      deviceId: identity.deviceId,
      displayName: identity.displayName,
      platform: identity.platform,
      host: '',
      port: _transportPort,
      signingPublicKey: identity.signingPublicKey,
      exchangePublicKey: identity.exchangePublicKey,
      fingerprint: identity.fingerprint,
      avatarSeed: identity.avatarSeed,
      avatarColor: identity.avatarColor,
      lastSeen: DateTime.now(),
    );
    final json = peer.toJson();
    if (isReply) json['discovery_reply'] = true;
    return utf8.encode(jsonEncode(json));
  }

  void _sendPayloadTo(
    InternetAddress address,
    int port,
    List<int> data, {
    RawDatagramSocket? socket,
  }) {
    _sendObserver?.call(address, port, data);
    final sender = socket;
    if (sender == null) return;
    try {
      sender.send(data, address, port);
    } on SocketException catch (error) {
      _logger.warning('discovery.send_failed', {
        'address': address.address,
        'port': port,
        'errno': error.osError?.errorCode,
        'error': error.message,
      });
    } catch (error, stackTrace) {
      _logger.error('discovery.send_failed', error, stackTrace);
    }
  }

  bool _isReplyPacket(List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map) return decoded['discovery_reply'] == true;
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<RawDatagramSocket> _bindSocket(
    InternetAddress address,
    int port,
  ) {
    return RawDatagramSocket.bind(address, port, reuseAddress: true);
  }

  static Future<List<DiscoveryInterfaceAddress>> _loadInterfaces() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (address.type == InternetAddressType.IPv4)
            DiscoveryInterfaceAddress(name: interface.name, address: address),
    ];
  }

  static bool _isPrivateIpv4(InternetAddress address) {
    final parts = address.address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
}
