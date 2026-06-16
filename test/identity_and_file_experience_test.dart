import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/core/device_profile.dart';
import 'package:localchat/core/file_types.dart';
import 'package:localchat/data/app_database.dart';

void main() {
  test('default nickname is stable and platform specific', () {
    expect(defaultDeviceNickname('windows', 'abcdef012345'), 'Windows电脑-ABCD');
    expect(defaultDeviceNickname('android', '1234ef'), 'Android手机-1234');
  });

  test('avatar seed and color are stable for a device', () {
    final seed = avatarSeedFor('device-1', 'abcdef0123456789');
    expect(seed, avatarSeedFor('device-1', 'abcdef0123456789'));
    expect(avatarColorFor(seed), avatarColorFor(seed));
    expect(avatarColorFor(seed), startsWith('#'));
  });

  test('image files can be detected by mime type or extension', () {
    expect(isImageFile(mimeType: 'image/png', fileName: 'a.bin'), isTrue);
    expect(isImageFile(fileName: 'photo.webp'), isTrue);
    expect(isImageFile(fileName: 'package.apk'), isFalse);
  });

  test('transfer saved location is persisted', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.transfers)
        .insert(
          TransfersCompanion.insert(
            id: 'transfer-1',
            peerDeviceId: 'peer-1',
            direction: 'in',
            fileName: 'app.apk',
            fileSize: 1024,
            status: 'received',
            mimeType: const Value('application/vnd.android.package-archive'),
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

    await db.markTransferSaved(
      transferId: 'transfer-1',
      savedPath: r'C:\Users\me\Downloads\LocalChat\app.apk',
      savedUri: null,
    );

    final transfer = (await db.listTransfersByIds(['transfer-1'])).single;
    expect(transfer.savedPath, contains('Downloads'));
    expect(transfer.mimeType, 'application/vnd.android.package-archive');
  });
}
