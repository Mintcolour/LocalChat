import '../data/app_database.dart';

const peerOnlineWindow = Duration(seconds: 12);

bool isPeerOnline(Device device, {DateTime? now}) {
  final lastSeen = device.lastSeen;
  if (lastSeen == null) return false;
  return (now ?? DateTime.now()).difference(lastSeen) <= peerOnlineWindow;
}

String peerStatusLabel(Device device, {DateTime? now}) {
  if (!device.trusted) return '未配对';
  return isPeerOnline(device, now: now) ? '在线' : '离线，等待重新上线';
}
