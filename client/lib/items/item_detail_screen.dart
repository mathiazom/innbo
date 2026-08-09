import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

import '../device_credentials.dart';
import 'image_store.dart';
import 'image_sync.dart';

const _uuid = Uuid();
final _picker = ImagePicker();

class ItemDetailScreen extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String itemId;
  final String itemName;
  final String? itemPlacement;

  const ItemDetailScreen({
    super.key,
    required this.db,
    required this.credentials,
    required this.itemId,
    required this.itemName,
    this.itemPlacement,
  });

  Future<void> _addImage(BuildContext context, ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;
    final id = _uuid.v4();
    await ImageStore.saveFull(id, File(picked.path));
    await db.execute(
      'INSERT INTO image (id, item_id, created_at) VALUES (?, ?, ?)',
      [id, itemId, DateTime.now().millisecondsSinceEpoch],
    );
    final uploaded = await ImageSync.uploadFull(credentials, id);
    if (!uploaded && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Kunne ikke laste opp bildet.'),
          action: SnackBarAction(
            label: 'Prøv igjen',
            onPressed: () => ImageSync.uploadFull(credentials, id),
          ),
        ),
      );
    }
  }

  Future<void> _pickAndAddImage(BuildContext context) async {
    if (!Platform.isAndroid) {
      await _addImage(context, ImageSource.gallery);
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
    await _addImage(context, source);
  }

  Future<void> _viewImage(BuildContext context, String imageId) async {
    // Backstop: whatever ImageSync does internally, the UI must never
    // wait forever for it.
    final file = await ImageSync.ensureLocalFull(
      credentials,
      imageId,
    ).timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (!context.mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kunne ikke hente bildet.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(child: InteractiveViewer(child: Image.file(file))),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteImage(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slette bilde?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.execute('DELETE FROM image WHERE id = ?', [id]);
    await ImageStore.delete(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: itemPlacement == null
            ? kToolbarHeight
            : kToolbarHeight + 14,
        title: itemPlacement == null
            ? Text(itemName, overflow: TextOverflow.ellipsis)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(itemName, overflow: TextOverflow.ellipsis),
                  Text(
                    itemPlacement!,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(
          'SELECT id FROM image WHERE item_id = ? ORDER BY created_at ASC',
          parameters: [itemId],
        ),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? ResultSet([], null, []);
          if (rows.isEmpty) {
            return const Center(child: Text('Ingen bilder ennå.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final id = rows[index]['id'] as String;
              return GestureDetector(
                onTap: () => _viewImage(context, id),
                onLongPress: () => _deleteImage(context, id),
                child: FutureBuilder<File?>(
                  future: ImageSync.ensureLocalThumbnail(credentials, id),
                  builder: (context, snapshot) {
                    final file = snapshot.data;
                    if (file == null) return const SizedBox.shrink();
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        file,
                        fit: BoxFit.cover,
                        // The file may be a full-res original (see
                        // ImageSync.ensureLocalThumbnail) — decode at
                        // roughly grid-cell size, not full resolution.
                        cacheWidth: 300,
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAndAddImage(context),
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
