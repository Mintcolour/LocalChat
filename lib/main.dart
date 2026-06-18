import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'core/device_profile.dart';
import 'core/file_types.dart';
import 'core/formatters.dart';
import 'core/peer_status.dart';
import 'data/app_database.dart';
import 'models/protocol.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.initialize();
  runApp(LocalChatApp(controller: controller));
}

class LocalChatApp extends StatelessWidget {
  const LocalChatApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LocalChat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: LocalChatHome(controller: controller),
    );
  }
}

class LocalChatHome extends StatefulWidget {
  const LocalChatHome({super.key, required this.controller});

  final AppController controller;

  @override
  State<LocalChatHome> createState() => _LocalChatHomeState();
}

class _LocalChatHomeState extends State<LocalChatHome> {
  final _textController = TextEditingController();
  bool _dragging = false;
  String? _shownPairRequestId;
  int _shownNotificationSerial = 0;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final pendingPair = controller.pendingPairRequest;
        if (pendingPair == null) {
          _shownPairRequestId = null;
        } else if (_shownPairRequestId != pendingPair.id) {
          _shownPairRequestId = pendingPair.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showPairRequestDialog(context, controller, pendingPair);
            }
          });
        }
        if (controller.notificationSerial != _shownNotificationSerial &&
            controller.notificationText != null) {
          _shownNotificationSerial = controller.notificationSerial;
          final message = controller.notificationText!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(controller.text.appTitle),
            actions: [
              IconButton(
                tooltip: controller.text.rescan,
                onPressed: controller.rescan,
                icon: const Icon(Icons.travel_explore),
              ),
              IconButton(
                tooltip: controller.text.settings,
                onPressed: () => _showSettingsDialog(context, controller),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 820;
                final devicePane = _DevicePane(controller: controller);
                final chatPane = _ChatPane(
                  controller: controller,
                  textController: _textController,
                  dragging: _dragging,
                  onDragState: (value) => setState(() => _dragging = value),
                  showHeader: !narrow,
                );
                if (narrow) {
                  return controller.selectedDevice == null
                      ? devicePane
                      : Column(
                          children: [
                            _MobilePeerHeader(controller: controller),
                            Expanded(child: chatPane),
                          ],
                        );
                }
                return Row(
                  children: [
                    SizedBox(width: 340, child: devicePane),
                    const VerticalDivider(width: 1),
                    Expanded(child: chatPane),
                  ],
                );
              },
            ),
          ),
          bottomNavigationBar: _StatusBar(controller: controller),
        );
      },
    );
  }
}

class _DevicePane extends StatelessWidget {
  const _DevicePane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final trusted = controller.devices
        .where((device) => device.trusted)
        .toList();
    final discovered = controller.devices
        .where((device) => !device.trusted)
        .toList();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _LocalIdentityCard(controller: controller),
          const SizedBox(height: 16),
          _SectionTitle(
            title: controller.text.trustedDevices,
            count: trusted.length,
          ),
          if (trusted.isEmpty) _EmptyHint(controller.text.noTrustedDevices),
          for (final device in trusted)
            _DeviceTile(controller: controller, device: device),
          const SizedBox(height: 16),
          _SectionTitle(
            title: controller.text.discoveredDevices,
            count: discovered.length,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.rescan,
              icon: const Icon(Icons.travel_explore),
              label: Text(controller.text.rescan),
            ),
          ),
          if (discovered.isEmpty) _EmptyHint(controller.text.listeningLan),
          for (final device in discovered)
            _DeviceTile(controller: controller, device: device),
        ],
      ),
    );
  }
}

class _LocalIdentityCard extends StatelessWidget {
  const _LocalIdentityCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final identity = controller.identity;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (identity != null)
                _DeviceAvatar(
                  name: identity.displayName,
                  platform: identity.platform,
                  avatarSeed: identity.avatarSeed,
                  avatarColor: identity.avatarColor,
                ),
              if (identity != null) const SizedBox(width: 10),
              Expanded(
                child: Text(
                  identity?.displayName ?? 'LocalChat',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            identity == null
                ? controller.text.identityStarting
                : '${identity.platform} · ${shortFingerprint(identity.fingerprint)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.controller, required this.device});

  final AppController controller;
  final Device device;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice?.id == device.id;
    final endpoint =
        device.host == null ||
            device.host!.isEmpty ||
            device.port == null ||
            device.port! <= 0
        ? controller.text.notConnected
        : displayHost(device.host, device.port);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListTile(
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: _DeviceAvatar(
          name: controller.titleFor(device),
          platform: device.platform,
          avatarSeed: device.avatarSeed,
          avatarColor: device.avatarColor,
          trusted: device.trusted,
        ),
        title: Text(
          controller.titleFor(device),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${controller.text.peerStatus(device)} · ${device.platform} · $endpoint',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: device.trusted
            ? const Icon(Icons.chevron_right)
            : FilledButton.tonal(
                onPressed: controller.busy
                    ? null
                    : () => controller.pair(device),
                child: Text(controller.text.pair),
              ),
        onTap: () => controller.selectDevice(device),
      ),
    );
  }
}

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({
    required this.name,
    required this.platform,
    required this.avatarSeed,
    required this.avatarColor,
    this.trusted = true,
    this.radius = 20,
  });

  final String name;
  final String platform;
  final String avatarSeed;
  final String avatarColor;
  final bool trusted;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(
      avatarColor.isEmpty ? avatarColorFor(avatarSeed) : avatarColor,
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: trusted
          ? Text(
              avatarInitial(name, platform),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(Icons.lock_open, color: Colors.white, size: radius),
    );
  }
}

Color _colorFromHex(String value) {
  final clean = value.replaceFirst('#', '');
  final parsed = int.tryParse(
    clean.length == 6 ? 'FF$clean' : clean,
    radix: 16,
  );
  return Color(parsed ?? 0xFF2563EB);
}

class _ChatPane extends StatelessWidget {
  const _ChatPane({
    required this.controller,
    required this.textController,
    required this.dragging,
    required this.onDragState,
    required this.showHeader,
  });

  final AppController controller;
  final TextEditingController textController;
  final bool dragging;
  final ValueChanged<bool> onDragState;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final peer = controller.selectedDevice;
    if (peer == null) {
      return Center(child: Text(controller.text.selectDevice));
    }
    final online = isPeerOnline(peer);
    return DropTarget(
      enable: peer.trusted,
      onDragEntered: (_) => onDragState(true),
      onDragExited: (_) => onDragState(false),
      onDragDone: (details) {
        onDragState(false);
        final files = <String>[];
        final folders = <String>[];
        for (final entry in details.files) {
          if (entry.path.isEmpty) continue;
          if (FileSystemEntity.isDirectorySync(entry.path)) {
            folders.add(entry.path);
          } else {
            files.add(entry.path);
          }
        }
        if (files.isNotEmpty) {
          controller.sendFiles(files);
        }
        for (final folder in folders) {
          controller.sendFolder(folder);
        }
      },
      child: Column(
        children: [
          if (showHeader)
            _DesktopPeerHeader(controller: controller, peer: peer),
          if (peer.trusted && !online)
            _ConnectionBanner(controller: controller, peer: peer),
          if (dragging) _DropBanner(controller: controller),
          Expanded(
            child: controller.messages.isEmpty
                ? Center(
                    child: Text(
                      peer.trusted
                          ? controller.text.sayOrDropFile
                          : controller.text.pairFirst,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.messages.length,
                    itemBuilder: (context, index) {
                      return _MessageBubble(
                        controller: controller,
                        message: controller.messages[index],
                      );
                    },
                  ),
          ),
          _Composer(
            controller: controller,
            textController: textController,
            peer: peer,
          ),
        ],
      ),
    );
  }
}

class _DesktopPeerHeader extends StatelessWidget {
  const _DesktopPeerHeader({required this.controller, required this.peer});

  final AppController controller;
  final Device peer;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _DeviceAvatar(
            name: controller.titleFor(peer),
            platform: peer.platform,
            avatarSeed: peer.avatarSeed,
            avatarColor: peer.avatarColor,
            trusted: peer.trusted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.titleFor(peer),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${controller.text.peerStatus(peer)} · ${shortFingerprint(peer.fingerprint)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (peer.trusted)
            IconButton(
              tooltip: controller.text.renameConversation,
              onPressed: () => _showRenameDialog(context, controller, peer),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (peer.trusted)
            IconButton(
              tooltip: controller.text.deleteConversation,
              onPressed: () => _confirmDeleteConversation(context, controller),
              icon: const Icon(Icons.delete_outline),
            ),
          if (!peer.trusted)
            FilledButton.icon(
              onPressed: controller.busy ? null : () => controller.pair(peer),
              icon: const Icon(Icons.handshake),
              label: Text(controller.text.firstPair),
            ),
        ],
      ),
    );
  }
}

class _MobilePeerHeader extends StatelessWidget {
  const _MobilePeerHeader({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final peer = controller.selectedDevice;
    if (peer == null) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: controller.closeConversation,
      ),
      title: Text(controller.titleFor(peer)),
      subtitle: Text(controller.text.peerStatus(peer)),
      trailing: peer.trusted
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: controller.text.renameConversation,
                  onPressed: () => _showRenameDialog(context, controller, peer),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: controller.text.deleteConversation,
                  onPressed: () =>
                      _confirmDeleteConversation(context, controller),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : null,
    );
  }
}

Future<void> _showRenameDialog(
  BuildContext context,
  AppController controller,
  Device peer,
) async {
  var input = controller.titleFor(peer);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.renameConversation),
      content: TextFormField(
        initialValue: input,
        autofocus: true,
        decoration: InputDecoration(
          labelText: controller.text.conversationName,
        ),
        onChanged: (value) => input = value,
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(input),
          child: Text(controller.text.save),
        ),
      ],
    ),
  );
  if (value != null) {
    await controller.renameSelectedConversation(value);
  }
}

Future<void> _confirmDeleteConversation(
  BuildContext context,
  AppController controller,
) async {
  final peer = controller.selectedDevice;
  if (peer == null) return;
  final title = controller.titleFor(peer);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.deleteConversationTitle),
      content: Text(controller.text.deleteConversationBody(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(controller.text.delete),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.deleteSelectedConversation();
  }
}

Future<void> _showSettingsDialog(
  BuildContext context,
  AppController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AlertDialog(
        title: Text(controller.text.settings),
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
                  onPressed: () => _showLocalRenameDialog(context, controller),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.autoCopyReceivedText),
                subtitle: Text(controller.text.autoCopyReceivedTextSubtitle),
                value: controller.autoCopyReceivedText,
                onChanged: controller.setAutoCopyReceivedText,
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
              ],
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.clearHistory),
                subtitle: Text(controller.text.clearHistorySubtitle),
                trailing: TextButton(
                  onPressed: controller.clearHistory,
                  child: Text(controller.text.clear),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.clearTransfers),
                subtitle: Text(controller.text.clearTransfersSubtitle),
                trailing: TextButton(
                  onPressed: controller.clearTransferIndex,
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

Future<void> _showLocalRenameDialog(
  BuildContext context,
  AppController controller,
) async {
  var input = controller.identity?.displayName ?? 'LocalChat';
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.editLocalNickname),
      content: TextFormField(
        initialValue: input,
        autofocus: true,
        decoration: InputDecoration(
          labelText: controller.text.deviceNameVisible,
        ),
        onChanged: (value) => input = value,
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(input),
          child: Text(controller.text.save),
        ),
      ],
    ),
  );
  if (value != null) {
    await controller.renameLocalDevice(value);
  }
}

Future<void> _showPairRequestDialog(
  BuildContext context,
  AppController controller,
  PendingPairRequest request,
) async {
  final endpoint = request.host.isEmpty || request.port <= 0
      ? controller.text.notConnected
      : displayHost(request.host, request.port);
  final allowed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(controller.text.allowPairTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DeviceAvatar(
                name: request.displayName,
                platform: request.platform,
                avatarSeed: request.avatarSeed,
                avatarColor: request.avatarColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${request.platform} · $endpoint'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${controller.text.verificationCode}: ${request.code}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '${controller.text.fingerprint}: ${shortFingerprint(request.fingerprint)}',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(controller.text.reject),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(controller.text.allow),
        ),
      ],
    ),
  );
  if (allowed == true) {
    await controller.approvePendingPair();
  } else {
    await controller.rejectPendingPair();
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.textController,
    required this.peer,
  });

  final AppController controller;
  final TextEditingController textController;
  final Device peer;

  @override
  Widget build(BuildContext context) {
    final enabled = peer.trusted && !controller.busy;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (enabled) {
            _pasteFromClipboard();
          }
        },
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: controller.text.chooseFile,
              onPressed: enabled ? controller.pickAndSendFiles : null,
              icon: const Icon(Icons.attach_file),
            ),
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
              IconButton(
                tooltip: controller.text.chooseFolder,
                onPressed: enabled ? controller.pickAndSendFolder : null,
                icon: const Icon(Icons.folder_outlined),
              ),
            IconButton(
              tooltip: controller.text.pasteFileOrImage,
              onPressed: enabled ? _pasteFromClipboard : null,
              icon: const Icon(Icons.content_paste),
            ),
            Expanded(
              child: TextField(
                controller: textController,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: peer.trusted
                      ? controller.text.inputHint
                      : controller.text.pairBeforeSend,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: enabled ? _send : null,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final text = textController.text;
    textController.clear();
    controller.sendText(text);
  }

  Future<void> _pasteFromClipboard() async {
    final sentFiles = await controller.pasteAndSendClipboardFiles();
    if (sentFiles) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final value = textController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final newText = value.text.replaceRange(start, end, text);
    final offset = start + text.length;
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.controller, required this.message});

  final AppController controller;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == 'out';
    final color = outgoing
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final align = outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final peer = outgoing ? null : controller.selectedDevice;
    final identity = controller.identity;
    final title = outgoing
        ? identity?.displayName ?? controller.text.me
        : (peer == null ? controller.text.peer : controller.titleFor(peer));
    final avatar = outgoing
        ? (identity == null
              ? null
              : _DeviceAvatar(
                  name: identity.displayName,
                  platform: identity.platform,
                  avatarSeed: identity.avatarSeed,
                  avatarColor: identity.avatarColor,
                  radius: 16,
                ))
        : (peer == null
              ? null
              : _DeviceAvatar(
                  name: controller.titleFor(peer),
                  platform: peer.platform,
                  avatarSeed: peer.avatarSeed,
                  avatarColor: peer.avatarColor,
                  radius: 16,
                ));
    final bubble = Column(
      crossAxisAlignment: align,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: message.kind == 'file'
              ? _FileMessage(
                  controller: controller,
                  message: message,
                  transfer: message.transferId == null
                      ? null
                      : controller.transfersById[message.transferId!],
                )
              : _TextMessage(message),
        ),
        const SizedBox(height: 3),
        Text(
          '${controller.text.messageStatus(message.status)} ${formatMessageTimestamp(message.createdAt)}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: outgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!outgoing && avatar != null) ...[
            avatar,
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
          if (outgoing && avatar != null) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }
}

class _TextMessage extends StatelessWidget {
  const _TextMessage(this.message);

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return SelectableText(message.body ?? '');
  }
}

class _FileMessage extends StatelessWidget {
  const _FileMessage({
    required this.controller,
    required this.message,
    required this.transfer,
  });

  final AppController controller;
  final ChatMessage message;
  final Transfer? transfer;

  @override
  Widget build(BuildContext context) {
    final fileSize = transfer?.fileSize ?? message.fileSize ?? 0;
    final receivedBytes =
        transfer?.receivedBytes ??
        (message.status == 'sent' || message.status == 'received'
            ? fileSize
            : 0);
    final progress = fileSize <= 0
        ? null
        : (receivedBytes / fileSize).clamp(0.0, 1.0);
    final mimeType = transfer?.mimeType ?? message.mimeType;
    final openTarget =
        transfer?.savedUri ?? transfer?.savedPath ?? message.filePath;
    final saved = transfer?.savedPath != null || transfer?.savedUri != null;
    final showProgress =
        progress != null &&
        progress < 1 &&
        (message.status == 'sending' || message.status == 'receiving');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilePreview(message: message, mimeType: mimeType),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.relativePath ??
                        message.fileName ??
                        controller.text.file,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fileSize > 0)
                    Text(
                      formatBytes(fileSize),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (saved)
                    Text(
                      controller.text.savedLocal,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: controller.text.open,
              onPressed: openTarget == null
                  ? null
                  : () => controller.openPath(openTarget),
              icon: const Icon(Icons.open_in_new),
            ),
            IconButton(
              tooltip: controller.text.openFolder,
              onPressed: message.filePath == null
                  ? null
                  : () => controller.openFolder(message.filePath),
              icon: const Icon(Icons.folder_open),
            ),
            IconButton(
              tooltip: controller.text.saveLocal,
              onPressed: saved
                  ? null
                  : () => controller.saveMessageFile(message),
              icon: const Icon(Icons.save_alt),
            ),
          ],
        ),
        if (showProgress) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 4),
          Text(
            '${formatBytes(receivedBytes)} / ${formatBytes(fileSize)} · ${(progress * 100).toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.message, required this.mimeType});

  final ChatMessage message;
  final String? mimeType;

  @override
  Widget build(BuildContext context) {
    final path = message.filePath;
    if (path != null &&
        isImageFile(
          mimeType: mimeType,
          fileName: message.fileName,
          path: path,
        )) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.image_not_supported),
          ),
        ),
      );
    }
    return const Icon(Icons.insert_drive_file);
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (controller.busy)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Expanded(
              child: Text(
                controller.lastError == null
                    ? controller.status
                    : controller.text.statusWithError(
                        controller.status,
                        controller.lastError!,
                      ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropBanner extends StatelessWidget {
  const _DropBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(controller.text.releaseToSend),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.controller, required this.peer});

  final AppController controller;
  final Device peer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        controller.text.offlineBanner(peer.displayName),
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$title · $count',
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
