import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

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
            title: const Text('LocalChat'),
            actions: [
              IconButton(
                tooltip: '重新搜索',
                onPressed: controller.rescan,
                icon: const Icon(Icons.travel_explore),
              ),
              IconButton(
                tooltip: '设置',
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
          _SectionTitle(title: '已信任设备', count: trusted.length),
          if (trusted.isEmpty)
            const _EmptyHint('还没有已信任设备。让手机/电脑打开 LocalChat 并处在同一 Wi-Fi。'),
          for (final device in trusted)
            _DeviceTile(controller: controller, device: device),
          const SizedBox(height: 16),
          _SectionTitle(title: '发现的设备', count: discovered.length),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.rescan,
              icon: const Icon(Icons.travel_explore),
              label: const Text('重新搜索'),
            ),
          ),
          if (discovered.isEmpty) const _EmptyHint('正在监听局域网广播...'),
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
                ? '身份初始化中'
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
          '${peerStatusLabel(device)} · ${device.platform} · ${displayHost(device.host, device.port)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: device.trusted
            ? const Icon(Icons.chevron_right)
            : FilledButton.tonal(
                onPressed: controller.busy
                    ? null
                    : () => controller.pair(device),
                child: const Text('配对'),
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
      return const Center(child: Text('选择一个设备开始聊天式传输'));
    }
    final online = isPeerOnline(peer);
    return DropTarget(
      enable: peer.trusted,
      onDragEntered: (_) => onDragState(true),
      onDragExited: (_) => onDragState(false),
      onDragDone: (details) {
        onDragState(false);
        final paths = details.files
            .where((file) => file.path.isNotEmpty)
            .map((file) => file.path)
            .toList();
        controller.sendFiles(paths);
      },
      child: Column(
        children: [
          if (showHeader)
            _DesktopPeerHeader(controller: controller, peer: peer),
          if (peer.trusted && !online) _ConnectionBanner(peer: peer),
          if (dragging) const _DropBanner(),
          Expanded(
            child: controller.messages.isEmpty
                ? Center(
                    child: Text(peer.trusted ? '发一句话，或把文件拖进来。' : '先完成首次配对。'),
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
                  '${peerStatusLabel(peer)} · ${shortFingerprint(peer.fingerprint)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (peer.trusted)
            IconButton(
              tooltip: '重命名会话',
              onPressed: () => _showRenameDialog(context, controller, peer),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (peer.trusted)
            IconButton(
              tooltip: '删除会话',
              onPressed: () => _confirmDeleteConversation(context, controller),
              icon: const Icon(Icons.delete_outline),
            ),
          if (!peer.trusted)
            FilledButton.icon(
              onPressed: controller.busy ? null : () => controller.pair(peer),
              icon: const Icon(Icons.handshake),
              label: const Text('首次配对'),
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
      subtitle: Text(peerStatusLabel(peer)),
      trailing: peer.trusted
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '重命名会话',
                  onPressed: () => _showRenameDialog(context, controller, peer),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除会话',
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
      title: const Text('重命名会话'),
      content: TextFormField(
        initialValue: input,
        autofocus: true,
        decoration: const InputDecoration(labelText: '会话名称'),
        onChanged: (value) => input = value,
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(input),
          child: const Text('保存'),
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
      title: const Text('删除会话？'),
      content: Text('将删除“$title”的聊天记录、传输索引、连接信息和信任关系，磁盘上的文件不会被删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
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
        title: const Text('设置'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('本机昵称'),
                subtitle: Text(controller.identity?.displayName ?? 'LocalChat'),
                trailing: IconButton(
                  tooltip: '修改本机昵称',
                  onPressed: () => _showLocalRenameDialog(context, controller),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动复制收到的文字'),
                subtitle: const Text('收到文字或链接时自动复制到系统剪贴板'),
                value: controller.autoCopyReceivedText,
                onChanged: controller.setAutoCopyReceivedText,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('清空聊天记录'),
                subtitle: const Text('删除所有会话和消息，不删除磁盘文件'),
                trailing: TextButton(
                  onPressed: controller.clearHistory,
                  child: const Text('清空'),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('清空接收文件索引'),
                subtitle: const Text('只清理记录，不删除磁盘文件'),
                trailing: TextButton(
                  onPressed: controller.clearTransferIndex,
                  child: const Text('清空'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
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
      title: const Text('修改本机昵称'),
      content: TextFormField(
        initialValue: input,
        autofocus: true,
        decoration: const InputDecoration(labelText: '别人看到的设备名称'),
        onChanged: (value) => input = value,
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(input),
          child: const Text('保存'),
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
  final allowed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('允许设备配对？'),
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
                    Text(
                      '${request.platform} · ${displayHost(request.host, request.port)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '校验码：${request.code}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('指纹：${shortFingerprint(request.fingerprint)}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('允许'),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '选择文件',
            onPressed: enabled ? controller.pickAndSendFiles : null,
            icon: const Icon(Icons.attach_file),
          ),
          Expanded(
            child: TextField(
              controller: textController,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: peer.trusted ? '输入消息，或粘贴链接...' : '先配对后发送',
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
    );
  }

  void _send() {
    final text = textController.text;
    textController.clear();
    controller.sendText(text);
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
        ? identity?.displayName ?? '我'
        : (peer == null ? '对方' : controller.titleFor(peer));
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
          '${messageStatusLabel(message.status)} ${formatMessageTimestamp(message.createdAt)}',
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
                    message.fileName ?? '文件',
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
                      '已保存到本地',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '打开',
              onPressed: openTarget == null
                  ? null
                  : () => controller.openPath(openTarget),
              icon: const Icon(Icons.open_in_new),
            ),
            IconButton(
              tooltip: '打开文件夹',
              onPressed: message.filePath == null
                  ? null
                  : () => controller.openFolder(message.filePath),
              icon: const Icon(Icons.folder_open),
            ),
            IconButton(
              tooltip: '保存到本地',
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
                    : '${controller.status}：${controller.lastError}',
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
  const _DropBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Text('松开鼠标即可发送文件'),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.peer});

  final Device peer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        '${peer.displayName} 当前离线。发送时会自动等待重新发现并重连。',
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
