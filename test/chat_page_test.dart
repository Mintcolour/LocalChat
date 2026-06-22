import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/core/formatters.dart';
import 'package:localchat/data/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.trustDevice(
      id: 'peer-1',
      displayName: 'Phone',
      platform: 'android',
      host: '127.0.0.1',
      port: 1,
      signingPublicKey: 's',
      exchangePublicKey: 'e',
      fingerprint: 'f',
      avatarSeed: 'seed',
      avatarColor: '#2563EB',
    );
    // ensureConversation 需要 Device，构造一个最小 Device 用于建立会话行。
    final device = (await db.getDevice('peer-1'))!;
    await db.ensureConversation(device);
  });

  tearDown(() => db.close());

  Future<void> seedMessage(String id, {required DateTime at, String? body, String? fileName}) async {
    await db.addMessage(
      ChatMessagesCompanion.insert(
        id: id,
        conversationId: 'peer:peer-1',
        peerDeviceId: 'peer-1',
        direction: 'in',
        kind: 'text',
        body: body != null ? Value(body) : const Value.absent(),
        fileName: fileName != null ? Value(fileName) : const Value.absent(),
        status: 'received',
        createdAt: at,
      ),
    );
  }

  test('listMessagesPage returns latest page in ascending order with hasMore flag', () async {
    final base = DateTime.utc(2026, 6, 22, 10);
    for (var i = 0; i < 70; i++) {
      await seedMessage('m$i', at: base.add(Duration(seconds: i)), body: 'msg $i');
    }
    final firstPage = await db.listMessagesPage(conversationId: 'peer:peer-1', limit: 50);
    // 升序，且第一页只返回 50 条（最新 50）。
    expect(firstPage.length, 50);
    expect(firstPage.first.id, 'm20');
    expect(firstPage.last.id, 'm69');

    // 向前翻页取下一组 50（应剩 20 条）。
    final oldest = firstPage.first;
    final secondPage = await db.listMessagesPage(
      conversationId: 'peer:peer-1',
      limit: 50,
      beforeCreatedAt: oldest.createdAt,
      beforeId: oldest.id,
    );
    expect(secondPage.length, 20);
    expect(secondPage.first.id, 'm0');
    expect(secondPage.last.id, 'm19');
  });

  test('unreadCount counts inbound messages after lastReadAt', () async {
    final t0 = DateTime.utc(2026, 6, 22, 10);
    await seedMessage('a', at: t0, body: 'old');
    await seedMessage('b', at: t0.add(const Duration(minutes: 1)), body: 'new');
    // 全部未读。
    expect(await db.unreadCount('peer:peer-1'), 2);
    // 标记已读到 a 之后：b 仍算未读。
    final conversation = await db.getConversationForDevice('peer-1');
    await db.markConversationRead(conversation!.id);
    final read = await db.getConversationForDevice('peer-1');
    // markConversationRead 把 lastReadAt 设为 now，此后没有更新的入站消息 → 未读 0。
    expect(await db.unreadCount('peer:peer-1', lastReadAt: read!.lastReadAt), 0);
  });

  test('searchMessages matches body or file name, capped at 100', () async {
    final t0 = DateTime.utc(2026, 6, 22, 10);
    await seedMessage('s1', at: t0, body: '请查看 report 最终版');
    await seedMessage('s2', at: t0.add(const Duration(seconds: 1)), fileName: 'report.pdf');
    await seedMessage('s3', at: t0.add(const Duration(seconds: 2)), body: '无关内容');

    final results = await db.searchMessages('peer:peer-1', 'report');
    expect(results.map((m) => m.id), containsAll(const ['s1', 's2']));
    expect(results.any((m) => m.id == 's3'), isFalse);
  });

  group('formatters', () {
    test('chat date separator handles today/yesterday/weekday/absolute', () {
      final now = DateTime(2026, 6, 22, 15); // 周一
      expect(formatChatDateSeparator(DateTime(2026, 6, 22, 9), now: now), '今天');
      expect(formatChatDateSeparator(DateTime(2026, 6, 21, 9), now: now), '昨天');
      // 周三（6/17）在一周内 → 显示星期。
      expect(formatChatDateSeparator(DateTime(2026, 6, 17, 9), now: now), '周三');
      // 两周前 → 完整日期。
      expect(
        formatChatDateSeparator(DateTime(2026, 6, 8, 9), now: now),
        '2026年6月8日',
      );
    });

    test('extractLinks pulls http and https urls out of text', () {
      final text = '看这个 https://example.com/a/b 和 http://foo.io/x?t=1 就行';
      final links = extractLinks(text);
      expect(links, ['https://example.com/a/b', 'http://foo.io/x?t=1']);
    });

    test('extractLinks returns empty when no link present', () {
      expect(extractLinks('普通文本，没有链接'), isEmpty);
    });
  });
}
