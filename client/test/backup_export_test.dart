import 'package:flutter_test/flutter_test.dart';
import 'package:innbo/backup/backup_export.dart';

void main() {
  test('missing images land in missingImages, not images', () {
    final manifest = buildManifest(
      rooms: [
        {'id': 'r1', 'name': 'Stue'},
      ],
      containers: [],
      items: [
        {
          'id': 'i1',
          'name': 'Lampe',
          'placement': null,
          'room_id': 'r1',
          'container_id': null,
        },
      ],
      images: [
        {
          'id': 'img1',
          'item_id': 'i1',
          'container_id': null,
          'room_id': null,
          'created_at': 1,
        },
        {
          'id': 'img2',
          'item_id': 'i1',
          'container_id': null,
          'room_id': null,
          'created_at': 2,
        },
      ],
      missingImageIds: ['img2'],
    );

    expect(manifest['schemaVersion'], 1);
    expect(manifest['rooms'], hasLength(1));
    expect(manifest['items'], hasLength(1));
    expect(manifest['images'], hasLength(2));
    expect(manifest['missingImages'], ['img2']);
  });

  test('backup file name is a sortable, filesystem-safe zip name', () {
    final name = backupFileName(DateTime.utc(2026, 8, 30, 14, 32, 5));
    expect(name, startsWith('innbo-backup-2026-08-30T14-32-05'));
    expect(name, endsWith('.zip'));
    expect(name, isNot(contains(':')));
  });
}
