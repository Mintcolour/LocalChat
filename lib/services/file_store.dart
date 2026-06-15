import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileStore {
  Future<Directory> receiveDirectory() async {
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        final dir = Directory(p.join(profile, 'Downloads', 'LocalChat'));
        await dir.create(recursive: true);
        return dir;
      }
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'LocalChat'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> createReceiveFile(String fileName) async {
    final dir = await receiveDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var candidate = File(p.join(dir.path, safeName));
    if (!await candidate.exists()) return candidate;
    final extension = p.extension(safeName);
    final stem = p.basenameWithoutExtension(safeName);
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(dir.path, '$stem ($index)$extension'));
      index++;
    }
    return candidate;
  }
}
