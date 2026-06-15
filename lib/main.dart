import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'core/formatters.dart';
import 'data/app_database.dart';

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
        return Scaffold(
          appBar: AppBar(
            title: const Text('LocalChat'),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
              PopupMenuButton<String>(
                tooltip: '设置',
                onSelected: (value) {
                  if (value == 'clear_history') controller.clearHistory();
                  if (value == 'clear_transfers') controller.clearTransferIndex();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'clear_history', child: Text('清空聊天记录')),
                  PopupMenuItem(value: 'clear_transfers', child: Text('清空接收文件索引')),
                ],
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
    final trusted = controller.devices.where((device) => device.trusted).toList();
    final discovered = controller.devices.where((device) => !device.trusted).toList();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _LocalIdentityCard(controller: controller),
          const SizedBox(height: 16),
          _SectionTitle(title: '已信任设备', count: trusted.length),
          if (trusted.isEmpty) const _EmptyHint('还没有已信任设备。让手机/电脑打开 LocalChat 并处在同一 Wi-Fi。'),
          for (final device in trusted) _DeviceTile(controller: controller, device: device),
          const SizedBox(height: 16),
          _SectionTitle(title: '发现的设备', count: discovered.length),
          if (discovered.isEmpty) const _EmptyHint('正在监听局域网广播...'),
          for (final device in discovered) _DeviceTile(controller: controller, device: device),
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
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(identity?.displayName ?? 'LocalChat', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            identity == null ? '身份初始化中' : '${identity.platform} · ${shortFingerprint(identity.fingerprint)}',
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
        leading: CircleAvatar(child: Icon(device.trusted ? Icons.verified_user : Icons.devices)),
        title: Text(device.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${device.platform} · ${displayHost(device.host, device.port)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: device.trusted
            ? const Icon(Icons.chevron_right)
            : FilledButton.tonal(
                onPressed: controller.busy ? null : () => controller.pair(device),
                child: const Text('配对'),
              ),
        onTap: () => controller.selectDevice(device),
      ),
    );
  }
}

class _ChatPane extends StatelessWidget {
  const _ChatPane({
    required this.controller,
    required this.textController,
    required this.dragging,
    required this.onDragState,
  });

  final AppController controller;
  final TextEditingController textController;
  final bool dragging;
  final ValueChanged<bool> onDragState;

  @override
  Widget build(BuildContext context) {
    final peer = controller.selectedDevice;
    if (peer == null) {
      return const Center(child: Text('选择一个设备开始聊天式传输'));
    }
    return DropTarget(
      enable: peer.trusted,
      onDragEntered: (_) => onDragState(true),
      onDragExited: (_) => onDragState(false),
      onDragDone: (details) {
        onDragState(false);
        final paths = details.files.where((file) => file.path.isNotEmpty).map((file) => file.path).toList();
        controller.sendFiles(paths);
      },
      child: Column(
        children: [
          _DesktopPeerHeader(controller: controller, peer: peer),
          if (dragging) const _DropBanner(),
          Expanded(
            child: controller.messages.isEmpty
                ? Center(child: Text(peer.trusted ? '发一句话，或把文件拖进来。' : '先完成首次配对。'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.messages.length,
                    itemBuilder: (context, index) {
                      return _MessageBubble(controller: controller, message: controller.messages[index]);
                    },
                  ),
          ),
          _Composer(controller: controller, textController: textController, peer: peer),
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
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          CircleAvatar(child: Icon(peer.trusted ? Icons.verified : Icons.lock_open)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.displayName, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${peer.trusted ? '已信任' : '未配对'} · ${shortFingerprint(peer.fingerprint)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
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
    if (peer == null) return const SizedBox.shrink();
    return ListTile(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: controller.closeConversation,
      ),
      title: Text(peer.displayName),
      subtitle: Text(peer.trusted ? '已信任' : '未配对'),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.textController, required this.peer});

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: message.kind == 'file' ? _FileMessage(controller: controller, message: message) : _TextMessage(message),
          ),
          const SizedBox(height: 3),
          Text(message.status, style: Theme.of(context).textTheme.labelSmall),
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
  const _FileMessage({required this.controller, required this.message});

  final AppController controller;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.insert_drive_file),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.fileName ?? '文件', maxLines: 2, overflow: TextOverflow.ellipsis),
              if (message.fileSize != null)
                Text(formatBytes(message.fileSize!), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          tooltip: '打开',
          onPressed: () => controller.openPath(message.filePath),
          icon: const Icon(Icons.open_in_new),
        ),
        IconButton(
          tooltip: '打开文件夹',
          onPressed: () => controller.openFolder(message.filePath),
          icon: const Icon(Icons.folder_open),
        ),
      ],
    );
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
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Expanded(
              child: Text(
                controller.lastError == null ? controller.status : '${controller.status}：${controller.lastError}',
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Text('$title · $count', style: Theme.of(context).textTheme.titleSmall);
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
