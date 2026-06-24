import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/services/file_store.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileStore.sanitizeRelativeDirs', () {
    test('null or empty returns no segments', () {
      expect(FileStore.sanitizeRelativeDirs(null), isEmpty);
      expect(FileStore.sanitizeRelativeDirs(''), isEmpty);
    });

    test('drops the trailing filename segment, keeps directory segments', () {
      // 输入 "root/sub/file.txt" → 目录段 ["root", "sub"]，文件名由调用方单独传入。
      expect(FileStore.sanitizeRelativeDirs('root/sub/file.txt'), [
        'root',
        'sub',
      ]);
    });

    test('single segment (root file) yields no directory segments', () {
      expect(FileStore.sanitizeRelativeDirs('file.txt'), isEmpty);
    });

    test('strips path traversal and dot segments', () {
      expect(FileStore.sanitizeRelativeDirs('../root/../sub/./file.txt'), [
        'root',
        'sub',
      ]);
    });

    test('cleans illegal filename characters per segment', () {
      // 每段单独清洗，分隔符不会被保留为路径穿越入口。
      expect(FileStore.sanitizeRelativeDirs('ro:ot/su<b/fi>le.txt'), [
        'ro_ot',
        'su_b',
      ]);
    });

    test(
      'backslashes are treated as illegal characters within a single segment',
      () {
        // 无 POSIX / 分隔时整串是一个段，反斜杠被清洗，removeLast 后无目录段。
        expect(FileStore.sanitizeRelativeDirs(r'root\sub\file.txt'), isEmpty);
      },
    );

    test('empty segments between slashes are dropped', () {
      expect(FileStore.sanitizeRelativeDirs('root//sub/file.txt'), [
        'root',
        'sub',
      ]);
    });
  });

  group('FileStore destination and rename rules', () {
    test(
      'standalone files are classified below the conversation and month',
      () {
        expect(
          FileStore.destinationSubpath(
            conversationFolder: 'Phone',
            at: DateTime(2026, 6, 22),
            fileName: 'photo.png',
            mimeType: 'image/png',
          ).replaceAll(r'\', '/'),
          'Phone/26/06/Images',
        );
      },
    );

    test('folder transfers stay under Others and preserve directories', () {
      expect(
        FileStore.destinationSubpath(
          conversationFolder: 'Phone',
          at: DateTime(2026, 6, 22),
          fileName: 'report.pdf',
          mimeType: 'application/pdf',
          relativePath: 'project/docs/report.pdf',
        ).replaceAll(r'\', '/'),
        'Phone/26/06/Others/project/docs',
      );
    });

    test('renaming a folder file changes only the last path segment', () {
      expect(
        FileStore.replaceRelativeFileName(
          'project/docs/report.pdf',
          'final.docx',
        ),
        'project/docs/final.docx',
      );
    });

    test('file name validation rejects unsafe and reserved names', () {
      expect(FileStore.validateFileName(''), 'empty');
      expect(FileStore.validateFileName('../report.pdf'), 'invalid');
      expect(FileStore.validateFileName('CON.txt'), 'reserved');
      expect(FileStore.validateFileName('report. '), 'trailing');
      expect(FileStore.validateFileName('report.pdf'), isNull);
    });
  });

  group('FileStore storage root rules', () {
    test('uses a configured Windows storage root', () async {
      if (!Platform.isWindows) return;
      final root = await Directory.systemTemp.createTemp('localchat-root');
      addTearDown(() => root.delete(recursive: true));
      final store = FileStore()..setStorageRootPath(root.path);

      expect(
        FileStore.isSamePath(await store.currentStorageRootPath(), root.path),
        isTrue,
      );
      final prepared = await store.prepareStorageRootDirectory(root.path);
      expect(FileStore.isSamePath(prepared.path, root.path), isTrue);
    });

    test('rejects relative custom storage roots on Windows', () async {
      if (!Platform.isWindows) return;
      final store = FileStore();

      expect(
        () => store.prepareStorageRootDirectory(p.join('relative', 'folder')),
        throwsA(isA<FormatException>()),
      );
    });

    test('creates unique names inside a target directory', () async {
      final root = await Directory.systemTemp.createTemp('localchat-unique');
      addTearDown(() => root.delete(recursive: true));
      await File(p.join(root.path, 'report.txt')).writeAsString('old');
      final store = FileStore();

      final target = await store.uniqueFileInDirectory(root, 'report.txt');

      expect(p.basename(target.path), 'report (1).txt');
    });
  });
}
