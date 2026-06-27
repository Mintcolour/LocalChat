import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/main.dart';
import 'package:localchat/models/app_info.dart';
import 'package:localchat/models/update_check.dart';
import 'package:localchat/services/app_info_service.dart';
import 'package:localchat/services/update_check_service.dart';

class _FakeAppInfoService extends AppInfoService {
  const _FakeAppInfoService();

  @override
  Future<AppInfo> load() async => const AppInfo(
    appName: 'LocalChat',
    version: '1.3.3',
    buildNumber: '7',
    platform: 'Windows',
  );
}

class _PendingUpdateCheckService extends UpdateCheckService {
  _PendingUpdateCheckService() : super(fetcher: () async => {});

  final completer = Completer<UpdateCheckResult>();
  int calls = 0;

  @override
  Future<UpdateCheckResult> check({required String currentVersion}) {
    calls++;
    return completer.future;
  }
}

void main() {
  testWidgets('settings opens about dialog with project metadata', (
    tester,
  ) async {
    final updateService = _PendingUpdateCheckService();
    final controller = AppController(
      database: AppDatabase(NativeDatabase.memory()),
      appInfoService: const _FakeAppInfoService(),
      updateCheckService: updateService,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(LocalChatApp(controller: controller));
    await tester.tap(find.byTooltip(controller.text.settings));
    await tester.pumpAndSettle();

    final aboutTile = find.text(controller.text.aboutLocalChat).first;
    await tester.ensureVisible(aboutTile);
    await tester.tap(aboutTile);
    await tester.pumpAndSettle();

    expect(find.text(controller.text.aboutLocalChat), findsWidgets);
    expect(find.text('1.3.3+7'), findsOneWidget);
    expect(find.text('Mintcolour'), findsOneWidget);
    expect(find.text(controller.text.mitLicense), findsOneWidget);
    expect(find.text(controller.text.githubCommunity), findsOneWidget);
    expect(find.text(controller.text.releasePage), findsOneWidget);
    expect(find.text(controller.text.issueTracker), findsOneWidget);
    expect(find.text(controller.text.dailyUpdateCheck), findsOneWidget);
    expect(find.text(controller.text.checkForUpdates), findsOneWidget);

    final checkButton = find.widgetWithText(
      FilledButton,
      controller.text.checkForUpdates,
    );
    await tester.ensureVisible(checkButton);
    await tester.pumpAndSettle();
    await tester.tap(checkButton);
    await tester.pump();

    expect(updateService.calls, 1);
    final checkingButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, controller.text.checkingForUpdates),
    );
    expect(checkingButton.onPressed, isNull);

    updateService.completer.complete(
      UpdateCheckResult.upToDate(
        currentVersion: '1.3.3+7',
        latestRelease: const ReleaseInfo(
          tagName: 'v1.3.3',
          htmlUrl:
              'https://github.com/Mintcolour/LocalChat/releases/tag/v1.3.3',
          name: '',
          body: '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(controller.text.updateUpToDate('v1.3.3')),
      findsAtLeastNWidgets(1),
    );
  });
}
