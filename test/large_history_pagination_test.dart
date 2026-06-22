import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';

void main() {
  test('paginated query stays bounded for 10000 messages', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.trustDevice(
      id: 'peer-1',
      displayName: 'Phone',
      platform: 'android',
      host: '1.1.1.1',
      port: 1,
      signingPublicKey: 's',
      exchangePublicKey: 'e',
      fingerprint: 'f',
      avatarSeed: 'seed',
      avatarColor: '#000',
    );
    final device = (await db.getDevice('peer-1'))!;
    await db.ensureConversation(device);

    // 批量插入 10000 条消息，验证分页只取 50 条而非全量。
    final base = DateTime.utc(2026, 6, 22);
    await db.batch((batch) {
      for (var i = 0; i < 10000; i++) {
        batch.insert(
          db.chatMessages,
          ChatMessagesCompanion.insert(
            id: 'm$i',
            conversationId: 'peer:peer-1',
            peerDeviceId: 'peer-1',
            direction: i.isEven ? 'in' : 'out',
            kind: 'text',
            body: Value('message $i'),
            status: 'received',
            createdAt: base.add(Duration(seconds: i)),
          ),
        );
      }
    });

    final stopwatch = Stopwatch()..start();
    final firstPage = await db.listMessagesPage(conversationId: 'peer:peer-1', limit: 50);
    stopwatch.stop();

    expect(firstPage.length, 50);
    // 第一页是最新 50 条（升序），最后一条是 m9999。
    expect(firstPage.last.id, 'm9999');
    // 分页查询应在合理时间内完成（远小于全量 10000 条往返）。
    expect(stopwatch.elapsedMilliseconds, lessThan(3000));
  });
}
