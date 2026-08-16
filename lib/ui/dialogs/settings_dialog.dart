import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/ui/dialogs/about_dialog.dart';
import 'package:localchat/ui/dialogs/add_peer_dialog.dart';
import 'package:localchat/ui/dialogs/network_diagnostics_dialog.dart';
import 'package:localchat/ui/dialogs/peer_dialogs.dart';

Future<void> showSettingsDialog(
  BuildContext context,
  AppController controller,
) async {
  final localEndpointsFuture = controller.loadLocalNetworkEndpoints();
  await showDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AlertDialog(
        title: Text(controller.text.settings),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.localNickname),
                subtitle: Text(controller.identity?.displayName ?? 'LocalChat'),
                trailing: IconButton(
                  tooltip: controller.text.editLocalNickname,
                  onPressed: () => showLocalRenameDialog(context, controller),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              FutureBuilder<List<String>>(
                future: localEndpointsFuture,
                builder: (context, snapshot) {
                  final endpoints = snapshot.data ?? const <String>[];
                  final subtitle =
                      snapshot.connectionState == ConnectionState.done
                      ? (endpoints.isEmpty
                            ? controller.text.localNetworkEndpointsEmpty(
                                controller.localListenPort,
                              )
                            : endpoints.join('\n'))
                      : controller.text.loadingLocalNetworkEndpoints;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lan_outlined),
                    title: Text(controller.text.localNetworkEndpoints),
                    subtitle: SelectableText(subtitle),
                  );
                },
              ),
              if (Platform.isWindows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(controller.text.storageRootPath),
                  subtitle: SelectableText(
                    controller.text.storageRootPathSubtitle(
                      controller.storageRootPath,
                    ),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: controller.text.chooseStorageRoot,
                        onPressed: controller.storageRootOperationInProgress
                            ? null
                            : () => chooseStorageRoot(context, controller),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: controller.text.resetStorageRoot,
                        onPressed:
                            controller.storageRootOperationInProgress ||
                                !controller.hasCustomStorageRootPath
                            ? null
                            : () => confirmStorageRootChange(
                                context,
                                controller,
                                controller.defaultStorageRootPath,
                                resetToDefault: true,
                              ),
                        icon: const Icon(Icons.restart_alt_outlined),
                      ),
                    ],
                  ),
                ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.autoCopyReceivedText),
                subtitle: Text(controller.text.autoCopyReceivedTextSubtitle),
                value: controller.autoCopyReceivedText,
                onChanged: controller.setAutoCopyReceivedText,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.notifications_active_outlined),
                title: Text(controller.text.systemNotifications),
                subtitle: Text(controller.text.systemNotificationsSubtitle),
                value: controller.notificationsEnabled,
                onChanged: controller.setNotificationsEnabled,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.visibility_outlined),
                title: Text(controller.text.notificationPreview),
                subtitle: Text(controller.text.notificationPreviewSubtitle),
                value: controller.notificationPreviewEnabled,
                onChanged: controller.notificationsEnabled
                    ? controller.setNotificationPreviewEnabled
                    : null,
              ),
              if (controller.keepAliveSupported)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.phonelink_lock_outlined),
                  title: Text(controller.text.keepAliveConnection),
                  subtitle: Text(controller.text.keepAliveConnectionSubtitle),
                  value: controller.keepAliveEnabled,
                  onChanged: controller.setKeepAliveEnabled,
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.language),
                trailing: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'zh',
                      label: Text(controller.text.chinese),
                    ),
                    ButtonSegment(
                      value: 'en',
                      label: Text(controller.text.english),
                    ),
                  ],
                  selected: {controller.languageCode},
                  onSelectionChanged: (values) {
                    controller.setLanguageCode(values.single);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.appearance),
                trailing: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'system',
                      tooltip: controller.text.themeSystem,
                      icon: const Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: 'light',
                      tooltip: controller.text.themeLight,
                      icon: const Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      tooltip: controller.text.themeDark,
                      icon: const Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {controller.themeModeCode},
                  onSelectionChanged: (values) {
                    controller.setThemeModeCode(values.single);
                  },
                ),
              ),
              if (Platform.isWindows) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(controller.text.minimizeToTray),
                  subtitle: Text(controller.text.minimizeToTraySubtitle),
                  value: controller.trayEnabled,
                  onChanged: controller.setTrayEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(controller.text.startOnBoot),
                  subtitle: Text(controller.text.startOnBootSubtitle),
                  value: controller.autostartEnabled,
                  onChanged: controller.setAutostartEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(controller.text.quickSend),
                  subtitle: Text(controller.text.quickSendSubtitle),
                  value: controller.quickSendEnabled,
                  onChanged: controller.setQuickSendEnabled,
                ),
                if (controller.quickSendEnabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(controller.text.quickSendAutoHide),
                      subtitle: Text(controller.text.quickSendAutoHideSubtitle),
                      value: controller.quickSendAutoHide,
                      onChanged: controller.setQuickSendAutoHide,
                    ),
                  ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.addPeerManually),
                subtitle: Text(controller.text.addPeerManuallySubtitle),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showAddPeerDialog(context, controller);
                  },
                  child: Text(controller.text.add),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.network_check_outlined),
                title: Text(controller.text.networkDiagnosticsAndLogs),
                subtitle: Text(
                  controller.text.networkDiagnosticsSubtitle(
                    controller.discoveryHealth.availability,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showNetworkDiagnosticsDialog(context, controller),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(controller.text.aboutLocalChat),
                subtitle: Text(
                  controller.text.aboutVersionSubtitle(
                    controller.appVersionLabel,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLocalChatAboutDialog(context, controller),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.clearHistory),
                subtitle: Text(controller.text.clearHistorySubtitle),
                trailing: TextButton(
                  // 危险操作：二次确认（计划：危险操作增加二次确认）。
                  onPressed: () async {
                    final ok = await confirmDanger(
                      context,
                      controller,
                      controller.text.clearHistory,
                      controller.text.clearHistorySubtitle,
                    );
                    if (ok) controller.clearHistory();
                  },
                  child: Text(controller.text.clear),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.clearTransfers),
                subtitle: Text(controller.text.clearTransfersSubtitle),
                trailing: TextButton(
                  onPressed: () async {
                    final ok = await confirmDanger(
                      context,
                      controller,
                      controller.text.clearTransfers,
                      controller.text.clearTransfersSubtitle,
                    );
                    if (ok) controller.clearTransferIndex();
                  },
                  child: Text(controller.text.clear),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(controller.text.done),
          ),
        ],
      ),
    ),
  );
}

enum _StorageRootChangeAction { updateOnly, migrate }

Future<void> chooseStorageRoot(
  BuildContext context,
  AppController controller,
) async {
  final path = await FilePicker.platform.getDirectoryPath(
    dialogTitle: controller.text.chooseStorageRoot,
    initialDirectory: controller.storageRootPath.isEmpty
        ? null
        : controller.storageRootPath,
  );
  if (path == null || path.isEmpty || !context.mounted) return;
  await confirmStorageRootChange(context, controller, path);
}

Future<void> confirmStorageRootChange(
  BuildContext context,
  AppController controller,
  String path, {
  bool resetToDefault = false,
}) async {
  final action = await showDialog<_StorageRootChangeAction>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.changeStorageRootTitle),
      content: SelectableText(controller.text.changeStorageRootBody(path)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(controller.text.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_StorageRootChangeAction.updateOnly),
          child: Text(controller.text.changeStorageRootOnly),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_StorageRootChangeAction.migrate),
          child: Text(controller.text.changeStorageRootAndMigrate),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  final migrate = action == _StorageRootChangeAction.migrate;
  if (resetToDefault) {
    await controller.resetStorageRootPath(migrateIndexedFiles: migrate);
  } else {
    await controller.setStorageRootPath(path, migrateIndexedFiles: migrate);
  }
}
