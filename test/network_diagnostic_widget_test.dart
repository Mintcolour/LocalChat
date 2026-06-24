import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';

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
}
