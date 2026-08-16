import 'dart:io';

import 'package:flutter/services.dart';

import '../models/network_health.dart';
import 'diagnostic_log_service.dart';

class WindowsFirewallService {
  WindowsFirewallService({
    this._logger = const NoopDiagnosticLogger(),
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('localchat/windows_network');

  final DiagnosticLogger _logger;
  final MethodChannel _channel;

  bool get isSupported => Platform.isWindows;

  Future<WindowsFirewallStatus> getStatus() async {
    if (!isSupported) return const WindowsFirewallStatus.unsupported();
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'getFirewallStatus',
      );
      return _decode(value);
    } on MissingPluginException catch (error) {
      _logger.error('firewall.plugin_missing', error);
      return const WindowsFirewallStatus(
        state: WindowsFirewallRuleState.unknown,
        detail: 'Windows firewall integration is unavailable.',
      );
    } on PlatformException catch (error) {
      _logger.error('firewall.status_failed', error);
      return WindowsFirewallStatus(
        state: WindowsFirewallRuleState.unknown,
        errorCode: int.tryParse(error.code),
        detail: error.message,
      );
    } catch (error, stackTrace) {
      _logger.error('firewall.status_failed', error, stackTrace);
      return WindowsFirewallStatus(
        state: WindowsFirewallRuleState.unknown,
        detail: '$error',
      );
    }
  }

  Future<WindowsFirewallStatus> repair() async {
    if (!isSupported) return const WindowsFirewallStatus.unsupported();
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'repairFirewall',
      );
      final status = _decode(value);
      _logger.info('firewall.repair_result', {
        'state': status.state.name,
        'errorCode': status.errorCode,
      });
      return status;
    } on PlatformException catch (error) {
      final canceled = error.code == '1223' || error.code == 'canceled';
      _logger.warning('firewall.repair_failed', {
        'code': error.code,
        'error': error.message,
      });
      return WindowsFirewallStatus(
        state: canceled
            ? WindowsFirewallRuleState.missing
            : WindowsFirewallRuleState.denied,
        errorCode: int.tryParse(error.code),
        detail: canceled
            ? 'The administrator prompt was canceled.'
            : error.message,
      );
    } catch (error, stackTrace) {
      _logger.error('firewall.repair_failed', error, stackTrace);
      return WindowsFirewallStatus(
        state: WindowsFirewallRuleState.unknown,
        detail: '$error',
      );
    }
  }

  WindowsFirewallStatus _decode(Map<String, Object?>? value) {
    if (value == null) {
      return const WindowsFirewallStatus(
        state: WindowsFirewallRuleState.unknown,
        detail: 'No firewall status was returned.',
      );
    }
    final udp = value['udpConfigured'] == true;
    final tcp = value['tcpConfigured'] == true;
    final denied = value['denied'] == true;
    final configured = udp && tcp;
    return WindowsFirewallStatus(
      state: denied
          ? WindowsFirewallRuleState.denied
          : configured
          ? WindowsFirewallRuleState.configured
          : WindowsFirewallRuleState.missing,
      udpConfigured: udp,
      tcpConfigured: tcp,
      errorCode: value['errorCode'] is int ? value['errorCode'] as int : null,
      detail: value['detail'] as String?,
    );
  }
}
