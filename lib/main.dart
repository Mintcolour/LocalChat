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
import 'models/protocol.dart';
import 'services/file_store.dart';
import 'ui/attachment_preview.dart';
import 'ui/transfer_center_page.dart';

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
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LocalChat',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
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

class _LocalChatHomeState extends State<LocalChatHome> {
  final _textController = TextEditingController();
  bool _dragging = false;
  String? _shownPairRequestId;
  int _shownNotificationSerial = 0;
  int? _shownAttachmentBatchId;

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
                      SizedBox(width: 340, child: devicePane),
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListTile(
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            _DeviceAvatar(
              name: controller.titleFor(device),
              platform: device.platform,
              avatarSeed: device.avatarSeed,
              avatarColor: device.avatarColor,
              trusted: device.trusted,
            ),
            if (unread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
        title: Text(
          controller.titleFor(device),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          preview.isEmpty
              ? '${controller.text.peerStatus(device)} · ${device.platform} · $endpoint'
              : preview,
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

class _ChatPane extends StatefulWidget {
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
          if (peer.trusted) _SearchBar(
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
            onPrev: () => setState(() {
              if (_searchResults.isNotEmpty) {
                _searchIndex = (_searchIndex - 1) < 0
                    ? _searchResults.length - 1
                    : _searchIndex - 1;
                _scrollToMessage(_searchResults[_searchIndex]);
              }
            }),
            onNext: () => setState(() {
              if (_searchResults.isNotEmpty) {
                _searchIndex = (_searchIndex + 1) % _searchResults.length;
                _scrollToMessage(_searchResults[_searchIndex]);
              }
            }),
          ),
          if (controller.pendingAttachmentBatch != null)
            _AttachmentTray(controller: controller),
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
        return _MessageBubble(
          controller: controller,
          message: item.message!,
        );
      },
    );
  }

  void _scrollToMessage(ChatMessage target) {
    // 简单实现：目标在当前已加载页内则滚动到对应位置；否则跳到底部提示加载。
    final index = controller.messages.indexWhere((m) => m.id == target.id);
    if (index < 0) return;
    // 估算偏移：消息项含气泡 + padding，按粗略高度滚动。
    if (_scrollController.hasClients) {
      final offset = (index * 88.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
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
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final item in batch.items)
            Chip(
              label: Text(item.fileName),
              onDeleted: () => controller.removeAttachmentFromBatch(
                batch.id,
                item,
              ),
            ),
          ActionChip(
            label: Text(controller.text.confirmSend(batch.items.length)),
            onPressed: () => controller.completeAttachmentBatch(
              batch.id,
              batch.items,
            ),
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

Future<void> _showAddPeerDialog(
  BuildContext context,
  AppController controller,
) async {
  var host = '';
  var port = '40123';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(controller.text.cancel),
          ),
          FilledButton(
            onPressed: () async {
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
    // 文件传输已入队异步执行，不再用全局 busy 禁用输入框；仅当当前会话正在
    // 发送文本时短暂禁用，避免重复提交（计划 P1：传输期间仍可输入和发送）。
    final enabled = peer.trusted &&
        !controller.isOperationActive('sendText:${peer.id}');
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
              : _TextMessage(controller: controller, message: message),
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
                label: Text(
                  link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
    final isTerminalFailed = message.status == 'failed' ||
        message.status == 'canceled' ||
        message.status == 'interrupted';
    return Column(
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
                    message.relativePath ??
                        message.fileName ??
                        controller.text.file,
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
                  if (isQueued || isTerminalFailed)
                    Text(
                      messageStatusLabel(message.status),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isTerminalFailed
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                    ),
                ],
              ),
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
        if (isQueued) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
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
                IconButton(
                  tooltip: controller.text.retry,
                  onPressed: controller.busy
                      ? null
                      : () => controller.retryMessage(message),
                  icon: const Icon(Icons.refresh),
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
                onPressed: folderTarget == null
                    ? null
                    : () => controller.openFolder(folderTarget),
                icon: const Icon(Icons.folder_open),
              ),
              if (canRename)
                IconButton(
                  tooltip: controller.text.renameFile,
                  onPressed: controller.busy
                      ? null
                      : () => _showRenameFileDialog(
                          context,
                          controller,
                          message,
                          transfer!,
                        ),
                  icon: const Icon(Icons.drive_file_rename_outline),
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
        ),
      ],
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
  final cursorOffset =
      dot > 0 ? dot : initial.length; // 放在扩展名前面（无扩展名时置于末尾）
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
