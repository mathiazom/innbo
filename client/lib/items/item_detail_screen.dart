import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

import 'image_store.dart';

const _uuid = Uuid();
final _picker = ImagePicker();

class ItemDetailScreen extends StatelessWidget {
  final PowerSyncDatabase db;
  final String itemId;
  final String itemName;

  const ItemDetailScreen({
    super.key,
    required this.db,
    required this.itemId,
    required this.itemName,
  });

  Future<void> _addImage(BuildContext context, ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;
    final fileName = await ImageStore.save(File(picked.path));
    await db.execute(
      'INSERT INTO image (id, item_id, file_name, created_at) VALUES (?, ?, ?, ?)',
      [
        _uuid.v4(),
        itemId,
        fileName,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
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

  Future<void> _viewImage(BuildContext context, String fileName) async {
    final file = await ImageStore.file(fileName);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: InteractiveViewer(child: Image.file(file)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteImage(
    BuildContext context,
    String id,
    String fileName,
  ) async {
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
    await ImageStore.delete(fileName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(itemName)),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(
          'SELECT id, file_name FROM image WHERE item_id = ? ORDER BY created_at ASC',
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
              final fileName = rows[index]['file_name'] as String;
              return GestureDetector(
                onTap: () => _viewImage(context, fileName),
                onLongPress: () => _deleteImage(context, id, fileName),
                child: FutureBuilder<File>(
                  future: ImageStore.file(fileName),
                  builder: (context, snapshot) {
                    final file = snapshot.data;
                    if (file == null) return const SizedBox.shrink();
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(file, fit: BoxFit.cover),
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
