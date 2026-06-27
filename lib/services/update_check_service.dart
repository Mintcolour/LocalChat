import 'package:dio/dio.dart' as dio;

import '../models/update_check.dart';

typedef ReleaseJsonFetcher = Future<Map<String, dynamic>> Function();

const localChatRepositoryUrl = 'https://github.com/Mintcolour/LocalChat';
const localChatReleasesUrl = '$localChatRepositoryUrl/releases';
const localChatIssuesUrl = '$localChatRepositoryUrl/issues';

class UpdateCheckService {
  UpdateCheckService({dio.Dio? client, Uri? latestReleaseEndpoint, this.fetcher})
    : _client =
          client ??
          dio.Dio(
            dio.BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          ),
      _latestReleaseEndpoint =
          latestReleaseEndpoint ??
          Uri.parse(
            'https://api.github.com/repos/Mintcolour/LocalChat/releases/latest',
          );

  final dio.Dio _client;
  final Uri _latestReleaseEndpoint;
  final ReleaseJsonFetcher? fetcher;

  Future<UpdateCheckResult> check({required String currentVersion}) async {
    try {
      final json = await _fetchLatestReleaseJson();
      final tagName = (json['tag_name'] as String?)?.trim() ?? '';
      final htmlUrl = (json['html_url'] as String?)?.trim() ?? '';
      if (tagName.isEmpty || htmlUrl.isEmpty) {
        return UpdateCheckResult.failed(
          currentVersion: currentVersion,
          error: 'Latest release payload is incomplete.',
        );
      }
      final latestRelease = ReleaseInfo(
        tagName: tagName,
        htmlUrl: htmlUrl,
        name: (json['name'] as String?)?.trim() ?? '',
        body: (json['body'] as String?)?.trim() ?? '',
      );
      final comparison = compareAppVersions(tagName, currentVersion);
      if (comparison == null) {
        return UpdateCheckResult.failed(
          currentVersion: currentVersion,
          error: 'Latest release version could not be parsed.',
        );
      }
      if (comparison > 0) {
        return UpdateCheckResult.updateAvailable(
          currentVersion: currentVersion,
          latestRelease: latestRelease,
        );
      }
      return UpdateCheckResult.upToDate(
        currentVersion: currentVersion,
        latestRelease: latestRelease,
      );
    } catch (error) {
      return UpdateCheckResult.failed(
        currentVersion: currentVersion,
        error: error.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _fetchLatestReleaseJson() async {
    final fetcher = this.fetcher;
    if (fetcher != null) return fetcher();
    final response = await _client.getUri<Map<String, dynamic>>(
      _latestReleaseEndpoint,
      options: dio.Options(
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'LocalChat update checker',
        },
      ),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Empty release response.');
    }
    return data;
  }
}

int? compareAppVersions(String left, String right) {
  final leftVersion = ParsedAppVersion.tryParse(left);
  final rightVersion = ParsedAppVersion.tryParse(right);
  if (leftVersion == null || rightVersion == null) return null;
  return leftVersion.compareTo(rightVersion);
}

class ParsedAppVersion implements Comparable<ParsedAppVersion> {
  const ParsedAppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:\+.*)?$');

  static ParsedAppVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    return ParsedAppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(ParsedAppVersion other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) return majorComparison;
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) return minorComparison;
    return patch.compareTo(other.patch);
  }
}
