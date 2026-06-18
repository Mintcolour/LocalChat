import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/device_profile.dart';

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
  TextColumn get avatarSeed => text().withDefault(const Constant(''))();
  TextColumn get avatarColor => text().withDefault(const Constant('#2563EB'))();
  BoolColumn get trusted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSeen => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  // auto: 由 UDP 发现或 TCP 源 IP 自动学习的端点；manual: 用户手动填写的跨网段 IP:port，
  // 不应被自动学习逻辑覆盖。
  TextColumn get endpointSource => text().withDefault(const Constant('auto'))();

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
  TextColumn get mimeType => text().nullable()();
  TextColumn get status => text()();
  TextColumn get transferId => text().nullable()();
  // 文件夹递归传输时相对根目录的路径（POSIX 分隔符），单文件为 null。
  TextColumn get relativePath => text().nullable()();
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
  TextColumn get mimeType => text().nullable()();
  TextColumn get savedPath => text().nullable()();
  TextColumn get savedUri => text().nullable()();
  TextColumn get status => text()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalChunks => integer().withDefault(const Constant(0))();
  // 文件夹递归传输时相对根目录的路径（POSIX 分隔符），单文件为 null。
  TextColumn get relativePath => text().nullable()();
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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(devices, devices.avatarSeed);
        await m.addColumn(devices, devices.avatarColor);
        await m.addColumn(chatMessages, chatMessages.mimeType);
        await m.addColumn(transfers, transfers.mimeType);
        await m.addColumn(transfers, transfers.savedPath);
        await m.addColumn(transfers, transfers.savedUri);
        final rows = await select(devices).get();
        for (final device in rows) {
          final seed = avatarSeedFor(device.id, device.fingerprint);
          await (update(
            devices,
          )..where((tbl) => tbl.id.equals(device.id))).write(
            DevicesCompanion(
              avatarSeed: Value(seed),
              avatarColor: Value(avatarColorFor(seed)),
            ),
          );
        }
      }
      if (from < 3) {
        await m.addColumn(chatMessages, chatMessages.relativePath);
        await m.addColumn(transfers, transfers.relativePath);
      }
      if (from < 4) {
        await m.addColumn(devices, devices.endpointSource);
      }
    },
  );

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
          ..orderBy([
            (tbl) => OrderingTerm.asc(tbl.displayName),
            (tbl) => OrderingTerm.asc(tbl.createdAt),
          ]))
        .get();
  }

  Future<List<Device>> listDevices() {
    return (select(devices)..orderBy([
          (tbl) => OrderingTerm.asc(tbl.displayName),
          (tbl) => OrderingTerm.asc(tbl.createdAt),
        ]))
        .get();
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
    required String avatarSeed,
    required String avatarColor,
  }) async {
    final existing = await getDevice(id);
    // 手动添加的跨网段设备：保留用户填写的 host/port 与 endpointSource，
    // 不被 UDP 广播或入站请求的源 IP 覆盖（仅刷新展示名、公钥、头像、lastSeen）。
    final isManual = existing?.endpointSource == 'manual';
    await into(devices).insertOnConflictUpdate(
      DevicesCompanion.insert(
        id: id,
        displayName: displayName,
        platform: platform,
        signingPublicKey: signingPublicKey,
        exchangePublicKey: exchangePublicKey,
        fingerprint: fingerprint,
        avatarSeed: Value(avatarSeed),
        avatarColor: Value(avatarColor),
        trusted: Value(existing?.trusted ?? false),
        host: Value(isManual ? existing!.host! : host),
        port: Value(isManual ? existing!.port! : port),
        lastSeen: Value(DateTime.now()),
        endpointSource: Value(existing?.endpointSource ?? 'auto'),
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
    required String avatarSeed,
    required String avatarColor,
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
        avatarSeed: Value(avatarSeed),
        avatarColor: Value(avatarColor),
        trusted: const Value(true),
        host: Value(host),
        port: Value(port),
        lastSeen: Value(DateTime.now()),
        endpointSource: Value(existing?.endpointSource ?? 'auto'),
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  Future<void> updateDeviceEndpoint({
    required String id,
    required String host,
    required int port,
    bool force = false,
  }) async {
    // 手动添加的跨网段端点不应被 UDP 发现或 TCP 源 IP 自动覆盖。
    if (!force) {
      final existing = await getDevice(id);
      if (existing != null && existing.endpointSource == 'manual') {
        return;
      }
    }
    await (update(devices)..where((tbl) => tbl.id.equals(id))).write(
      DevicesCompanion(
        host: Value(host),
        port: Value(port),
        lastSeen: Value(DateTime.now()),
      ),
    );
  }

  /// 以手动方式落库一个跨网段设备（未信任，等待配对确认）。
  /// host/port 来自用户输入，endpointSource 标记为 manual，避免被自动逻辑改写。
  Future<void> upsertManualDevice({
    required String id,
    required String displayName,
    required String platform,
    required String host,
    required int port,
    required String signingPublicKey,
    required String exchangePublicKey,
    required String fingerprint,
    required String avatarSeed,
    required String avatarColor,
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
        avatarSeed: Value(avatarSeed),
        avatarColor: Value(avatarColor),
        trusted: Value(existing?.trusted ?? false),
        host: Value(host),
        port: Value(port),
        lastSeen: Value(DateTime.now()),
        endpointSource: const Value('manual'),
        createdAt: existing == null ? DateTime.now() : existing.createdAt,
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

  Future<void> deleteConversation(String conversationId) async {
    final rows = await (select(
      chatMessages,
    )..where((tbl) => tbl.conversationId.equals(conversationId))).get();
    final transferIds = rows
        .map((message) => message.transferId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (transferIds.isNotEmpty) {
      await (delete(transfers)..where((tbl) => tbl.id.isIn(transferIds))).go();
    }
    await (delete(
      chatMessages,
    )..where((tbl) => tbl.conversationId.equals(conversationId))).go();
    await (delete(
      conversations,
    )..where((tbl) => tbl.id.equals(conversationId))).go();
  }

  Future<void> deletePeerSession(String deviceId) async {
    await (delete(
      transfers,
    )..where((tbl) => tbl.peerDeviceId.equals(deviceId))).go();
    await (delete(
      chatMessages,
    )..where((tbl) => tbl.peerDeviceId.equals(deviceId))).go();
    await (delete(
      conversations,
    )..where((tbl) => tbl.peerDeviceId.equals(deviceId))).go();
    await (delete(devices)..where((tbl) => tbl.id.equals(deviceId))).go();
  }

  Future<void> deleteStaleUntrustedDevices(DateTime cutoff) async {
    await (delete(devices)..where(
          (tbl) =>
              tbl.trusted.equals(false) &
              (tbl.lastSeen.isNull() | tbl.lastSeen.isSmallerThanValue(cutoff)),
        ))
        .go();
  }

  Future<List<ChatMessage>> listMessages(String conversationId) {
    return (select(chatMessages)
          ..where((tbl) => tbl.conversationId.equals(conversationId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();
  }

  Future<List<Transfer>> listTransfersByIds(Iterable<String> ids) {
    final values = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (values.isEmpty) return Future.value(const <Transfer>[]);
    return (select(transfers)..where((tbl) => tbl.id.isIn(values))).get();
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

  Future<void> markTransferSaved({
    required String transferId,
    String? savedPath,
    String? savedUri,
  }) async {
    await (update(transfers)..where((tbl) => tbl.id.equals(transferId))).write(
      TransfersCompanion(
        savedPath: Value(savedPath),
        savedUri: Value(savedUri),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
