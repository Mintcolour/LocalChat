import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/app/app_controller.dart';
import 'package:localchat/data/app_database.dart';

void main() {
  late AppDatabase db;
  late AppController controller;
  final readAt = DateTime.utc(2000);
  var messageIndex = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    controller = AppController(database: db);
    messageIndex = 0;
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
    final device = (await db.getDevice('peer-1'))!;
    await controller.selectDevice(device);
    await (db.update(db.conversations)
          ..where((tbl) => tbl.id.equals('peer:peer-1')))
        .write(ConversationsCompanion(lastReadAt: Value(readAt)));
  });

  tearDown(() => controller.dispose());

  Future<void> addInboundMessage(String id) {
    return db.addMessage(
      ChatMessagesCompanion.insert(
        id: id,
        conversationId: 'peer:peer-1',
        peerDeviceId: 'peer-1',
        direction: 'in',
        kind: 'text',
        body: const Value('hello'),
        status: 'received',
        createdAt: readAt.add(Duration(seconds: ++messageIndex)),
      ),
    );
  }

  test('foreground selected conversation stays read after refresh', () async {
    controller.setAppForeground(true);
    await addInboundMessage('foreground-message');

    await controller.refresh();

    expect(controller.unreadCounts['peer:peer-1'], 0);
    final conversation = await db.getConversationForDevice('peer-1');
    expect(
      await db.unreadCount('peer:peer-1', lastReadAt: conversation!.lastReadAt),
      0,
    );
  });

  test(
    'background selected conversation keeps unread count after refresh',
    () async {
      controller.setAppForeground(false);
      await addInboundMessage('background-message');

      await controller.refresh();

      expect(controller.unreadCounts['peer:peer-1'], 1);
    },
  );
}
