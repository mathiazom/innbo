import 'package:powersync/powersync.dart';

/// Mirrors backend/migrations/0001_init.sql's `room`/`item` tables. Column
/// names and types must match what the Go backend's /upload endpoint
/// accepts (internal/httpapi/upload.go's allowedColumns).
const schema = Schema([
  Table('room', [Column.text('name')]),
  Table('item', [Column.text('name'), Column.text('room_id')]),
  // Local-only: attached photos never sync to the backend, so this table
  // isn't in backend/migrations or upload.go's allowedColumns.
  Table.localOnly('image', [
    Column.text('item_id'),
    Column.text('file_name'),
    Column.integer('created_at'), // epoch millis; determines cover order
  ], indexes: [
    Index('image_item_id', [IndexedColumn.ascending('item_id')]),
  ]),
]);
