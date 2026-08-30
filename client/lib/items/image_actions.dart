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

/// Saves a picked file as a new image row owned by [ownerId] via
/// [ownerColumn] (`item_id`, `container_id`, or `room_id` — always a
/// hardcoded literal from the call site, never user input): copies it into
/// local storage, inserts the `image` row, then tries an immediate upload —
/// falling back to [UploadQueue]'s durable retry (with a snackbar) if that
/// fails.
Future<void> addPickedImage(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  String ownerColumn,
  String ownerId,
  XFile picked,
) async {
  try {
    final id = _uuid.v4();
    await ImageStore.saveFull(id, File(picked.path));
    await db.execute(
      'INSERT INTO image (id, $ownerColumn, created_at) VALUES (?, ?, ?)',
      [id, ownerId, DateTime.now().millisecondsSinceEpoch],
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
      _showErrorSnackBar(context, 'addPickedImage($ownerId)', e);
    } else {
      debugPrint('addPickedImage($ownerId): $e');
    }
  }
}

/// Opens the device camera app directly (no camera/library choice) and
/// adds the result to the owner [ensureOwnerId] resolves to. [ensureOwnerId]
/// is only called once a photo is actually taken, so cancelling never
/// creates anything.
Future<void> addFromCamera(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  String ownerColumn,
  Future<String> Function() ensureOwnerId,
) async {
  try {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final ownerId = await ensureOwnerId();
    if (!context.mounted) return;
    await addPickedImage(
      context,
      db,
      credentials,
      ownerColumn,
      ownerId,
      picked,
    );
  } catch (e) {
    if (context.mounted) _showErrorSnackBar(context, 'addFromCamera', e);
  }
}

/// Opens the gallery picker directly (no camera/library choice) and adds
/// whatever's picked to the owner [ensureOwnerId] resolves to. Picks
/// multiple files unless [multiple] is false (a single-image owner like a
/// container or room's cover image). [ensureOwnerId] is only called once
/// at least one file has actually been picked, so cancelling the picker
/// never creates anything.
Future<void> addFromLibrary(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  String ownerColumn,
  Future<String> Function() ensureOwnerId, {
  bool multiple = true,
}) async {
  try {
    final picked = multiple
        ? await _picker.pickMultiImage()
        : await _picker
              .pickImage(source: ImageSource.gallery)
              .then((file) => file == null ? <XFile>[] : [file]);
    if (picked.isEmpty) return;
    final ownerId = await ensureOwnerId();
    for (final file in picked) {
      if (!context.mounted) return;
      await addPickedImage(
        context,
        db,
        credentials,
        ownerColumn,
        ownerId,
        file,
      );
    }
  } catch (e) {
    if (context.mounted) _showErrorSnackBar(context, 'addFromLibrary', e);
  }
}

/// Opens the camera/library source picker (camera vs. gallery on Android;
/// straight to the gallery picker elsewhere) and adds whatever's picked to
/// the owner [ensureOwnerId] resolves to, limited to a single image when
/// [multiple] is false. [ensureOwnerId] is only called once at least one
/// file has actually been picked, so cancelling the picker never creates
/// anything.
Future<void> pickAndAddImage(
  BuildContext context,
  PowerSyncDatabase db,
  DeviceCredentials credentials,
  String ownerColumn,
  Future<String> Function() ensureOwnerId, {
  bool multiple = true,
}) async {
  if (!Platform.isAndroid) {
    await addFromLibrary(
      context,
      db,
      credentials,
      ownerColumn,
      ensureOwnerId,
      multiple: multiple,
    );
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
    await addFromCamera(context, db, credentials, ownerColumn, ensureOwnerId);
  } else {
    await addFromLibrary(
      context,
      db,
      credentials,
      ownerColumn,
      ensureOwnerId,
      multiple: multiple,
    );
  }
}
