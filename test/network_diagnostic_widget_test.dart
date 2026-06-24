import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';

void main() {
  testWidgets(
    'settings exposes a standalone campus network diagnostic button',
    (tester) async {
      final controller = AppController(
        database: AppDatabase(NativeDatabase.memory()),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(LocalChatApp(controller: controller));
      await tester.tap(find.byTooltip(controller.text.settings));
      await tester.pumpAndSettle();

      expect(
        find.text(controller.text.campusNetworkDiagnostic),
        findsOneWidget,
      );
      expect(find.text(controller.text.runNetworkDiagnostic), findsOneWidget);
    },
  );
}
