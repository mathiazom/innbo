import 'package:powersync/powersync.dart';

import '../items/image_store.dart';

/// Percentage of the household's images that have a full-res file present
/// on this device's local disk — see backend/migrations/0004_paired_device.sql.
/// 100 when there are no images yet (nothing to be missing).
Future<int> computeImageCompletenessPct(PowerSyncDatabase db) async {
  final rows = await db.getAll('SELECT id FROM image');
  if (rows.isEmpty) return 100;

  var localCount = 0;
  // ponytail: sequential file-exists scan over every image, fine at
  // household scale; revisit if this ever needs to run over thousands of
  // images.
  for (final row in rows) {
    final id = row['id'] as String;
    final file = await ImageStore.localFullFile(id);
    if (await file.exists() && await file.length() > 0) localCount++;
  }
  return (localCount * 100 / rows.length).round();
}
