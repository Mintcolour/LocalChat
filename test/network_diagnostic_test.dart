import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/core/app_text.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/models/network_diagnostic.dart';
import 'package:localchat/services/file_store.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/security_service.dart';
import 'package:localchat/services/transport_service.dart';

void main() {
  test('probeHello rejects invalid input without network access', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final identity = IdentityService(db);
    await identity.load();
    final transport = TransportService(
      db,
      identity,
      SecurityService(identity),
      FileStore(),
    );
    addTearDown(() async {
      await transport.stop();
      await db.close();
    });

    final result = await transport.probeHello('', 0);

    expect(result.status, NetworkDiagnosticStatus.invalidInput);
  });

  test('diagnostic advice explains campus network isolation', () {
    final text = AppText('zh');
    final result = NetworkDiagnosticResult(
      host: '172.30.72.176',
      port: 40123,
      status: NetworkDiagnosticStatus.timeout,
    );

    expect(text.networkDiagnosticSummary(result), contains('超时'));
    expect(text.networkDiagnosticAdviceFor(result), contains('校园网'));
    expect(text.networkDiagnosticAdviceFor(result), contains('VLAN'));
  });
}
