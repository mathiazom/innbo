import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:share_plus/share_plus.dart';

import '../items/image_store.dart';

/// Builds the JSON manifest for a backup export from already-fetched rows.
/// Kept separate from the database/file IO in [buildBackupZip] so this,
/// the only piece with actual branching logic, can be unit-tested directly.
Map<String, dynamic> buildManifest({
  required List<Map<String, dynamic>> rooms,
  required List<Map<String, dynamic>> containers,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> images,
  required List<String> missingImageIds,
}) {
  return {
    'schemaVersion': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'rooms': rooms,
    'containers': containers,
    'items': items,
    'images': images,
    'missingImages': missingImageIds,
  };
}

String backupFileName(DateTime now) =>
    'innbo-backup-${now.toIso8601String().replaceAll(RegExp('[:.]'), '-')}.zip';

/// Reads the current local replica (rooms/containers/items/images) and
/// bundles it, along with every full-res image this device has cached
/// locally, into a zip file in the OS temp directory — a share-and-discard
/// artifact, not app state, so it doesn't belong in
/// getApplicationSupportDirectory (see ImageStore, which uses that
/// directory for the persistent local image cache instead).
Future<File> buildBackupZip(PowerSyncDatabase db) async {
  final rooms = await db.getAll('SELECT id, name FROM room ORDER BY name');
  final containers = await db.getAll(
    'SELECT id, name, room_id, parent_container_id FROM container ORDER BY name',
  );
  final items = await db.getAll(
    'SELECT id, name, placement, room_id, container_id FROM item ORDER BY name',
  );
  final imageRows = await db.getAll(
    'SELECT id, item_id, container_id, room_id, created_at FROM image ORDER BY created_at',
  );

  final archive = Archive();
  final missingImageIds = <String>[];
  for (final row in imageRows) {
    final id = row['id'] as String;
    final file = await ImageStore.localFullFile(id);
    if (!await file.exists()) {
      missingImageIds.add(id);
      continue;
    }
    final bytes = await file.readAsBytes();
    // ImageStore keys local files by id with no extension (format is
    // determined from content, not filename — see
    // docs/adr/0006-image-storage-and-sync.md), but a human browsing this
    // zip needs one to open the file directly. The server always
    // re-encodes to JPEG regardless of upload format
    // (backend/internal/httpapi/images.go's encodeTo/imaging.JPEG), so
    // ".jpg" is correct unconditionally, no content-sniffing needed.
    archive.addFile(ArchiveFile('images/$id.jpg', bytes.length, bytes));
  }

  final manifest = buildManifest(
    rooms: rooms,
    containers: containers,
    items: items,
    images: imageRows,
    missingImageIds: missingImageIds,
  );
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  archive.addFile(
    ArchiveFile('data.json', manifestBytes.length, manifestBytes),
  );

  final zipBytes = ZipEncoder().encode(archive);
  final tempDir = await getTemporaryDirectory();
  await tempDir.create(recursive: true);
  final zipFile = File('${tempDir.path}/${backupFileName(DateTime.now())}');
  await zipFile.writeAsBytes(zipBytes);
  return zipFile;
}

/// Builds the backup zip and hands it to the OS share sheet — shared by
/// [BackupScreen] and the stale-queue guard's "Sikkerhetskopier" action in
/// main.dart, so both go through the exact same export+share step.
Future<void> exportAndShareBackup(PowerSyncDatabase db) async {
  final file = await buildBackupZip(db);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}
