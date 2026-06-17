import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/app_text.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/protocol.dart';
import '../services/clipboard_import_service.dart';
import '../services/discovery_service.dart';
import '../services/file_store.dart';
import '../services/identity_service.dart';
import '../services/security_service.dart';
import '../services/transport_service.dart';

const _autoCopyReceivedTextKey = 'auto_copy_received_text';
const _languageCodeKey = 'language_code';
const _staleDiscoveredDeviceAge = Duration(seconds: 20);
const _refreshCoalesceDelay = Duration(milliseconds: 200);

class AppController extends ChangeNotifier {
  AppController()
    : db = AppDatabase(),
      fileStore = FileStore(),
      clipboardImportService = ClipboardImportService() {
    identityService = IdentityService(db);
    securityService = SecurityService(identityService);
    transportService = TransportService(
      db,
      identityService,
      securityService,
      fileStore,
    );
    discoveryService = DiscoveryService(db, identityService);
  }

  final AppDatabase db;
  final FileStore fileStore;
  final ClipboardImportService clipboardImportService;
  late final IdentityService identityService;
  late final SecurityService securityService;
  late final TransportService transportService;
  late final DiscoveryService discoveryService;

  LocalIdentity? identity;
  List<Device> devices = [];
  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  Map<String, Transfer> transfersById = {};
  Device? selectedDevice;
  Conversation? selectedConversation;
  PendingPairRequest? pendingPairRequest;
  bool initialized = false;
  bool busy = false;
  bool autoCopyReceivedText = true;
  String languageCode = 'zh';
  String status = '正在启动 LocalChat...';
  String? lastError;
  String? notificationText;
  int notificationSerial = 0;
  List<String> pendingSharedFiles = [];
  String? pendingSharedText;

  StreamSubscription<void>? _transportSub;
  StreamSubscription<String>? _notificationSub;
  StreamSubscription<DiscoveredPeer>? _discoverySub;
  StreamSubscription<PendingPairRequest>? _pairRequestSub;
  StreamSubscription<List<SharedMediaFile>>? _sharingSub;
  Timer? _presenceTimer;
  Timer? _refreshTimer;
  bool _refreshingPresence = false;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  AppText get text => AppText(languageCode);

  Future<void> initialize() async {
    busy = true;
    notifyListeners();
    try {
      identity = await identityService.load();
      languageCode = await db.getSetting(_languageCodeKey) ?? 'zh';
      autoCopyReceivedText =
          await db.getSetting(_autoCopyReceivedTextKey) != 'false';
      transportService.autoCopyReceivedText = autoCopyReceivedText;
      transportService.languageCode = languageCode;
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
      _discoverySub = discoveryService.peers.listen((_) => _scheduleRefresh());
      _pairRequestSub = transportService.pairRequests.listen((request) {
        pendingPairRequest = request;
        status = languageCode == 'en'
            ? '${request.displayName} requests pairing. Confirm code ${request.code}.'
            : '${request.displayName} 请求配对，请确认 6 位校验码 ${request.code}';
        notifyListeners();
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
        messages = await db.listMessages(selectedConversation!.id);
        final transferIds = messages
            .map((message) => message.transferId)
            .whereType<String>();
        final transfers = await db.listTransfersByIds(transferIds);
        transfersById = {
          for (final transfer in transfers) transfer.id: transfer,
        };
      }
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
    messages = await db.listMessages(selectedConversation!.id);
    notifyListeners();
    await _flushPendingShareIfPossible();
  }

  void closeConversation() {
    selectedDevice = null;
    selectedConversation = null;
    messages = [];
    transfersById = {};
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
    await db.deletePeerSession(peer.id);
    selectedConversation = null;
    selectedDevice = null;
    messages = [];
    transfersById = {};
    status = languageCode == 'en' ? 'Deleted chat $title' : '已删除会话 $title';
    await refresh();
  }

  Future<void> setLanguageCode(String value) async {
    if (value != 'zh' && value != 'en') return;
    languageCode = value;
    transportService.languageCode = value;
    await db.setSetting(_languageCodeKey, value);
    status = value == 'en' ? 'Language set to English' : '语言已切换为中文';
    notifyListeners();
  }

  Future<void> setAutoCopyReceivedText(bool value) async {
    autoCopyReceivedText = value;
    transportService.autoCopyReceivedText = value;
    await db.setSetting(_autoCopyReceivedTextKey, value ? 'true' : 'false');
    status = value
        ? (languageCode == 'en'
              ? 'Auto-copy received text enabled'
              : '已开启自动复制收到的文字')
        : (languageCode == 'en'
              ? 'Auto-copy received text disabled'
              : '已关闭自动复制收到的文字');
    notifyListeners();
  }

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
    transportService.approvePairRequest(request.id);
    pendingPairRequest = null;
    status = languageCode == 'en'
        ? 'Allowed pairing with ${request.displayName}'
        : '已允许 ${request.displayName} 配对';
    await refresh();
  }

  Future<void> rejectPendingPair() async {
    final request = pendingPairRequest;
    if (request == null) return;
    transportService.rejectPairRequest(request.id);
    pendingPairRequest = null;
    status = languageCode == 'en'
        ? 'Rejected pairing with ${request.displayName}'
        : '已拒绝 ${request.displayName} 配对';
    notifyListeners();
  }

  Future<void> pair(Device device) async {
    final code = randomCode();
    status = languageCode == 'en'
        ? 'Connecting to ${device.displayName} with code $code'
        : '正在用配对码 $code 连接 ${device.displayName}';
    busy = true;
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
      busy = false;
      notifyListeners();
    }
  }

  Future<void> sendText(String text) async {
    final peer = await _currentSelectedPeer();
    if (peer == null || !peer.trusted || text.trim().isEmpty) return;
    busy = true;
    notifyListeners();
    try {
      await transportService.sendText(peer, text.trim());
      await refresh();
      status = languageCode == 'en'
          ? 'Sent to ${titleFor(peer)}'
          : '${titleFor(peer)} 已发送';
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en'
          ? '${titleFor(peer)} disconnected, message failed'
          : '${titleFor(peer)} 连接断开，消息发送失败';
    } finally {
      busy = false;
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
    await sendFiles(paths);
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
    busy = true;
    notifyListeners();
    try {
      await transportService.sendFiles(peer, paths);
      await refresh();
      status = languageCode == 'en'
          ? 'Files sent to ${titleFor(peer)}'
          : '${titleFor(peer)} 文件发送完成';
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en'
          ? '${titleFor(peer)} disconnected, file transfer failed'
          : '${titleFor(peer)} 连接断开，文件发送失败';
    } finally {
      busy = false;
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
    await sendFiles(paths);
    return true;
  }

  Future<void> openPath(String? path) async {
    if (path == null || path.isEmpty) return;
    await OpenFilex.open(path);
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

  Future<void> saveMessageFile(ChatMessage message) async {
    final path = message.filePath;
    final transferId = message.transferId;
    if (path == null || path.isEmpty || transferId == null) return;
    busy = true;
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
      );
      await db.markTransferSaved(
        transferId: transferId,
        savedPath: saved.path,
        savedUri: saved.uri,
      );
      status = languageCode == 'en'
          ? 'Saved to ${saved.path ?? saved.uri ?? 'Downloads/LocalChat'}'
          : '已保存到 ${saved.path ?? saved.uri ?? 'Downloads/LocalChat'}';
      await refresh();
    } catch (error) {
      lastError = '$error';
      status = languageCode == 'en' ? 'Save failed' : '保存失败';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
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
      await sendFiles(files);
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
    await discoveryService.announce();
    final existing = await db.getDevice(deviceId);
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
    _discoverySub?.cancel();
    _pairRequestSub?.cancel();
    _sharingSub?.cancel();
    _presenceTimer?.cancel();
    _refreshTimer?.cancel();
    discoveryService.stop();
    transportService.stop();
    db.close();
    super.dispose();
  }
}
