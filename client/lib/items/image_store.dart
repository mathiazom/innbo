import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stores item photos on local disk, keyed by the `image` row's own id —
/// the same id the backend uses for its `<storageDir>/<id>/{full,thumb}`
/// layout (see backend/internal/httpapi/images.go), so no separate
/// filename/content-type needs to be tracked or synced.
class ImageStore {
  static Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/images');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> localFullFile(String id) async =>
      File('${(await _dir()).path}/$id.full');

  static Future<File> localThumbFile(String id) async =>
      File('${(await _dir()).path}/$id.thumb');

  /// Copies [source] into local storage as the full-res image for [id].
  static Future<void> saveFull(String id, File source) async {
    await source.copy((await localFullFile(id)).path);
  }

  static Future<void> delete(String id) async {
    for (final file in [await localFullFile(id), await localThumbFile(id)]) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
