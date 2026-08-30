import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

import '../about_dialog.dart';
import '../containers/contents_screen.dart';
import '../device_credentials.dart';
import '../powersync/synced_list_view.dart';

const _roomsQuery = '''
  SELECT room.id, room.name,
    (SELECT id FROM image WHERE room_id = room.id ORDER BY created_at DESC LIMIT 1) AS cover_image_id
  FROM room ORDER BY name
''';

const _uuid = Uuid();

class RoomListScreen extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;

  const RoomListScreen({
    super.key,
    required this.db,
    required this.credentials,
  });

  Future<void> _addRoom(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nytt rom'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Navn'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Legg til'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    await db.execute('INSERT INTO room (id, name) VALUES (?, ?)', [
      _uuid.v4(),
      name,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => showAboutAppDialog(context, credentials, db),
          child: Image.asset('assets/icon/icon.png', height: 32),
        ),
      ),
      body: SyncedListView(
        db: db,
        query: db.watch(_roomsQuery),
        emptyText: 'Ingen rom ennå.',
        itemBuilder: (context, rows) => ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final id = row['id'] as String;
            final name = row['name'] as String;
            return ListTile(
              leading: ItemThumbnail(
                credentials: credentials,
                coverImageId: row['cover_image_id'] as String?,
                placeholderIcon: Icons.meeting_room,
              ),
              title: Text(name),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContentsScreen(
                    db: db,
                    credentials: credentials,
                    roomId: id,
                    containerId: null,
                    title: name,
                    breadcrumbs: const [],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addRoom(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
