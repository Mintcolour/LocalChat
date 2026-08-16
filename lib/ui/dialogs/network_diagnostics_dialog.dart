import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/models/network_diagnostic.dart';
import 'package:localchat/models/network_health.dart';

Future<void> showNetworkDiagnosticsDialog(
  BuildContext context,
  AppController controller,
) async {
  unawaited(controller.refreshNetworkHealth());
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AnimatedBuilder(
      animation: controller,
      builder: (dialogContext, _) {
        final text = controller.text;
        final discovery = controller.discoveryHealth;
        final firewall = controller.firewallStatus;
        final snapshot = controller.networkHealthSnapshot;
        final failures = discovery.bindFailures
            .map(
              (failure) =>
                  '${failure.port}: errno=${failure.errorCode ?? '-'} '
                  '${failure.message}',
            )
            .join('\n');
        return AlertDialog(
          title: Text(text.networkDiagnosticsAndLogs),
          scrollable: true,
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (discovery.availability) {
                    DiscoveryAvailability.active => Icons.check_circle_outline,
                    DiscoveryAvailability.degraded =>
                      Icons.warning_amber_outlined,
                    DiscoveryAvailability.unavailable => Icons.error_outline,
                    DiscoveryAvailability.notStarted =>
                      Icons.hourglass_empty_outlined,
                  }),
                  title: Text(
                    text.networkDiagnosticsSubtitle(discovery.availability),
                  ),
                  subtitle: Text(
                    '${text.discoveryListenPort}: '
                    '${discovery.boundPort ?? '-'}',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.swap_horiz_outlined),
                  title: Text(text.transportListenPort),
                  trailing: Text('${controller.localListenPort}'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.router_outlined),
                  title: Text(text.discoveryInterfaces),
                  subtitle: SelectableText(
                    discovery.interfaceAddresses.isEmpty
                        ? '-'
                        : discovery.interfaceAddresses.join('\n'),
                  ),
                ),
                if (failures.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.report_problem_outlined),
                    title: Text(text.discoveryBindFailures),
                    subtitle: SelectableText(failures),
                  ),
                if (Platform.isWindows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(text.firewallStatus),
                    subtitle: Text(text.firewallStatusLabel(firewall.state)),
                    trailing: firewall.configured
                        ? const Icon(Icons.check_circle_outline)
                        : FilledButton.icon(
                            onPressed: controller.firewallRepairInProgress
                                ? null
                                : controller.repairWindowsFirewall,
                            icon: controller.firewallRepairInProgress
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.build_outlined),
                            label: Text(text.repairFirewall),
                          ),
                  ),
                if (snapshot != null && snapshot.localEndpoints.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lan_outlined),
                    title: Text(text.localNetworkEndpoints),
                    subtitle: SelectableText(
                      snapshot.localEndpoints.join('\n'),
                    ),
                  ),
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.networkHealthInProgress
                          ? null
                          : controller.refreshNetworkHealth,
                      icon: const Icon(Icons.refresh),
                      label: Text(text.refreshNetworkStatus),
                    ),
                    OutlinedButton.icon(
                      onPressed: discovery.available
                          ? controller.reannounceDiscovery
                          : null,
                      icon: const Icon(Icons.campaign_outlined),
                      label: Text(text.sendDiscoveryAnnouncement),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: controller.buildDiagnosticSummary(),
                          ),
                        );
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(text.diagnosticSummaryCopied)),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(text.copyDiagnosticSummary),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.diagnosticLogService == null
                          ? null
                          : controller.exportDiagnosticReport,
                      icon: const Icon(Icons.save_alt_outlined),
                      label: Text(text.exportDiagnosticLogs),
                    ),
                    if (Platform.isWindows)
                      IconButton(
                        tooltip: text.openDiagnosticLogFolder,
                        onPressed:
                            controller.diagnosticLogService?.directoryPath ==
                                null
                            ? null
                            : controller.openDiagnosticLogFolder,
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(text.done),
            ),
          ],
        );
      },
    ),
  );
}

class NetworkDiagnosticResultCard extends StatelessWidget {
  const NetworkDiagnosticResultCard({
    super.key,
    required this.controller,
    required this.result,
  });

  final AppController controller;
  final NetworkDiagnosticResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = result.reachable;
    final color = success ? scheme.primary : scheme.error;
    final localEndpoints = result.localEndpoints;
    return Card(
      margin: EdgeInsets.zero,
      color: success ? scheme.primaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  success ? Icons.check_circle_outline : Icons.error_outline,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    controller.text.networkDiagnosticSummary(result),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: success
                          ? scheme.onPrimaryContainer
                          : scheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              controller.text.networkDiagnosticAdvice,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(controller.text.networkDiagnosticAdviceFor(result)),
            const SizedBox(height: 8),
            Text(
              controller.text.networkDiagnosticLocalAddress,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              localEndpoints.isEmpty
                  ? controller.text.networkDiagnosticNoLocalAddress
                  : localEndpoints.join('\n'),
            ),
            if (result.errorDetail != null &&
                result.errorDetail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                'detail: ${result.errorDetail}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
