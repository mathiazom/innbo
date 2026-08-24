import 'package:powersync/powersync.dart';

/// Mirrors the Postgres schema in backend/migrations/. Column names and
/// types must match what the Go backend's /upload endpoint accepts
/// (internal/httpapi/upload.go's allowedColumns).
const schema = Schema([
  Table('room', [Column.text('name')]),
  Table('item', [
    Column.text('name'),
    Column.text('room_id'),
    Column.text('placement'),
  ]),
  // See backend/migrations/0002_image.sql and upload.go's allowedColumns.
  // No file_name/content_type column: files are stored/served keyed by
  // this row's own id, sniffed by content rather than extension (see
  // ImageStore/backend's images.go) — see docs/adr/0006.
  Table(
    'image',
    [
      Column.text('item_id'),
      Column.integer('created_at'), // epoch millis; determines cover order
    ],
    indexes: [
      Index('image_item_id', [IndexedColumn.ascending('item_id')]),
    ],
  ),
  // See backend/migrations/0004_paired_device.sql. No revoked_at column:
  // this client doesn't act on revocation yet, so it's left out of the
  // synced subset until a revoke UI needs it.
  Table('paired_device', [
    Column.text('device_id'),
    Column.text('name'),
    Column.text('platform'),
    Column.integer('last_sync_at'), // epoch millis
    Column.integer('image_completeness_pct'),
    Column.integer('pending_upload_count'),
    Column.integer('failed_upload_count'),
  ]),
]);
