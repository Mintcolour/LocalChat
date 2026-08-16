import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/app_text.dart';
import '../models/network_health.dart';
import '../services/diagnostic_log_service.dart';
import '../services/discovery_service.dart';
import '../services/windows_firewall_service.dart';

/// 网络健康子控制器：持有发现/防火墙健康状态，负责快照构建、诊断摘要
/// 与日志导出等纯逻辑。
///
/// AppController P1 拆分的一部分（同 [SettingsController] 约定）：本类只持有
/// 网络健康相关状态与读写逻辑；操作互斥（operation key）、状态文案、错误与
/// 刷新广播仍由 AppController 门面统一处理。AppController 持有本实例并把
/// 对外字段/方法委托到这里，公共 API 保持不变。
class NetworkHealthController extends ChangeNotifier {
  NetworkHealthController({
    required this.discoveryService,
    required this.windowsFirewallService,
    this.diagnosticLogService,
    required int Function() readTransportPort,
    required AppText Function() readText,
    required DateTime Function() readNow,
    required DiagnosticLogger log,
    required Future<void> Function(String path) openDirectory,
  }) : _transportPort = readTransportPort,
       _text = readText,
       _now = readNow,
       _logger = log,
       _openFolder = openDirectory;

  final DiscoveryService discoveryService;
  final WindowsFirewallService windowsFirewallService;
  final DiagnosticLogService? diagnosticLogService;
  final int Function() _transportPort;
  final AppText Function() _text;
  final DateTime Function() _now;
  final DiagnosticLogger _logger;
  final Future<void> Function(String path) _openFolder;

  DiscoveryHealth discoveryHealth = const DiscoveryHealth.notStarted();
  WindowsFirewallStatus firewallStatus = const WindowsFirewallStatus(
    state: WindowsFirewallRuleState.unknown,
  );
  NetworkHealthSnapshot? snapshot;

  /// 由 AppController 在发现服务启动/降级路径上回写健康状态。
  void applyDiscoveryHealth(DiscoveryHealth health) {
    discoveryHealth = health;
  }

  /// 聚合发现、防火墙与本机端点为一份健康快照并更新本地字段。
  Future<NetworkHealthSnapshot> buildSnapshot() async {
    discoveryHealth = discoveryService.health;
    firewallStatus = await windowsFirewallService.getStatus();
    final endpoints = await loadLocalNetworkEndpoints();
    final snapshot = NetworkHealthSnapshot(
      createdAt: _now(),
      transportPort: _transportPort(),
      discovery: discoveryHealth,
      localEndpoints: endpoints,
      firewall: firewallStatus,
    );
    this.snapshot = snapshot;
    return snapshot;
  }

  /// 修复 Windows 防火墙入站规则：成功后重新广播一次发现。
  /// 返回修复后的规则状态，由调用方决定文案。
  Future<WindowsFirewallStatus> repairFirewall() async {
    firewallStatus = await windowsFirewallService.repair();
    if (firewallStatus.configured) {
      await discoveryService.announce();
    }
    return firewallStatus;
  }

  /// 手动重新广播发现包并刷新健康状态，返回最新健康快照字段。
  Future<DiscoveryHealth> reannounce() async {
    await discoveryService.announce();
    discoveryHealth = discoveryService.health;
    _logger.info('discovery.manual_announce');
    return discoveryHealth;
  }

  /// 启动阶段按发现可用性生成状态文案。
  String startupNetworkStatus(int port) {
    switch (discoveryHealth.availability) {
      case DiscoveryAvailability.active:
        return _text().startupDiscoveryActive(port);
      case DiscoveryAvailability.degraded:
        return _text().startupDiscoveryDegraded(
          discoveryHealth.boundPort ?? 0,
          port,
        );
      case DiscoveryAvailability.unavailable:
        return _text().startupDiscoveryUnavailable;
      case DiscoveryAvailability.notStarted:
        return _text().startupDiscoveryNotStarted;
    }
  }

  /// 生成多行诊断摘要文本。[appLine]/[platformLine] 由调用方提供版本与平台行。
  String buildDiagnosticSummary({
    required String appLine,
    required String platformLine,
  }) {
    final lines = <String>[
      appLine,
      platformLine,
      'Generated: ${_now().toIso8601String()}',
      'Transport port: ${_transportPort()}',
      'Discovery: ${discoveryHealth.availability.name}',
      'Discovery port: ${discoveryHealth.boundPort ?? '-'}',
      'Discovery interfaces: ${discoveryHealth.interfaceAddresses.join(', ')}',
      'Firewall: ${firewallStatus.state.name}',
      'Firewall UDP: ${firewallStatus.udpConfigured}',
      'Firewall TCP: ${firewallStatus.tcpConfigured}',
      'Local endpoints: ${snapshot?.localEndpoints.join(', ') ?? '-'}',
    ];
    for (final failure in discoveryHealth.bindFailures) {
      lines.add(
        'Bind failure: port=${failure.port} errno=${failure.errorCode ?? '-'} '
        'detail=${failure.message}',
      );
    }
    if (firewallStatus.detail != null) {
      lines.add('Firewall detail: ${firewallStatus.detail}');
    }
    return lines.join('\n');
  }

  /// 导出诊断报告；返回导出路径，用户取消时返回 null。
  Future<String?> exportDiagnosticReport(String summary) async {
    final logger = diagnosticLogService;
    if (logger == null) return null;
    final report = await logger.buildExport(summary);
    final fileName =
        'LocalChat-diagnostics-${_now().toIso8601String().replaceAll(':', '-')}.txt';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: _text().exportDiagnosticLogs,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: Platform.isAndroid
          ? Uint8List.fromList(utf8.encode(report))
          : null,
    );
    if (path == null) return null;
    if (!Platform.isAndroid) {
      await File(path).writeAsString(report, flush: true);
    }
    return path;
  }

  /// 打开诊断日志目录（有日志服务时）。
  Future<void> openDiagnosticLogFolder() async {
    final path = diagnosticLogService?.directoryPath;
    if (path == null || path.isEmpty) return;
    await _openFolder(path);
  }

  /// 列举本机活动 IPv4 网卡的 ip:port 端点。
  Future<List<String>> loadLocalNetworkEndpoints() async {
    final port = _transportPort();
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final endpoints = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
            continue;
          }
          final ip = address.address.trim();
          if (ip.isEmpty) continue;
          endpoints.add(port > 0 ? '$ip:$port' : ip);
        }
      }
      return endpoints.toList()..sort();
    } on SocketException {
      return const [];
    }
  }
}
