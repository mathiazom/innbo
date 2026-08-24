import 'package:flutter/foundation.dart' show debugPrint;
import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show ResultSet;

import '../device_credentials.dart';
import 'image_store.dart';
import 'image_sync.dart';

/// A single image's retry-queue state, as seen by e.g. a per-image badge.
enum UploadStatus {
  /// Not in the queue at all — either uploaded successfully, or never
  /// attempted.
  none,

  /// Queued, waiting for its next retry attempt.
  pending,

  /// Retries exhausted; needs a manual reset to try again.
  failed,
}

/// Household-wide pending/failed upload counts for one device — see
/// paired_device.pending_upload_count/failed_upload_count.
class UploadCounts {
  final int pending;
  final int failed;

  const UploadCounts({required this.pending, required this.failed});
}

/// Backoff before each retry attempt, indexed by the attempt number just
/// completed (attempt 1 failed -> wait backoff[0] before attempt 2, etc.).
/// Spread over real time rather than "one try per resume" so a few minutes
/// of app-switching during one transient network blip doesn't burn through
/// the whole cap.
const _backoff = [
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 30),
  Duration(hours: 2),
  Duration(days: 1),
];

/// Durable retry queue for `ImageSync.uploadFull`, since a single failed
/// attempt there is otherwise never retried once its caller's one-shot
/// SnackBar is dismissed (see docs/BACKLOG.md's persistent-retry-queue
/// item). Backed by a local-only SQLite table — not part of `schema.dart`,
/// so it's never synced — since upload progress is inherently per-device.
class UploadQueue {
  static const _table = 'upload_queue';

  static const _metaTable = 'upload_queue_meta';

  static Future<void> ensureTable(PowerSyncDatabase db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_table ('
      'image_id TEXT PRIMARY KEY, '
      'attempts INTEGER NOT NULL DEFAULT 0, '
      'next_attempt_at INTEGER NOT NULL, '
      'failed INTEGER NOT NULL DEFAULT 0)',
    );
    // Tracks whether backfill() has ever run — a successful upload
    // deletes its row from $_table, so "not currently in $_table" can't
    // by itself mean "never confirmed uploaded" on a later run; without
    // this marker, backfill would re-enqueue every already-succeeded
    // image on every single app start, forever.
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_metaTable (backfilled INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      'INSERT INTO $_metaTable (backfilled) '
      'SELECT 0 WHERE NOT EXISTS (SELECT 1 FROM $_metaTable)',
    );
  }

  static Future<void> enqueue(PowerSyncDatabase db, String imageId) async {
    await db.execute(
      'INSERT OR REPLACE INTO $_table (image_id, attempts, next_attempt_at, failed) '
      'VALUES (?, 0, ?, 0)',
      [imageId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  static Future<void> resetForManualRetry(
    PowerSyncDatabase db,
    String imageId,
  ) async {
    await db.execute(
      'UPDATE $_table SET attempts = 0, failed = 0, next_attempt_at = ? '
      'WHERE image_id = ?',
      [DateTime.now().millisecondsSinceEpoch, imageId],
    );
  }

  /// Catches images that predate this feature: any synced `image` row
  /// with a local full-res file whose upload was never confirmed. Runs
  /// at most once ever (see $_metaTable) — a local file's mere presence
  /// can't distinguish "never uploaded" from "uploaded successfully
  /// years ago," so this can only safely run before anything's had a
  /// chance to succeed and leave the queue. Images added going forward
  /// are enqueued explicitly by their caller on upload failure instead.
  static Future<void> backfill(PowerSyncDatabase db) async {
    final meta = await db.get('SELECT backfilled FROM $_metaTable');
    if ((meta['backfilled'] as int) != 0) return;

    final rows = await db.getAll(
      'SELECT id FROM image WHERE id NOT IN (SELECT image_id FROM $_table)',
    );
    for (final row in rows) {
      final id = row['id'] as String;
      final file = await ImageStore.localFullFile(id);
      if (!await file.exists() || await file.length() == 0) continue;
      await enqueue(db, id);
    }
    await db.execute('UPDATE $_metaTable SET backfilled = 1');
  }

  static Future<UploadCounts> counts(PowerSyncDatabase db) async {
    final row = await db.get(
      'SELECT COUNT(*) FILTER (WHERE failed = 0) AS pending, '
      'COUNT(*) FILTER (WHERE failed = 1) AS failed FROM $_table',
    );
    return UploadCounts(
      pending: row['pending'] as int,
      failed: row['failed'] as int,
    );
  }

  static Stream<UploadStatus> statusStream(
    PowerSyncDatabase db,
    String imageId,
  ) {
    return db
        .watch(
          'SELECT failed FROM $_table WHERE image_id = ?',
          parameters: [imageId],
        )
        .map(_statusFromRows);
  }

  static UploadStatus _statusFromRows(ResultSet rows) {
    if (rows.isEmpty) return UploadStatus.none;
    return (rows[0]['failed'] as int) != 0
        ? UploadStatus.failed
        : UploadStatus.pending;
  }

  /// Uploads every image whose backoff has elapsed. Call on app resume.
  static Future<void> retryDue(
    PowerSyncDatabase db,
    DeviceCredentials credentials,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.getAll(
      'SELECT image_id, attempts FROM $_table WHERE failed = 0 AND next_attempt_at <= ?',
      [now],
    );
    debugPrint('UploadQueue.retryDue: ${rows.length} image(s) due');
    for (final row in rows) {
      await _attempt(
        db,
        credentials,
        row['image_id'] as String,
        row['attempts'] as int,
      );
    }
  }

  /// Uploads every currently-pending image immediately, ignoring
  /// next_attempt_at — an on-demand escape hatch for telling "genuinely
  /// stuck" apart from "still waiting out its backoff" (see retryDue).
  static Future<void> retryAllNow(
    PowerSyncDatabase db,
    DeviceCredentials credentials,
  ) async {
    final rows = await db.getAll(
      'SELECT image_id, attempts FROM $_table WHERE failed = 0',
    );
    debugPrint('UploadQueue.retryAllNow: ${rows.length} pending image(s)');
    for (final row in rows) {
      await _attempt(
        db,
        credentials,
        row['image_id'] as String,
        row['attempts'] as int,
      );
    }
  }

  static Future<void> _attempt(
    PowerSyncDatabase db,
    DeviceCredentials credentials,
    String imageId,
    int attempts,
  ) async {
    final uploaded = await ImageSync.uploadFull(credentials, imageId);
    if (uploaded) {
      await db.execute('DELETE FROM $_table WHERE image_id = ?', [imageId]);
      return;
    }
    final nextAttempts = attempts + 1;
    if (nextAttempts >= _backoff.length) {
      await db.execute(
        'UPDATE $_table SET attempts = ?, failed = 1 WHERE image_id = ?',
        [nextAttempts, imageId],
      );
    } else {
      final nextAttemptAt = DateTime.now()
          .add(_backoff[attempts])
          .millisecondsSinceEpoch;
      await db.execute(
        'UPDATE $_table SET attempts = ?, next_attempt_at = ? WHERE image_id = ?',
        [nextAttempts, nextAttemptAt, imageId],
      );
    }
  }
}
