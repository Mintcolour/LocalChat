import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/core/app_text.dart';
import 'package:localchat/core/formatters.dart';
import 'package:localchat/core/peer_status.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/protocol.dart';
import 'package:localchat/ui/banners.dart';
import 'package:localchat/ui/composer.dart';
import 'package:localchat/ui/device_pane.dart';
import 'package:localchat/ui/dialogs/peer_dialogs.dart';
import 'package:localchat/ui/message_bubble.dart';

class ChatPane extends StatefulWidget {
  const ChatPane({
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
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
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
            ConnectionBanner(controller: controller, peer: peer),
          if (widget.dragging) DropBanner(controller: controller),
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
          Composer(
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
        return MessageBubble(controller: controller, message: item.message!);
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

class _PairRequestCard extends StatefulWidget {
  const _PairRequestCard({required this.controller, required this.request});

  final AppController controller;
  final PendingPairRequest request;

  @override
  State<_PairRequestCard> createState() => _PairRequestCardState();
}

class _PairRequestCardState extends State<_PairRequestCard> {
  final _codeInputController = TextEditingController();

  @override
  void dispose() {
    _codeInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final request = widget.request;
    final scheme = Theme.of(context).colorScheme;
    final busy = controller.isOperationActive('pairRequest:${request.id}');
    final endpoint = request.host.isEmpty || request.port <= 0
        ? controller.text.notConnected
        : displayHost(request.host, request.port);
    // SAS 请求：展示码与待输入码都使用本地派生值，忽略明文传输的 code。
    final displayCode = request.sasCode ?? request.code;
    final requiresCodeEntry = request.sasCode != null;
    final codeEntered =
        !requiresCodeEntry ||
        _codeInputController.text.trim() == request.sasCode;
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
                      DeviceAvatar(
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
                  Text(
                    requiresCodeEntry
                        ? controller.text.pairSasPrompt
                        : controller.text.firstConnectionConfirmCode,
                  ),
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
                      _formatPairCode(displayCode),
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
                  if (requiresCodeEntry) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeInputController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        border: const OutlineInputBorder(),
                        hintText: controller.text.pairCodeInputHint,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: busy || !codeEntered
                              ? null
                              : () => controller.approvePairRequest(
                                  request.id,
                                  code: request.sasCode,
                                ),
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
          DeviceAvatar(
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
              onPressed: () => showRenameDialog(context, controller, peer),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (peer.trusted)
            IconButton(
              tooltip: controller.text.deleteConversation,
              onPressed: () => confirmDeleteConversation(context, controller),
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

class MobilePeerHeader extends StatelessWidget {
  const MobilePeerHeader({super.key, required this.controller});

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
                  onPressed: () => showRenameDialog(context, controller, peer),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: controller.text.deleteConversation,
                  onPressed: () =>
                      confirmDeleteConversation(context, controller),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : null,
    );
  }
}
