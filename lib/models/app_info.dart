class AppInfo {
  const AppInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.platform,
  });

  final String appName;
  final String version;
  final String buildNumber;
  final String platform;

  String get displayVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';

  String get shareText =>
      '$appName $displayVersion ($platform)\n'
      'https://github.com/Mintcolour/LocalChat';
}
