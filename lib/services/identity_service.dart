import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../core/device_profile.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/protocol.dart';
import 'secure_key_store.dart';

class IdentityService {
  IdentityService(this._db, {SecureKeyStore? secureKeyStore})
    // ignore: prefer_initializing_formals
    : _secureKeyStore = secureKeyStore;

  final AppDatabase _db;
  // ignore: prefer_initializing_formals
  final SecureKeyStore? _secureKeyStore;
  final _signing = Ed25519();
  final _exchange = X25519();

  LocalIdentity? _identity;
  SimpleKeyPair? _signingKeyPair;
  SimpleKeyPair? _exchangeKeyPair;
  bool _identityResetDuringLoad = false;
  String? _identityResetReason;

  bool get identityResetDuringLoad => _identityResetDuringLoad;
  String? get identityResetReason => _identityResetReason;

  LocalIdentity get identity {
    final value = _identity;
    if (value == null) {
      throw StateError('Identity has not been loaded.');
    }
    return value;
  }

  SimpleKeyPair get signingKeyPair {
    final value = _signingKeyPair;
    if (value == null) {
      throw StateError('Signing key pair has not been loaded.');
    }
    return value;
  }

  SimpleKeyPair get exchangeKeyPair {
    final value = _exchangeKeyPair;
    if (value == null) {
      throw StateError('Exchange key pair has not been loaded.');
    }
    return value;
  }

  Future<LocalIdentity> load() async {
    _identityResetDuringLoad = false;
    _identityResetReason = null;
    final existingDeviceId = await _db.getSetting('identity.device_id');
    if (existingDeviceId != null) {
      var secureStoreUnavailable = false;
      String? secureStoreError;
      var signingPrivate = _nonEmpty(
        await _readSecurePrivateKey(
          () async => _secureKeyStore == null
              ? null
              : await _secureKeyStore.readSigningPrivateKey(),
          onUnavailable: (error) {
            secureStoreUnavailable = true;
            secureStoreError = error;
          },
        ),
      );
      var exchangePrivate = _nonEmpty(
        await _readSecurePrivateKey(
          () async => _secureKeyStore == null
              ? null
              : await _secureKeyStore.readExchangePrivateKey(),
          onUnavailable: (error) {
            secureStoreUnavailable = true;
            secureStoreError = error;
          },
        ),
      );
      final legacySigningPrivate = _nonEmpty(
        await _db.getSetting('identity.signing_private_key'),
      );
      final legacyExchangePrivate = _nonEmpty(
        await _db.getSetting('identity.exchange_private_key'),
      );
      var migrated = false;
      if (signingPrivate == null && legacySigningPrivate != null) {
        signingPrivate = legacySigningPrivate;
        migrated = true;
      }
      if (exchangePrivate == null && legacyExchangePrivate != null) {
        exchangePrivate = legacyExchangePrivate;
        migrated = true;
      }
      final signingPublic = await _db.getSetting('identity.signing_public_key');
      final exchangePublic = await _db.getSetting(
        'identity.exchange_public_key',
      );
      final displayName = await _db.getSetting('identity.display_name');
      final platform = await _db.getSetting('identity.platform');
      final fingerprint = await _db.getSetting('identity.fingerprint');
      var avatarSeed = await _db.getSetting('identity.avatar_seed');
      var avatarColor = await _db.getSetting('identity.avatar_color');
      if (signingPrivate == null || exchangePrivate == null) {
        if (_secureKeyStore != null) {
          await _resetUnreadableSecureIdentity(
            secureStoreError ?? 'Stored identity private keys are unavailable.',
          );
        } else {
          throw StateError(
            'Stored identity private keys are unavailable. Reset the local '
            'identity and pair devices again.',
          );
        }
      } else if (secureStoreUnavailable) {
        await _clearUnreadableSecureStore();
      }
      if (signingPrivate != null &&
          exchangePrivate != null &&
          signingPublic != null &&
          exchangePublic != null &&
          displayName != null &&
          platform != null &&
          fingerprint != null) {
        avatarSeed ??= avatarSeedFor(existingDeviceId, fingerprint);
        avatarColor ??= avatarColorFor(avatarSeed);
        await _db.setSetting('identity.avatar_seed', avatarSeed);
        await _db.setSetting('identity.avatar_color', avatarColor);
        // 迁移：把私钥写入系统安全存储并清除数据库明文（仅当安全存储可用时）。
        if (_secureKeyStore != null &&
            (secureStoreUnavailable ||
                migrated ||
                !(await _secureKeyStore.isMigrated()))) {
          await _secureKeyStore.writeSigningPrivateKey(signingPrivate);
          await _secureKeyStore.writeExchangePrivateKey(exchangePrivate);
          await _db.setSetting('identity.signing_private_key', '');
          await _db.setSetting('identity.exchange_private_key', '');
          await _secureKeyStore.markMigrated();
        }
        _signingKeyPair = SimpleKeyPairData(
          unb64(signingPrivate),
          publicKey: SimplePublicKey(
            unb64(signingPublic),
            type: KeyPairType.ed25519,
          ),
          type: KeyPairType.ed25519,
        );
        _exchangeKeyPair = SimpleKeyPairData(
          unb64(exchangePrivate),
          publicKey: SimplePublicKey(
            unb64(exchangePublic),
            type: KeyPairType.x25519,
          ),
          type: KeyPairType.x25519,
        );
        return _identity = LocalIdentity(
          deviceId: existingDeviceId,
          displayName: displayName,
          platform: platform,
          signingPrivateKey: signingPrivate,
          signingPublicKey: signingPublic,
          exchangePrivateKey: exchangePrivate,
          exchangePublicKey: exchangePublic,
          fingerprint: fingerprint,
          avatarSeed: avatarSeed,
          avatarColor: avatarColor,
        );
      }
    }

    final signingKeyPair = await _signing.newKeyPair();
    final exchangeKeyPair = await _exchange.newKeyPair();
    final signingPrivate = b64(await signingKeyPair.extractPrivateKeyBytes());
    final exchangePrivate = b64(await exchangeKeyPair.extractPrivateKeyBytes());
    final signingPublic = b64((await signingKeyPair.extractPublicKey()).bytes);
    final exchangePublic = b64(
      (await exchangeKeyPair.extractPublicKey()).bytes,
    );
    final fingerprint = sha256Hex(unb64(signingPublic));
    final deviceId = fingerprint.substring(0, 20);
    final platform = Platform.operatingSystem;
    final displayName = defaultDeviceNickname(platform, fingerprint);
    final avatarSeed = avatarSeedFor(deviceId, fingerprint);
    final avatarColor = avatarColorFor(avatarSeed);

    await _db.setSetting('identity.device_id', deviceId);
    await _db.setSetting('identity.display_name', displayName);
    await _db.setSetting('identity.avatar_seed', avatarSeed);
    await _db.setSetting('identity.avatar_color', avatarColor);
    await _db.setSetting('identity.platform', platform);
    // 私钥写入系统安全存储（若可用）；数据库只留公钥与空占位，避免明文落盘。
    if (_secureKeyStore != null) {
      await _secureKeyStore.writeSigningPrivateKey(signingPrivate);
      await _secureKeyStore.writeExchangePrivateKey(exchangePrivate);
      await _secureKeyStore.markMigrated();
      await _db.setSetting('identity.signing_private_key', '');
      await _db.setSetting('identity.exchange_private_key', '');
    } else {
      await _db.setSetting('identity.signing_private_key', signingPrivate);
      await _db.setSetting('identity.exchange_private_key', exchangePrivate);
    }
    await _db.setSetting('identity.signing_public_key', signingPublic);
    await _db.setSetting('identity.exchange_public_key', exchangePublic);
    await _db.setSetting('identity.fingerprint', fingerprint);

    _signingKeyPair = signingKeyPair;
    _exchangeKeyPair = exchangeKeyPair;
    return _identity = LocalIdentity(
      deviceId: deviceId,
      displayName: displayName,
      platform: platform,
      signingPrivateKey: signingPrivate,
      signingPublicKey: signingPublic,
      exchangePrivateKey: exchangePrivate,
      exchangePublicKey: exchangePublic,
      fingerprint: fingerprint,
      avatarSeed: avatarSeed,
      avatarColor: avatarColor,
    );
  }

  String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  Future<String?> _readSecurePrivateKey(
    Future<String?> Function() read, {
    required void Function(String error) onUnavailable,
  }) async {
    try {
      return await read();
    } on SecureKeyStoreException catch (error) {
      if (!error.isDataProtectionFailure) rethrow;
      onUnavailable(error.message);
      return null;
    }
  }

  Future<void> _resetUnreadableSecureIdentity(String reason) async {
    await _clearUnreadableSecureStore();
    _identityResetDuringLoad = true;
    _identityResetReason = reason;
  }

  Future<void> _clearUnreadableSecureStore() async {
    try {
      await _secureKeyStore?.clearAll();
    } on SecureKeyStoreException {
      // If the secure storage entry cannot be read, delete is best-effort. The
      // following writes will replace the keys needed by the new identity.
    }
  }

  Future<LocalIdentity> updateDisplayName(String displayName) async {
    final current = identity;
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return current;
    await _db.setSetting('identity.display_name', trimmed);
    return _identity = LocalIdentity(
      deviceId: current.deviceId,
      displayName: trimmed,
      platform: current.platform,
      signingPrivateKey: current.signingPrivateKey,
      signingPublicKey: current.signingPublicKey,
      exchangePrivateKey: current.exchangePrivateKey,
      exchangePublicKey: current.exchangePublicKey,
      fingerprint: current.fingerprint,
      avatarSeed: current.avatarSeed,
      avatarColor: current.avatarColor,
    );
  }
}
