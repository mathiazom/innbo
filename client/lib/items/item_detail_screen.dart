import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;

import '../containers/breadcrumb_bar.dart';
import '../device_credentials.dart';
import 'image_actions.dart';
import 'item_image_grid.dart';
import 'item_name_text.dart';

class ItemDetailScreen extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String itemId;
  final String? itemName;
  final String? itemPlacement;
  final List<String> breadcrumbs;

  const ItemDetailScreen({
    super.key,
    required this.db,
    required this.credentials,
    required this.itemId,
    required this.itemName,
    this.itemPlacement,
    required this.breadcrumbs,
  });

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late String? _name = widget.itemName;
  late String? _placement = widget.itemPlacement;

  PowerSyncDatabase get db => widget.db;
  DeviceCredentials get credentials => widget.credentials;
  String get itemId => widget.itemId;

  Future<void> _editItem(BuildContext context) async {
    final nameController = TextEditingController(text: _name ?? '');
    final placementController = TextEditingController(text: _placement ?? '');
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rediger gjenstand'),
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
            child: const Text('Lagre'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final (name, placement) = result;
    final newName = name.isEmpty ? null : name;
    final newPlacement = placement.isEmpty ? null : placement;
    await db.execute('UPDATE item SET name = ?, placement = ? WHERE id = ?', [
      newName,
      newPlacement,
      itemId,
    ]);
    setState(() {
      _name = newName;
      _placement = newPlacement;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: _placement == null
            ? kToolbarHeight
            : kToolbarHeight + 14,
        title: _placement == null
            ? ItemNameText(name: _name, overflow: TextOverflow.ellipsis)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ItemNameText(name: _name, overflow: TextOverflow.ellipsis),
                  Text(
                    _placement!,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editItem(context),
          ),
        ],
      ),
      body: Column(
        children: [
          BreadcrumbBar(path: widget.breadcrumbs),
          Expanded(
            child: ItemImageGrid(
              db: db,
              credentials: credentials,
              itemId: itemId,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            pickAndAddImage(context, db, credentials, () async => itemId),
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
