import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/protocol.dart';
import '../services/discovery_service.dart';
import '../services/file_store.dart';
import '../services/identity_service.dart';
import '../services/security_service.dart';
import '../services/transport_service.dart';

class AppController extends ChangeNotifier {
  AppController() : db = AppDatabase(), fileStore = FileStore() {
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
  late final IdentityService identityService;
  late final SecurityService securityService;
  late final TransportService transportService;
  late final DiscoveryService discoveryService;

  LocalIdentity? identity;
  List<Device> devices = [];
  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  Device? selectedDevice;
  Conversation? selectedConversation;
  bool initialized = false;
  bool busy = false;
  String status = '正在启动 LocalChat...';
  String? lastError;
  List<String> pendingSharedFiles = [];
  String? pendingSharedText;

  StreamSubscription<void>? _transportSub;
  StreamSubscription<DiscoveredPeer>? _discoverySub;
  StreamSubscription<List<SharedMediaFile>>? _sharingSub;
  Timer? _presenceTimer;

  Future<void> initialize() async {
    busy = true;
    notifyListeners();
    try {
      identity = await identityService.load();
      transportService.reconnectPeer = _waitForReconnectedPeer;
      final port = await transportService.start();
      await discoveryService.start(listenPort: port);
      _transportSub = transportService.updates.listen((_) => refresh());
      _discoverySub = discoveryService.peers.listen((_) => refresh());
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => notifyListeners(),
      );
      await _loadSharingIntents();
      await refresh();
      status = '正在局域网内发现设备，本机端口 $port';
      initialized = true;
    } catch (error) {
      lastError = '$error';
      status = '启动失败';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    devices = await db.listDevices();
    conversations = await db.listConversations();
    if (selectedDevice != null) {
      selectedDevice =
          devices
              .where((device) => device.id == selectedDevice!.id)
              .firstOrNull ??
          selectedDevice;
      selectedConversation = await db.ensureConversation(selectedDevice!);
      messages = await db.listMessages(selectedConversation!.id);
    }
    notifyListeners();
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
    status = '会话已重命名为 $trimmed';
    await refresh();
  }

  Future<void> pair(Device device) async {
    final code = randomCode();
    status = '正在用配对码 $code 连接 ${device.displayName}';
    busy = true;
    notifyListeners();
    try {
      await transportService.pairWith(device, code);
      await refresh();
      status = '已信任 ${device.displayName}，之后可以像聊天一样直接发送';
    } catch (error) {
      lastError = '$error';
      status = '配对失败';
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
      status = '${titleFor(peer)} 已发送';
    } catch (error) {
      lastError = '$error';
      status = '${titleFor(peer)} 连接断开，消息发送失败';
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
      status = '先选择一个已信任设备，再发送 ${paths.length} 个文件';
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      await transportService.sendFiles(peer, paths);
      await refresh();
      status = '${titleFor(peer)} 文件发送完成';
    } catch (error) {
      lastError = '$error';
      status = '${titleFor(peer)} 连接断开，文件发送失败';
    } finally {
      busy = false;
      notifyListeners();
    }
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

  Future<void> clearHistory() async {
    await db.clearHistory();
    messages = [];
    conversations = [];
    status = '聊天记录已清空';
    notifyListeners();
  }

  Future<void> clearTransferIndex() async {
    await db.clearTransferIndex();
    status = '接收文件索引已清空，磁盘上的文件不会被删除';
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
    status =
        '收到系统分享：${sharedFiles.length} 个文件${pendingSharedText == null ? '' : ' 和文本'}';
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

  Future<Device?> _waitForReconnectedPeer(String deviceId) async {
    final selectedTitle =
        selectedDevice?.id == deviceId && selectedDevice != null
        ? titleFor(selectedDevice!)
        : '设备';
    status = '$selectedTitle 连接断开，正在自动重连...';
    lastError = null;
    notifyListeners();
    await discoveryService.announce();
    final existing = await db.getDevice(deviceId);
    if (existing != null &&
        existing.host != null &&
        existing.port != null &&
        existing.lastSeen != null) {
      status = '$selectedTitle 已重新连接';
      notifyListeners();
      return existing;
    }
    try {
      final peer = await discoveryService.peers
          .where((peer) => peer.deviceId == deviceId)
          .timeout(const Duration(seconds: 12))
          .first;
      final device = await db.getDevice(peer.deviceId);
      status = '${device == null ? selectedTitle : titleFor(device)} 已重新连接';
      notifyListeners();
      return device;
    } on TimeoutException {
      status = '$selectedTitle 离线，等待重新上线';
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    _transportSub?.cancel();
    _discoverySub?.cancel();
    _sharingSub?.cancel();
    _presenceTimer?.cancel();
    discoveryService.stop();
    transportService.stop();
    db.close();
    super.dispose();
  }
}
