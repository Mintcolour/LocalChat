enum DiscoveryAvailability { notStarted, active, degraded, unavailable }

class DiscoveryBindFailure {
  const DiscoveryBindFailure({
    required this.port,
    required this.message,
    this.errorCode,
    this.address,
    this.interfaceName,
  });

  final int port;
  final int? errorCode;
  final String message;
  final String? address;
  final String? interfaceName;
}

class DiscoveryHealth {
  const DiscoveryHealth({
    required this.availability,
    this.boundPort,
    this.bindFailures = const <DiscoveryBindFailure>[],
    this.interfaceAddresses = const <String>[],
  });

  const DiscoveryHealth.notStarted()
    : availability = DiscoveryAvailability.notStarted,
      boundPort = null,
      bindFailures = const <DiscoveryBindFailure>[],
      interfaceAddresses = const <String>[];

  final DiscoveryAvailability availability;
  final int? boundPort;
  final List<DiscoveryBindFailure> bindFailures;
  final List<String> interfaceAddresses;

  bool get available =>
      availability == DiscoveryAvailability.active ||
      availability == DiscoveryAvailability.degraded;
}

enum WindowsFirewallRuleState {
  unsupported,
  configured,
  missing,
  denied,
  unknown,
}

class WindowsFirewallStatus {
  const WindowsFirewallStatus({
    required this.state,
    this.udpConfigured = false,
    this.tcpConfigured = false,
    this.errorCode,
    this.detail,
  });

  const WindowsFirewallStatus.unsupported()
    : state = WindowsFirewallRuleState.unsupported,
      udpConfigured = false,
      tcpConfigured = false,
      errorCode = null,
      detail = null;

  final WindowsFirewallRuleState state;
  final bool udpConfigured;
  final bool tcpConfigured;
  final int? errorCode;
  final String? detail;

  bool get configured => state == WindowsFirewallRuleState.configured;
}

class NetworkHealthSnapshot {
  const NetworkHealthSnapshot({
    required this.createdAt,
    required this.transportPort,
    required this.discovery,
    required this.localEndpoints,
    required this.firewall,
  });

  final DateTime createdAt;
  final int transportPort;
  final DiscoveryHealth discovery;
  final List<String> localEndpoints;
  final WindowsFirewallStatus firewall;
}
