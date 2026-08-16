import 'dart:async';

import 'package:flutter/material.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/models/network_diagnostic.dart';
import 'package:localchat/ui/dialogs/network_diagnostics_dialog.dart';

Future<void> showAddPeerDialog(
  BuildContext context,
  AppController controller,
) async {
  var host = '';
  var port = '40123';
  NetworkDiagnosticResult? diagnostic;
  var diagnosing = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> runDiagnostic() async {
          final portValue = int.tryParse(port);
          if (host.isEmpty || portValue == null || portValue <= 0) {
            setState(() {
              diagnostic = NetworkDiagnosticResult(
                host: host,
                port: portValue ?? 0,
                status: NetworkDiagnosticStatus.invalidInput,
              );
            });
            return;
          }
          setState(() => diagnosing = true);
          final result = await controller.checkManualPeerConnectivity(
            host,
            portValue,
          );
          if (!dialogContext.mounted) return;
          setState(() {
            diagnostic = result;
            diagnosing = false;
          });
        }

        return AlertDialog(
          title: Text(controller.text.addPeerManually),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: controller.text.peerHost,
                    hintText: '192.168.10.5',
                  ),
                  onChanged: (value) => host = value.trim(),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: controller.text.peerPort,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => port = value.trim(),
                ),
                if (diagnostic != null) ...[
                  const SizedBox(height: 12),
                  NetworkDiagnosticResultCard(
                    controller: controller,
                    result: diagnostic!,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: diagnosing
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(controller.text.cancel),
            ),
            OutlinedButton.icon(
              onPressed: diagnosing ? null : runDiagnostic,
              icon: diagnosing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(controller.text.testBeforeAddPeer),
            ),
            FilledButton(
              onPressed: diagnosing
                  ? null
                  : () async {
                      final portValue = int.tryParse(port);
                      if (host.isEmpty || portValue == null || portValue <= 0) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                      await controller.addPeerManually(host, portValue);
                    },
              child: Text(controller.text.add),
            ),
          ],
        );
      },
    ),
  );
}
