import 'package:powersync/powersync.dart';

/// Mirrors backend/migrations/0001_init.sql's `room`/`item` tables. Column
/// names and types must match what the Go backend's /upload endpoint
/// accepts (internal/httpapi/upload.go's allowedColumns).
const schema = Schema([
  Table('room', [Column.text('name')]),
  Table('item', [Column.text('name'), Column.text('room_id')]),
]);
