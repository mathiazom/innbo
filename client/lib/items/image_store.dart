import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Stores item photos on local disk, keyed by a generated filename.
/// Only the filename (not a full path) is persisted in the `image` table,
/// so the storage location can move without invalidating stored rows.
class ImageStore {
  static Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/images');
    await dir.create(recursive: true);
    return dir;
  }

  /// Copies [source] into local storage under a new generated filename,
  /// preserving its extension, and returns that filename.
  static Future<String> save(File source) async {
    final extension = source.path.contains('.')
        ? source.path.substring(source.path.lastIndexOf('.'))
        : '';
    final fileName = '${_uuid.v4()}$extension';
    final dir = await _dir();
    await source.copy('${dir.path}/$fileName');
    return fileName;
  }

  static Future<File> file(String fileName) async {
    final dir = await _dir();
    return File('${dir.path}/$fileName');
  }

  static Future<void> delete(String fileName) async {
    final target = await file(fileName);
    if (await target.exists()) {
      await target.delete();
    }
  }
}
