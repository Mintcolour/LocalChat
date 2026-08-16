import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef SecureKeyRead = Future<String?> Function(String key);
typedef SecureKeyWrite = Future<void> Function(String key, String value);
typedef SecureKeyDeleteAll = Future<void> Function();

class SecureKeyStoreException implements Exception {
  const SecureKeyStoreException(this.operation, this.message, this.cause);

  final String operation;
  final String message;
  final Object cause;

  bool get isDataProtectionFailure {
    final lower = message.toLowerCase();
    return lower.contains('cryptunprotectdata') ||
        lower.contains('data protection') ||
        lower.contains('dpapi');
  }

  @override
  String toString() => 'SecureKeyStoreException($operation): $message';
}

/// 系统安全存储层：把身份私钥迁移到 Android Keystore / Windows DPAPI，替代
/// 明文存于 SQLite（计划 P0：身份私钥明文存于 SQLite）。
///
/// 旧版本私钥仍可能残留在数据库 settings 表中；迁移成功后由 IdentityService 调用
/// [clearLegacyPlaintext] 删除。读取时优先取安全存储，回退到旧明文以兼容升级路径。
class SecureKeyStore {
  const SecureKeyStore({
    FlutterSecureStorage? storage,
    SecureKeyRead? readOverride,
    SecureKeyWrite? writeOverride,
    SecureKeyDeleteAll? deleteAllOverride,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           ),
       // ignore: prefer_initializing_formals
       _readOverride = readOverride,
       // ignore: prefer_initializing_formals
       _writeOverride = writeOverride,
       // ignore: prefer_initializing_formals
       _deleteAllOverride = deleteAllOverride;

  final FlutterSecureStorage _storage;
  final SecureKeyRead? _readOverride;
  final SecureKeyWrite? _writeOverride;
  final SecureKeyDeleteAll? _deleteAllOverride;

  static const _signingPrivateKeyKey = 'identity.signing_private_key';
  static const _exchangePrivateKeyKey = 'identity.exchange_private_key';
  static const _migratedKey = 'identity.keys_migrated';

  Future<String?> readSigningPrivateKey() =>
      _read(_signingPrivateKeyKey, 'read_signing_private_key');

  Future<String?> readExchangePrivateKey() =>
      _read(_exchangePrivateKeyKey, 'read_exchange_private_key');

  Future<void> writeSigningPrivateKey(String value) =>
      _write(_signingPrivateKeyKey, value, 'write_signing_private_key');

  Future<void> writeExchangePrivateKey(String value) =>
      _write(_exchangePrivateKeyKey, value, 'write_exchange_private_key');

  Future<bool> isMigrated() async =>
      (await _read(_migratedKey, 'read_migrated_flag')) == 'true';

  Future<void> markMigrated() =>
      _write(_migratedKey, 'true', 'write_migrated_flag');

  /// 迁移成功后清空安全存储里的迁移标记（用于重置/测试）。
  Future<void> clearAll() => _guard('delete_all', () {
    final override = _deleteAllOverride;
    if (override != null) return override();
    return _storage.deleteAll();
  });

  Future<String?> _read(String key, String operation) => _guard(operation, () {
    final override = _readOverride;
    if (override != null) return override(key);
    return _storage.read(key: key);
  });

  Future<void> _write(String key, String value, String operation) =>
      _guard(operation, () {
        final override = _writeOverride;
        if (override != null) return override(key, value);
        return _storage.write(key: key, value: value);
      });

  Future<T> _guard<T>(String operation, Future<T> Function() callback) async {
    try {
      return await callback();
    } on PlatformException catch (error) {
      throw SecureKeyStoreException(
        operation,
        error.message ?? error.code,
        error,
      );
    } catch (error) {
      final text = '$error';
      if (text.contains('CryptUnprotectData') ||
          text.toLowerCase().contains('dpapi')) {
        throw SecureKeyStoreException(operation, text, error);
      }
      rethrow;
    }
  }
}
