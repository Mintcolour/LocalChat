import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

bool isImageFile({String? mimeType, String? fileName, String? path}) {
  final mime = mimeType ?? lookupMimeType(path ?? fileName ?? '');
  if (mime != null && mime.startsWith('image/')) return true;
  final extension = p.extension(path ?? fileName ?? '').toLowerCase();
  return const {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  }.contains(extension);
}
