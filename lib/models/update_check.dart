enum UpdateCheckStatus { updateAvailable, upToDate, failed }

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.htmlUrl,
    required this.name,
    required this.body,
  });

  final String tagName;
  final String htmlUrl;
  final String name;
  final String body;

  String get displayName => name.isEmpty ? tagName : name;
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.latestRelease,
    this.error,
  });

  final UpdateCheckStatus status;
  final String currentVersion;
  final ReleaseInfo? latestRelease;
  final String? error;

  bool get hasUpdate => status == UpdateCheckStatus.updateAvailable;
  bool get isUpToDate => status == UpdateCheckStatus.upToDate;
  bool get failed => status == UpdateCheckStatus.failed;

  factory UpdateCheckResult.updateAvailable({
    required String currentVersion,
    required ReleaseInfo latestRelease,
  }) => UpdateCheckResult(
    status: UpdateCheckStatus.updateAvailable,
    currentVersion: currentVersion,
    latestRelease: latestRelease,
  );

  factory UpdateCheckResult.upToDate({
    required String currentVersion,
    required ReleaseInfo latestRelease,
  }) => UpdateCheckResult(
    status: UpdateCheckStatus.upToDate,
    currentVersion: currentVersion,
    latestRelease: latestRelease,
  );

  factory UpdateCheckResult.failed({
    required String currentVersion,
    required String error,
  }) => UpdateCheckResult(
    status: UpdateCheckStatus.failed,
    currentVersion: currentVersion,
    error: error,
  );
}
