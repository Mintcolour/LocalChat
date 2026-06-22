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
    final existingDeviceId = await _db.getSetting('identity.device_id');
    if (existingDeviceId != null) {
      var signingPrivate = await _secureKeyStore?.readSigningPrivateKey();
      var exchangePrivate = await _secureKeyStore?.readExchangePrivateKey();
      final legacySigningPrivate = await _db.getSetting(
        'identity.signing_private_key',
      );
      final legacyExchangePrivate = await _db.getSetting(
        'identity.exchange_private_key',
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
      if (signingPrivate != null &&
          signingPublic != null &&
          exchangePrivate != null &&
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
            (migrated || !(await _secureKeyStore.isMigrated()))) {
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
