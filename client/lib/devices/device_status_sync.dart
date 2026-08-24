import 'package:powersync/powersync.dart';

import '../device_credentials.dart';
import '../items/upload_queue.dart';
import 'image_completeness.dart';

/// Recomputes and writes this device's own paired_device row — see
/// backend/migrations/0004_paired_device.sql. Called on app foreground and
/// whenever the device overview screen opens; there's no background job for
/// this yet (see docs/BACKLOG.md's background image sync item).
Future<void> refreshDeviceStatus(
  PowerSyncDatabase db,
  DeviceCredentials credentials,
) async {
  final lastSyncedAt = db.currentStatus.lastSyncedAt;
  final completenessPct = await computeImageCompletenessPct(db);
  final uploadCounts = await UploadQueue.counts(db);
  await db.execute(
    'UPDATE paired_device SET last_sync_at = ?, image_completeness_pct = ?, '
    'pending_upload_count = ?, failed_upload_count = ? WHERE device_id = ?',
    [
      lastSyncedAt?.millisecondsSinceEpoch,
      completenessPct,
      uploadCounts.pending,
      uploadCounts.failed,
      credentials.deviceId,
    ],
  );
}
