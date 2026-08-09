import 'dart:io';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../device_credentials.dart';
import '../powersync/synced_list_view.dart';
import 'image_sync.dart';
import 'item_detail_screen.dart';

const _uuid = Uuid();

class ItemListScreen extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String roomId;
  final String roomName;

  const ItemListScreen({
    super.key,
    required this.db,
    required this.credentials,
    required this.roomId,
    required this.roomName,
  });

  Future<void> _addItem(BuildContext context) async {
    final nameController = TextEditingController();
    final placementController = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ny gjenstand'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Navn'),
            ),
            TextField(
              controller: placementController,
              decoration: const InputDecoration(
                labelText: 'Plassering (valgfritt)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              nameController.text.trim(),
              placementController.text.trim(),
            )),
            child: const Text('Legg til'),
          ),
        ],
      ),
    );

    if (result == null || result.$1.isEmpty) return;
    final (name, placement) = result;
    await db.execute(
      'INSERT INTO item (id, name, room_id, placement) VALUES (?, ?, ?, ?)',
      [_uuid.v4(), name, roomId, placement.isEmpty ? null : placement],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(roomName)),
      body: SyncedListView(
        db: db,
        query: db.watch(
          '''
          SELECT item.id, item.name, item.placement,
            (SELECT id FROM image WHERE item_id = item.id ORDER BY created_at ASC LIMIT 1) AS cover_image_id
          FROM item WHERE room_id = ? ORDER BY name
          ''',
          parameters: [roomId],
        ),
        emptyText: 'Ingen gjenstander ennå.',
        itemBuilder: (context, rows) => ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final id = rows[index]['id'] as String;
            final name = rows[index]['name'] as String;
            final placement = rows[index]['placement'] as String?;
            final coverImageId = rows[index]['cover_image_id'] as String?;
            return ListTile(
              leading: coverImageId == null
                  ? null
                  : FutureBuilder<File?>(
                      future: ImageSync.ensureLocalThumbnail(
                        credentials,
                        coverImageId,
                      ),
                      builder: (context, snapshot) {
                        final file = snapshot.data;
                        if (file == null) return const SizedBox.shrink();
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            file,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            // The file may be a full-res original (see
                            // ImageSync.ensureLocalThumbnail) — decode
                            // at display size, not full resolution.
                            cacheWidth: 96,
                          ),
                        );
                      },
                    ),
              title: Text(name),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ItemDetailScreen(
                    db: db,
                    credentials: credentials,
                    itemId: id,
                    itemName: name,
                    itemPlacement: placement,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addItem(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
