import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'core/app_text.dart';
import 'core/device_profile.dart';
import 'core/file_types.dart';
import 'core/formatters.dart';
import 'core/peer_status.dart';
import 'data/app_database.dart';
import 'models/network_diagnostic.dart';
import 'models/protocol.dart';
import 'services/file_store.dart';
import 'services/secure_key_store.dart';
import 'ui/attachment_preview.dart';
import 'ui/transfer_center_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 生产环境启用系统安全存储（Android Keystore / Windows DPAPI）保存身份私钥。
  final controller = AppController(secureKeyStore: const SecureKeyStore());
  await controller.initialize();
  runApp(LocalChatApp(controller: controller));
}

class LocalChatApp extends StatelessWidget {
  const LocalChatApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LocalChat',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1FA37A), // LocalChat 自有绿色系，非微信品牌。
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1FA37A),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: switch (controller.themeModeCode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: LocalChatHome(controller: controller),
      ),
    );
  }
}

class LocalChatHome extends StatefulWidget {
  const LocalChatHome({super.key, required this.controller});

  final AppController controller;

  @override
  State<LocalChatHome> createState() => _LocalChatHomeState();
}

class _LocalChatHomeState extends State<LocalChatHome>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  bool _dragging = false;
  int _shownNotificationSerial = 0;
  int? _shownAttachmentBatchId;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.setAppForeground(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setAppForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.setAppForeground(false);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
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
        final attachmentBatch = controller.pendingAttachmentBatch;
        if (attachmentBatch == null) {
          _shownAttachmentBatchId = null;
        } else if (_shownAttachmentBatchId != attachmentBatch.id) {
          _shownAttachmentBatchId = attachmentBatch.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => AttachmentPreviewPage(
                  controller: controller,
                  batch: attachmentBatch,
                ),
              ),
            );
          });
        }
        final inConversation = controller.selectedDevice != null;
        return PopScope(
          canPop: !inConversation,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && controller.selectedDevice != null) {
              controller.closeConversation();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(controller.text.appTitle),
              actions: [
                IconButton(
                  tooltip: controller.text.transferCenter,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TransferCenterPage(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.swap_vert),
                ),
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
                    key: ValueKey(
                      'chat-${controller.selectedDevice?.id ?? 'none'}',
                    ),
                    controller: controller,
                    textController: _textController,
                    dragging: _dragging,
                    onDragState: (value) => setState(() => _dragging = value),
                    showHeader: !narrow,
                  );
                  if (narrow) {
                    final selectedDevice = controller.selectedDevice;
                    final page = selectedDevice == null
                        ? KeyedSubtree(
                            key: const ValueKey('mobile-device-list'),
                            child: devicePane,
                          )
                        : KeyedSubtree(
                            key: ValueKey(
                              'mobile-conversation-${selectedDevice.id}',
                            ),
                            child: Column(
                              children: [
                                _MobilePeerHeader(controller: controller),
                                Expanded(child: chatPane),
                              ],
                            ),
                          );
                    return AnimatedSwitcher(
                      key: const ValueKey('mobile-page-transition'),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      reverseDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final enteringConversation =
                            child.key is ValueKey<String> &&
                            (child.key! as ValueKey<String>).value.startsWith(
                              'mobile-conversation-',
                            );
                        final offset = enteringConversation
                            ? const Offset(0.08, 0)
                            : const Offset(-0.04, 0);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: offset,
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: page,
                    );
                  }
                  return Row(
                    children: [
                      // 桌面端会话列表约 300px + 内容区（计划：导航栏 64 + 会话列表 ~300 + 内容区）。
                      SizedBox(width: 300, child: devicePane),
                      const VerticalDivider(width: 1),
                      Expanded(child: chatPane),
                    ],
                  );
                },
              ),
            ),
            bottomNavigationBar: _StatusBar(controller: controller),
          ),
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
    final filter = controller.conversationFilter.toLowerCase();
    bool matches(Device device) =>
        filter.isEmpty ||
        controller.titleFor(device).toLowerCase().contains(filter);
    final trusted = controller.devices
        .where((device) => device.trusted && matches(device))
        .toList();
    final trustedOnline = trusted.where((d) => isPeerOnline(d)).toList();
    final trustedOffline = trusted.where((d) => !isPeerOnline(d)).toList();
    final discovered = controller.devices
        .where((device) => !device.trusted && matches(device))
        .toList();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _LocalIdentityCard(controller: controller),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: controller.text.filterConversations,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => controller.setConversationFilter(value),
          ),
          const SizedBox(height: 16),
          if (trusted.isEmpty) ...[
            _SectionTitle(
              title: controller.text.trustedDevices,
              count: 0,
            ),
            _EmptyHint(controller.text.noTrustedDevices),
          ] else ...[
            _SectionTitle(
              title: controller.text.trustedDevicesOnline,
              count: trustedOnline.length,
            ),
            if (trustedOnline.isEmpty) _EmptyHint(controller.text.noOnlineDevices),
            for (final device in trustedOnline)
              _DeviceTile(controller: controller, device: device),
            if (trustedOffline.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionTitle(
                title: controller.text.trustedDevicesOffline,
                count: trustedOffline.length,
              ),
              for (final device in trustedOffline)
                _DeviceTile(controller: controller, device: device),
            ],
          ],
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
    final conversation = controller.conversations
        .where((c) => c.peerDeviceId == device.id)
        .firstOrNull;
    final unread = conversation == null
        ? 0
        : (controller.unreadCounts[conversation.id] ?? 0);
    final lastMessage = conversation == null
        ? null
        : controller.lastMessages[conversation.id];
    final preview = controller.text.lastMessagePreview(
      lastMessage?.body,
      lastMessage?.fileName,
    );
    final statusLabel = controller.text.peerStatus(device);
    final hasPairRequest =
        controller.pendingPairRequestForDevice(device.id) != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListTile(
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: isPeerOnline(device) ? 1.0 : 0.6,
              child: _DeviceAvatar(
                name: controller.titleFor(device),
                platform: device.platform,
                avatarSeed: device.avatarSeed,
                avatarColor: device.avatarColor,
                trusted: device.trusted,
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: _PeerStatusBadge(device: device, label: statusLabel),
            ),
            if (unread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    '$unread',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Tooltip(
          message: controller.titleFor(device),
          child: Text(
            controller.titleFor(device),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        subtitle: Text(
          preview.isEmpty ? '${device.platform} · $endpoint' : preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: device.trusted
            ? (unread > 0
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  : const Icon(Icons.chevron_right))
            : hasPairRequest
            ? Tooltip(
                message: controller.text.pairRequestPending,
                child: const Icon(Icons.lock_outline),
              )
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

class _PeerStatusBadge extends StatelessWidget {
  const _PeerStatusBadge({required this.device, required this.label});

  final Device device;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = isPeerOnline(device);
    final icon = !device.trusted
        ? Icons.link_off
        : online
        ? Icons.fiber_manual_record
        : Icons.fiber_manual_record;
    final color = !device.trusted
        ? scheme.outline
        : online
        ? const Color(0xFF10B981) // Clean emerald green for online status
        : scheme.outline;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.surface, width: 0.5),
          ),
          child: Icon(
            icon,
            size: 11,
            color: color,
          ),
        ),
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

class _ChatPane extends StatefulWidget {
  const _ChatPane({
    super.key,
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
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  final ScrollController _scrollController = ScrollController();
  bool _atBottom = true;
  int _lastMessageCount = 0;
  bool _searching = false;
  String _searchQuery = '';
  List<ChatMessage> _searchResults = const [];
  int _searchIndex = 0;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final count = controller.messages.length;
    // 新消息到达且用户不在底部时，显示“新消息”按钮（不强制滚动）。
    if (count > _lastMessageCount && !_atBottom) {
      setState(() {});
    }
    // 用户在底部且消息增加，自动滚到底部。
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      if (_atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      } else {
        setState(() {});
      }
    }
  }

  void _onScroll() {
    final pos = _scrollController.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (nearBottom != _atBottom) {
      setState(() => _atBottom = nearBottom);
    }
    // 滚到顶部加载更早消息。
    if (pos.pixels <= 100 && controller.hasMoreMessages) {
      final prevMax = pos.maxScrollExtent;
      controller.loadMoreMessages().then((_) {
        // 保持视觉位置：加载后把滚动条下移新增内容高度。
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final delta = _scrollController.position.maxScrollExtent - prevMax;
          if (delta > 0) {
            _scrollController.jumpTo(_scrollController.offset + delta);
          }
        });
      });
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _runSearch(String query) async {
    _searchQuery = query;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchIndex = 0;
      });
      return;
    }
    final results = await controller.searchSelectedMessages(query);
    if (!mounted || _searchQuery != query) return;
    setState(() {
      _searchResults = results;
      _searchIndex = results.isNotEmpty ? results.length - 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final peer = controller.selectedDevice;
    if (peer == null) {
      return Center(child: Text(controller.text.selectDevice));
    }
    final online = isPeerOnline(peer);
    final pairRequest = controller.pendingPairRequestForDevice(peer.id);
    final pairingResult = controller.pairingResultForDevice(peer.id);
    return DropTarget(
      enable: peer.trusted,
      onDragEntered: (_) => widget.onDragState(true),
      onDragExited: (_) => widget.onDragState(false),
      onDragDone: (details) {
        widget.onDragState(false);
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
          controller.queueFilesForSending(files);
        }
        for (final folder in folders) {
          controller.sendFolder(folder);
        }
      },
      child: Column(
        children: [
          if (widget.showHeader)
            _DesktopPeerHeader(controller: controller, peer: peer),
          if (peer.trusted && !online)
            _ConnectionBanner(controller: controller, peer: peer),
          if (widget.dragging) _DropBanner(controller: controller),
          if (peer.trusted)
            _SearchBar(
              controller: controller,
              searching: _searching,
              query: _searchQuery,
              resultCount: _searchResults.length,
              index: _searchIndex,
              onToggle: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchQuery = '';
                  _searchResults = const [];
                }
              }),
              onChanged: _runSearch,
              onPrev: () {
                if (_searchResults.isNotEmpty) {
                  setState(() {
                    _searchIndex = (_searchIndex - 1) < 0
                        ? _searchResults.length - 1
                        : _searchIndex - 1;
                  });
                  _scrollToMessage(_searchResults[_searchIndex]);
                }
              },
              onNext: () {
                if (_searchResults.isNotEmpty) {
                  setState(() {
                    _searchIndex = (_searchIndex + 1) % _searchResults.length;
                  });
                  _scrollToMessage(_searchResults[_searchIndex]);
                }
              },
            ),
          if (controller.pendingAttachmentBatch != null)
            _AttachmentTray(controller: controller),
          Expanded(
            child: ColoredBox(
              // 浅灰聊天背景（深色模式取 surfaceContainerLow）。
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFEDEDED)
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  if (pairRequest != null)
                    _PairRequestCard(
                      controller: controller,
                      request: pairRequest,
                    ),
                  if (pairingResult != null)
                    _PairingResultLine(message: pairingResult),
                  Expanded(
                    child: controller.messages.isEmpty
                        ? Center(
                            child: Text(
                              peer.trusted
                                  ? controller.text.sayOrDropFile
                                  : controller.text.pairFirst,
                            ),
                          )
                        : _messageList(),
                  ),
                ],
              ),
            ),
          ),
          if (!_atBottom && controller.messages.isNotEmpty)
            _NewMessageButton(onTap: _jumpToBottom),
          _Composer(
            controller: controller,
            textController: widget.textController,
            peer: peer,
          ),
        ],
      ),
    );
  }

  Widget _messageList() {
    final messages = controller.messages;
    final items = <_MessageItem>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      // 日期分隔：首条或与上一条不在同一天时插入分隔条。
      final prev = i == 0 ? null : messages[i - 1];
      final showDate =
          prev == null || !_sameDay(prev.createdAt, message.createdAt);
      if (showDate) {
        items.add(
          _MessageItem(
            key: ValueKey('date-${message.createdAt.millisecondsSinceEpoch}'),
            isDateSeparator: true,
            date: message.createdAt,
          ),
        );
      }
      items.add(
        _MessageItem(key: ValueKey('msg-${message.id}'), message: message),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isDateSeparator) {
          return _DateSeparator(date: item.date!, text: controller.text);
        }
        return _MessageBubble(controller: controller, message: item.message!);
      },
    );
  }

  Future<void> _scrollToMessage(ChatMessage target) async {
    var index = controller.messages.indexWhere((m) => m.id == target.id);
    if (index < 0) {
      final loaded = await controller.loadSearchResult(target);
      if (!mounted || !loaded) return;
      await WidgetsBinding.instance.endOfFrame;
      index = controller.messages.indexWhere((m) => m.id == target.id);
    }
    if (index < 0) return;
    // 估算偏移：消息项含气泡 + padding，按粗略高度滚动。
    if (_scrollController.hasClients) {
      final offset = (index * 88.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  bool _sameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }
}

class _MessageItem {
  const _MessageItem({
    this.key,
    this.message,
    this.date,
    this.isDateSeparator = false,
  });

  final Key? key;
  final ChatMessage? message;
  final DateTime? date;
  final bool isDateSeparator;
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date, required this.text});
  final DateTime date;
  final AppText text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            formatChatDateSeparator(date),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

class _NewMessageButton extends StatelessWidget {
  const _NewMessageButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FloatingActionButton.small(
          heroTag: const ValueKey('jump-to-bottom'),
          onPressed: onTap,
          child: const Icon(Icons.arrow_downward),
        ),
      ),
    );
  }
}

class _PairRequestCard extends StatelessWidget {
  const _PairRequestCard({required this.controller, required this.request});

  final AppController controller;
  final PendingPairRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = controller.isOperationActive('pairRequest:${request.id}');
    final endpoint = request.host.isEmpty || request.port <= 0
        ? controller.text.notConnected
        : displayHost(request.host, request.port);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.text.securePairRequest,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${request.platform} · $endpoint',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(controller.text.firstConnectionConfirmCode),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formatPairCode(request.code),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${controller.text.fingerprint}: ${shortFingerprint(request.fingerprint)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: busy
                              ? null
                              : () => controller.approvePairRequest(request.id),
                          child: Text(controller.text.allow),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => controller.rejectPairRequest(request.id),
                        child: Text(controller.text.reject),
                      ),
                    ],
                  ),
                  if (busy) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatPairCode(String code) {
    final compact = code.replaceAll(RegExp(r'\s+'), '');
    if (compact.length == 6) {
      return '${compact.substring(0, 3)} ${compact.substring(3)}';
    }
    return code;
  }
}

class _PairingResultLine extends StatelessWidget {
  const _PairingResultLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined, size: 16, color: scheme.outline),
            const SizedBox(width: 6),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.searching,
    required this.query,
    required this.resultCount,
    required this.index,
    required this.onToggle,
    required this.onChanged,
    required this.onPrev,
    required this.onNext,
  });

  final AppController controller;
  final bool searching;
  final String query;
  final int resultCount;
  final int index;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    if (!searching) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8, top: 4),
          child: IconButton(
            tooltip: controller.text.searchMessages,
            onPressed: onToggle,
            icon: const Icon(Icons.search, size: 20),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: controller.text.searchMessages,
                prefixIcon: const Icon(Icons.search, size: 18),
                border: const OutlineInputBorder(),
              ),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            resultCount == 0
                ? controller.text.noResults
                : controller.text.searchResultLabel(index + 1, resultCount),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            onPressed: resultCount == 0 ? null : onPrev,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            onPressed: resultCount == 0 ? null : onNext,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          IconButton(
            tooltip: controller.text.close,
            onPressed: onToggle,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// 输入框上方的待发送附件托盘：展示当前批量附件，支持移除单项后统一确认发送。
class _AttachmentTray extends StatelessWidget {
  const _AttachmentTray({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final batch = controller.pendingAttachmentBatch;
    if (batch == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final item in batch.items)
            Chip(
              label: Text(item.fileName),
              onDeleted: () =>
                  controller.removeAttachmentFromBatch(batch.id, item),
            ),
          ActionChip(
            label: Text(controller.text.confirmSend(batch.items.length)),
            onPressed: () =>
                controller.completeAttachmentBatch(batch.id, batch.items),
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
    final hasPairRequest =
        controller.pendingPairRequestForDevice(peer.id) != null;
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
          if (!peer.trusted && hasPairRequest)
            Chip(
              avatar: const Icon(Icons.lock_outline, size: 18),
              label: Text(controller.text.pairRequestPending),
            ),
          if (!peer.trusted && !hasPairRequest)
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

Future<bool> _confirmDanger(
  BuildContext context,
  AppController controller,
  String title,
  String body,
) async {
  final text = controller.text;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(text.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(text.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> _showSettingsDialog(
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
                  onPressed: () => _showLocalRenameDialog(context, controller),
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
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.addPeerManually),
                subtitle: Text(controller.text.addPeerManuallySubtitle),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showAddPeerDialog(context, controller);
                  },
                  child: Text(controller.text.add),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.text.clearHistory),
                subtitle: Text(controller.text.clearHistorySubtitle),
                trailing: TextButton(
                  // 危险操作：二次确认（计划：危险操作增加二次确认）。
                  onPressed: () async {
                    final ok = await _confirmDanger(
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
                    final ok = await _confirmDanger(
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

Future<void> _showAddPeerDialog(
  BuildContext context,
  AppController controller,
) async {
  var host = '';
  var port = '40123';
  NetworkDiagnosticResult? diagnostic;
  var diagnosing = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> runDiagnostic() async {
          final portValue = int.tryParse(port);
          if (host.isEmpty || portValue == null || portValue <= 0) {
            setState(() {
              diagnostic = NetworkDiagnosticResult(
                host: host,
                port: portValue ?? 0,
                status: NetworkDiagnosticStatus.invalidInput,
              );
            });
            return;
          }
          setState(() => diagnosing = true);
          final result = await controller.checkManualPeerConnectivity(
            host,
            portValue,
          );
          if (!dialogContext.mounted) return;
          setState(() {
            diagnostic = result;
            diagnosing = false;
          });
        }

        return AlertDialog(
          title: Text(controller.text.addPeerManually),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: controller.text.peerHost,
                    hintText: '192.168.10.5',
                  ),
                  onChanged: (value) => host = value.trim(),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: controller.text.peerPort,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => port = value.trim(),
                ),
                if (diagnostic != null) ...[
                  const SizedBox(height: 12),
                  _NetworkDiagnosticResultCard(
                    controller: controller,
                    result: diagnostic!,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: diagnosing
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(controller.text.cancel),
            ),
            OutlinedButton.icon(
              onPressed: diagnosing ? null : runDiagnostic,
              icon: diagnosing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(controller.text.testBeforeAddPeer),
            ),
            FilledButton(
              onPressed: diagnosing
                  ? null
                  : () async {
                      final portValue = int.tryParse(port);
                      if (host.isEmpty || portValue == null || portValue <= 0) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                      await controller.addPeerManually(host, portValue);
                    },
              child: Text(controller.text.add),
            ),
          ],
        );
      },
    ),
  );
}


class _NetworkDiagnosticResultCard extends StatelessWidget {
  const _NetworkDiagnosticResultCard({
    required this.controller,
    required this.result,
  });

  final AppController controller;
  final NetworkDiagnosticResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = result.reachable;
    final color = success ? scheme.primary : scheme.error;
    final localEndpoints = result.localEndpoints;
    return Card(
      margin: EdgeInsets.zero,
      color: success ? scheme.primaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  success ? Icons.check_circle_outline : Icons.error_outline,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    controller.text.networkDiagnosticSummary(result),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: success
                          ? scheme.onPrimaryContainer
                          : scheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              controller.text.networkDiagnosticAdvice,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(controller.text.networkDiagnosticAdviceFor(result)),
            const SizedBox(height: 8),
            Text(
              controller.text.networkDiagnosticLocalAddress,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              localEndpoints.isEmpty
                  ? controller.text.networkDiagnosticNoLocalAddress
                  : localEndpoints.join('\n'),
            ),
            if (result.errorDetail != null &&
                result.errorDetail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                'detail: ${result.errorDetail}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
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
    // 文件传输已入队异步执行，不再用全局 busy 禁用输入框；仅当当前会话正在
    // 发送文本时短暂禁用，避免重复提交（计划 P1：传输期间仍可输入和发送）。
    final enabled =
        peer.trusted && !controller.isOperationActive('sendText:${peer.id}');
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
    final scheme = Theme.of(context).colorScheme;
    // 出站：绿色气泡；入站：白色/暗色表面气泡（微信式左右分列）。
    final bubbleColor = outgoing
        ? scheme.primary
        : (Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : scheme.surfaceContainerHighest);
    final textColor = outgoing ? scheme.onPrimary : scheme.onSurface;
    final align = outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final peer = outgoing ? null : controller.selectedDevice;
    final identity = controller.identity;
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
        Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(outgoing ? 14 : 4),
              bottomRight: Radius.circular(outgoing ? 4 : 14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: textColor),
            child: message.kind == 'file'
                ? _FileMessage(
                    controller: controller,
                    message: message,
                    transfer: message.transferId == null
                        ? null
                        : controller.transfersById[message.transferId!],
                  )
                : _TextMessage(controller: controller, message: message),
          ),
        ),
        if (outgoing && message.status == 'failed' && message.kind != 'file')
          TextButton.icon(
            onPressed: controller.busy
                ? null
                : () => controller.retryMessage(message),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(controller.text.retry),
          ),
        const SizedBox(height: 3),
        Text(
          '${controller.text.messageStatus(message.status)} ${formatMessageTimestamp(message.createdAt)}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
  const _TextMessage({required this.controller, required this.message});

  final AppController controller;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final body = message.body ?? '';
    final links = extractLinks(body);
    if (links.isEmpty) {
      return SelectableText(body);
    }
    // 含链接时用富文本渲染，链接可点击打开（保留文本选择）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(body),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final link in links)
              ActionChip(
                avatar: const Icon(Icons.link, size: 16),
                label: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: () => controller.openUrl(link),
              ),
          ],
        ),
      ],
    );
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
    final folderTarget = transfer?.savedUri != null && Platform.isAndroid
        ? null
        : transfer?.savedPath ?? message.filePath;
    final canRename = controller.canRenameMessageFile(message, transfer);
    final canRetry =
        message.direction == 'out' &&
        message.status == 'failed' &&
        transfer != null;
    final showProgress =
        progress != null &&
        progress < 1 &&
        (message.status == 'sending' || message.status == 'receiving');
    final isQueued = message.status == 'queued';
    final isTerminalFailed =
        message.status == 'failed' ||
        message.status == 'canceled' ||
        message.status == 'interrupted';
    final outgoing = message.direction == 'out';
    final scheme = Theme.of(context).colorScheme;
    final panelColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.14)
        : scheme.surfaceContainerHigh;
    final panelBorderColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.22)
        : scheme.outlineVariant;
    final primaryTextColor = outgoing ? scheme.onPrimary : scheme.onSurface;
    final secondaryTextColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.82)
        : scheme.onSurfaceVariant;
    final disabledActionColor = outgoing
        ? scheme.onPrimary.withValues(alpha: 0.36)
        : scheme.onSurface.withValues(alpha: 0.34);
    final failureTextColor = outgoing ? scheme.onPrimary : scheme.error;
    final fileName =
        message.relativePath ?? message.fileName ?? controller.text.file;
    final smallTextStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: secondaryTextColor);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: panelBorderColor),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: primaryTextColor),
        child: IconTheme.merge(
          data: IconThemeData(color: primaryTextColor),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilePreview(message: message, mimeType: mimeType),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: primaryTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (fileSize > 0)
                          Text(formatBytes(fileSize), style: smallTextStyle),
                        if (saved)
                          Text(
                            controller.text.savedLocal,
                            style: smallTextStyle,
                          ),
                        if (isQueued || isTerminalFailed)
                          Text(
                            messageStatusLabel(message.status),
                            style: smallTextStyle?.copyWith(
                              color: isTerminalFailed
                                  ? failureTextColor
                                  : secondaryTextColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  color: primaryTextColor,
                  backgroundColor: primaryTextColor.withValues(alpha: 0.22),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatBytes(receivedBytes)} / ${formatBytes(fileSize)} · ${(progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: secondaryTextColor),
                ),
              ],
              if (isQueued) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  color: primaryTextColor,
                  backgroundColor: primaryTextColor.withValues(alpha: 0.22),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  alignment: WrapAlignment.end,
                  children: [
                    if (canRetry)
                      _fileActionButton(
                        tooltip: controller.text.retry,
                        onPressed: controller.busy
                            ? null
                            : () => controller.retryMessage(message),
                        icon: Icons.refresh,
                        color: primaryTextColor,
                        disabledColor: disabledActionColor,
                      ),
                    _fileActionButton(
                      tooltip: controller.text.open,
                      onPressed: openTarget == null
                          ? null
                          : () => controller.openPath(openTarget),
                      icon: Icons.open_in_new,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
                    ),
                    _fileActionButton(
                      tooltip: controller.text.openFolder,
                      onPressed: folderTarget == null
                          ? null
                          : () => controller.openFolder(folderTarget),
                      icon: Icons.folder_open,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
                    ),
                    if (canRename)
                      _fileActionButton(
                        tooltip: controller.text.renameFile,
                        onPressed: controller.busy
                            ? null
                            : () => _showRenameFileDialog(
                                context,
                                controller,
                                message,
                                transfer!,
                              ),
                        icon: Icons.drive_file_rename_outline,
                        color: primaryTextColor,
                        disabledColor: disabledActionColor,
                      ),
                    _fileActionButton(
                      tooltip: controller.text.saveLocal,
                      onPressed: saved
                          ? null
                          : () => controller.saveMessageFile(message),
                      icon: Icons.save_alt,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
                    ),
                    _fileActionButton(
                      tooltip: controller.text.delete,
                      onPressed: () => _showDeleteFileMessageDialog(
                        context,
                        controller,
                        message,
                        transfer,
                      ),
                      icon: Icons.delete_outline,
                      color: primaryTextColor,
                      disabledColor: disabledActionColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileActionButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
    required Color color,
    required Color disabledColor,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: color,
      disabledColor: disabledColor,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

Future<void> _showRenameFileDialog(
  BuildContext context,
  AppController controller,
  ChatMessage message,
  Transfer transfer,
) async {
  final formKey = GlobalKey<FormState>();
  final initial = transfer.fileName;
  final dot = initial.lastIndexOf('.');
  final cursorOffset = dot > 0 ? dot : initial.length; // 放在扩展名前面（无扩展名时置于末尾）
  final textController = TextEditingController(text: initial)
    ..selection = TextSelection.collapsed(offset: cursorOffset);
  var value = initial;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(controller.text.renameFile),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(labelText: controller.text.fileName),
          onChanged: (text) => value = text,
          validator: (text) => FileStore.validateFileName(text ?? '') == null
              ? null
              : controller.text.invalidFileName,
          onFieldSubmitted: (_) {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(value);
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(controller.text.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(value);
            }
          },
          child: Text(controller.text.save),
        ),
      ],
    ),
  );
  if (result != null) {
    await controller.renameMessageFile(message, transfer, result);
  }
  textController.dispose();
}

Future<void> _showDeleteFileMessageDialog(
  BuildContext context,
  AppController controller,
  ChatMessage message,
  Transfer? transfer,
) async {
  final filePath = transfer?.savedPath ?? message.filePath;
  final hasLocalFile = filePath != null &&
      filePath.isNotEmpty &&
      (File(filePath).existsSync() || Directory(filePath).existsSync());

  await showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(controller.text.deleteFileConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(controller.text.deleteFileMessageConfirmBody),
            const SizedBox(height: 16),
            Text(
              controller.text.localFilePath,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SelectableText(
                filePath != null && filePath.isNotEmpty
                    ? filePath
                    : controller.text.localFileNotExist,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: filePath != null && filePath.isNotEmpty
                      ? scheme.onSurface
                      : scheme.error,
                ),
              ),
            ),
            if (filePath != null && filePath.isNotEmpty && !hasLocalFile) ...[
              const SizedBox(height: 8),
              Text(
                controller.text.localFileNotExist,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(controller.text.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              controller.deleteFileMessage(message, false);
            },
            child: Text(controller.text.deleteRecordOnly),
          ),
          FilledButton(
            onPressed: hasLocalFile
                ? () {
                    Navigator.of(context).pop();
                    controller.deleteFileMessage(message, true);
                  }
                : null,
            child: Text(controller.text.deleteFileAndRecord),
          ),
        ],
      );
    },
  );
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
