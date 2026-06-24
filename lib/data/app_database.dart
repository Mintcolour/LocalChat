import 'dart:convert';

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
  // 对端广播的能力列表（JSON 数组字符串）。旧版本不广播能力时为 null。
  TextColumn get capabilities => text().nullable()();
  // 已信任设备的签名/交换公钥或指纹发生变化时置 true，禁止发送并要求删除后重新配对。
  // nullable 以兼容旧库与构造；判定时以 == true 为准。
  BoolColumn get identityChanged => boolean().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get peerDeviceId => text()();
  TextColumn get title => text()();
  DateTimeColumn get updatedAt => dateTime()();
  // 该会话最后被用户阅读到的时间，用于未读消息统计。nullable 兼容旧库。
  DateTimeColumn get lastReadAt => dateTime().nullable()();

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
  // 批量/文件夹传输的聚合分组标识，支持整组查看与取消。单文件为 null。
  TextColumn get groupId => text().nullable()();
  // 失败/中断时的机器可读错误码（如 connection_lost、canceled）。
  TextColumn get errorCode => text().nullable()();
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        if (!await _columnExists('devices', 'avatar_seed')) {
          await m.addColumn(devices, devices.avatarSeed);
        }
        if (!await _columnExists('devices', 'avatar_color')) {
          await m.addColumn(devices, devices.avatarColor);
        }
        if (!await _columnExists('chat_messages', 'mime_type')) {
          await m.addColumn(chatMessages, chatMessages.mimeType);
        }
        if (!await _columnExists('transfers', 'mime_type')) {
          await m.addColumn(transfers, transfers.mimeType);
        }
        if (!await _columnExists('transfers', 'saved_path')) {
          await m.addColumn(transfers, transfers.savedPath);
        }
        if (!await _columnExists('transfers', 'saved_uri')) {
          await m.addColumn(transfers, transfers.savedUri);
        }
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
        if (!await _columnExists('chat_messages', 'relative_path')) {
          await m.addColumn(chatMessages, chatMessages.relativePath);
        }
        if (!await _columnExists('transfers', 'relative_path')) {
          await m.addColumn(transfers, transfers.relativePath);
        }
      }
      if (from < 4 && !await _columnExists('devices', 'endpoint_source')) {
        await m.addColumn(devices, devices.endpointSource);
      }
      if (from < 5) {
        if (!await _columnExists('devices', 'capabilities')) {
          await m.addColumn(devices, devices.capabilities);
        }
        if (!await _columnExists('devices', 'identity_changed')) {
          await m.addColumn(devices, devices.identityChanged);
        }
        if (!await _columnExists('conversations', 'last_read_at')) {
          await m.addColumn(conversations, conversations.lastReadAt);
        }
        if (!await _columnExists('transfers', 'group_id')) {
          await m.addColumn(transfers, transfers.groupId);
        }
        if (!await _columnExists('transfers', 'error_code')) {
          await m.addColumn(transfers, transfers.errorCode);
        }
      }
    },
    // 索引在 beforeOpen 中以 IF NOT EXISTS 创建，覆盖全新库与升级库两条路径。
    beforeOpen: (details) async {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation_created '
        'ON chat_messages (conversation_id, created_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_transfers_group_status '
        'ON transfers (group_id, status)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_conversations_updated '
        'ON conversations (updated_at)',
      );
    },
  );

  Future<bool> _columnExists(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info("$tableName")').get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

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
    List<String>? capabilities,
  }) async {
    final existing = await getDevice(id);
    // 手动添加的跨网段设备：保留用户填写的 host/port 与 endpointSource，
    // 不被 UDP 广播或入站请求的源 IP 覆盖（仅刷新展示名、公钥、头像、lastSeen）。
    final isManual = existing?.endpointSource == 'manual';
    final capsValue = _capabilitiesValue(capabilities);
    if (existing != null && existing.trusted) {
      // 已信任设备：固定首次配对时的签名/交换公钥与指纹（P0 公钥固定）。
      // 发现信息只刷新地址、名称、头像、在线状态与能力；签名/交换公钥/指纹绝不
      // 被覆盖。检测到任一身份字段变化即标记 identity_changed，发送侧据此拦截，
      // 要求用户删除后重新配对。
      final identityChanged =
          existing.identityChanged == true ||
          signingPublicKey != existing.signingPublicKey ||
          exchangePublicKey != existing.exchangePublicKey ||
          fingerprint != existing.fingerprint;
      await (update(devices)..where((tbl) => tbl.id.equals(id))).write(
        DevicesCompanion(
          displayName: Value(displayName),
          platform: Value(platform),
          avatarSeed: Value(avatarSeed),
          avatarColor: Value(avatarColor),
          host: Value(isManual ? existing.host! : host),
          port: Value(isManual ? existing.port! : port),
          lastSeen: Value(DateTime.now()),
          capabilities: capsValue,
          identityChanged: Value(identityChanged),
        ),
      );
      return;
    }
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
        capabilities: capsValue,
        identityChanged: const Value(false),
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
    List<String>? capabilities,
  }) async {
    final existing = await getDevice(id);
    // 建立信任即（重新）固定身份公钥：把入参公钥/指纹写入并清除 identity_changed。
    // 这是从“删除后重新配对”恢复正常发送的唯一入口。
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
        capabilities: _capabilitiesValue(capabilities),
        identityChanged: const Value(false),
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
    List<String>? capabilities,
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
        capabilities: _capabilitiesValue(capabilities),
        identityChanged: const Value(false),
        endpointSource: const Value('manual'),
        createdAt: existing == null ? DateTime.now() : existing.createdAt,
      ),
    );
  }

  /// 把能力列表序列化为可写入 capabilities 列的 [Value]；null 表示不更新该列。
  Value<String?> _capabilitiesValue(List<String>? capabilities) {
    if (capabilities == null) return const Value.absent();
    return Value(jsonEncode(capabilities));
  }

  /// 读取设备能力列表。capabilities 列为空或反序列化失败时返回空列表。
  List<String> deviceCapabilities(Device device) {
    final raw = device.capabilities;
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return const <String>[];
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

  Future<void> deleteChatMessage(String messageId) async {
    final message = await (select(chatMessages)..where((tbl) => tbl.id.equals(messageId))).getSingleOrNull();
    if (message != null && message.transferId != null && message.transferId!.isNotEmpty) {
      await (delete(transfers)..where((tbl) => tbl.id.equals(message.transferId!))).go();
    }
    await (delete(chatMessages)..where((tbl) => tbl.id.equals(messageId))).go();
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

  /// 以 (createdAt, id) 为游标向前分页加载消息，取最新的 [limit] 条（或游标之前
  /// 的 [limit] 条）。返回按时间升序排列（与 [listMessages] 一致），便于直接追加。
  Future<List<ChatMessage>> listMessagesPage({
    required String conversationId,
    int limit = 50,
    DateTime? beforeCreatedAt,
    String? beforeId,
  }) {
    final query = select(chatMessages)
      ..where((tbl) => tbl.conversationId.equals(conversationId))
      ..orderBy([
        (tbl) => OrderingTerm.desc(tbl.createdAt),
        (tbl) => OrderingTerm.desc(tbl.id),
      ])
      ..limit(limit + 1); // 多取 1 条用于判断是否还有更早的页。
    if (beforeCreatedAt != null && beforeId != null) {
      query.where(
        (tbl) =>
            tbl.createdAt.isSmallerThanValue(beforeCreatedAt) |
            (tbl.createdAt.equals(beforeCreatedAt) &
                tbl.id.isSmallerThanValue(beforeId)),
      );
    }
    return query.get().then((rows) {
      // 截掉多余的探测行，只返回 limit 条；反转为升序方便 UI 展示。
      final trimmed = rows.length > limit ? rows.sublist(0, limit) : rows;
      return trimmed.reversed.toList();
    });
  }

  /// 读取以指定消息为末尾的一页，用于从全历史搜索结果直接定位到尚未加载的消息。
  Future<List<ChatMessage>> listMessagesPageEndingAt({
    required String conversationId,
    required DateTime createdAt,
    required String id,
    int limit = 50,
  }) {
    final query = select(chatMessages)
      ..where((tbl) => tbl.conversationId.equals(conversationId))
      ..where(
        (tbl) =>
            tbl.createdAt.isSmallerThanValue(createdAt) |
            (tbl.createdAt.equals(createdAt) &
                (tbl.id.isSmallerThanValue(id) | tbl.id.equals(id))),
      )
      ..orderBy([
        (tbl) => OrderingTerm.desc(tbl.createdAt),
        (tbl) => OrderingTerm.desc(tbl.id),
      ])
      ..limit(limit);
    return query.get().then((rows) => rows.reversed.toList());
  }

  /// 计算会话在 lastReadAt 之后的未读消息数。lastReadAt 为空时全部计入。
  Future<int> unreadCount(String conversationId, {DateTime? lastReadAt}) async {
    final query = select(chatMessages)
      ..where((tbl) => tbl.conversationId.equals(conversationId))
      ..where((tbl) => tbl.direction.equals('in'));
    if (lastReadAt != null) {
      query.where((tbl) => tbl.createdAt.isBiggerThanValue(lastReadAt));
    }
    final count = await query.get().then((rows) => rows.length);
    return count;
  }

  /// 当前会话内搜索消息体/文件名，结果上限 100 条，按时间升序。
  Future<List<ChatMessage>> searchMessages(
    String conversationId,
    String query,
  ) async {
    final like = '%$query%';
    final rows =
        await (select(chatMessages)
              ..where((tbl) => tbl.conversationId.equals(conversationId))
              ..where(
                (tbl) => (tbl.body.like(like)) | (tbl.fileName.like(like)),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)])
              ..limit(100))
            .get();
    return rows;
  }

  /// 更新会话最后阅读时间，用于未读统计清零。
  Future<void> markConversationRead(String conversationId) async {
    await (update(conversations)..where((tbl) => tbl.id.equals(conversationId)))
        .write(ConversationsCompanion(lastReadAt: Value(DateTime.now())));
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

  Future<List<Transfer>> listReceivedTransfersForStorageMigration() {
    return (select(transfers)
          ..where(
            (tbl) =>
                tbl.direction.equals('in') &
                tbl.savedUri.isNull() &
                (tbl.savedPath.isNotNull() | tbl.filePath.isNotNull()),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();
  }

  Future<void> markTransferSaved({
    required String transferId,
    String? savedPath,
    String? savedUri,
    String? fileName,
    String? localFilePath,
  }) => transaction(() async {
    await (update(transfers)..where((tbl) => tbl.id.equals(transferId))).write(
      TransfersCompanion(
        savedPath: Value(savedPath),
        savedUri: Value(savedUri),
        fileName: fileName == null ? const Value.absent() : Value(fileName),
        filePath: localFilePath == null
            ? const Value.absent()
            : Value(localFilePath),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (fileName != null) {
      await (update(chatMessages)
            ..where((tbl) => tbl.transferId.equals(transferId)))
          .write(ChatMessagesCompanion(fileName: Value(fileName)));
    }
    if (localFilePath != null) {
      await (update(chatMessages)
            ..where((tbl) => tbl.transferId.equals(transferId)))
          .write(ChatMessagesCompanion(filePath: Value(localFilePath)));
    }
  });

  Future<void> renameReceivedTransfer({
    required String transferId,
    required String fileName,
    required String? mimeType,
    required String? savedPath,
    required String? savedUri,
    required String? relativePath,
  }) => transaction(() async {
    final now = DateTime.now();
    await (update(transfers)..where((tbl) => tbl.id.equals(transferId))).write(
      TransfersCompanion(
        fileName: Value(fileName),
        mimeType: Value(mimeType),
        savedPath: Value(savedPath),
        savedUri: Value(savedUri),
        filePath: savedUri == null && savedPath != null
            ? Value(savedPath)
            : const Value.absent(),
        relativePath: Value(relativePath),
        updatedAt: Value(now),
      ),
    );
    await (update(
      chatMessages,
    )..where((tbl) => tbl.transferId.equals(transferId))).write(
      ChatMessagesCompanion(
        fileName: Value(fileName),
        mimeType: Value(mimeType),
        filePath: savedUri == null && savedPath != null
            ? Value(savedPath)
            : const Value.absent(),
        relativePath: Value(relativePath),
      ),
    );
  });
}
