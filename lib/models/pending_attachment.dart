import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../core/file_types.dart';

class PendingAttachment {
  const PendingAttachment({
    required this.originalPath,
    required this.path,
    this.edited = false,
  });

  factory PendingAttachment.fromPath(String path) =>
      PendingAttachment(originalPath: path, path: path);

  final String originalPath;
  final String path;
  final bool edited;

  String get fileName => p.basename(path);
  String? get mimeType => lookupMimeType(path);
  bool get isImage => isImageFile(mimeType: mimeType, path: path);
  bool get isEditableImage =>
      isEditableImageFile(mimeType: mimeType, path: path);

  PendingAttachment withEditedPath(String value) =>
      PendingAttachment(originalPath: originalPath, path: value, edited: true);
}

class PendingAttachmentBatch {
  const PendingAttachmentBatch({required this.id, required this.items});

  final int id;
  final List<PendingAttachment> items;
}
