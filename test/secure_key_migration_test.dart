import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/services/identity_service.dart';
import 'package:localchat/services/secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // flutter_secure_storage 在测试里用内存模拟键值存储。
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'new identity stores private keys in secure storage, not DB plaintext',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final identity = IdentityService(
        db,
        secureKeyStore: const SecureKeyStore(),
      );
      final local = await identity.load();

      // 安全存储应持有私钥。
      final secure = const SecureKeyStore();
      expect(await secure.readSigningPrivateKey(), local.signingPrivateKey);
      expect(await secure.readExchangePrivateKey(), local.exchangePrivateKey);
      // 数据库中的明文私钥应为空占位。
      expect(await db.getSetting('identity.signing_private_key'), '');
      expect(await db.getSetting('identity.exchange_private_key'), '');
    },
  );

  test(
    'legacy plaintext private keys migrate to secure storage and are cleared',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // 模拟旧版本：把一套身份写进数据库（含明文私钥）。
      final legacy = IdentityService(db); // 不传 secureKeyStore，纯 DB
      final local = await legacy.load();
      final legacySigningPrivate = local.signingPrivateKey;
      final legacyExchangePrivate = local.exchangePrivateKey;
      expect(await db.getSetting('identity.signing_private_key'), isNotEmpty);

      // 升级：用带 secureKeyStore 的 IdentityService 重新加载。
      final migrated = IdentityService(
        db,
        secureKeyStore: const SecureKeyStore(),
      );
      final reloaded = await migrated.load();

      // 身份公钥/指纹不变。
      expect(reloaded.signingPublicKey, local.signingPublicKey);
      expect(reloaded.fingerprint, local.fingerprint);
      // 私钥已迁入安全存储，与旧明文一致。
      final secure = const SecureKeyStore();
      expect(await secure.readSigningPrivateKey(), legacySigningPrivate);
      expect(await secure.readExchangePrivateKey(), legacyExchangePrivate);
      // 数据库明文已清空。
      expect(await db.getSetting('identity.signing_private_key'), '');
      expect(await db.getSetting('identity.exchange_private_key'), '');
    },
  );

  test('identity is stable across reloads after migration', () async {
    final file = File(
      '${Directory.systemTemp.path}/localchat-secure-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final db = AppDatabase(NativeDatabase(file));
    final first = await IdentityService(
      db,
      secureKeyStore: const SecureKeyStore(),
    ).load();
    await db.close();

    // 模拟进程重启：新连接 + 已迁移的安全存储。
    FlutterSecureStorage.setMockInitialValues({
      'identity.signing_private_key': first.signingPrivateKey,
      'identity.exchange_private_key': first.exchangePrivateKey,
      'identity.keys_migrated': 'true',
    });
    final db2 = AppDatabase(NativeDatabase(file));
    addTearDown(db2.close);
    final second = await IdentityService(
      db2,
      secureKeyStore: const SecureKeyStore(),
    ).load();
    expect(second.deviceId, first.deviceId);
    expect(second.signingPublicKey, first.signingPublicKey);
    expect(second.fingerprint, first.fingerprint);
  });

  test(
    'missing secure keys fail closed instead of accepting DB placeholders',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secure = const SecureKeyStore();
      await IdentityService(db, secureKeyStore: secure).load();
      expect(await db.getSetting('identity.signing_private_key'), '');

      await secure.clearAll();

      await expectLater(
        IdentityService(db, secureKeyStore: secure).load(),
        throwsA(isA<StateError>()),
      );
    },
  );
}
