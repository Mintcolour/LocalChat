import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 系统安全存储层：把身份私钥迁移到 Android Keystore / Windows DPAPI，替代
/// 明文存于 SQLite（计划 P0：身份私钥明文存于 SQLite）。
///
/// 旧版本私钥仍可能残留在数据库 settings 表中；迁移成功后由 IdentityService 调用
/// [clearLegacyPlaintext] 删除。读取时优先取安全存储，回退到旧明文以兼容升级路径。
class SecureKeyStore {
  const SecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const _signingPrivateKeyKey = 'identity.signing_private_key';
  static const _exchangePrivateKeyKey = 'identity.exchange_private_key';
  static const _migratedKey = 'identity.keys_migrated';

  Future<String?> readSigningPrivateKey() =>
      _storage.read(key: _signingPrivateKeyKey);

  Future<String?> readExchangePrivateKey() =>
      _storage.read(key: _exchangePrivateKeyKey);

  Future<void> writeSigningPrivateKey(String value) =>
      _storage.write(key: _signingPrivateKeyKey, value: value);

  Future<void> writeExchangePrivateKey(String value) =>
      _storage.write(key: _exchangePrivateKeyKey, value: value);

  Future<bool> isMigrated() async =>
      (await _storage.read(key: _migratedKey)) == 'true';

  Future<void> markMigrated() => _storage.write(key: _migratedKey, value: 'true');

  /// 迁移成功后清空安全存储里的迁移标记（用于重置/测试）。
  Future<void> clearAll() => _storage.deleteAll();
}
