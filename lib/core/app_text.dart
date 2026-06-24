import '../data/app_database.dart';
import '../models/network_diagnostic.dart';
import 'peer_status.dart';

class AppText {
  const AppText(this.languageCode);

  final String languageCode;

  bool get en => languageCode == 'en';
  String get retry => en ? 'Retry' : '重试';

  String get appTitle => 'LocalChat';
  String get rescan => en ? 'Rescan' : '重新搜索';
  String get settings => en ? 'Settings' : '设置';
  String get trustedDevices => en ? 'Trusted devices' : '已信任设备';
  String get trustedDevicesOnline => en ? 'Trusted devices · Online' : '已信任设备 · 在线';
  String get trustedDevicesOffline => en ? 'Trusted devices · Offline' : '已信任设备 · 离线';
  String get noOnlineDevices => en ? 'No online devices' : '暂无在线设备';
  String get discoveredDevices => en ? 'Discovered devices' : '发现的设备';
  String get noTrustedDevices => en
      ? 'No trusted devices yet. Open LocalChat on another device on the same Wi-Fi.'
      : '还没有已信任设备。让手机/电脑打开 LocalChat 并处在同一 Wi-Fi。';
  String get listeningLan =>
      en ? 'Listening for LAN broadcasts...' : '正在监听局域网广播...';
  String get identityStarting => en ? 'Initializing identity' : '身份初始化中';
  String get notConnected => en ? 'Not connected' : '未连接';
  String get pair => en ? 'Pair' : '配对';
  String get selectDevice =>
      en ? 'Select a device to start chatting' : '选择一个设备开始聊天式传输';
  String get sayOrDropFile =>
      en ? 'Send a message, or drop files here.' : '发一句话，或把文件拖进来。';
  String get pairFirst => en ? 'Pair this device first.' : '先完成首次配对。';
  String get releaseToSend => en ? 'Release to send files' : '松开鼠标即可发送文件';
  String get renameConversation => en ? 'Rename chat' : '重命名会话';
  String get deleteConversation => en ? 'Delete chat' : '删除会话';
  String get firstPair => en ? 'Pair device' : '首次配对';
  String get conversationName => en ? 'Chat name' : '会话名称';
  String get cancel => en ? 'Cancel' : '取消';
  String get save => en ? 'Save' : '保存';
  String get delete => en ? 'Delete' : '删除';
  String get done => en ? 'Done' : '完成';
  String get deleteConversationTitle => en ? 'Delete chat?' : '删除会话？';
  String get deleteFileConfirmTitle => en ? 'Delete File Message' : '删除文件消息确认';
  String get deleteRecordOnly => en ? 'Only delete record' : '仅删除记录';
  String get deleteFileAndRecord => en ? 'Delete local file & record' : '删除本地文件与记录';
  String get localFileNotExist => en ? 'Local file not saved or does not exist.' : '本地文件未保存或不存在';
  String get localFilePath => en ? 'Local file path: ' : '本地文件路径：';
  String get deleteFileMessageConfirmBody => en
      ? 'Are you sure you want to delete this file message?'
      : '确定要删除此文件消息吗？';
  String deleteConversationBody(String title) => en
      ? 'This will delete chat history, transfer indexes, connection info, and trust for "$title". Files on disk will not be deleted.'
      : '将删除“$title”的聊天记录、传输索引、连接信息和信任关系，磁盘上的文件不会被删除。';
  String get localNickname => en ? 'Local nickname' : '本机昵称';
  String get editLocalNickname => en ? 'Edit local nickname' : '修改本机昵称';
  String get localNetworkEndpoints => en ? 'Local IP / port' : '本机 IP / 端口';
  String get loadingLocalNetworkEndpoints =>
      en ? 'Detecting local network addresses...' : '正在检测本机局域网地址...';
  String localNetworkEndpointsEmpty(int port) => en
      ? 'No LAN IPv4 address detected. Listening port: ${port > 0 ? port : '-'}'
      : '未发现可用局域网 IPv4。监听端口：${port > 0 ? port : '-'}';
  String get deviceNameVisible =>
      en ? 'Device name visible to others' : '别人看到的设备名称';
  String get language => en ? 'Language' : '语言';
  String get appearance => en ? 'Appearance' : '外观模式';
  String get themeSystem => en ? 'System' : '跟随系统';
  String get themeLight => en ? 'Light' : '浅色';
  String get themeDark => en ? 'Dark' : '深色';
  String get chinese => '中文';
  String get english => 'English';
  String get autoCopyReceivedText =>
      en ? 'Auto-copy received text' : '自动复制收到的文字';
  String get autoCopyReceivedTextSubtitle => en
      ? 'Copy received text or links to the system clipboard'
      : '收到文字或链接时自动复制到系统剪贴板';
  String get systemNotifications => en ? 'System notifications' : '系统消息通知';
  String get systemNotificationsSubtitle => en
      ? 'Show Windows/Android notifications when LocalChat is in the background'
      : 'LocalChat 在后台、最小化或托盘运行时显示系统通知';
  String get notificationPreview =>
      en ? 'Show notification content preview' : '通知显示内容预览';
  String get notificationPreviewSubtitle => en
      ? 'Off by default: notifications only show sender and message type'
      : '默认关闭：通知只显示发送者和消息/文件类型，避免锁屏泄露内容';
  String get keepAliveConnection =>
      en ? 'Keep background connection alive' : '后台保持连接';
  String get keepAliveConnectionSubtitle => en
      ? 'Android only: keep LAN listening and discovery running with a persistent notification. Turning it off reduces background reliability.'
      : '仅 Android：通过常驻通知保持局域网监听和发现。关闭后后台收消息可靠性会下降。';
  String get clearHistory => en ? 'Clear chat history' : '清空聊天记录';
  String get clearHistorySubtitle => en
      ? 'Delete all chats and messages. Files on disk are kept.'
      : '删除所有会话和消息，不删除磁盘文件';
  String get clearTransfers => en ? 'Clear received file index' : '清空接收文件索引';
  String get clearTransfersSubtitle =>
      en ? 'Clear records only. Files on disk are kept.' : '只清理记录，不删除磁盘文件';
  String get clear => en ? 'Clear' : '清空';
  String get allowPairTitle => en ? 'Allow pairing?' : '允许设备配对？';
  String get reject => en ? 'Reject' : '拒绝';
  String get allow => en ? 'Allow' : '允许';
  String get verificationCode => en ? 'Code' : '校验码';
  String get fingerprint => en ? 'Fingerprint' : '指纹';
  String get securePairRequest => en ? 'Secure pairing request' : '安全配对请求';
  String get firstConnectionConfirmCode => en
      ? 'First connection. Confirm the 6-digit security code:'
      : '首次连接，请确认 6 位安全校验码：';
  String get trustedChannelEstablished =>
      en ? 'Trusted encrypted channel established' : '已建立可信安全加密通道';
  String get pairRequestRejected => en ? 'Pairing request rejected' : '已拒绝配对请求';
  String get pairRequestExpired => en ? 'Pairing request expired' : '配对请求已超时';
  String get pairRequestPending =>
      en ? 'Pending secure pairing confirmation' : '等待确认安全配对';
  String pairRequestNotificationBody(String name) => en
      ? '$name requests secure pairing. Open LocalChat to confirm the code.'
      : '$name 请求安全配对，打开 LocalChat 确认校验码。';
  String get notificationNewMessage => en ? 'New LocalChat message' : '收到一条新消息';
  String get notificationNewFile => en ? 'New LocalChat file' : '收到一个文件';
  String get chooseFile => en ? 'Choose files' : '选择文件';
  String get pasteFileOrImage => en ? 'Paste file or image' : '粘贴文件或图片';
  String get inputHint =>
      en ? 'Message, link, or paste files/images...' : '输入消息，或粘贴文件/图片...';
  String get pairBeforeSend => en ? 'Pair before sending' : '先配对后发送';
  String get me => en ? 'Me' : '我';
  String get peer => en ? 'Peer' : '对方';
  String get file => en ? 'File' : '文件';
  String get savedLocal => en ? 'Saved locally' : '已保存到本地';
  String get open => en ? 'Open' : '打开';
  String get openFolder => en ? 'Open folder' : '打开文件夹';
  String get saveLocal => en ? 'Save locally' : '保存到本地';
  String get imageNotSupported => en ? 'Image not supported' : '图片不可预览';
  String get attachmentPreview => en ? 'Review attachments' : '预览附件';
  String get editImage => en ? 'Edit image' : '编辑图片';
  String get edited => en ? 'Edited' : '已编辑';
  String get animatedImageOriginalOnly => en
      ? 'Animated or unsupported images are sent unchanged'
      : '动图或不支持的图片将原样发送';
  String confirmSend(int count) => en ? 'Send $count items' : '发送 $count 个附件';
  String get renameFile => en ? 'Rename file' : '重命名文件';
  String get fileName => en ? 'File name' : '文件名';
  String get invalidFileName => en
      ? 'Use a valid file name without reserved characters or trailing spaces.'
      : '请输入有效文件名，不能包含非法字符、保留名或末尾空格。';
  String get chooseFolder => en ? 'Choose folder' : '选择文件夹';
  String get minimizeToTray => en ? 'Minimize to tray' : '最小化到托盘';
  String get minimizeToTraySubtitle =>
      en ? 'Keep running in background when window closes' : '关闭窗口时保持后台运行';
  String get startOnBoot => en ? 'Start on boot' : '开机自启';
  String get startOnBootSubtitle => en
      ? 'Launch LocalChat automatically when Windows starts'
      : 'Windows 启动时自动运行 LocalChat';
  String get addPeerManually => en ? 'Add remote peer' : '添加跨网段好友';
  String get addPeerManuallySubtitle => en
      ? 'Connect to a peer on another subnet by IP and port'
      : '通过 IP 和端口连接其他网段的设备';
  String get campusNetworkDiagnostic =>
      en ? 'Local network connection test' : '局域网连接测试';
  String get campusNetworkDiagnosticSubtitle => en
      ? 'Test whether a peer IP and port can reach LocalChat directly'
      : '测试对方 IP 和端口是否能直连 LocalChat，并给出排查建议';
  String get runNetworkDiagnostic => en ? 'Test connection' : '连接测试';
  String get testBeforeAddPeer => en ? 'Test first' : '先测试连接';
  String get networkDiagnosticResult => en ? 'Diagnostic result' : '诊断结果';
  String get networkDiagnosticAdvice => en ? 'Suggested checks' : '排查建议';
  String get networkDiagnosticLocalAddress =>
      en ? 'My visible addresses' : '本机可用地址';
  String get networkDiagnosticNoLocalAddress =>
      en ? 'No non-loopback IPv4 address was detected.' : '未检测到非本机回环的 IPv4 地址。';
  String get peerHost => en ? 'Peer IP / host' : '对方 IP / 主机';
  String get peerPort => en ? 'Port' : '端口';
  String get networkDiagnosticPortHelper => en
      ? "Use the port shown in the peer's LocalChat settings."
      : 'LocalChat 默认随机监听端口，请以对方设置页显示为准';
  String get add => en ? 'Add' : '添加';
  String get transferCenter => en ? 'Transfer center' : '传输中心';
  String get transferCenterSubtitle =>
      en ? 'Track and manage file transfers' : '查看和管理文件传输';
  String get transfersActive => en ? 'In progress' : '进行中';
  String get transfersCompleted => en ? 'Completed' : '已完成';
  String get transfersFailed => en ? 'Failed / canceled' : '失败 / 已取消';
  String get noTransfers => en ? 'No transfers yet.' : '还没有传输记录。';
  String get cancelTransfer => en ? 'Cancel transfer' : '取消传输';
  String get cancelGroup => en ? 'Cancel group' : '取消整组';
  String get retryTransfer => en ? 'Retry' : '重试';
  String transferEta(int seconds) =>
      en ? '~${seconds}s left' : '约 ${seconds}s 后完成';
  String transferSpeed(double bytesPerSecond) => en
      ? '${_formatBytes(bytesPerSecond)}/s'
      : '${_formatBytes(bytesPerSecond)}/秒';
  String get transferCanceledHint => en
      ? 'The peer version does not support canceling in-progress transfers.'
      : '对端版本不支持取消进行中的传输。';
  String get searchMessages => en ? 'Search messages' : '搜索消息';
  String get noResults => en ? 'No results' : '无结果';
  String searchResultLabel(int index, int total) =>
      en ? '$index / $total' : '$index / $total';
  String get close => en ? 'Close' : '关闭';
  String get filterConversations => en ? 'Filter conversations' : '过滤会话';
  String lastMessagePreview(String? body, String? fileName) {
    if (body != null && body.isNotEmpty) return body;
    if (fileName != null && fileName.isNotEmpty) return '[$fileName]';
    return '';
  }

  String _formatBytes(double bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[i]}';
  }

  String peerStatus(Device device, {DateTime? now}) {
    if (!device.trusted) return en ? 'Unpaired' : '未配对';
    return isPeerOnline(device, now: now)
        ? (en ? 'Online' : '在线')
        : (en ? 'Offline, waiting to reconnect' : '离线，等待重新上线');
  }

  String messageStatus(String status) {
    return switch (status) {
      'sending' => en ? 'Sending' : '发送中',
      'sent' => en ? 'Sent' : '已发送',
      'failed' => en ? 'Failed' : '发送失败',
      'receiving' => en ? 'Receiving' : '接收中',
      'received' => en ? 'Received' : '已接收',
      _ => status,
    };
  }

  String offlineBanner(String name) => en
      ? '$name is offline. Sending will wait for rediscovery and reconnect.'
      : '$name 当前离线。发送时会自动等待重新发现并重连。';

  String statusWithError(String status, String error) =>
      en ? '$status: $error' : '$status：$error';

  String networkDiagnosticSummary(NetworkDiagnosticResult result) {
    switch (result.status) {
      case NetworkDiagnosticStatus.reachable:
        final name = result.peer?.displayName ?? result.endpoint;
        return en
            ? 'Reachable: $name is a LocalChat device.'
            : '可连接：$name 是 LocalChat 设备。';
      case NetworkDiagnosticStatus.invalidInput:
        return en ? 'Invalid IP or port.' : 'IP 或端口无效。';
      case NetworkDiagnosticStatus.timeout:
        return en
            ? 'Timed out when connecting to ${result.endpoint}.'
            : '连接 ${result.endpoint} 超时。';
      case NetworkDiagnosticStatus.connectionRefused:
        return en
            ? '${result.endpoint} refused the connection.'
            : '${result.endpoint} 拒绝连接。';
      case NetworkDiagnosticStatus.networkUnreachable:
        return en
            ? '${result.endpoint} is unreachable from this network.'
            : '当前网络无法到达 ${result.endpoint}。';
      case NetworkDiagnosticStatus.nonLocalChat:
        return en
            ? '${result.endpoint} is reachable, but it is not LocalChat.'
            : '${result.endpoint} 可达，但不是 LocalChat 服务。';
      case NetworkDiagnosticStatus.identityMismatch:
        return en
            ? '${result.endpoint} replied, but identity validation failed.'
            : '${result.endpoint} 有响应，但身份校验失败。';
      case NetworkDiagnosticStatus.unknownError:
        return en ? 'Could not complete the connection test.' : '无法完成连接测试。';
    }
  }

  String networkDiagnosticAdviceFor(NetworkDiagnosticResult result) {
    switch (result.status) {
      case NetworkDiagnosticStatus.reachable:
        return en
            ? 'Direct TCP works. If auto-discovery still fails, the network is likely blocking UDP broadcast; add the peer manually with this IP and port.'
            : '直连 TCP 正常。如果仍然自动搜索不到，通常是 UDP 广播被跨网段/VLAN 拦截；直接用这个 IP 和端口手动添加即可。';
      case NetworkDiagnosticStatus.invalidInput:
        return en
            ? 'Enter the peer address shown in LocalChat settings, for example 172.30.72.176:40123.'
            : '请输入对方设置页显示的地址，例如 172.30.72.176:40123。';
      case NetworkDiagnosticStatus.timeout:
      case NetworkDiagnosticStatus.networkUnreachable:
        return en
            ? 'Common local network issue: devices may be on different subnets or AP/client isolation is enabled, blocking direct traffic. Try connecting both to the same phone/PC hotspot; if that works, the router or network provider is blocking direct device-to-device access.'
            : '局域网常见连接失败原因：设备位于不同网段或开启了客户端/AP隔离，导致终端之间不能互访。建议尝试让两台设备接入同一个手机热点/电脑热点再测试；如果热点正常，说明当前网络环境阻断了局域网终端直接通信。';
      case NetworkDiagnosticStatus.connectionRefused:
        return en
            ? 'The target IP is reachable but the port is not accepting connections. Make sure LocalChat is open on the peer, use the peer settings page port, and allow LocalChat through the OS firewall.'
            : '目标 IP 可达，但端口没有接受连接。确认对方 LocalChat 正在运行、端口填写的是对方设置页显示的端口，并在系统防火墙中放行 LocalChat 入站连接。';
      case NetworkDiagnosticStatus.nonLocalChat:
        return en
            ? 'The IP/port is answering, but not with the LocalChat protocol. Recheck the peer IP and port shown in Settings.'
            : '这个 IP/端口有响应，但不是 LocalChat 协议。请重新核对对方设置页里的 IP 和端口。';
      case NetworkDiagnosticStatus.identityMismatch:
        return en
            ? 'Do not pair with this endpoint. The identity payload is inconsistent; recheck the address and reinstall/re-pair only after confirming the device.'
            : '不要和这个端点配对。对方身份数据不自洽；请核对地址，确认设备后再重新配对。';
      case NetworkDiagnosticStatus.unknownError:
        return en
            ? 'Retry after confirming both devices are on the same network. If it fails on public or corporate networks, direct device-to-device access is likely blocked.'
            : '确认两台设备在同一网络后重试。如果在公共网络或企业局域网失败，大概率是当前网络环境禁止终端直接互访。';
    }
  }
}
