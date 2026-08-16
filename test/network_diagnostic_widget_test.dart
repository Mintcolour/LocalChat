import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';
import 'package:localchat/models/network_health.dart';
import 'package:localchat/services/windows_firewall_service.dart';

class _PendingFirewallService extends WindowsFirewallService {
  _PendingFirewallService();

  final repairCompleter = Completer<WindowsFirewallStatus>();
  WindowsFirewallStatus status = const WindowsFirewallStatus(
    state: WindowsFirewallRuleState.missing,
  );

  @override
  bool get isSupported => true;

  @override
  Future<WindowsFirewallStatus> getStatus() async => status;

  @override
  Future<WindowsFirewallStatus> repair() async {
    status = await repairCompleter.future;
    return status;
  }
}

void main() {
  testWidgets(
    'settings exposes manual peer dialog with connectivity test button',
    (tester) async {
      final controller = AppController(
        database: AppDatabase(NativeDatabase.memory()),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(LocalChatApp(controller: controller));
      await tester.tap(find.byTooltip(controller.text.settings));
      await tester.pumpAndSettle();

      expect(find.text(controller.text.addPeerManually), findsOneWidget);
      final addFinder = find.descendant(
        of: find.ancestor(
          of: find.text(controller.text.addPeerManually),
          matching: find.byType(ListTile),
        ),
        matching: find.text(controller.text.add),
      );
      await tester.ensureVisible(addFinder);
      await tester.pumpAndSettle();
      await tester.tap(addFinder);
      await tester.pumpAndSettle();

      expect(find.text(controller.text.addPeerManually), findsOneWidget);
      expect(find.text(controller.text.testBeforeAddPeer), findsOneWidget);
    },
  );

  testWidgets('network diagnostics exposes firewall repair and status', (
    tester,
  ) async {
    final firewall = _PendingFirewallService();
    final controller = AppController(
      database: AppDatabase(NativeDatabase.memory()),
      windowsFirewallService: firewall,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(LocalChatApp(controller: controller));
    await tester.tap(find.byTooltip(controller.text.settings));
    await tester.pumpAndSettle();

    final diagnostics = find.text(controller.text.networkDiagnosticsAndLogs);
    await tester.ensureVisible(diagnostics.first);
    await tester.tap(diagnostics.first);
    await tester.pumpAndSettle();

    expect(find.text(controller.text.firewallStatus), findsOneWidget);
    final repairButton = find.widgetWithText(
      FilledButton,
      controller.text.repairFirewall,
    );
    expect(repairButton, findsOneWidget);
    await tester.tap(repairButton);
    await tester.pump();

    final pendingButton = tester.widget<FilledButton>(repairButton);
    expect(pendingButton.onPressed, isNull);

    firewall.repairCompleter.complete(
      const WindowsFirewallStatus(
        state: WindowsFirewallRuleState.configured,
        udpConfigured: true,
        tcpConfigured: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        controller.text.firewallStatusLabel(
          WindowsFirewallRuleState.configured,
        ),
      ),
      findsOneWidget,
    );
  });
}
