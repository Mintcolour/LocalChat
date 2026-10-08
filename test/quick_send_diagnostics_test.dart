import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/services/window_service.dart';

class _DiagnosticWindowService extends WindowService {
  @override
  bool get isSupported => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('localchat/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native drag snapshot preserves counters and rejection reasons',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getQuickSendDiagnostics');
        return {
          'build': 'drag-diagnostics-v1',
          'enabled': true,
          'monitorRunning': true,
          'mousePresses': 3,
          'dragsAccepted': 0,
          'recentProbes': [
            {'sourceClass': 'DirectUIHWND', 'decision': 'not_shell_window'},
          ],
        };
      });
      final snapshot = await _DiagnosticWindowService()
          .getQuickSendDiagnostics();
      expect(snapshot['available'], true);
      expect(snapshot['mousePresses'], 3);
      expect(
        snapshot['recentProbes'],
        contains(containsPair('decision', 'not_shell_window')),
      );
    },
  );

  test('old or missing native plugin is explicitly identified', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );
    final snapshot = await _DiagnosticWindowService().getQuickSendDiagnostics();
    expect(snapshot['available'], false);
    expect(snapshot['error'], 'diagnostics_not_available');
  });
}
