import 'package:powersync/powersync.dart';

/// Mirrors backend/migrations/0001_init.sql's `room`/`item` tables. Column
/// names and types must match what the Go backend's /upload endpoint
/// accepts (internal/httpapi/upload.go's allowedColumns).
const schema = Schema([
  Table('room', [Column.text('name')]),
  Table('item', [Column.text('name'), Column.text('room_id')]),
  // See backend/migrations/0002_image.sql and upload.go's allowedColumns.
  // No file_name/content_type column: files are stored/served keyed by
  // this row's own id, sniffed by content rather than extension (see
  // ImageStore/backend's images.go) — see docs/adr/0006.
  Table('image', [
    Column.text('item_id'),
    Column.integer('created_at'), // epoch millis; determines cover order
  ], indexes: [
    Index('image_item_id', [IndexedColumn.ascending('item_id')]),
  ]),
]);
