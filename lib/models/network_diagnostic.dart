import 'protocol.dart';

enum NetworkDiagnosticStatus {
  reachable,
  invalidInput,
  timeout,
  connectionRefused,
  networkUnreachable,
  nonLocalChat,
  identityMismatch,
  unknownError,
}

class NetworkDiagnosticResult {
  const NetworkDiagnosticResult({
    required this.host,
    required this.port,
    required this.status,
    this.peer,
    this.errorDetail,
    this.localEndpoints = const <String>[],
  });

  final String host;
  final int port;
  final NetworkDiagnosticStatus status;
  final DiscoveredPeer? peer;
  final String? errorDetail;
  final List<String> localEndpoints;

  bool get reachable => status == NetworkDiagnosticStatus.reachable;
  String get endpoint => '$host:$port';

  NetworkDiagnosticResult withLocalEndpoints(List<String> endpoints) {
    return NetworkDiagnosticResult(
      host: host,
      port: port,
      status: status,
      peer: peer,
      errorDetail: errorDetail,
      localEndpoints: endpoints,
    );
  }
}
