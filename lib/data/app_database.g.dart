// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _signingPublicKeyMeta = const VerificationMeta(
    'signingPublicKey',
  );
  @override
  late final GeneratedColumn<String> signingPublicKey = GeneratedColumn<String>(
    'signing_public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exchangePublicKeyMeta = const VerificationMeta(
    'exchangePublicKey',
  );
  @override
  late final GeneratedColumn<String> exchangePublicKey =
      GeneratedColumn<String>(
        'exchange_public_key',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarSeedMeta = const VerificationMeta(
    'avatarSeed',
  );
  @override
  late final GeneratedColumn<String> avatarSeed = GeneratedColumn<String>(
    'avatar_seed',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avatarColorMeta = const VerificationMeta(
    'avatarColor',
  );
  @override
  late final GeneratedColumn<String> avatarColor = GeneratedColumn<String>(
    'avatar_color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#2563EB'),
  );
  static const VerificationMeta _trustedMeta = const VerificationMeta(
    'trusted',
  );
  @override
  late final GeneratedColumn<bool> trusted = GeneratedColumn<bool>(
    'trusted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("trusted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endpointSourceMeta = const VerificationMeta(
    'endpointSource',
  );
  @override
  late final GeneratedColumn<String> endpointSource = GeneratedColumn<String>(
    'endpoint_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('auto'),
  );
  static const VerificationMeta _capabilitiesMeta = const VerificationMeta(
    'capabilities',
  );
  @override
  late final GeneratedColumn<String> capabilities = GeneratedColumn<String>(
    'capabilities',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityChangedMeta = const VerificationMeta(
    'identityChanged',
  );
  @override
  late final GeneratedColumn<bool> identityChanged = GeneratedColumn<bool>(
    'identity_changed',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("identity_changed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    platform,
    host,
    port,
    signingPublicKey,
    exchangePublicKey,
    fingerprint,
    avatarSeed,
    avatarColor,
    trusted,
    lastSeen,
    createdAt,
    endpointSource,
    capabilities,
    identityChanged,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Device> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('signing_public_key')) {
      context.handle(
        _signingPublicKeyMeta,
        signingPublicKey.isAcceptableOrUnknown(
          data['signing_public_key']!,
          _signingPublicKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_signingPublicKeyMeta);
    }
    if (data.containsKey('exchange_public_key')) {
      context.handle(
        _exchangePublicKeyMeta,
        exchangePublicKey.isAcceptableOrUnknown(
          data['exchange_public_key']!,
          _exchangePublicKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exchangePublicKeyMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('avatar_seed')) {
      context.handle(
        _avatarSeedMeta,
        avatarSeed.isAcceptableOrUnknown(data['avatar_seed']!, _avatarSeedMeta),
      );
    }
    if (data.containsKey('avatar_color')) {
      context.handle(
        _avatarColorMeta,
        avatarColor.isAcceptableOrUnknown(
          data['avatar_color']!,
          _avatarColorMeta,
        ),
      );
    }
    if (data.containsKey('trusted')) {
      context.handle(
        _trustedMeta,
        trusted.isAcceptableOrUnknown(data['trusted']!, _trustedMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('endpoint_source')) {
      context.handle(
        _endpointSourceMeta,
        endpointSource.isAcceptableOrUnknown(
          data['endpoint_source']!,
          _endpointSourceMeta,
        ),
      );
    }
    if (data.containsKey('capabilities')) {
      context.handle(
        _capabilitiesMeta,
        capabilities.isAcceptableOrUnknown(
          data['capabilities']!,
          _capabilitiesMeta,
        ),
      );
    }
    if (data.containsKey('identity_changed')) {
      context.handle(
        _identityChangedMeta,
        identityChanged.isAcceptableOrUnknown(
          data['identity_changed']!,
          _identityChangedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      ),
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      ),
      signingPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signing_public_key'],
      )!,
      exchangePublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange_public_key'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      avatarSeed: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_seed'],
      )!,
      avatarColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_color'],
      )!,
      trusted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}trusted'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      endpointSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endpoint_source'],
      )!,
      capabilities: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capabilities'],
      ),
      identityChanged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}identity_changed'],
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class Device extends DataClass implements Insertable<Device> {
  final String id;
  final String displayName;
  final String platform;
  final String? host;
  final int? port;
  final String signingPublicKey;
  final String exchangePublicKey;
  final String fingerprint;
  final String avatarSeed;
  final String avatarColor;
  final bool trusted;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final String endpointSource;
  final String? capabilities;
  final bool? identityChanged;
  const Device({
    required this.id,
    required this.displayName,
    required this.platform,
    this.host,
    this.port,
    required this.signingPublicKey,
    required this.exchangePublicKey,
    required this.fingerprint,
    required this.avatarSeed,
    required this.avatarColor,
    required this.trusted,
    this.lastSeen,
    required this.createdAt,
    required this.endpointSource,
    this.capabilities,
    this.identityChanged,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['platform'] = Variable<String>(platform);
    if (!nullToAbsent || host != null) {
      map['host'] = Variable<String>(host);
    }
    if (!nullToAbsent || port != null) {
      map['port'] = Variable<int>(port);
    }
    map['signing_public_key'] = Variable<String>(signingPublicKey);
    map['exchange_public_key'] = Variable<String>(exchangePublicKey);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['avatar_seed'] = Variable<String>(avatarSeed);
    map['avatar_color'] = Variable<String>(avatarColor);
    map['trusted'] = Variable<bool>(trusted);
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<DateTime>(lastSeen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['endpoint_source'] = Variable<String>(endpointSource);
    if (!nullToAbsent || capabilities != null) {
      map['capabilities'] = Variable<String>(capabilities);
    }
    if (!nullToAbsent || identityChanged != null) {
      map['identity_changed'] = Variable<bool>(identityChanged);
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      id: Value(id),
      displayName: Value(displayName),
      platform: Value(platform),
      host: host == null && nullToAbsent ? const Value.absent() : Value(host),
      port: port == null && nullToAbsent ? const Value.absent() : Value(port),
      signingPublicKey: Value(signingPublicKey),
      exchangePublicKey: Value(exchangePublicKey),
      fingerprint: Value(fingerprint),
      avatarSeed: Value(avatarSeed),
      avatarColor: Value(avatarColor),
      trusted: Value(trusted),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
      createdAt: Value(createdAt),
      endpointSource: Value(endpointSource),
      capabilities: capabilities == null && nullToAbsent
          ? const Value.absent()
          : Value(capabilities),
      identityChanged: identityChanged == null && nullToAbsent
          ? const Value.absent()
          : Value(identityChanged),
    );
  }

  factory Device.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      platform: serializer.fromJson<String>(json['platform']),
      host: serializer.fromJson<String?>(json['host']),
      port: serializer.fromJson<int?>(json['port']),
      signingPublicKey: serializer.fromJson<String>(json['signingPublicKey']),
      exchangePublicKey: serializer.fromJson<String>(json['exchangePublicKey']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      avatarSeed: serializer.fromJson<String>(json['avatarSeed']),
      avatarColor: serializer.fromJson<String>(json['avatarColor']),
      trusted: serializer.fromJson<bool>(json['trusted']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      endpointSource: serializer.fromJson<String>(json['endpointSource']),
      capabilities: serializer.fromJson<String?>(json['capabilities']),
      identityChanged: serializer.fromJson<bool?>(json['identityChanged']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'platform': serializer.toJson<String>(platform),
      'host': serializer.toJson<String?>(host),
      'port': serializer.toJson<int?>(port),
      'signingPublicKey': serializer.toJson<String>(signingPublicKey),
      'exchangePublicKey': serializer.toJson<String>(exchangePublicKey),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'avatarSeed': serializer.toJson<String>(avatarSeed),
      'avatarColor': serializer.toJson<String>(avatarColor),
      'trusted': serializer.toJson<bool>(trusted),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'endpointSource': serializer.toJson<String>(endpointSource),
      'capabilities': serializer.toJson<String?>(capabilities),
      'identityChanged': serializer.toJson<bool?>(identityChanged),
    };
  }

  Device copyWith({
    String? id,
    String? displayName,
    String? platform,
    Value<String?> host = const Value.absent(),
    Value<int?> port = const Value.absent(),
    String? signingPublicKey,
    String? exchangePublicKey,
    String? fingerprint,
    String? avatarSeed,
    String? avatarColor,
    bool? trusted,
    Value<DateTime?> lastSeen = const Value.absent(),
    DateTime? createdAt,
    String? endpointSource,
    Value<String?> capabilities = const Value.absent(),
    Value<bool?> identityChanged = const Value.absent(),
  }) => Device(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    platform: platform ?? this.platform,
    host: host.present ? host.value : this.host,
    port: port.present ? port.value : this.port,
    signingPublicKey: signingPublicKey ?? this.signingPublicKey,
    exchangePublicKey: exchangePublicKey ?? this.exchangePublicKey,
    fingerprint: fingerprint ?? this.fingerprint,
    avatarSeed: avatarSeed ?? this.avatarSeed,
    avatarColor: avatarColor ?? this.avatarColor,
    trusted: trusted ?? this.trusted,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
    createdAt: createdAt ?? this.createdAt,
    endpointSource: endpointSource ?? this.endpointSource,
    capabilities: capabilities.present ? capabilities.value : this.capabilities,
    identityChanged: identityChanged.present
        ? identityChanged.value
        : this.identityChanged,
  );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      platform: data.platform.present ? data.platform.value : this.platform,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      signingPublicKey: data.signingPublicKey.present
          ? data.signingPublicKey.value
          : this.signingPublicKey,
      exchangePublicKey: data.exchangePublicKey.present
          ? data.exchangePublicKey.value
          : this.exchangePublicKey,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      avatarSeed: data.avatarSeed.present
          ? data.avatarSeed.value
          : this.avatarSeed,
      avatarColor: data.avatarColor.present
          ? data.avatarColor.value
          : this.avatarColor,
      trusted: data.trusted.present ? data.trusted.value : this.trusted,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      endpointSource: data.endpointSource.present
          ? data.endpointSource.value
          : this.endpointSource,
      capabilities: data.capabilities.present
          ? data.capabilities.value
          : this.capabilities,
      identityChanged: data.identityChanged.present
          ? data.identityChanged.value
          : this.identityChanged,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('platform: $platform, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('signingPublicKey: $signingPublicKey, ')
          ..write('exchangePublicKey: $exchangePublicKey, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('avatarSeed: $avatarSeed, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('trusted: $trusted, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('createdAt: $createdAt, ')
          ..write('endpointSource: $endpointSource, ')
          ..write('capabilities: $capabilities, ')
          ..write('identityChanged: $identityChanged')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    platform,
    host,
    port,
    signingPublicKey,
    exchangePublicKey,
    fingerprint,
    avatarSeed,
    avatarColor,
    trusted,
    lastSeen,
    createdAt,
    endpointSource,
    capabilities,
    identityChanged,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.platform == this.platform &&
          other.host == this.host &&
          other.port == this.port &&
          other.signingPublicKey == this.signingPublicKey &&
          other.exchangePublicKey == this.exchangePublicKey &&
          other.fingerprint == this.fingerprint &&
          other.avatarSeed == this.avatarSeed &&
          other.avatarColor == this.avatarColor &&
          other.trusted == this.trusted &&
          other.lastSeen == this.lastSeen &&
          other.createdAt == this.createdAt &&
          other.endpointSource == this.endpointSource &&
          other.capabilities == this.capabilities &&
          other.identityChanged == this.identityChanged);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String> platform;
  final Value<String?> host;
  final Value<int?> port;
  final Value<String> signingPublicKey;
  final Value<String> exchangePublicKey;
  final Value<String> fingerprint;
  final Value<String> avatarSeed;
  final Value<String> avatarColor;
  final Value<bool> trusted;
  final Value<DateTime?> lastSeen;
  final Value<DateTime> createdAt;
  final Value<String> endpointSource;
  final Value<String?> capabilities;
  final Value<bool?> identityChanged;
  final Value<int> rowid;
  const DevicesCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.platform = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.signingPublicKey = const Value.absent(),
    this.exchangePublicKey = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.avatarSeed = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.trusted = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.endpointSource = const Value.absent(),
    this.capabilities = const Value.absent(),
    this.identityChanged = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String id,
    required String displayName,
    required String platform,
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    required String signingPublicKey,
    required String exchangePublicKey,
    required String fingerprint,
    this.avatarSeed = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.trusted = const Value.absent(),
    this.lastSeen = const Value.absent(),
    required DateTime createdAt,
    this.endpointSource = const Value.absent(),
    this.capabilities = const Value.absent(),
    this.identityChanged = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       platform = Value(platform),
       signingPublicKey = Value(signingPublicKey),
       exchangePublicKey = Value(exchangePublicKey),
       fingerprint = Value(fingerprint),
       createdAt = Value(createdAt);
  static Insertable<Device> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? platform,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? signingPublicKey,
    Expression<String>? exchangePublicKey,
    Expression<String>? fingerprint,
    Expression<String>? avatarSeed,
    Expression<String>? avatarColor,
    Expression<bool>? trusted,
    Expression<DateTime>? lastSeen,
    Expression<DateTime>? createdAt,
    Expression<String>? endpointSource,
    Expression<String>? capabilities,
    Expression<bool>? identityChanged,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (platform != null) 'platform': platform,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (signingPublicKey != null) 'signing_public_key': signingPublicKey,
      if (exchangePublicKey != null) 'exchange_public_key': exchangePublicKey,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (avatarSeed != null) 'avatar_seed': avatarSeed,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (trusted != null) 'trusted': trusted,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (createdAt != null) 'created_at': createdAt,
      if (endpointSource != null) 'endpoint_source': endpointSource,
      if (capabilities != null) 'capabilities': capabilities,
      if (identityChanged != null) 'identity_changed': identityChanged,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String>? platform,
    Value<String?>? host,
    Value<int?>? port,
    Value<String>? signingPublicKey,
    Value<String>? exchangePublicKey,
    Value<String>? fingerprint,
    Value<String>? avatarSeed,
    Value<String>? avatarColor,
    Value<bool>? trusted,
    Value<DateTime?>? lastSeen,
    Value<DateTime>? createdAt,
    Value<String>? endpointSource,
    Value<String?>? capabilities,
    Value<bool?>? identityChanged,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      platform: platform ?? this.platform,
      host: host ?? this.host,
      port: port ?? this.port,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      exchangePublicKey: exchangePublicKey ?? this.exchangePublicKey,
      fingerprint: fingerprint ?? this.fingerprint,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      avatarColor: avatarColor ?? this.avatarColor,
      trusted: trusted ?? this.trusted,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
      endpointSource: endpointSource ?? this.endpointSource,
      capabilities: capabilities ?? this.capabilities,
      identityChanged: identityChanged ?? this.identityChanged,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (signingPublicKey.present) {
      map['signing_public_key'] = Variable<String>(signingPublicKey.value);
    }
    if (exchangePublicKey.present) {
      map['exchange_public_key'] = Variable<String>(exchangePublicKey.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (avatarSeed.present) {
      map['avatar_seed'] = Variable<String>(avatarSeed.value);
    }
    if (avatarColor.present) {
      map['avatar_color'] = Variable<String>(avatarColor.value);
    }
    if (trusted.present) {
      map['trusted'] = Variable<bool>(trusted.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (endpointSource.present) {
      map['endpoint_source'] = Variable<String>(endpointSource.value);
    }
    if (capabilities.present) {
      map['capabilities'] = Variable<String>(capabilities.value);
    }
    if (identityChanged.present) {
      map['identity_changed'] = Variable<bool>(identityChanged.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('platform: $platform, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('signingPublicKey: $signingPublicKey, ')
          ..write('exchangePublicKey: $exchangePublicKey, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('avatarSeed: $avatarSeed, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('trusted: $trusted, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('createdAt: $createdAt, ')
          ..write('endpointSource: $endpointSource, ')
          ..write('capabilities: $capabilities, ')
          ..write('identityChanged: $identityChanged, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDeviceIdMeta = const VerificationMeta(
    'peerDeviceId',
  );
  @override
  late final GeneratedColumn<String> peerDeviceId = GeneratedColumn<String>(
    'peer_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReadAt = GeneratedColumn<DateTime>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    peerDeviceId,
    title,
    updatedAt,
    lastReadAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('peer_device_id')) {
      context.handle(
        _peerDeviceIdMeta,
        peerDeviceId.isAcceptableOrUnknown(
          data['peer_device_id']!,
          _peerDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDeviceIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      peerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_read_at'],
      ),
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String id;
  final String peerDeviceId;
  final String title;
  final DateTime updatedAt;
  final DateTime? lastReadAt;
  const Conversation({
    required this.id,
    required this.peerDeviceId,
    required this.title,
    required this.updatedAt,
    this.lastReadAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['peer_device_id'] = Variable<String>(peerDeviceId);
    map['title'] = Variable<String>(title);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      peerDeviceId: Value(peerDeviceId),
      title: Value(title),
      updatedAt: Value(updatedAt),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      peerDeviceId: serializer.fromJson<String>(json['peerDeviceId']),
      title: serializer.fromJson<String>(json['title']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'peerDeviceId': serializer.toJson<String>(peerDeviceId),
      'title': serializer.toJson<String>(title),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
    };
  }

  Conversation copyWith({
    String? id,
    String? peerDeviceId,
    String? title,
    DateTime? updatedAt,
    Value<DateTime?> lastReadAt = const Value.absent(),
  }) => Conversation(
    id: id ?? this.id,
    peerDeviceId: peerDeviceId ?? this.peerDeviceId,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      peerDeviceId: data.peerDeviceId.present
          ? data.peerDeviceId.value
          : this.peerDeviceId,
      title: data.title.present ? data.title.value : this.title,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('title: $title, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastReadAt: $lastReadAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, peerDeviceId, title, updatedAt, lastReadAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.peerDeviceId == this.peerDeviceId &&
          other.title == this.title &&
          other.updatedAt == this.updatedAt &&
          other.lastReadAt == this.lastReadAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> peerDeviceId;
  final Value<String> title;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> lastReadAt;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.peerDeviceId = const Value.absent(),
    this.title = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    required String peerDeviceId,
    required String title,
    required DateTime updatedAt,
    this.lastReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       peerDeviceId = Value(peerDeviceId),
       title = Value(title),
       updatedAt = Value(updatedAt);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? peerDeviceId,
    Expression<String>? title,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastReadAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (peerDeviceId != null) 'peer_device_id': peerDeviceId,
      if (title != null) 'title': title,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? peerDeviceId,
    Value<String>? title,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? lastReadAt,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (peerDeviceId.present) {
      map['peer_device_id'] = Variable<String>(peerDeviceId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('title: $title, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDeviceIdMeta = const VerificationMeta(
    'peerDeviceId',
  );
  @override
  late final GeneratedColumn<String> peerDeviceId = GeneratedColumn<String>(
    'peer_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transferIdMeta = const VerificationMeta(
    'transferId',
  );
  @override
  late final GeneratedColumn<String> transferId = GeneratedColumn<String>(
    'transfer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    peerDeviceId,
    direction,
    kind,
    body,
    fileName,
    filePath,
    fileSize,
    mimeType,
    status,
    transferId,
    relativePath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('peer_device_id')) {
      context.handle(
        _peerDeviceIdMeta,
        peerDeviceId.isAcceptableOrUnknown(
          data['peer_device_id']!,
          _peerDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDeviceIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('transfer_id')) {
      context.handle(
        _transferIdMeta,
        transferId.isAcceptableOrUnknown(data['transfer_id']!, _transferIdMeta),
      );
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      peerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      transferId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_id'],
      ),
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final String id;
  final String conversationId;
  final String peerDeviceId;
  final String direction;
  final String kind;
  final String? body;
  final String? fileName;
  final String? filePath;
  final int? fileSize;
  final String? mimeType;
  final String status;
  final String? transferId;
  final String? relativePath;
  final DateTime createdAt;
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.peerDeviceId,
    required this.direction,
    required this.kind,
    this.body,
    this.fileName,
    this.filePath,
    this.fileSize,
    this.mimeType,
    required this.status,
    this.transferId,
    this.relativePath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['peer_device_id'] = Variable<String>(peerDeviceId);
    map['direction'] = Variable<String>(direction);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || transferId != null) {
      map['transfer_id'] = Variable<String>(transferId);
    }
    if (!nullToAbsent || relativePath != null) {
      map['relative_path'] = Variable<String>(relativePath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      peerDeviceId: Value(peerDeviceId),
      direction: Value(direction),
      kind: Value(kind),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      status: Value(status),
      transferId: transferId == null && nullToAbsent
          ? const Value.absent()
          : Value(transferId),
      relativePath: relativePath == null && nullToAbsent
          ? const Value.absent()
          : Value(relativePath),
      createdAt: Value(createdAt),
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      peerDeviceId: serializer.fromJson<String>(json['peerDeviceId']),
      direction: serializer.fromJson<String>(json['direction']),
      kind: serializer.fromJson<String>(json['kind']),
      body: serializer.fromJson<String?>(json['body']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      status: serializer.fromJson<String>(json['status']),
      transferId: serializer.fromJson<String?>(json['transferId']),
      relativePath: serializer.fromJson<String?>(json['relativePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'peerDeviceId': serializer.toJson<String>(peerDeviceId),
      'direction': serializer.toJson<String>(direction),
      'kind': serializer.toJson<String>(kind),
      'body': serializer.toJson<String?>(body),
      'fileName': serializer.toJson<String?>(fileName),
      'filePath': serializer.toJson<String?>(filePath),
      'fileSize': serializer.toJson<int?>(fileSize),
      'mimeType': serializer.toJson<String?>(mimeType),
      'status': serializer.toJson<String>(status),
      'transferId': serializer.toJson<String?>(transferId),
      'relativePath': serializer.toJson<String?>(relativePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? peerDeviceId,
    String? direction,
    String? kind,
    Value<String?> body = const Value.absent(),
    Value<String?> fileName = const Value.absent(),
    Value<String?> filePath = const Value.absent(),
    Value<int?> fileSize = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    String? status,
    Value<String?> transferId = const Value.absent(),
    Value<String?> relativePath = const Value.absent(),
    DateTime? createdAt,
  }) => ChatMessage(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    peerDeviceId: peerDeviceId ?? this.peerDeviceId,
    direction: direction ?? this.direction,
    kind: kind ?? this.kind,
    body: body.present ? body.value : this.body,
    fileName: fileName.present ? fileName.value : this.fileName,
    filePath: filePath.present ? filePath.value : this.filePath,
    fileSize: fileSize.present ? fileSize.value : this.fileSize,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    status: status ?? this.status,
    transferId: transferId.present ? transferId.value : this.transferId,
    relativePath: relativePath.present ? relativePath.value : this.relativePath,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      peerDeviceId: data.peerDeviceId.present
          ? data.peerDeviceId.value
          : this.peerDeviceId,
      direction: data.direction.present ? data.direction.value : this.direction,
      kind: data.kind.present ? data.kind.value : this.kind,
      body: data.body.present ? data.body.value : this.body,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      status: data.status.present ? data.status.value : this.status,
      transferId: data.transferId.present
          ? data.transferId.value
          : this.transferId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('direction: $direction, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('fileSize: $fileSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('status: $status, ')
          ..write('transferId: $transferId, ')
          ..write('relativePath: $relativePath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    peerDeviceId,
    direction,
    kind,
    body,
    fileName,
    filePath,
    fileSize,
    mimeType,
    status,
    transferId,
    relativePath,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.peerDeviceId == this.peerDeviceId &&
          other.direction == this.direction &&
          other.kind == this.kind &&
          other.body == this.body &&
          other.fileName == this.fileName &&
          other.filePath == this.filePath &&
          other.fileSize == this.fileSize &&
          other.mimeType == this.mimeType &&
          other.status == this.status &&
          other.transferId == this.transferId &&
          other.relativePath == this.relativePath &&
          other.createdAt == this.createdAt);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> peerDeviceId;
  final Value<String> direction;
  final Value<String> kind;
  final Value<String?> body;
  final Value<String?> fileName;
  final Value<String?> filePath;
  final Value<int?> fileSize;
  final Value<String?> mimeType;
  final Value<String> status;
  final Value<String?> transferId;
  final Value<String?> relativePath;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.peerDeviceId = const Value.absent(),
    this.direction = const Value.absent(),
    this.kind = const Value.absent(),
    this.body = const Value.absent(),
    this.fileName = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.status = const Value.absent(),
    this.transferId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String peerDeviceId,
    required String direction,
    required String kind,
    this.body = const Value.absent(),
    this.fileName = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.mimeType = const Value.absent(),
    required String status,
    this.transferId = const Value.absent(),
    this.relativePath = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       peerDeviceId = Value(peerDeviceId),
       direction = Value(direction),
       kind = Value(kind),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<ChatMessage> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? peerDeviceId,
    Expression<String>? direction,
    Expression<String>? kind,
    Expression<String>? body,
    Expression<String>? fileName,
    Expression<String>? filePath,
    Expression<int>? fileSize,
    Expression<String>? mimeType,
    Expression<String>? status,
    Expression<String>? transferId,
    Expression<String>? relativePath,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (peerDeviceId != null) 'peer_device_id': peerDeviceId,
      if (direction != null) 'direction': direction,
      if (kind != null) 'kind': kind,
      if (body != null) 'body': body,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
      if (fileSize != null) 'file_size': fileSize,
      if (mimeType != null) 'mime_type': mimeType,
      if (status != null) 'status': status,
      if (transferId != null) 'transfer_id': transferId,
      if (relativePath != null) 'relative_path': relativePath,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? peerDeviceId,
    Value<String>? direction,
    Value<String>? kind,
    Value<String?>? body,
    Value<String?>? fileName,
    Value<String?>? filePath,
    Value<int?>? fileSize,
    Value<String?>? mimeType,
    Value<String>? status,
    Value<String?>? transferId,
    Value<String?>? relativePath,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      direction: direction ?? this.direction,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      status: status ?? this.status,
      transferId: transferId ?? this.transferId,
      relativePath: relativePath ?? this.relativePath,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (peerDeviceId.present) {
      map['peer_device_id'] = Variable<String>(peerDeviceId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (transferId.present) {
      map['transfer_id'] = Variable<String>(transferId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('direction: $direction, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('fileSize: $fileSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('status: $status, ')
          ..write('transferId: $transferId, ')
          ..write('relativePath: $relativePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransfersTable extends Transfers
    with TableInfo<$TransfersTable, Transfer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDeviceIdMeta = const VerificationMeta(
    'peerDeviceId',
  );
  @override
  late final GeneratedColumn<String> peerDeviceId = GeneratedColumn<String>(
    'peer_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savedPathMeta = const VerificationMeta(
    'savedPath',
  );
  @override
  late final GeneratedColumn<String> savedPath = GeneratedColumn<String>(
    'saved_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savedUriMeta = const VerificationMeta(
    'savedUri',
  );
  @override
  late final GeneratedColumn<String> savedUri = GeneratedColumn<String>(
    'saved_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedBytesMeta = const VerificationMeta(
    'receivedBytes',
  );
  @override
  late final GeneratedColumn<int> receivedBytes = GeneratedColumn<int>(
    'received_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalChunksMeta = const VerificationMeta(
    'totalChunks',
  );
  @override
  late final GeneratedColumn<int> totalChunks = GeneratedColumn<int>(
    'total_chunks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    peerDeviceId,
    direction,
    fileName,
    filePath,
    fileSize,
    sha256,
    mimeType,
    savedPath,
    savedUri,
    status,
    receivedBytes,
    totalChunks,
    relativePath,
    groupId,
    errorCode,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Transfer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('peer_device_id')) {
      context.handle(
        _peerDeviceIdMeta,
        peerDeviceId.isAcceptableOrUnknown(
          data['peer_device_id']!,
          _peerDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDeviceIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('saved_path')) {
      context.handle(
        _savedPathMeta,
        savedPath.isAcceptableOrUnknown(data['saved_path']!, _savedPathMeta),
      );
    }
    if (data.containsKey('saved_uri')) {
      context.handle(
        _savedUriMeta,
        savedUri.isAcceptableOrUnknown(data['saved_uri']!, _savedUriMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('received_bytes')) {
      context.handle(
        _receivedBytesMeta,
        receivedBytes.isAcceptableOrUnknown(
          data['received_bytes']!,
          _receivedBytesMeta,
        ),
      );
    }
    if (data.containsKey('total_chunks')) {
      context.handle(
        _totalChunksMeta,
        totalChunks.isAcceptableOrUnknown(
          data['total_chunks']!,
          _totalChunksMeta,
        ),
      );
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transfer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transfer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      peerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      savedPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_path'],
      ),
      savedUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_uri'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      receivedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_bytes'],
      )!,
      totalChunks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_chunks'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TransfersTable createAlias(String alias) {
    return $TransfersTable(attachedDatabase, alias);
  }
}

class Transfer extends DataClass implements Insertable<Transfer> {
  final String id;
  final String peerDeviceId;
  final String direction;
  final String fileName;
  final String? filePath;
  final int fileSize;
  final String? sha256;
  final String? mimeType;
  final String? savedPath;
  final String? savedUri;
  final String status;
  final int receivedBytes;
  final int totalChunks;
  final String? relativePath;
  final String? groupId;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Transfer({
    required this.id,
    required this.peerDeviceId,
    required this.direction,
    required this.fileName,
    this.filePath,
    required this.fileSize,
    this.sha256,
    this.mimeType,
    this.savedPath,
    this.savedUri,
    required this.status,
    required this.receivedBytes,
    required this.totalChunks,
    this.relativePath,
    this.groupId,
    this.errorCode,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['peer_device_id'] = Variable<String>(peerDeviceId);
    map['direction'] = Variable<String>(direction);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    map['file_size'] = Variable<int>(fileSize);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || savedPath != null) {
      map['saved_path'] = Variable<String>(savedPath);
    }
    if (!nullToAbsent || savedUri != null) {
      map['saved_uri'] = Variable<String>(savedUri);
    }
    map['status'] = Variable<String>(status);
    map['received_bytes'] = Variable<int>(receivedBytes);
    map['total_chunks'] = Variable<int>(totalChunks);
    if (!nullToAbsent || relativePath != null) {
      map['relative_path'] = Variable<String>(relativePath);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TransfersCompanion toCompanion(bool nullToAbsent) {
    return TransfersCompanion(
      id: Value(id),
      peerDeviceId: Value(peerDeviceId),
      direction: Value(direction),
      fileName: Value(fileName),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      fileSize: Value(fileSize),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      savedPath: savedPath == null && nullToAbsent
          ? const Value.absent()
          : Value(savedPath),
      savedUri: savedUri == null && nullToAbsent
          ? const Value.absent()
          : Value(savedUri),
      status: Value(status),
      receivedBytes: Value(receivedBytes),
      totalChunks: Value(totalChunks),
      relativePath: relativePath == null && nullToAbsent
          ? const Value.absent()
          : Value(relativePath),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Transfer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transfer(
      id: serializer.fromJson<String>(json['id']),
      peerDeviceId: serializer.fromJson<String>(json['peerDeviceId']),
      direction: serializer.fromJson<String>(json['direction']),
      fileName: serializer.fromJson<String>(json['fileName']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      savedPath: serializer.fromJson<String?>(json['savedPath']),
      savedUri: serializer.fromJson<String?>(json['savedUri']),
      status: serializer.fromJson<String>(json['status']),
      receivedBytes: serializer.fromJson<int>(json['receivedBytes']),
      totalChunks: serializer.fromJson<int>(json['totalChunks']),
      relativePath: serializer.fromJson<String?>(json['relativePath']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'peerDeviceId': serializer.toJson<String>(peerDeviceId),
      'direction': serializer.toJson<String>(direction),
      'fileName': serializer.toJson<String>(fileName),
      'filePath': serializer.toJson<String?>(filePath),
      'fileSize': serializer.toJson<int>(fileSize),
      'sha256': serializer.toJson<String?>(sha256),
      'mimeType': serializer.toJson<String?>(mimeType),
      'savedPath': serializer.toJson<String?>(savedPath),
      'savedUri': serializer.toJson<String?>(savedUri),
      'status': serializer.toJson<String>(status),
      'receivedBytes': serializer.toJson<int>(receivedBytes),
      'totalChunks': serializer.toJson<int>(totalChunks),
      'relativePath': serializer.toJson<String?>(relativePath),
      'groupId': serializer.toJson<String?>(groupId),
      'errorCode': serializer.toJson<String?>(errorCode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Transfer copyWith({
    String? id,
    String? peerDeviceId,
    String? direction,
    String? fileName,
    Value<String?> filePath = const Value.absent(),
    int? fileSize,
    Value<String?> sha256 = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<String?> savedPath = const Value.absent(),
    Value<String?> savedUri = const Value.absent(),
    String? status,
    int? receivedBytes,
    int? totalChunks,
    Value<String?> relativePath = const Value.absent(),
    Value<String?> groupId = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Transfer(
    id: id ?? this.id,
    peerDeviceId: peerDeviceId ?? this.peerDeviceId,
    direction: direction ?? this.direction,
    fileName: fileName ?? this.fileName,
    filePath: filePath.present ? filePath.value : this.filePath,
    fileSize: fileSize ?? this.fileSize,
    sha256: sha256.present ? sha256.value : this.sha256,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    savedPath: savedPath.present ? savedPath.value : this.savedPath,
    savedUri: savedUri.present ? savedUri.value : this.savedUri,
    status: status ?? this.status,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalChunks: totalChunks ?? this.totalChunks,
    relativePath: relativePath.present ? relativePath.value : this.relativePath,
    groupId: groupId.present ? groupId.value : this.groupId,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Transfer copyWithCompanion(TransfersCompanion data) {
    return Transfer(
      id: data.id.present ? data.id.value : this.id,
      peerDeviceId: data.peerDeviceId.present
          ? data.peerDeviceId.value
          : this.peerDeviceId,
      direction: data.direction.present ? data.direction.value : this.direction,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      savedPath: data.savedPath.present ? data.savedPath.value : this.savedPath,
      savedUri: data.savedUri.present ? data.savedUri.value : this.savedUri,
      status: data.status.present ? data.status.value : this.status,
      receivedBytes: data.receivedBytes.present
          ? data.receivedBytes.value
          : this.receivedBytes,
      totalChunks: data.totalChunks.present
          ? data.totalChunks.value
          : this.totalChunks,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transfer(')
          ..write('id: $id, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('direction: $direction, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('fileSize: $fileSize, ')
          ..write('sha256: $sha256, ')
          ..write('mimeType: $mimeType, ')
          ..write('savedPath: $savedPath, ')
          ..write('savedUri: $savedUri, ')
          ..write('status: $status, ')
          ..write('receivedBytes: $receivedBytes, ')
          ..write('totalChunks: $totalChunks, ')
          ..write('relativePath: $relativePath, ')
          ..write('groupId: $groupId, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    peerDeviceId,
    direction,
    fileName,
    filePath,
    fileSize,
    sha256,
    mimeType,
    savedPath,
    savedUri,
    status,
    receivedBytes,
    totalChunks,
    relativePath,
    groupId,
    errorCode,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transfer &&
          other.id == this.id &&
          other.peerDeviceId == this.peerDeviceId &&
          other.direction == this.direction &&
          other.fileName == this.fileName &&
          other.filePath == this.filePath &&
          other.fileSize == this.fileSize &&
          other.sha256 == this.sha256 &&
          other.mimeType == this.mimeType &&
          other.savedPath == this.savedPath &&
          other.savedUri == this.savedUri &&
          other.status == this.status &&
          other.receivedBytes == this.receivedBytes &&
          other.totalChunks == this.totalChunks &&
          other.relativePath == this.relativePath &&
          other.groupId == this.groupId &&
          other.errorCode == this.errorCode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TransfersCompanion extends UpdateCompanion<Transfer> {
  final Value<String> id;
  final Value<String> peerDeviceId;
  final Value<String> direction;
  final Value<String> fileName;
  final Value<String?> filePath;
  final Value<int> fileSize;
  final Value<String?> sha256;
  final Value<String?> mimeType;
  final Value<String?> savedPath;
  final Value<String?> savedUri;
  final Value<String> status;
  final Value<int> receivedBytes;
  final Value<int> totalChunks;
  final Value<String?> relativePath;
  final Value<String?> groupId;
  final Value<String?> errorCode;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TransfersCompanion({
    this.id = const Value.absent(),
    this.peerDeviceId = const Value.absent(),
    this.direction = const Value.absent(),
    this.fileName = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.savedPath = const Value.absent(),
    this.savedUri = const Value.absent(),
    this.status = const Value.absent(),
    this.receivedBytes = const Value.absent(),
    this.totalChunks = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.groupId = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransfersCompanion.insert({
    required String id,
    required String peerDeviceId,
    required String direction,
    required String fileName,
    this.filePath = const Value.absent(),
    required int fileSize,
    this.sha256 = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.savedPath = const Value.absent(),
    this.savedUri = const Value.absent(),
    required String status,
    this.receivedBytes = const Value.absent(),
    this.totalChunks = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.groupId = const Value.absent(),
    this.errorCode = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       peerDeviceId = Value(peerDeviceId),
       direction = Value(direction),
       fileName = Value(fileName),
       fileSize = Value(fileSize),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Transfer> custom({
    Expression<String>? id,
    Expression<String>? peerDeviceId,
    Expression<String>? direction,
    Expression<String>? fileName,
    Expression<String>? filePath,
    Expression<int>? fileSize,
    Expression<String>? sha256,
    Expression<String>? mimeType,
    Expression<String>? savedPath,
    Expression<String>? savedUri,
    Expression<String>? status,
    Expression<int>? receivedBytes,
    Expression<int>? totalChunks,
    Expression<String>? relativePath,
    Expression<String>? groupId,
    Expression<String>? errorCode,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (peerDeviceId != null) 'peer_device_id': peerDeviceId,
      if (direction != null) 'direction': direction,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
      if (fileSize != null) 'file_size': fileSize,
      if (sha256 != null) 'sha256': sha256,
      if (mimeType != null) 'mime_type': mimeType,
      if (savedPath != null) 'saved_path': savedPath,
      if (savedUri != null) 'saved_uri': savedUri,
      if (status != null) 'status': status,
      if (receivedBytes != null) 'received_bytes': receivedBytes,
      if (totalChunks != null) 'total_chunks': totalChunks,
      if (relativePath != null) 'relative_path': relativePath,
      if (groupId != null) 'group_id': groupId,
      if (errorCode != null) 'error_code': errorCode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransfersCompanion copyWith({
    Value<String>? id,
    Value<String>? peerDeviceId,
    Value<String>? direction,
    Value<String>? fileName,
    Value<String?>? filePath,
    Value<int>? fileSize,
    Value<String?>? sha256,
    Value<String?>? mimeType,
    Value<String?>? savedPath,
    Value<String?>? savedUri,
    Value<String>? status,
    Value<int>? receivedBytes,
    Value<int>? totalChunks,
    Value<String?>? relativePath,
    Value<String?>? groupId,
    Value<String?>? errorCode,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TransfersCompanion(
      id: id ?? this.id,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      direction: direction ?? this.direction,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      sha256: sha256 ?? this.sha256,
      mimeType: mimeType ?? this.mimeType,
      savedPath: savedPath ?? this.savedPath,
      savedUri: savedUri ?? this.savedUri,
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalChunks: totalChunks ?? this.totalChunks,
      relativePath: relativePath ?? this.relativePath,
      groupId: groupId ?? this.groupId,
      errorCode: errorCode ?? this.errorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (peerDeviceId.present) {
      map['peer_device_id'] = Variable<String>(peerDeviceId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (savedPath.present) {
      map['saved_path'] = Variable<String>(savedPath.value);
    }
    if (savedUri.present) {
      map['saved_uri'] = Variable<String>(savedUri.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (receivedBytes.present) {
      map['received_bytes'] = Variable<int>(receivedBytes.value);
    }
    if (totalChunks.present) {
      map['total_chunks'] = Variable<int>(totalChunks.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransfersCompanion(')
          ..write('id: $id, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('direction: $direction, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('fileSize: $fileSize, ')
          ..write('sha256: $sha256, ')
          ..write('mimeType: $mimeType, ')
          ..write('savedPath: $savedPath, ')
          ..write('savedUri: $savedUri, ')
          ..write('status: $status, ')
          ..write('receivedBytes: $receivedBytes, ')
          ..write('totalChunks: $totalChunks, ')
          ..write('relativePath: $relativePath, ')
          ..write('groupId: $groupId, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $TransfersTable transfers = $TransfersTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    devices,
    conversations,
    chatMessages,
    transfers,
    settings,
  ];
}

typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      required String id,
      required String displayName,
      required String platform,
      Value<String?> host,
      Value<int?> port,
      required String signingPublicKey,
      required String exchangePublicKey,
      required String fingerprint,
      Value<String> avatarSeed,
      Value<String> avatarColor,
      Value<bool> trusted,
      Value<DateTime?> lastSeen,
      required DateTime createdAt,
      Value<String> endpointSource,
      Value<String?> capabilities,
      Value<bool?> identityChanged,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<String> platform,
      Value<String?> host,
      Value<int?> port,
      Value<String> signingPublicKey,
      Value<String> exchangePublicKey,
      Value<String> fingerprint,
      Value<String> avatarSeed,
      Value<String> avatarColor,
      Value<bool> trusted,
      Value<DateTime?> lastSeen,
      Value<DateTime> createdAt,
      Value<String> endpointSource,
      Value<String?> capabilities,
      Value<bool?> identityChanged,
      Value<int> rowid,
    });

class $$DevicesTableFilterComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signingPublicKey => $composableBuilder(
    column: $table.signingPublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchangePublicKey => $composableBuilder(
    column: $table.exchangePublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarSeed => $composableBuilder(
    column: $table.avatarSeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get trusted => $composableBuilder(
    column: $table.trusted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endpointSource => $composableBuilder(
    column: $table.endpointSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get identityChanged => $composableBuilder(
    column: $table.identityChanged,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signingPublicKey => $composableBuilder(
    column: $table.signingPublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchangePublicKey => $composableBuilder(
    column: $table.exchangePublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarSeed => $composableBuilder(
    column: $table.avatarSeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get trusted => $composableBuilder(
    column: $table.trusted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endpointSource => $composableBuilder(
    column: $table.endpointSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get identityChanged => $composableBuilder(
    column: $table.identityChanged,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get signingPublicKey => $composableBuilder(
    column: $table.signingPublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exchangePublicKey => $composableBuilder(
    column: $table.exchangePublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarSeed => $composableBuilder(
    column: $table.avatarSeed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get trusted =>
      $composableBuilder(column: $table.trusted, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get endpointSource => $composableBuilder(
    column: $table.endpointSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get identityChanged => $composableBuilder(
    column: $table.identityChanged,
    builder: (column) => column,
  );
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DevicesTable,
          Device,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (Device, BaseReferences<_$AppDatabase, $DevicesTable, Device>),
          Device,
          PrefetchHooks Function()
        > {
  $$DevicesTableTableManager(_$AppDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<String?> host = const Value.absent(),
                Value<int?> port = const Value.absent(),
                Value<String> signingPublicKey = const Value.absent(),
                Value<String> exchangePublicKey = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String> avatarSeed = const Value.absent(),
                Value<String> avatarColor = const Value.absent(),
                Value<bool> trusted = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> endpointSource = const Value.absent(),
                Value<String?> capabilities = const Value.absent(),
                Value<bool?> identityChanged = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                id: id,
                displayName: displayName,
                platform: platform,
                host: host,
                port: port,
                signingPublicKey: signingPublicKey,
                exchangePublicKey: exchangePublicKey,
                fingerprint: fingerprint,
                avatarSeed: avatarSeed,
                avatarColor: avatarColor,
                trusted: trusted,
                lastSeen: lastSeen,
                createdAt: createdAt,
                endpointSource: endpointSource,
                capabilities: capabilities,
                identityChanged: identityChanged,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required String platform,
                Value<String?> host = const Value.absent(),
                Value<int?> port = const Value.absent(),
                required String signingPublicKey,
                required String exchangePublicKey,
                required String fingerprint,
                Value<String> avatarSeed = const Value.absent(),
                Value<String> avatarColor = const Value.absent(),
                Value<bool> trusted = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                required DateTime createdAt,
                Value<String> endpointSource = const Value.absent(),
                Value<String?> capabilities = const Value.absent(),
                Value<bool?> identityChanged = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                id: id,
                displayName: displayName,
                platform: platform,
                host: host,
                port: port,
                signingPublicKey: signingPublicKey,
                exchangePublicKey: exchangePublicKey,
                fingerprint: fingerprint,
                avatarSeed: avatarSeed,
                avatarColor: avatarColor,
                trusted: trusted,
                lastSeen: lastSeen,
                createdAt: createdAt,
                endpointSource: endpointSource,
                capabilities: capabilities,
                identityChanged: identityChanged,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DevicesTable,
      Device,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (Device, BaseReferences<_$AppDatabase, $DevicesTable, Device>),
      Device,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String id,
      required String peerDeviceId,
      required String title,
      required DateTime updatedAt,
      Value<DateTime?> lastReadAt,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> id,
      Value<String> peerDeviceId,
      Value<String> title,
      Value<DateTime> updatedAt,
      Value<DateTime?> lastReadAt,
      Value<int> rowid,
    });

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (
            Conversation,
            BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>,
          ),
          Conversation,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> peerDeviceId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                peerDeviceId: peerDeviceId,
                title: title,
                updatedAt: updatedAt,
                lastReadAt: lastReadAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String peerDeviceId,
                required String title,
                required DateTime updatedAt,
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                peerDeviceId: peerDeviceId,
                title: title,
                updatedAt: updatedAt,
                lastReadAt: lastReadAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (
        Conversation,
        BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>,
      ),
      Conversation,
      PrefetchHooks Function()
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      required String id,
      required String conversationId,
      required String peerDeviceId,
      required String direction,
      required String kind,
      Value<String?> body,
      Value<String?> fileName,
      Value<String?> filePath,
      Value<int?> fileSize,
      Value<String?> mimeType,
      required String status,
      Value<String?> transferId,
      Value<String?> relativePath,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> peerDeviceId,
      Value<String> direction,
      Value<String> kind,
      Value<String?> body,
      Value<String?> fileName,
      Value<String?> filePath,
      Value<int?> fileSize,
      Value<String?> mimeType,
      Value<String> status,
      Value<String?> transferId,
      Value<String?> relativePath,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMessagesTable,
          ChatMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessage,
            BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>,
          ),
          ChatMessage,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$AppDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> peerDeviceId = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> transferId = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                conversationId: conversationId,
                peerDeviceId: peerDeviceId,
                direction: direction,
                kind: kind,
                body: body,
                fileName: fileName,
                filePath: filePath,
                fileSize: fileSize,
                mimeType: mimeType,
                status: status,
                transferId: transferId,
                relativePath: relativePath,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String peerDeviceId,
                required String direction,
                required String kind,
                Value<String?> body = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                required String status,
                Value<String?> transferId = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                peerDeviceId: peerDeviceId,
                direction: direction,
                kind: kind,
                body: body,
                fileName: fileName,
                filePath: filePath,
                fileSize: fileSize,
                mimeType: mimeType,
                status: status,
                transferId: transferId,
                relativePath: relativePath,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMessagesTable,
      ChatMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessage,
        BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>,
      ),
      ChatMessage,
      PrefetchHooks Function()
    >;
typedef $$TransfersTableCreateCompanionBuilder =
    TransfersCompanion Function({
      required String id,
      required String peerDeviceId,
      required String direction,
      required String fileName,
      Value<String?> filePath,
      required int fileSize,
      Value<String?> sha256,
      Value<String?> mimeType,
      Value<String?> savedPath,
      Value<String?> savedUri,
      required String status,
      Value<int> receivedBytes,
      Value<int> totalChunks,
      Value<String?> relativePath,
      Value<String?> groupId,
      Value<String?> errorCode,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TransfersTableUpdateCompanionBuilder =
    TransfersCompanion Function({
      Value<String> id,
      Value<String> peerDeviceId,
      Value<String> direction,
      Value<String> fileName,
      Value<String?> filePath,
      Value<int> fileSize,
      Value<String?> sha256,
      Value<String?> mimeType,
      Value<String?> savedPath,
      Value<String?> savedUri,
      Value<String> status,
      Value<int> receivedBytes,
      Value<int> totalChunks,
      Value<String?> relativePath,
      Value<String?> groupId,
      Value<String?> errorCode,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$TransfersTableFilterComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savedPath => $composableBuilder(
    column: $table.savedPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savedUri => $composableBuilder(
    column: $table.savedUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalChunks => $composableBuilder(
    column: $table.totalChunks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransfersTableOrderingComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savedPath => $composableBuilder(
    column: $table.savedPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savedUri => $composableBuilder(
    column: $table.savedUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalChunks => $composableBuilder(
    column: $table.totalChunks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransfersTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get savedPath =>
      $composableBuilder(column: $table.savedPath, builder: (column) => column);

  GeneratedColumn<String> get savedUri =>
      $composableBuilder(column: $table.savedUri, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalChunks => $composableBuilder(
    column: $table.totalChunks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TransfersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransfersTable,
          Transfer,
          $$TransfersTableFilterComposer,
          $$TransfersTableOrderingComposer,
          $$TransfersTableAnnotationComposer,
          $$TransfersTableCreateCompanionBuilder,
          $$TransfersTableUpdateCompanionBuilder,
          (Transfer, BaseReferences<_$AppDatabase, $TransfersTable, Transfer>),
          Transfer,
          PrefetchHooks Function()
        > {
  $$TransfersTableTableManager(_$AppDatabase db, $TransfersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> peerDeviceId = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> savedPath = const Value.absent(),
                Value<String?> savedUri = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> receivedBytes = const Value.absent(),
                Value<int> totalChunks = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransfersCompanion(
                id: id,
                peerDeviceId: peerDeviceId,
                direction: direction,
                fileName: fileName,
                filePath: filePath,
                fileSize: fileSize,
                sha256: sha256,
                mimeType: mimeType,
                savedPath: savedPath,
                savedUri: savedUri,
                status: status,
                receivedBytes: receivedBytes,
                totalChunks: totalChunks,
                relativePath: relativePath,
                groupId: groupId,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String peerDeviceId,
                required String direction,
                required String fileName,
                Value<String?> filePath = const Value.absent(),
                required int fileSize,
                Value<String?> sha256 = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> savedPath = const Value.absent(),
                Value<String?> savedUri = const Value.absent(),
                required String status,
                Value<int> receivedBytes = const Value.absent(),
                Value<int> totalChunks = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TransfersCompanion.insert(
                id: id,
                peerDeviceId: peerDeviceId,
                direction: direction,
                fileName: fileName,
                filePath: filePath,
                fileSize: fileSize,
                sha256: sha256,
                mimeType: mimeType,
                savedPath: savedPath,
                savedUri: savedUri,
                status: status,
                receivedBytes: receivedBytes,
                totalChunks: totalChunks,
                relativePath: relativePath,
                groupId: groupId,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransfersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransfersTable,
      Transfer,
      $$TransfersTableFilterComposer,
      $$TransfersTableOrderingComposer,
      $$TransfersTableAnnotationComposer,
      $$TransfersTableCreateCompanionBuilder,
      $$TransfersTableUpdateCompanionBuilder,
      (Transfer, BaseReferences<_$AppDatabase, $TransfersTable, Transfer>),
      Transfer,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$TransfersTableTableManager get transfers =>
      $$TransfersTableTableManager(_db, _db.transfers);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
