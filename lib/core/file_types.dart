import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

enum FileCategory {
  images('Images'),
  videos('Videos'),
  documents('Documents'),
  audio('Audio'),
  archives('Archives'),
  apps('Apps'),
  others('Others');

  const FileCategory(this.folderName);

  final String folderName;
}

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

bool isEditableImageFile({String? mimeType, String? fileName, String? path}) {
  if (!isImageFile(mimeType: mimeType, fileName: fileName, path: path)) {
    return false;
  }
  return const {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  }.contains(p.extension(path ?? fileName ?? '').toLowerCase());
}

FileCategory fileCategoryFor({String? mimeType, String? fileName}) {
  final name = fileName ?? '';
  final mime = (mimeType ?? lookupMimeType(name) ?? '').toLowerCase();
  final extension = p.extension(name).toLowerCase();

  if (mime.startsWith('image/')) return FileCategory.images;
  if (mime.startsWith('video/')) return FileCategory.videos;
  if (mime.startsWith('audio/')) return FileCategory.audio;

  if (mime.startsWith('text/') ||
      const {
        '.pdf',
        '.doc',
        '.docx',
        '.xls',
        '.xlsx',
        '.ppt',
        '.pptx',
        '.odt',
        '.ods',
        '.odp',
        '.rtf',
        '.epub',
      }.contains(extension)) {
    return FileCategory.documents;
  }

  if (const {
    '.zip',
    '.rar',
    '.7z',
    '.tar',
    '.gz',
    '.bz2',
    '.xz',
  }.contains(extension)) {
    return FileCategory.archives;
  }

  if (const {
    '.apk',
    '.aab',
    '.exe',
    '.msi',
    '.msix',
    '.appx',
  }.contains(extension)) {
    return FileCategory.apps;
  }

  return FileCategory.others;
}
