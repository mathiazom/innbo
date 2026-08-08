import 'dart:io';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

import 'image_store.dart';
import 'item_detail_screen.dart';

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
          '''
          SELECT item.id, item.name,
            (SELECT file_name FROM image WHERE item_id = item.id ORDER BY created_at ASC LIMIT 1) AS cover_file_name
          FROM item WHERE room_id = ? ORDER BY name
          ''',
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
              final id = rows[index]['id'] as String;
              final name = rows[index]['name'] as String;
              final coverFileName = rows[index]['cover_file_name'] as String?;
              return ListTile(
                leading: coverFileName == null
                    ? null
                    : FutureBuilder<File>(
                        future: ImageStore.file(coverFileName),
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
                            ),
                          );
                        },
                      ),
                title: Text(name),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        ItemDetailScreen(db: db, itemId: id, itemName: name),
                  ),
                ),
              );
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
