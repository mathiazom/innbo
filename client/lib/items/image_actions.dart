import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../device_credentials.dart';
import 'image_store.dart';
import 'image_sync.dart';
import 'upload_queue.dart';

const _uuid = Uuid();
final _picker = ImagePicker();

/// Shows a generic failure snackbar and logs [e] — the shared fallback for
/// anything unexpected in the image pipeline (picker plugin, disk, DB),
/// so a thrown exception ends in visible feedback instead of propagating
/// uncaught out of a fire-and-forget button handler.
void _showErrorSnackBar(BuildContext context, String from, Object e) {
  debugPrint('$from: $e');
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Noe gikk galt med bildet.')));
}

/// Saves a picked file as a new image row on [itemId]: copies it into local
/// storage, inserts the `image` row, then tries an immediate upload —
/// falling back to [UploadQueue]'s durable retry (with a snackbar) if that
/// fails.
Future<void> addPickedImage(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  String itemId,
  XFile picked,
) async {
  try {
    final id = _uuid.v4();
    await ImageStore.saveFull(id, File(picked.path));
    await db.execute(
      'INSERT INTO image (id, item_id, created_at) VALUES (?, ?, ?)',
      [id, itemId, DateTime.now().millisecondsSinceEpoch],
    );
    final uploaded = await ImageSync.uploadFull(credentials, id);
    if (!uploaded) {
      await UploadQueue.enqueue(db, id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Kunne ikke laste opp bildet.'),
            action: SnackBarAction(
              label: 'Prøv igjen',
              onPressed: () => UploadQueue.retryDue(db, credentials),
            ),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      _showErrorSnackBar(context, 'addPickedImage($itemId)', e);
    } else {
      debugPrint('addPickedImage($itemId): $e');
    }
  }
}

/// Opens the device camera app directly (no camera/library choice) and
/// adds the result to the item [ensureItemId] resolves to. [ensureItemId]
/// is only called once a photo is actually taken, so cancelling never
/// creates an item.
Future<void> addFromCamera(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  Future<String> Function() ensureItemId,
) async {
  try {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final itemId = await ensureItemId();
    if (!context.mounted) return;
    await addPickedImage(context, db, credentials, itemId, picked);
  } catch (e) {
    if (context.mounted) _showErrorSnackBar(context, 'addFromCamera', e);
  }
}

/// Opens the gallery multi-picker directly (no camera/library choice) and
/// adds whatever's picked to the item [ensureItemId] resolves to.
/// [ensureItemId] is only called once at least one file has actually been
/// picked, so cancelling the picker never creates an item.
Future<void> addFromLibrary(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  Future<String> Function() ensureItemId,
) async {
  try {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;
    final itemId = await ensureItemId();
    for (final file in picked) {
      if (!context.mounted) return;
      await addPickedImage(context, db, credentials, itemId, file);
    }
  } catch (e) {
    if (context.mounted) _showErrorSnackBar(context, 'addFromLibrary', e);
  }
}

/// Opens the camera/library source picker (camera vs. gallery on Android;
/// straight to the gallery picker elsewhere) and adds whatever's picked to
/// the item [ensureItemId] resolves to. [ensureItemId] is only called once
/// at least one file has actually been picked, so cancelling the picker
/// never creates an item.
Future<void> pickAndAddImage(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  Future<String> Function() ensureItemId,
) async {
  if (!Platform.isAndroid) {
    await addFromLibrary(context, db, credentials, ensureItemId);
    return;
  }
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Ta bilde'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Velg fra bibliotek'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;
  if (source == ImageSource.camera) {
    await addFromCamera(context, db, credentials, ensureItemId);
  } else {
    await addFromLibrary(context, db, credentials, ensureItemId);
  }
}
