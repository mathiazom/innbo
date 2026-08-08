import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class ItemListScreen extends StatelessWidget {
  final PowerSyncDatabase db;
  final String roomId;
  final String roomName;

  const ItemListScreen({
    super.key,
    required this.db,
    required this.roomId,
    required this.roomName,
  });

  Future<void> _addItem(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ny gjenstand'),
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
    await db.execute('INSERT INTO item (id, name, room_id) VALUES (?, ?, ?)', [
      _uuid.v4(),
      name,
      roomId,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(roomName)),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(
          'SELECT id, name FROM item WHERE room_id = ? ORDER BY name',
          parameters: [roomId],
        ),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? ResultSet([], null, []);
          if (rows.isEmpty) {
            return const Center(child: Text('Ingen gjenstander ennå.'));
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final name = rows[index]['name'] as String;
              return ListTile(title: Text(name));
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addItem(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
