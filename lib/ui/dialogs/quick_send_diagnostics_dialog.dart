import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';

Future<void> showQuickSendDiagnosticsDialog(
  BuildContext context,
  AppController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _QuickSendDiagnosticsDialog(controller: controller),
);

class _QuickSendDiagnosticsDialog extends StatefulWidget {
  const _QuickSendDiagnosticsDialog({required this.controller});
  final AppController controller;

  @override
  State<_QuickSendDiagnosticsDialog> createState() =>
      _QuickSendDiagnosticsDialogState();
}

class _QuickSendDiagnosticsDialogState
    extends State<_QuickSendDiagnosticsDialog> {
  Timer? _timer;
  bool _reading = false;
  Map<String, Object?>? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_read()),
    );
  }

  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      final snapshot = await widget.controller.loadQuickSendDiagnostics();
      if (mounted) setState(() => _snapshot = snapshot);
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final snapshot = _snapshot;
    final unavailable = snapshot?['available'] == false;
    return AlertDialog(
      title: Text(text.quickSendDiagnostics),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.quickSendDiagnosticsHint),
            const SizedBox(height: 12),
            if (unavailable) Text(text.quickSendDiagnosticsUnavailable),
            if (snapshot == null)
              const CircularProgressIndicator()
            else
              SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(snapshot),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        FilledButton.icon(
          onPressed: snapshot == null
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent(
                        '  ',
                      ).convert(snapshot),
                    ),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(text.diagnosticSummaryCopied)),
                  );
                },
          icon: const Icon(Icons.copy_outlined),
          label: Text(text.quickSendCopyDiagnostics),
        ),
      ],
    );
  }
}
