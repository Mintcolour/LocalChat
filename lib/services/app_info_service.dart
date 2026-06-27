import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_info.dart';

class AppInfoService {
  const AppInfoService();

  Future<AppInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(
      appName: info.appName.isEmpty ? 'LocalChat' : info.appName,
      version: info.version,
      buildNumber: info.buildNumber,
      platform: _platformName(),
    );
  }

  String _platformName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    return Platform.operatingSystem;
  }
}
