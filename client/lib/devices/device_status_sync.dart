import 'package:powersync/powersync.dart';

import '../device_credentials.dart';
import 'image_completeness.dart';

/// Recomputes and writes this device's own paired_device row — see
/// backend/migrations/0004_paired_device.sql. Called on app foreground and
/// whenever the device overview screen opens; there's no background job for
/// this yet (see docs/BACKLOG.md's background image sync item).
/// One-time cleanup for a fixed bug: before the [refreshDeviceStatus] guard
/// below existed, a refresh could fire before the local `paired_device` row
/// existed, queuing a PUT missing the required `name` column. The backend
/// rejects that PUT with 400 forever, and since PowerSync's upload queue is
/// strictly FIFO, it blocks every other queued write behind it. Safe to call
/// on every startup — it's a no-op once no such entry remains.
Future<void> clearStuckPairedDeviceUpload(PowerSyncDatabase db) async {
  final batch = await db.getCrudBatch();
  if (batch == null) return;
  for (final entry in batch.crud) {
    if (entry.table == 'paired_device' &&
        entry.op == UpdateType.put &&
        entry.opData?.containsKey('name') != true) {
      await db.execute('DELETE FROM ps_crud WHERE id = ?', [entry.clientId]);
    }
  }
}

Future<void> refreshDeviceStatus(
  PowerSyncDatabase db,
  DeviceCredentials credentials,
) async {
  if (db.currentStatus.hasSynced != true) return;
  final lastSyncedAt = db.currentStatus.lastSyncedAt;
  final completenessPct = await computeImageCompletenessPct(db);
  await db.execute(
    'UPDATE paired_device SET last_sync_at = ?, image_completeness_pct = ? '
    'WHERE device_id = ?',
    [
      lastSyncedAt?.millisecondsSinceEpoch,
      completenessPct,
      credentials.deviceId,
    ],
  );
}
