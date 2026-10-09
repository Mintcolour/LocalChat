import '../data/app_database.dart';

/// Bounded workers prevent an unreachable peer from blocking the whole list.
class PeerPresenceMonitor {
  PeerPresenceMonitor({this.concurrency = 4}) : assert(concurrency > 0);

  final int concurrency;
  bool _running = false;
  bool _stopped = false;

  Future<void> refresh({
    required Future<List<Device>> Function() loadPeers,
    required Future<bool> Function(Device) checkPeer,
    required Future<void> Function() onComplete,
  }) async {
    if (_running || _stopped) return;
    _running = true;
    try {
      final peers = await loadPeers();
      var next = 0;
      Future<void> worker() async {
        while (!_stopped && next < peers.length) {
          final peer = peers[next++];
          await checkPeer(peer);
        }
      }

      await Future.wait([
        for (var i = 0; i < concurrency && i < peers.length; i++) worker(),
      ]);
      if (!_stopped) await onComplete();
    } finally {
      _running = false;
    }
  }

  void stop() => _stopped = true;
}
