import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get platform => text()();
  TextColumn get host => text().nullable()();
  IntColumn get port => integer().nullable()();
  TextColumn get signingPublicKey => text()();
  TextColumn get exchangePublicKey => text()();
  TextColumn get fingerprint => text()();
  BoolColumn get trusted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSeen => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get peerDeviceId => text()();
  TextColumn get title => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get peerDeviceId => text()();
  TextColumn get direction => text()();
  TextColumn get kind => text()();
  TextColumn get body => text().nullable()();
  TextColumn get fileName => text().nullable()();
  TextColumn get filePath => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get status => text()();
  TextColumn get transferId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get peerDeviceId => text()();
  TextColumn get direction => text()();
  TextColumn get fileName => text()();
  TextColumn get filePath => text().nullable()();
  IntColumn get fileSize => integer()();
  TextColumn get sha256 => text().nullable()();
  TextColumn get status => text()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalChunks => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>>? get primaryKey => {key};
}

@DriftDatabase(
  tables: [Devices, Conversations, ChatMessages, Transfers, Settings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'localchat'));

  @override
  int get schemaVersion => 1;

  Future<String?> getSetting(String key) async {
    final row = await (select(
      settings,
    )..where((tbl) => tbl.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) {
    return into(
      settings,
    ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  }

  Future<List<Device>> listTrustedDevices() {
    return (select(devices)
          ..where((tbl) => tbl.trusted.equals(true))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastSeen)]))
        .get();
  }

  Future<List<Device>> listDevices() {
    return (select(
      devices,
    )..orderBy([(tbl) => OrderingTerm.desc(tbl.lastSeen)])).get();
  }

  Future<Device?> getDevice(String id) {
    return (select(
      devices,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<Conversation?> getConversationForDevice(String deviceId) {
    return (select(
      conversations,
    )..where((tbl) => tbl.peerDeviceId.equals(deviceId))).getSingleOrNull();
  }

  Future<void> upsertDiscoveredDevice({
    required String id,
    required String displayName,
    required String platform,
    required String host,
    required int port,
    required String signingPublicKey,
    required String exchangePublicKey,
    required String fingerprint,
  }) async {
    final existing = await getDevice(id);
    await into(devices).insertOnConflictUpdate(
      DevicesCompanion.insert(
        id: id,
        displayName: displayName,
        platform: platform,
        signingPublicKey: signingPublicKey,
        exchangePublicKey: exchangePublicKey,
        fingerprint: fingerprint,
        trusted: Value(existing?.trusted ?? false),
        host: Value(host),
        port: Value(port),
        lastSeen: Value(DateTime.now()),
        createdAt: existing == null ? DateTime.now() : existing.createdAt,
      ),
    );
  }

  Future<void> trustDevice({
    required String id,
    required String displayName,
    required String platform,
    required String host,
    required int port,
    required String signingPublicKey,
    required String exchangePublicKey,
    required String fingerprint,
  }) async {
    final existing = await getDevice(id);
    await into(devices).insertOnConflictUpdate(
      DevicesCompanion.insert(
        id: id,
        displayName: displayName,
        platform: platform,
        signingPublicKey: signingPublicKey,
        exchangePublicKey: exchangePublicKey,
        fingerprint: fingerprint,
        trusted: const Value(true),
        host: Value(host),
        port: Value(port),
        lastSeen: Value(DateTime.now()),
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  Future<void> updateDeviceEndpoint({
    required String id,
    required String host,
    required int port,
  }) async {
    await (update(devices)..where((tbl) => tbl.id.equals(id))).write(
      DevicesCompanion(
        host: Value(host),
        port: Value(port),
        lastSeen: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markDeviceOffline(String id) async {
    await (update(devices)..where((tbl) => tbl.id.equals(id))).write(
      const DevicesCompanion(lastSeen: Value(null)),
    );
  }

  Future<Conversation> ensureConversation(Device peer) async {
    final id = 'peer:${peer.id}';
    final now = DateTime.now();
    final existing = await (select(
      conversations,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (existing != null) return existing;
    await into(conversations).insert(
      ConversationsCompanion.insert(
        id: id,
        peerDeviceId: peer.id,
        title: peer.displayName,
        updatedAt: now,
      ),
    );
    return (select(
      conversations,
    )..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  Future<List<Conversation>> listConversations() {
    return (select(
      conversations,
    )..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])).get();
  }

  Future<void> renameConversation(String conversationId, String title) async {
    await (update(
      conversations,
    )..where((tbl) => tbl.id.equals(conversationId))).write(
      ConversationsCompanion(
        title: Value(title),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<ChatMessage>> listMessages(String conversationId) {
    return (select(chatMessages)
          ..where((tbl) => tbl.conversationId.equals(conversationId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();
  }

  Future<void> addMessage(ChatMessagesCompanion message) async {
    await into(chatMessages).insertOnConflictUpdate(message);
    await (update(conversations)
          ..where((tbl) => tbl.id.equals(message.conversationId.value)))
        .write(ConversationsCompanion(updatedAt: Value(DateTime.now())));
  }

  Future<void> clearHistory() async {
    await delete(chatMessages).go();
    await delete(transfers).go();
    await delete(conversations).go();
  }

  Future<void> clearTransferIndex() => delete(transfers).go();
}
