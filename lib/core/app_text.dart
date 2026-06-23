import '../data/app_database.dart';
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
  String get peerHost => en ? 'Peer IP / host' : '对方 IP / 主机';
  String get peerPort => en ? 'Port' : '端口';
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
}
