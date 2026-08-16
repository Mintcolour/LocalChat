import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/models/update_check.dart';
import 'package:localchat/services/update_check_service.dart';

Future<void> showLocalChatAboutDialog(
  BuildContext context,
  AppController controller,
) async {
  await controller.loadAppInfo();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final text = controller.text;
        return AlertDialog(
          title: Text(text.aboutLocalChat),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(text.appTitle),
                  subtitle: Text(text.githubCommunitySubtitle),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.new_releases_outlined),
                  title: Text(text.currentVersion),
                  subtitle: SelectableText(controller.appVersionLabel),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(text.author),
                  subtitle: const SelectableText('Mintcolour'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.balance_outlined),
                  title: Text(text.openSourceLicense),
                  subtitle: Text(text.mitLicense),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.public_outlined),
                  title: Text(text.githubCommunity),
                  subtitle: const SelectableText(localChatRepositoryUrl),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternalUrl(
                    context,
                    controller,
                    localChatRepositoryUrl,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: Text(text.releasePage),
                  subtitle: Text(text.releasePageSubtitle),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternalUrl(
                    context,
                    controller,
                    localChatReleasesUrl,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text(text.issueTracker),
                  subtitle: Text(text.issueTrackerSubtitle),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () =>
                      _openExternalUrl(context, controller, localChatIssuesUrl),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.copy_outlined),
                  title: Text(text.copyVersionInfo),
                  onTap: () => _copyVersionInfo(context, controller),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.article_outlined),
                  title: Text(text.thirdPartyLicenses),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: text.appTitle,
                    applicationVersion: controller.appVersionLabel,
                    applicationLegalese: text.mitLicense,
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.update_outlined),
                  title: Text(text.dailyUpdateCheck),
                  subtitle: Text(text.dailyUpdateCheckSubtitle),
                  value: controller.dailyUpdateCheckEnabled,
                  onChanged: controller.setDailyUpdateCheckEnabled,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: controller.updateCheckInProgress
                        ? null
                        : () async {
                            final result = await controller.checkForUpdates();
                            if (!context.mounted || result == null) return;
                            await _showUpdateCheckResult(
                              context,
                              controller,
                              result,
                            );
                          },
                    icon: controller.updateCheckInProgress
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt_outlined),
                    label: Text(
                      controller.updateCheckInProgress
                          ? text.checkingForUpdates
                          : text.checkForUpdates,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.done),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _copyVersionInfo(
  BuildContext context,
  AppController controller,
) async {
  final info = controller.appInfo;
  final value =
      info?.shareText ??
      'LocalChat ${controller.appVersionLabel}\n$localChatRepositoryUrl';
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(controller.text.versionInfoCopied)));
}

Future<void> _openExternalUrl(
  BuildContext context,
  AppController controller,
  String url,
) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(controller.text.linkCopiedAfterOpenFailed)),
    );
}

Future<void> _showUpdateCheckResult(
  BuildContext context,
  AppController controller,
  UpdateCheckResult result,
) async {
  final text = controller.text;
  final latest = result.latestRelease;
  final title = switch (result.status) {
    UpdateCheckStatus.updateAvailable => text.updateAvailable(
      latest?.tagName ?? '',
    ),
    UpdateCheckStatus.upToDate => text.updateUpToDate(latest?.tagName ?? ''),
    UpdateCheckStatus.failed => text.updateCheckFailed,
  };
  final body = switch (result.status) {
    UpdateCheckStatus.updateAvailable => text.updateAvailableBody(
      result.currentVersion,
      latest?.tagName ?? '',
    ),
    UpdateCheckStatus.upToDate => text.updateUpToDateBody(
      result.currentVersion,
    ),
    UpdateCheckStatus.failed => text.updateCheckFailedBody(result.error),
  };

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SelectableText(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(text.done),
        ),
        if (result.hasUpdate && latest != null)
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _openExternalUrl(context, controller, latest.htmlUrl);
            },
            child: Text(text.openReleasePage),
          ),
      ],
    ),
  );
}
