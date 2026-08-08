import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

import '../device_credentials.dart';
import '../items/item_list_screen.dart';

const _uuid = Uuid();

class RoomListScreen extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;

  const RoomListScreen({super.key, required this.db, required this.credentials});

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
      appBar: AppBar(title: const Text('Rom')),
      body: StreamBuilder<ResultSet>(
        stream: db.watch('SELECT id, name FROM room ORDER BY name'),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? ResultSet([], null, []);
          if (rows.isEmpty) {
            return const Center(child: Text('Ingen rom ennå.'));
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final id = row['id'] as String;
              final name = row['name'] as String;
              return ListTile(
                title: Text(name),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ItemListScreen(
                      db: db,
                      credentials: credentials,
                      roomId: id,
                      roomName: name,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addRoom(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
