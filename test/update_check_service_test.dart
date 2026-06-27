import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/models/update_check.dart';
import 'package:localchat/services/update_check_service.dart';

void main() {
  test('version comparison ignores v prefix and build metadata', () {
    expect(compareAppVersions('v1.3.4', '1.3.3+7'), greaterThan(0));
    expect(compareAppVersions('v1.3.3', '1.3.3+7'), 0);
    expect(compareAppVersions('v1.3.2', '1.3.3+7'), lessThan(0));
    expect(compareAppVersions('latest', '1.3.3+7'), isNull);
  });

  test('update service reports a newer GitHub release', () async {
    final service = UpdateCheckService(
      fetcher: () async => {
        'tag_name': 'v1.3.4',
        'html_url':
            'https://github.com/Mintcolour/LocalChat/releases/tag/v1.3.4',
        'name': 'LocalChat 1.3.4',
        'body': 'Release notes',
      },
    );

    final result = await service.check(currentVersion: '1.3.3+7');

    expect(result.status, UpdateCheckStatus.updateAvailable);
    expect(result.latestRelease?.tagName, 'v1.3.4');
    expect(result.latestRelease?.displayName, 'LocalChat 1.3.4');
  });

  test('update service reports current release as up to date', () async {
    final service = UpdateCheckService(
      fetcher: () async => {
        'tag_name': 'v1.3.3',
        'html_url':
            'https://github.com/Mintcolour/LocalChat/releases/tag/v1.3.3',
      },
    );

    final result = await service.check(currentVersion: '1.3.3+7');

    expect(result.status, UpdateCheckStatus.upToDate);
    expect(result.latestRelease?.tagName, 'v1.3.3');
  });

  test('update service treats GitHub failures as check failures', () async {
    final service = UpdateCheckService(
      fetcher: () async => throw Exception('network failed'),
    );

    final result = await service.check(currentVersion: '1.3.3+7');

    expect(result.status, UpdateCheckStatus.failed);
    expect(result.error, contains('network failed'));
  });

  test('update service rejects incomplete release payloads', () async {
    final service = UpdateCheckService(fetcher: () async => {});

    final result = await service.check(currentVersion: '1.3.3+7');

    expect(result.status, UpdateCheckStatus.failed);
    expect(result.latestRelease, isNull);
  });
}
