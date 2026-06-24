import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/app_text.dart';
import '../core/app_failure.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/network_diagnostic.dart';
import '../models/notification_event.dart';
import '../models/protocol.dart';
import '../models/pending_attachment.dart';
import '../models/transfer_views.dart';
import '../models/chat_page.dart';
import 'settings_controller.dart';
import '../services/android_keep_alive_service.dart';
import '../services/clipboard_import_service.dart';
import '../services/discovery_service.dart';
import '../services/file_store.dart';
import '../services/identity_service.dart';
import '../services/notification_service.dart';
import '../services/secure_key_store.dart';
import '../services/security_service.dart';
import '../services/transport_service.dart';
import '../services/window_service.dart';

const _staleDiscoveredDeviceAge = Duration(seconds: 20);
const _refreshCoalesceDelay = Duration(milliseconds: 200);

class AppController extends ChangeNotifier {
  AppController({
    AppDatabase? database,
    FileStore? fileStore,
    ClipboardImportService? clipboardImportService,
    SecureKeyStore? secureKeyStore,
    NotificationService? notificationService,
    AndroidKeepAliveService? keepAliveService,
  }) : db = database ?? AppDatabase(),
       fileStore = fileStore ?? FileStore(),
       clipboardImportService =
           clipboardImportService ?? ClipboardImportService(),
       notificationService = notificationService ?? NotificationService(),
       keepAliveService = keepAliveService ?? const AndroidKeepAliveService() {
    // 生产环境由 main() 传入真实 SecureKeyStore；测试默认不传（回退数据库明文），
    // 避免依赖平台安全存储插件。
    identityService = IdentityService(db, secureKeyStore: secureKeyStore);
    securityService = SecurityService(identityService);
    transportService = TransportService(
      db,
      identityService,
      securityService,
      this.fileStore,
    );
    discoveryService = DiscoveryService(db, identityService);
    settings = SettingsController(db: db, windowService: windowService);
  }

  final AppDatabase db;
  final FileStore fileStore;
  final ClipboardImportService clipboardImportService;
  final NotificationService notificationService;
  final AndroidKeepAliveService keepAliveService;
  final WindowService windowService = const WindowService();
  late final IdentityService identityService;
  late final SecurityService securityService;
  late final TransportService transportService;
  late final DiscoveryService discoveryService;

  /// 设置子控制器：语言/外观/自动复制/托盘/开机自启。对外字段与方法通过下方 getter
  /// 与同名方法委托，UI 无需感知拆分（计划 P1 控制器拆分）。
  late final SettingsController settings;

  LocalIdentity? identity;
  List<Device> devices = [];
  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  Map<String, Transfer> transfersById = {};

  /// 各会话未读数（conversationId -> count）。
  Map<String, int> unreadCounts = {};

  /// 各会话最后一条消息预览（conversationId -> message）。
  Map<String, ChatMessage> lastMessages = {};

  /// 会话列表名称过滤关键字。
  String conversationFilter = '';

  void setConversationFilter(String value) {
    if (value == conversationFilter) return;
    conversationFilter = value;
    notifyListeners();
  }

  PendingPairRequest? get pendingPairRequest =>
      pendingPairRequests.isEmpty ? null : pendingPairRequests.last;

  PendingPairRequest? pendingPairRequestForDevice(String deviceId) {
    for (final request in pendingPairRequests.reversed) {
      if (request.deviceId == deviceId) return request;
    }
    return null;
  }

  String? pairingResultForDevice(String deviceId) =>
      pairingResultMessagesByDevice[deviceId];

  void setAppForeground(bool value) {
    final changed = _appForeground != value;
    _appForeground = value;
    if (changed && value && selectedDevice != null) {
      _scheduleRefresh();
    }
  }

  /// 当前会话分页游标（用于判断是否还有更早的页 + 向前加载）。
  ChatPageCursor? messageCursor;

  /// 当前会话是否还有更早的消息可加载。
  bool hasMoreMessages = false;
  Device? selectedDevice;
  Conversation? selectedConversation;
  final List<PendingPairRequest> pendingPairRequests = [];
  final Map<String, String> pairingResultMessagesByDevice = {};
  bool initialized = false;
  bool busy = false;

  /// 细粒度操作状态：记录正在进行的特定操作（配对、重试等），替代仅靠全局 busy
  /// 禁用输入的做法。文件传输已入队异步执行，不再阻塞输入框（计划 P1）。
  final Set<String> activeOperations = {};
  bool isOperationActive(String key) => activeOperations.contains(key);

  void _beginOperation(String key) {
    activeOperations.add(key);
  }

  void _endOperation(String key) {
    activeOperations.remove(key);
  }

  /// 是否有任何特定操作进行中（不含文件传输，传输已入队异步执行）。
  bool get anyOperationActive => activeOperations.isNotEmpty;
  String status = '正在启动 LocalChat...';
  String? lastError;
  String? notificationText;
  int notificationSerial = 0;
  bool _appForeground = true;
  List<String> pendingSharedFiles = [];
  String? pendingSharedText;
  PendingAttachmentBatch? pendingAttachmentBatch;
  int _attachmentBatchSerial = 0;

  StreamSubscription<void>? _transportSub;
  StreamSubscription<String>? _notificationSub;
  StreamSubscription<AppNotificationEvent>? _notificationEventSub;
  StreamSubscription<DiscoveredPeer>? _discoverySub;
  StreamSubscription<PendingPairRequest>? _pairRequestSub;
  StreamSubscription<String>? _notificationTapSub;
  StreamSubscription<List<SharedMediaFile>>? _sharingSub;
  final Map<String, Timer> _pairRequestTimers = {};
  Timer? _presenceTimer;
  Timer? _refreshTimer;
  bool _refreshingPresence = false;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _loadingMore = false;

  AppText get text => AppText(languageCode);

  // 设置相关字段委托到 SettingsController，保持对外 API 不变。
  bool get autoCopyReceivedText => settings.autoCopyReceivedText;
  bool get trayEnabled => settings.trayEnabled;
  bool get autostartEnabled => settings.autostartEnabled;
  bool get notificationsEnabled => settings.notificationsEnabled;
  bool get notificationPreviewEnabled => settings.notificationPreviewEnabled;
  bool get keepAliveEnabled => settings.keepAliveEnabled;
  bool get keepAliveSupported => keepAliveService.isSupported;
  String get languageCode => settings.languageCode;
  String get themeModeCode => settings.themeModeCode;
  set themeModeCode(String value) => settings.themeModeCode = value;
  set languageCode(String value) => settings.languageCode = value;
  int get localListenPort => transportService.port;

  Future<void> initialize() async {
    busy = true;
    notifyListeners();
    try {
      identity = await identityService.load();
      await settings.load();
      if (settings.keepAliveEnabled && keepAliveService.isSupported) {
        await keepAliveService.start();
      }
      await notificationService.initialize();
      if (settings.notificationsEnabled) {
        await notificationService.requestPermissionIfNeeded();
      }
      _notificationTapSub = notificationService.notificationTapStream.listen(
        (payload) => unawaited(handleNotificationPayload(payload)),
      );
      transportService.autoCopyReceivedText = settings.autoCopyReceivedText;
      transportService.languageCode = settings.languageCode;
      transportService.reconnectPeer = _waitForReconnectedPeer;
      final port = await transportService.start();
      await discoveryService.start(listenPort: port);
      _transportSub = transportService.updates.listen(
        (_) => _scheduleRefresh(),
      );
      _notificationSub = transportService.notifications.listen((message) {
        notificationText = message;
        notificationSerial++;
        status = message;
        notifyListeners();
      });
      _notificationEventSub = transportService.notificationEvents.listen(
        (event) => unawaited(handleNotificationEvent(event)),
      );
      _discoverySub = discoveryService.peers.listen((_) => _scheduleRefresh());
      _pairRequestSub = transportService.pairRequests.listen((request) {
        unawaited(_handleIncomingPairRequest(request));
      });
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshPeerPresence(),
      );
      await _loadSharingIntents();
      await refresh();
      status = languageCode == 'en'
          ? 'Discovering LAN devices, local port $port'
          : '正在局域网内发现设备，本机端口 $port';
      initialized = true;
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en' ? 'Startup failed' : '启动失败';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    try {
      conversations = await db.listConversations();
      await db.deleteStaleUntrustedDevices(
        DateTime.now().subtract(_staleDiscoveredDeviceAge),
      );
      devices = await db.listDevices();
      _sortDevices();
      if (selectedDevice != null) {
        selectedDevice =
            devices
                .where((device) => device.id == selectedDevice!.id)
                .firstOrNull ??
            selectedDevice;
        selectedConversation = await db.ensureConversation(selectedDevice!);
        // 分页：刷新时只重载最新一页，避免大历史全量加载。
        final latestPage = await db.listMessagesPage(
          conversationId: selectedConversation!.id,
          limit: 50,
        );
        // 保留用户已经加载的旧页或搜索定位页，只合并最新页的状态与新增消息。
        // 否则传输进度/在线状态触发的 refresh 会每 200ms 把视图重置回最新 50 条。
        final merged =
            <String, ChatMessage>{
              for (final message in messages) message.id: message,
              for (final message in latestPage) message.id: message,
            }.values.toList()..sort((a, b) {
              final byTime = a.createdAt.compareTo(b.createdAt);
              return byTime != 0 ? byTime : a.id.compareTo(b.id);
            });
        messages = merged;
        _updateMessageCursor(messages);
        final transferIds = messages
            .map((message) => message.transferId)
            .whereType<String>();
        final transfers = await db.listTransfersByIds(transferIds);
        transfersById = {
          for (final transfer in transfers) transfer.id: transfer,
        };
        if (_appForeground) {
          await markConversationRead(selectedDevice!.id);
          conversations = await db.listConversations();
        }
      }
      await _loadConversationSummaries();
    } finally {
      _refreshInFlight = false;
    }
    notifyListeners();
    if (_refreshQueued) {
      _refreshQueued = false;
      _scheduleRefresh();
    }
  }

  Future<void> selectDevice(Device device) async {
    selectedDevice = device;
    selectedConversation = await db.ensureConversation(device);
    final page = await db.listMessagesPage(
      conversationId: selectedConversation!.id,
      limit: 50,
    );
    messages = page;
    _updateMessageCursor(page);
    await _ensureTransfersForCurrentMessages();
    await markConversationRead(device.id);
    notifyListeners();
    await _flushPendingShareIfPossible();
  }

  /// 向前加载更早的一页消息（用户滚到顶部时触发）。
  Future<void> loadMoreMessages() async {
    final conversation = selectedConversation;
    if (conversation == null || !hasMoreMessages || _loadingMore) return;
    _loadingMore = true;
    try {
      final page = await db.listMessagesPage(
        conversationId: conversation.id,
        limit: 50,
        beforeCreatedAt: messageCursor?.beforeCreatedAt,
        beforeId: messageCursor?.beforeId,
      );
      final more = page;
      if (more.isEmpty) {
        hasMoreMessages = false;
        notifyListeners();
        return;
      }
      messages = [...more, ...messages];
      _updateMessageCursor(messages);
      await _ensureTransfersForCurrentMessages();
      notifyListeners();
    } finally {
      _loadingMore = false;
    }
  }

  /// 标记当前选中会话为已读，清零未读数。
  Future<void> markConversationRead(String deviceId) async {
    final conversation = await db.getConversationForDevice(deviceId);
    if (conversation == null) return;
    await db.markConversationRead(conversation.id);
    unreadCounts[conversation.id] = 0;
  }

  /// 在当前会话内搜索消息（正文/文件名），结果上限 100 条。
  Future<List<ChatMessage>> searchSelectedMessages(String query) async {
    final conversation = selectedConversation;
    if (conversation == null || query.trim().isEmpty) return const [];
    return db.searchMessages(conversation.id, query.trim());
  }

  /// 将搜索命中的历史消息所在页载入当前会话，避免只搜索到结果却无法定位。
  Future<bool> loadSearchResult(ChatMessage target) async {
    final conversation = selectedConversation;
    if (conversation == null || target.conversationId != conversation.id) {
      return false;
    }
    if (messages.any((message) => message.id == target.id)) return true;
    final page = await db.listMessagesPageEndingAt(
      conversationId: conversation.id,
      createdAt: target.createdAt,
      id: target.id,
      limit: 50,
    );
    messages = page;
    _updateMessageCursor(page);
    await _ensureTransfersForCurrentMessages();
    notifyListeners();
    return page.any((message) => message.id == target.id);
  }

  void _updateMessageCursor(List<ChatMessage> page) {
    if (page.isEmpty) {
      messageCursor = null;
      hasMoreMessages = false;
      return;
    }
    final oldest = page.first;
    messageCursor = ChatPageCursor(
      beforeCreatedAt: oldest.createdAt,
      beforeId: oldest.id,
    );
    // listMessagesPage 多取 1 条；若本次返回等于 50，说明很可能还有更早页。
    hasMoreMessages = page.length >= 50;
  }

  Future<void> _ensureTransfersForCurrentMessages() async {
    final transferIds = messages
        .map((message) => message.transferId)
        .whereType<String>();
    final transfers = await db.listTransfersByIds(transferIds);
    transfersById = {for (final transfer in transfers) transfer.id: transfer};
  }

  Future<void> _loadConversationSummaries() async {
    final summaries = <String, int>{};
    final lasts = <String, ChatMessage>{};
    for (final conversation in conversations) {
      final lastPage = await db.listMessagesPage(
        conversationId: conversation.id,
        limit: 1,
      );
      final last = lastPage.isEmpty ? null : lastPage.first;
      if (last != null) lasts[conversation.id] = last;
      final unread = await db.unreadCount(
        conversation.id,
        lastReadAt: conversation.lastReadAt,
      );
      summaries[conversation.id] = unread;
    }
    unreadCounts = summaries;
    lastMessages = lasts;
  }

  void closeConversation() {
    selectedDevice = null;
    selectedConversation = null;
    messages = [];
    transfersById = {};
    messageCursor = null;
    hasMoreMessages = false;
    notifyListeners();
  }

  String titleFor(Device device) {
    final conversation = conversations
        .where((item) => item.peerDeviceId == device.id)
        .firstOrNull;
    return conversation?.title ?? device.displayName;
  }

  Future<void> renameSelectedConversation(String title) async {
    final conversation = selectedConversation;
    final trimmed = title.trim();
    if (conversation == null || trimmed.isEmpty) return;
    await db.renameConversation(conversation.id, trimmed);
    status = languageCode == 'en'
        ? 'Chat renamed to $trimmed'
        : '会话已重命名为 $trimmed';
    await refresh();
  }

  Future<void> deleteSelectedConversation() async {
    final peer = selectedDevice;
    if (peer == null) return;
    final title = titleFor(peer);
    await fileStore.deleteManagedEditedFiles(
      messages
          .where((message) => message.direction == 'out')
          .map((message) => message.filePath),
    );
    await fileStore.deleteIncomingFiles(
      messages
          .where((message) => message.direction == 'in')
          .map((message) => message.filePath),
    );
    await db.deletePeerSession(peer.id);
    selectedConversation = null;
    selectedDevice = null;
    messages = [];
    transfersById = {};
    status = languageCode == 'en' ? 'Deleted chat $title' : '已删除会话 $title';
    await refresh();
  }

  Future<void> deleteFileMessage(ChatMessage message, bool deleteLocalFile) async {
    if (deleteLocalFile) {
      final filePathsToDelete = <String>[];
      final String? pathOnDisk = message.filePath;
      if (pathOnDisk != null && pathOnDisk.isNotEmpty) {
        filePathsToDelete.add(pathOnDisk);
      }
      if (message.transferId != null && message.transferId!.isNotEmpty) {
        final transfer = transfersById[message.transferId];
        if (transfer != null && transfer.savedPath != null && transfer.savedPath!.isNotEmpty) {
          filePathsToDelete.add(transfer.savedPath!);
        }
      }

      for (final path in filePathsToDelete.toSet()) {
        try {
          if (await FileSystemEntity.isDirectory(path)) {
            final dir = Directory(path);
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          } else {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          }
        } catch (e) {
          status = languageCode == 'en'
              ? 'Failed to delete local file: $e'
              : '删除本地文件失败: $e';
        }
      }
    }

    await db.deleteChatMessage(message.id);
    messages = messages.where((m) => m.id != message.id).toList();
    status = languageCode == 'en' ? 'Message deleted' : '消息已删除';
    await refresh();
  }


  Future<void> setLanguageCode(String value) async {
    await settings.setLanguageCode(value);
    transportService.languageCode = settings.languageCode;
    status = settings.languageCode == 'en'
        ? 'Language set to English'
        : '语言已切换为中文';
    notifyListeners();
  }

  Future<void> setThemeModeCode(String value) async {
    await settings.setThemeModeCode(value);
    status = settings.languageCode == 'en' ? 'Appearance updated' : '外观模式已更新';
    notifyListeners();
  }

  Future<void> setAutoCopyReceivedText(bool value) async {
    await settings.setAutoCopyReceivedText(value);
    transportService.autoCopyReceivedText = settings.autoCopyReceivedText;
    status = value
        ? (settings.languageCode == 'en'
              ? 'Auto-copy received text enabled'
              : '已开启自动复制收到的文字')
        : (settings.languageCode == 'en'
              ? 'Auto-copy received text disabled'
              : '已关闭自动复制收到的文字');
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await settings.setNotificationsEnabled(value);
    if (value) {
      await notificationService.requestPermissionIfNeeded();
    }
    status = value
        ? (settings.languageCode == 'en'
              ? 'System notifications enabled'
              : '已开启系统消息通知')
        : (settings.languageCode == 'en'
              ? 'System notifications disabled'
              : '已关闭系统消息通知');
    notifyListeners();
  }

  Future<void> setNotificationPreviewEnabled(bool value) async {
    await settings.setNotificationPreviewEnabled(value);
    status = value
        ? (settings.languageCode == 'en'
              ? 'Notification content preview enabled'
              : '已开启通知内容预览')
        : (settings.languageCode == 'en'
              ? 'Notification content preview disabled'
              : '已关闭通知内容预览');
    notifyListeners();
  }

  Future<void> setKeepAliveEnabled(bool value) async {
    await settings.setKeepAliveEnabled(value);
    if (keepAliveService.isSupported) {
      if (value) {
        await keepAliveService.start();
      } else {
        await keepAliveService.stop();
      }
    }
    status = value
        ? (settings.languageCode == 'en'
              ? 'Background connection keep-alive enabled'
              : '已开启后台保持连接')
        : (settings.languageCode == 'en'
              ? 'Background reliability will be reduced'
              : '已关闭后台保持连接，后台可靠性会下降');
    notifyListeners();
  }

  Future<void> setTrayEnabled(bool value) async {
    await settings.setTrayEnabled(value);
    status = value
        ? (settings.languageCode == 'en'
              ? 'Minimize to tray enabled'
              : '已开启最小化到托盘')
        : (settings.languageCode == 'en'
              ? 'Minimize to tray disabled'
              : '已关闭最小化到托盘');
    notifyListeners();
  }

  Future<void> setAutostartEnabled(bool value) async {
    await settings.setAutostartEnabled(value);
    status = value
        ? (settings.languageCode == 'en' ? 'Start on boot enabled' : '已开启开机自启')
        : (settings.languageCode == 'en'
              ? 'Start on boot disabled'
              : '已关闭开机自启');
    notifyListeners();
  }

  /// 请求最小化到托盘（关窗时由 UI 触发）。
  Future<void> minimizeToTray() => windowService.minimizeToTray();

  /// 请求真正退出（托盘菜单退出项触发）。
  Future<void> quitApp() => windowService.quit();

  Future<void> rescan() async {
    status = languageCode == 'en'
        ? 'Rescanning LAN devices...'
        : '正在重新搜索局域网设备...';
    notifyListeners();
    await discoveryService.announce();
    await _refreshPeerPresence();
    await db.deleteStaleUntrustedDevices(
      DateTime.now().subtract(_staleDiscoveredDeviceAge),
    );
    await refresh();
    status = languageCode == 'en' ? 'Device list refreshed' : '已刷新设备列表';
    notifyListeners();
  }

  Future<void> renameLocalDevice(String title) async {
    identity = await identityService.updateDisplayName(title);
    status = languageCode == 'en'
        ? 'Local nickname changed to ${identity!.displayName}'
        : '本机昵称已改为 ${identity!.displayName}';
    await discoveryService.announce();
    notifyListeners();
  }

  Future<void> approvePendingPair() async {
    final request = pendingPairRequest;
    if (request == null) return;
    await approvePairRequest(request.id);
  }

  Future<void> rejectPendingPair() async {
    final request = pendingPairRequest;
    if (request == null) return;
    await rejectPairRequest(request.id);
  }

  Future<void> approvePairRequest(String requestId) async {
    final request = _pendingPairRequestById(requestId);
    if (request == null) return;
    final operationKey = 'pairRequest:$requestId';
    _beginOperation(operationKey);
    notifyListeners();
    try {
      transportService.approvePairRequest(requestId);
      _removePendingPairRequest(requestId);
      pairingResultMessagesByDevice[request.deviceId] =
          text.trustedChannelEstablished;
      status = languageCode == 'en'
          ? 'Allowed pairing with ${request.displayName}'
          : '已允许 ${request.displayName} 配对';
      await refresh();
    } finally {
      _endOperation(operationKey);
      notifyListeners();
    }
  }

  Future<void> rejectPairRequest(String requestId) async {
    final request = _pendingPairRequestById(requestId);
    if (request == null) return;
    final operationKey = 'pairRequest:$requestId';
    _beginOperation(operationKey);
    notifyListeners();
    try {
      transportService.rejectPairRequest(requestId);
      _removePendingPairRequest(requestId);
      pairingResultMessagesByDevice[request.deviceId] =
          text.pairRequestRejected;
      status = languageCode == 'en'
          ? 'Rejected pairing with ${request.displayName}'
          : '已拒绝 ${request.displayName} 配对';
    } finally {
      _endOperation(operationKey);
      notifyListeners();
    }
  }

  Future<void> handleNotificationEvent(AppNotificationEvent event) async {
    if (!settings.notificationsEnabled) return;
    if (!await _shouldShowSystemNotification()) return;
    await notificationService.showMessageNotification(
      event,
      includePreview: settings.notificationPreviewEnabled,
    );
  }

  Future<void> handleNotificationPayload(String payload) async {
    final parsed = AppNotificationPayload.tryParse(payload);
    if (parsed == null) return;
    await windowService.show();
    final deviceId = parsed.deviceId;
    if (deviceId == null) return;
    final device = await db.getDevice(deviceId);
    if (device == null) return;
    await selectDevice(device);
  }

  Future<void> _handleIncomingPairRequest(PendingPairRequest request) async {
    _removePendingPairRequest(request.id);
    pendingPairRequests.add(request);
    pairingResultMessagesByDevice.remove(request.deviceId);
    _pairRequestTimers[request.id] = Timer(const Duration(seconds: 65), () {
      final expired = _pendingPairRequestById(request.id);
      if (expired == null) return;
      _removePendingPairRequest(request.id);
      pairingResultMessagesByDevice[request.deviceId] = text.pairRequestExpired;
      status = text.pairRequestExpired;
      notifyListeners();
    });
    status = languageCode == 'en'
        ? '${request.displayName} requests pairing. Confirm code ${request.code}.'
        : '${request.displayName} 请求配对，请确认 6 位校验码 ${request.code}';
    await refresh();
    if (selectedDevice == null) {
      final device = await db.getDevice(request.deviceId);
      if (device != null) {
        await selectDevice(device);
      }
    }
    notifyListeners();
    if (settings.notificationsEnabled &&
        await _shouldShowSystemNotification()) {
      await notificationService.showPairRequestNotification(
        request,
        title: text.securePairRequest,
        body: text.pairRequestNotificationBody(request.displayName),
      );
    }
  }

  PendingPairRequest? _pendingPairRequestById(String requestId) {
    for (final request in pendingPairRequests) {
      if (request.id == requestId) return request;
    }
    return null;
  }

  void _removePendingPairRequest(String requestId) {
    _pairRequestTimers.remove(requestId)?.cancel();
    pendingPairRequests.removeWhere((request) => request.id == requestId);
  }

  Future<bool> _shouldShowSystemNotification() async {
    final nativeForeground = await windowService.isForeground();
    return !(nativeForeground ?? _appForeground);
  }

  Future<void> pair(Device device) async {
    final code = randomCode();
    status = languageCode == 'en'
        ? 'Connecting to ${device.displayName} with code $code'
        : '正在用配对码 $code 连接 ${device.displayName}';
    _beginOperation('pair:${device.id}');
    notifyListeners();
    try {
      await transportService.pairWith(device, code);
      await refresh();
      status = languageCode == 'en'
          ? '${device.displayName} is trusted. You can now send directly.'
          : '已信任 ${device.displayName}，之后可以像聊天一样直接发送';
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en' ? 'Pairing failed' : '配对失败';
    } finally {
      _endOperation('pair:${device.id}');
      notifyListeners();
    }
  }

  /// 跨网段手动加好友：按 host:port 探测对端身份并落库（未信任）。
  /// 返回落库设备；失败返回 null。成功后用户可在设备列表发起配对。
  Future<Device?> addPeerManually(String host, int port) async {
    _beginOperation('addPeer');
    status = languageCode == 'en'
        ? 'Connecting to $host:$port...'
        : '正在连接 $host:$port...';
    notifyListeners();
    try {
      final device = await transportService.fetchPeerIdentity(host, port);
      if (device == null) {
        lastError = languageCode == 'en'
            ? 'Cannot reach $host:$port or not a LocalChat device'
            : '无法连接 $host:$port，或对方不是 LocalChat 设备';
        status = lastError!;
        notifyListeners();
        return null;
      }
      await refresh();
      status = languageCode == 'en'
          ? 'Found ${device.displayName}. Pair to trust.'
          : '已发现 ${device.displayName}，请配对以建立信任';
      notifyListeners();
      return device;
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en' ? 'Add peer failed' : '添加好友失败';
      notifyListeners();
      return null;
    } finally {
      _endOperation('addPeer');
      notifyListeners();
    }
  }

  Future<NetworkDiagnosticResult> checkManualPeerConnectivity(
    String host,
    int port,
  ) async {
    final cleanHost = host.trim();
    _beginOperation('diagnosePeer');
    status = languageCode == 'en'
        ? 'Testing $cleanHost:$port...'
        : '正在测试 $cleanHost:$port...';
    notifyListeners();
    try {
      final endpoints = await loadLocalNetworkEndpoints();
      final result = (cleanHost.isEmpty || port <= 0 || port > 65535)
          ? NetworkDiagnosticResult(
              host: cleanHost,
              port: port,
              status: NetworkDiagnosticStatus.invalidInput,
              localEndpoints: endpoints,
            )
          : (await transportService.probeHello(
              cleanHost,
              port,
            )).withLocalEndpoints(endpoints);
      lastError = result.reachable ? null : result.errorDetail;
      status = text.networkDiagnosticSummary(result);
      return result;
    } catch (error) {
      final result = NetworkDiagnosticResult(
        host: cleanHost,
        port: port,
        status: NetworkDiagnosticStatus.unknownError,
        errorDetail: '$error',
        localEndpoints: await loadLocalNetworkEndpoints(),
      );
      lastError = result.errorDetail;
      status = text.networkDiagnosticSummary(result);
      return result;
    } finally {
      _endOperation('diagnosePeer');
      notifyListeners();
    }
  }

  Future<void> sendText(String text) async {
    final peer = await _currentSelectedPeer();
    if (peer == null || !peer.trusted || text.trim().isEmpty) return;
    _beginOperation('sendText:${peer.id}');
    notifyListeners();
    try {
      await transportService.sendText(peer, text.trim());
      await refresh();
      status = languageCode == 'en'
          ? 'Sent to ${titleFor(peer)}'
          : '${titleFor(peer)} 已发送';
    } catch (error) {
      lastError = '$error';
      status = error is AppFailure
          ? error.userMessage
          : (languageCode == 'en'
                ? '${titleFor(peer)} disconnected, message failed'
                : '${titleFor(peer)} 连接断开，消息发送失败');
    } finally {
      _endOperation('sendText:${peer.id}');
      notifyListeners();
    }
  }

  Future<void> pickAndSendFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    final paths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    await queueFilesForSending(paths);
  }

  Future<void> queueFilesForSending(List<String> paths) async {
    final validPaths = paths
        .where((path) => path.isNotEmpty && File(path).existsSync())
        .toList();
    if (validPaths.isEmpty) return;
    final peer = await _currentSelectedPeer();
    if (peer == null || !peer.trusted) {
      pendingSharedFiles = validPaths;
      status = languageCode == 'en'
          ? 'Select a trusted device before sending ${validPaths.length} files'
          : '先选择一个已信任设备，再发送 ${validPaths.length} 个文件';
      notifyListeners();
      return;
    }
    final items = validPaths.map(PendingAttachment.fromPath).toList();
    if (!items.any((item) => item.isImage)) {
      await sendFiles(validPaths);
      return;
    }
    pendingAttachmentBatch = PendingAttachmentBatch(
      id: ++_attachmentBatchSerial,
      items: items,
    );
    status = languageCode == 'en'
        ? 'Review attachments before sending'
        : '请预览附件后确认发送';
    notifyListeners();
  }

  Future<void> completeAttachmentBatch(
    int batchId,
    List<PendingAttachment> items,
  ) async {
    if (pendingAttachmentBatch?.id != batchId) return;
    pendingAttachmentBatch = null;
    notifyListeners();
    await sendFiles(items.map((item) => item.path).toList());
  }

  Future<void> cancelAttachmentBatch(
    int batchId,
    List<PendingAttachment> items,
  ) async {
    if (pendingAttachmentBatch?.id == batchId) {
      pendingAttachmentBatch = null;
    }
    for (final item in items.where((item) => item.edited)) {
      await fileStore.deleteManagedEditedFile(item.path);
    }
    status = languageCode == 'en' ? 'Sending cancelled' : '已取消发送';
    notifyListeners();
  }

  /// 从当前待发送批量中移除单个附件（托盘删除单项）。
  void removeAttachmentFromBatch(int batchId, PendingAttachment item) {
    final batch = pendingAttachmentBatch;
    if (batch == null || batch.id != batchId) return;
    final remaining = batch.items.where((it) => it.path != item.path).toList();
    if (remaining.isEmpty) {
      pendingAttachmentBatch = null;
    } else {
      pendingAttachmentBatch = PendingAttachmentBatch(
        id: batch.id,
        items: remaining,
      );
    }
    notifyListeners();
  }

  /// 选择一个文件夹并递归发送，保留目录结构。
  Future<void> pickAndSendFolder() async {
    final folderPath = await FilePicker.platform.getDirectoryPath();
    if (folderPath == null || folderPath.isEmpty) return;
    await sendFolder(folderPath);
  }

  /// 递归展开 [folderPath]，按相对路径发送给已选中的可信设备。
  Future<void> sendFolder(String folderPath) async {
    final peer = await _currentSelectedPeer();
    if (peer == null || !peer.trusted) {
      status = languageCode == 'en'
          ? 'Select a trusted device before sending a folder'
          : '先选择一个已信任设备，再发送文件夹';
      notifyListeners();
      return;
    }
    final rootName = p.basename(folderPath);
    final entries = <({String absolute, String relative})>[];
    try {
      final stream = Directory(
        folderPath,
      ).list(recursive: true, followLinks: false);
      await for (final entity in stream) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: folderPath);
          // POSIX 化分隔符，保证跨平台一致（接收端按 / 拆分）。
          final posixRel = p.join(rootName, rel).replaceAll(r'\', '/');
          entries.add((absolute: entity.path, relative: posixRel));
        }
      }
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en'
          ? 'Failed to read folder $rootName'
          : '读取文件夹 $rootName 失败';
      notifyListeners();
      return;
    }
    if (entries.isEmpty) {
      status = languageCode == 'en'
          ? 'Folder $rootName is empty'
          : '文件夹 $rootName 为空';
      notifyListeners();
      return;
    }
    entries.sort((a, b) => a.relative.compareTo(b.relative));
    try {
      await transportService.sendFolder(peer, rootName, entries);
      await refresh();
      status = languageCode == 'en'
          ? 'Folder $rootName queued for ${titleFor(peer)}'
          : '已将文件夹 $rootName 加入发给 ${titleFor(peer)} 的传输队列';
    } catch (error) {
      lastError = '$error';
      status = error is AppFailure
          ? error.userMessage
          : (languageCode == 'en'
                ? '${titleFor(peer)} disconnected, folder transfer failed'
                : '${titleFor(peer)} 连接断开，文件夹发送失败');
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendFiles(List<String> paths) async {
    final peer = await _currentSelectedPeer();
    if (peer == null || !peer.trusted || paths.isEmpty) {
      pendingSharedFiles = paths;
      status = languageCode == 'en'
          ? 'Select a trusted device before sending ${paths.length} files'
          : '先选择一个已信任设备，再发送 ${paths.length} 个文件';
      notifyListeners();
      return;
    }
    try {
      await transportService.sendFiles(peer, paths);
      await refresh();
      status = languageCode == 'en'
          ? '${paths.length} file(s) queued for ${titleFor(peer)}'
          : '已将 ${paths.length} 个文件加入发给 ${titleFor(peer)} 的传输队列';
    } catch (error) {
      lastError = '$error';
      status = error is AppFailure
          ? error.userMessage
          : (languageCode == 'en'
                ? '${titleFor(peer)} disconnected, file transfer failed'
                : '${titleFor(peer)} 连接断开，文件发送失败');
    } finally {
      notifyListeners();
    }
  }

  Future<bool> pasteAndSendClipboardFiles() async {
    final paths = await clipboardImportService.readFilePaths();
    if (paths.isEmpty) return false;
    status = languageCode == 'en'
        ? 'Read ${paths.length} files from clipboard, sending...'
        : '从剪贴板读取到 ${paths.length} 个文件，正在发送...';
    notifyListeners();
    await queueFilesForSending(paths);
    return true;
  }

  Future<void> openPath(String? path) async {
    if (path == null || path.isEmpty) return;
    await OpenFilex.open(path);
  }

  /// 打开消息中的链接：Windows 用默认浏览器，其他平台用 OpenFilex。
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    if (Platform.isWindows) {
      try {
        // 不经过 cmd.exe，避免消息中的 &、| 等字符被解释为 shell 命令。
        await Process.start('explorer.exe', [url]);
        return;
      } catch (_) {}
    }
    await OpenFilex.open(url);
  }

  Future<void> openFolder(String? path) async {
    if (path == null || path.isEmpty) return;
    final folder = FileSystemEntity.isDirectorySync(path)
        ? path
        : p.dirname(path);
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [folder]);
    } else {
      await OpenFilex.open(folder);
    }
  }

  Future<List<String>> loadLocalNetworkEndpoints() async {
    final port = localListenPort;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final endpoints = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
            continue;
          }
          final ip = address.address.trim();
          if (ip.isEmpty) continue;
          endpoints.add(port > 0 ? '$ip:$port' : ip);
        }
      }
      return endpoints.toList()..sort();
    } on SocketException {
      return const [];
    }
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (message.direction != 'out' || message.status != 'failed') return;
    final peer = await db.getDevice(message.peerDeviceId);
    if (peer == null || !peer.trusted) {
      status = languageCode == 'en'
          ? 'The peer is no longer trusted'
          : '对方设备已不在信任列表中';
      notifyListeners();
      return;
    }
    _beginOperation('retry:${message.id}');
    lastError = null;
    status = languageCode == 'en' ? 'Retrying...' : '正在重试发送…';
    notifyListeners();
    try {
      if (message.kind == 'file') {
        final transferId = message.transferId;
        if (transferId == null) throw StateError('Transfer record is missing');
        final cached = transfersById[transferId];
        final transfer =
            cached ?? (await db.listTransfersByIds([transferId])).firstOrNull;
        if (transfer == null) throw StateError('Transfer record is missing');
        await transportService.retryFile(peer, message, transfer);
      } else {
        await transportService.retryText(peer, message);
      }
      status = languageCode == 'en' ? 'Retry succeeded' : '重新发送成功';
    } catch (error) {
      lastError = '$error';
      status = error is AppFailure
          ? error.userMessage
          : (languageCode == 'en' ? 'Retry failed' : '重新发送失败');
    } finally {
      await refresh();
      _endOperation('retry:${message.id}');
      notifyListeners();
    }
  }

  Future<void> saveMessageFile(ChatMessage message) async {
    final path = message.filePath;
    final transferId = message.transferId;
    if (path == null || path.isEmpty || transferId == null) return;
    _beginOperation('save:$transferId');
    notifyListeners();
    try {
      final peer = await db.getDevice(message.peerDeviceId);
      final transfers = await db.listTransfersByIds([transferId]);
      final transfer = transfers.isEmpty ? null : transfers.first;
      final saved = await fileStore.saveToDownloads(
        sourcePath: path,
        fileName: message.fileName ?? p.basename(path),
        mimeType: message.mimeType,
        conversationFolder: FileStore.conversationFolder(
          peer?.displayName ?? message.peerDeviceId,
          message.peerDeviceId,
        ),
        at: transfer?.createdAt ?? DateTime.now(),
        relativePath: message.relativePath ?? transfer?.relativePath,
      );
      await db.markTransferSaved(
        transferId: transferId,
        savedPath: saved.path,
        savedUri: saved.uri,
        fileName: saved.actualFileName,
        localFilePath: null,
      );
      status = languageCode == 'en'
          ? 'Saved to ${saved.path ?? saved.uri ?? 'Downloads/LocalChat'}'
          : '已保存到 ${saved.path ?? saved.uri ?? 'Downloads/LocalChat'}';
      await refresh();
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en' ? 'Save failed' : '保存失败';
    } finally {
      _endOperation('save:$transferId');
      notifyListeners();
    }
  }

  bool canRenameMessageFile(ChatMessage message, Transfer? transfer) {
    return message.direction == 'in' &&
        message.transferId == transfer?.id &&
        transfer != null &&
        canRenameTransfer(transfer);
  }

  bool canRenameTransfer(Transfer transfer) {
    return transfer.direction == 'in' &&
        transfer.status == 'received' &&
        transfer.savedPath != null;
  }

  Future<bool> renameMessageFile(
    ChatMessage message,
    Transfer transfer,
    String newFileName,
  ) async {
    if (message.direction != 'in' || message.transferId != transfer.id) {
      return false;
    }
    return renameTransferFile(transfer, newFileName);
  }

  Future<bool> renameTransferFile(Transfer transfer, String newFileName) async {
    final transferId = transfer.id;
    final savedPath = transfer.savedPath;
    if (!canRenameTransfer(transfer) || savedPath == null) return false;
    final validation = FileStore.validateFileName(newFileName);
    if (validation != null) {
      lastError = 'invalid_file_name:$validation';
      status = languageCode == 'en'
          ? 'Invalid file name'
          : '文件名无效，请检查非法字符、保留名或末尾空格';
      notifyListeners();
      return false;
    }
    if (newFileName.trim() == transfer.fileName) return true;
    _beginOperation('rename:$transferId');
    notifyListeners();
    try {
      final peer = await db.getDevice(transfer.peerDeviceId);
      final renamed = await fileStore.renameSavedFile(
        currentPath: savedPath,
        currentUri: transfer.savedUri,
        newFileName: newFileName,
        conversationFolder: FileStore.conversationFolder(
          peer?.displayName ?? transfer.peerDeviceId,
          transfer.peerDeviceId,
        ),
        at: transfer.createdAt,
        relativePath: transfer.relativePath,
      );
      await db.renameReceivedTransfer(
        transferId: transferId,
        fileName: renamed.fileName,
        mimeType: renamed.mimeType,
        savedPath: renamed.path,
        savedUri: renamed.uri,
        relativePath: renamed.relativePath,
      );
      status = languageCode == 'en'
          ? 'File renamed to ${renamed.fileName}'
          : '文件已重命名为 ${renamed.fileName}';
      await refresh();
      return true;
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en' ? 'Rename failed' : '文件重命名失败';
      return false;
    } finally {
      _endOperation('rename:$transferId');
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    await fileStore.clearManagedEditedFiles();
    await fileStore.clearIncomingFiles();
    await db.clearHistory();
    messages = [];
    conversations = [];
    selectedDevice = null;
    selectedConversation = null;
    transfersById = {};
    status = languageCode == 'en' ? 'Chat history cleared' : '聊天记录已清空';
    await refresh();
  }

  Future<void> clearTransferIndex() async {
    await db.clearTransferIndex();
    status = languageCode == 'en'
        ? 'Received file index cleared. Files on disk are kept.'
        : '接收文件索引已清空，磁盘上的文件不会被删除';
    notifyListeners();
  }

  /// 构建传输中心所需的任务视图（合并 DB 进度与内存实时速度）。
  Future<List<TransferTaskView>> buildTransferTaskViews() =>
      transportService.buildTransferTaskViews();

  /// 构建传输中心所需的分组视图（按 groupId 聚合）。
  Future<List<TransferGroupView>> buildTransferGroupViews() =>
      transportService.buildTransferGroupViews();

  /// 取消一个出站传输。优先本地取消（排队或活动任务）；若该任务已发送到对端且
  /// 对端支持取消能力，则同时请求对端中断接收。返回是否成功取消。
  Future<bool> cancelTransfer(Transfer transfer) async {
    final wasActive = transportService.isOutboundActive(transfer.id);
    if (wasActive) {
      final peer = await db.getDevice(transfer.peerDeviceId);
      if (peer != null && transportService.deviceSupportsCancel(peer)) {
        // 先让接收端关闭并清理临时文件，再中止本地发送流。
        await transportService.requestRemoteCancel(peer, transfer.id);
      }
    }
    final localCanceled = await transportService.cancelOutbound(transfer.id);
    if (localCanceled) {
      status = languageCode == 'en' ? 'Transfer canceled' : '已取消传输';
      notifyListeners();
      return true;
    }
    // 非本地出站任务（如已发送中）：尝试请求对端取消。
    final peer = await db.getDevice(transfer.peerDeviceId);
    if (peer == null) return false;
    if (!transportService.deviceSupportsCancel(peer)) {
      status = languageCode == 'en'
          ? 'The peer does not support canceling transfers'
          : '对端版本不支持取消传输';
      notifyListeners();
      return false;
    }
    final ok = await transportService.requestRemoteCancel(peer, transfer.id);
    status = ok
        ? (languageCode == 'en' ? 'Transfer canceled' : '已取消传输')
        : (languageCode == 'en' ? 'Transfer could not be canceled' : '无法取消该传输');
    notifyListeners();
    return ok;
  }

  /// 取消整组出站传输（文件夹或批量附件）。
  Future<int> cancelTransferGroup(String groupId) async {
    final activeTransferId = transportService.activeOutboundTransferIdForGroup(
      groupId,
    );
    if (activeTransferId != null) {
      final transfers = await db.listTransfersByIds([activeTransferId]);
      final active = transfers.firstOrNull;
      if (active != null) {
        final peer = await db.getDevice(active.peerDeviceId);
        if (peer != null && transportService.deviceSupportsCancel(peer)) {
          await transportService.requestRemoteCancel(peer, active.id);
        }
      }
    }
    final count = await transportService.cancelOutboundGroup(groupId);
    status = languageCode == 'en'
        ? 'Canceled $count transfer(s)'
        : '已取消 $count 个传输';
    notifyListeners();
    return count;
  }

  /// 判断对端是否支持主动取消传输（供 UI 决定是否显示取消按钮）。
  bool peerSupportsCancel(Device peer) =>
      transportService.deviceSupportsCancel(peer);

  Future<void> _loadSharingIntents() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    await _acceptSharedMedia(initial);
    await ReceiveSharingIntent.instance.reset();
    _sharingSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _acceptSharedMedia,
    );
  }

  Future<void> _acceptSharedMedia(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final sharedFiles = <String>[];
    final sharedText = <String>[];
    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        sharedText.add(file.path);
      } else {
        sharedFiles.add(file.path);
      }
    }
    pendingSharedFiles = sharedFiles;
    pendingSharedText = sharedText.isEmpty ? null : sharedText.join('\n');
    status = languageCode == 'en'
        ? 'Received system share: ${sharedFiles.length} files${pendingSharedText == null ? '' : ' and text'}'
        : '收到系统分享：${sharedFiles.length} 个文件${pendingSharedText == null ? '' : ' 和文本'}';
    notifyListeners();
    await _flushPendingShareIfPossible();
  }

  Future<void> _flushPendingShareIfPossible() async {
    final peer = await _currentSelectedPeer();
    if (peer == null || !peer.trusted) return;
    final text = pendingSharedText;
    final files = List<String>.from(pendingSharedFiles);
    pendingSharedText = null;
    pendingSharedFiles = [];
    if (text != null && text.trim().isNotEmpty) {
      await sendText(text);
    }
    if (files.isNotEmpty) {
      await queueFilesForSending(files);
    }
  }

  Future<Device?> _currentSelectedPeer() async {
    final peer = selectedDevice;
    if (peer == null) return null;
    selectedDevice = await db.getDevice(peer.id) ?? peer;
    return selectedDevice;
  }

  void _sortDevices() {
    devices.sort((a, b) {
      if (a.trusted != b.trusted) {
        return a.trusted ? -1 : 1;
      }
      final titleCompare = titleFor(
        a,
      ).toLowerCase().compareTo(titleFor(b).toLowerCase());
      if (titleCompare != 0) return titleCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  void _scheduleRefresh() {
    if (_refreshTimer?.isActive == true) {
      _refreshQueued = true;
      return;
    }
    _refreshTimer = Timer(_refreshCoalesceDelay, () {
      _runScheduledRefresh();
    });
  }

  Future<void> _runScheduledRefresh() async {
    try {
      await refresh();
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en' ? 'Refresh failed' : '刷新失败';
      notifyListeners();
    }
  }

  Future<Device?> _waitForReconnectedPeer(String deviceId) async {
    final selectedTitle =
        selectedDevice?.id == deviceId && selectedDevice != null
        ? titleFor(selectedDevice!)
        : (languageCode == 'en' ? 'Device' : '设备');
    status = languageCode == 'en'
        ? '$selectedTitle disconnected, reconnecting...'
        : '$selectedTitle 连接断开，正在自动重连...';
    lastError = null;
    notifyListeners();
    final existing = await db.getDevice(deviceId);
    // 手动添加的跨网段设备：直接用存储的 host:port 探测，不依赖 UDP 广播。
    if (existing != null &&
        existing.host != null &&
        existing.port != null &&
        existing.endpointSource == 'manual') {
      final ok = await transportService.checkPeer(existing);
      if (ok) {
        status = languageCode == 'en'
            ? '$selectedTitle reconnected'
            : '$selectedTitle 已重新连接';
        notifyListeners();
        return existing;
      }
    }
    await discoveryService.announce();
    if (existing != null &&
        existing.host != null &&
        existing.port != null &&
        existing.lastSeen != null) {
      status = languageCode == 'en'
          ? '$selectedTitle reconnected'
          : '$selectedTitle 已重新连接';
      notifyListeners();
      return existing;
    }
    try {
      final peer = await discoveryService.peers
          .where((peer) => peer.deviceId == deviceId)
          .timeout(const Duration(seconds: 12))
          .first;
      final device = await db.getDevice(peer.deviceId);
      final title = device == null ? selectedTitle : titleFor(device);
      status = languageCode == 'en' ? '$title reconnected' : '$title 已重新连接';
      notifyListeners();
      return device;
    } on TimeoutException {
      status = languageCode == 'en'
          ? '$selectedTitle is offline, waiting to come back'
          : '$selectedTitle 离线，等待重新上线';
      notifyListeners();
      return null;
    }
  }

  Future<void> _refreshPeerPresence() async {
    if (_refreshingPresence) return;
    _refreshingPresence = true;
    try {
      final peers = await db.listTrustedDevices();
      for (final peer in peers) {
        await transportService.checkPeer(peer);
      }
      await refresh();
    } finally {
      _refreshingPresence = false;
    }
  }

  @override
  void dispose() {
    _transportSub?.cancel();
    _notificationSub?.cancel();
    _notificationEventSub?.cancel();
    _discoverySub?.cancel();
    _pairRequestSub?.cancel();
    _notificationTapSub?.cancel();
    _sharingSub?.cancel();
    for (final timer in _pairRequestTimers.values) {
      timer.cancel();
    }
    _pairRequestTimers.clear();
    _presenceTimer?.cancel();
    _refreshTimer?.cancel();
    unawaited(keepAliveService.stop());
    discoveryService.stop();
    transportService.stop();
    notificationService.dispose();
    db.close();
    super.dispose();
  }
}
