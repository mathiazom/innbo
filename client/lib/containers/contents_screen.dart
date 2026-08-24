import 'dart:io';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

import '../device_credentials.dart';
import '../items/image_sync.dart';
import '../items/item_detail_screen.dart';
import '../powersync/synced_list_view.dart';
import 'breadcrumb_bar.dart';

const _uuid = Uuid();

/// Folder-like browsing of a room's or a container's direct contents —
/// child containers first, then items. Reused recursively: tapping a
/// container pushes another [ContentsScreen] scoped one level deeper.
class ContentsScreen extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;

  /// The room every container/item under this screen ultimately belongs to.
  final String roomId;

  /// Null when browsing a room's own root; set when browsing inside that
  /// container.
  final String? containerId;

  final String title;

  /// Ancestor names above [title] — does not include [title] itself.
  final List<String> breadcrumbs;

  const ContentsScreen({
    super.key,
    required this.db,
    required this.credentials,
    required this.roomId,
    required this.containerId,
    required this.title,
    required this.breadcrumbs,
  });

  Future<void> _addContainer(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ny beholder'),
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
    await db.execute(
      'INSERT INTO container (id, name, room_id, parent_container_id) VALUES (?, ?, ?, ?)',
      [_uuid.v4(), name, containerId == null ? roomId : null, containerId],
    );
  }

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
      'INSERT INTO item (id, name, room_id, container_id, placement) VALUES (?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        name,
        roomId,
        containerId,
        placement.isEmpty ? null : placement,
      ],
    );
  }

  Future<void> _pickAddType(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2),
              title: const Text('Ny beholder'),
              onTap: () => Navigator.of(context).pop('container'),
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('Ny gjenstand'),
              onTap: () => Navigator.of(context).pop('item'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'container') {
      await _addContainer(context);
    } else {
      await _addItem(context);
    }
  }

  Stream<ResultSet> get _containersQuery => containerId == null
      ? db.watch(
          'SELECT id, name FROM container WHERE room_id = ? ORDER BY name',
          parameters: [roomId],
        )
      : db.watch(
          'SELECT id, name FROM container WHERE parent_container_id = ? ORDER BY name',
          parameters: [containerId],
        );

  Stream<ResultSet> get _itemsQuery => containerId == null
      ? db.watch(
          '''
          SELECT item.id, item.name, item.placement,
            (SELECT id FROM image WHERE item_id = item.id ORDER BY created_at ASC LIMIT 1) AS cover_image_id
          FROM item WHERE room_id = ? AND container_id IS NULL ORDER BY name
          ''',
          parameters: [roomId],
        )
      : db.watch(
          '''
          SELECT item.id, item.name, item.placement,
            (SELECT id FROM image WHERE item_id = item.id ORDER BY created_at ASC LIMIT 1) AS cover_image_id
          FROM item WHERE container_id = ? ORDER BY name
          ''',
          parameters: [containerId],
        );

  @override
  Widget build(BuildContext context) {
    final childBreadcrumbs = [...breadcrumbs, title];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          BreadcrumbBar(path: breadcrumbs),
          Expanded(
            child: SyncGate(
              db: db,
              builder: (context) => StreamBuilder<ResultSet>(
                stream: _containersQuery,
                builder: (context, containerSnapshot) {
                  if (!containerSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  return StreamBuilder<ResultSet>(
                    stream: _itemsQuery,
                    builder: (context, itemSnapshot) {
                      if (!itemSnapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      return _ContentsList(
                        db: db,
                        credentials: credentials,
                        roomId: roomId,
                        containers: containerSnapshot.data!,
                        items: itemSnapshot.data!,
                        childBreadcrumbs: childBreadcrumbs,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAddType(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// The containers-then-items list body for one [ContentsScreen], split out
/// so the screen's own `build()` isn't nested three `StreamBuilder`s deep.
class _ContentsList extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String roomId;
  final ResultSet containers;
  final ResultSet items;
  final List<String> childBreadcrumbs;

  const _ContentsList({
    required this.db,
    required this.credentials,
    required this.roomId,
    required this.containers,
    required this.items,
    required this.childBreadcrumbs,
  });

  @override
  Widget build(BuildContext context) {
    if (containers.isEmpty && items.isEmpty) {
      return const Center(
        child: Text('Ingen beholdere eller gjenstander ennå.'),
      );
    }
    return ListView.separated(
      itemCount: containers.length + items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index < containers.length) {
          final row = containers[index];
          return _ContainerTile(
            db: db,
            credentials: credentials,
            roomId: roomId,
            id: row['id'] as String,
            name: row['name'] as String,
            childBreadcrumbs: childBreadcrumbs,
          );
        }
        final row = items[index - containers.length];
        return _ItemTile(
          db: db,
          credentials: credentials,
          id: row['id'] as String,
          name: row['name'] as String,
          placement: row['placement'] as String?,
          coverImageId: row['cover_image_id'] as String?,
          breadcrumbs: childBreadcrumbs,
        );
      },
    );
  }
}

/// Fixed-size (matches [_ItemTile]'s thumbnail) box for a list tile's
/// leading visual, so containers and items line up regardless of whether
/// an item has a cover image.
class _LeadingBox extends StatelessWidget {
  final Widget child;

  const _LeadingBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: child),
    );
  }
}

/// Placeholder fill for [_LeadingBox] when there's no real image to show —
/// a container (which never has one) or an item that hasn't got a cover
/// image yet.
class _PlaceholderIcon extends StatelessWidget {
  final IconData icon;

  const _PlaceholderIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerHighest,
      child: Icon(icon, color: colors.onSurfaceVariant),
    );
  }
}

class _ContainerTile extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String roomId;
  final String id;
  final String name;
  final List<String> childBreadcrumbs;

  const _ContainerTile({
    required this.db,
    required this.credentials,
    required this.roomId,
    required this.id,
    required this.name,
    required this.childBreadcrumbs,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const _LeadingBox(
        child: _PlaceholderIcon(icon: Icons.inventory_2),
      ),
      title: Text(name),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContentsScreen(
            db: db,
            credentials: credentials,
            roomId: roomId,
            containerId: id,
            title: name,
            breadcrumbs: childBreadcrumbs,
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String id;
  final String name;
  final String? placement;
  final String? coverImageId;
  final List<String> breadcrumbs;

  const _ItemTile({
    required this.db,
    required this.credentials,
    required this.id,
    required this.name,
    required this.placement,
    required this.coverImageId,
    required this.breadcrumbs,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _LeadingBox(
        child: coverImageId == null
            ? const _PlaceholderIcon(icon: Icons.category)
            : FutureBuilder<File?>(
                future: ImageSync.ensureLocalThumbnail(
                  credentials,
                  coverImageId!,
                ),
                builder: (context, snapshot) {
                  final file = snapshot.data;
                  if (file == null) {
                    return const _PlaceholderIcon(icon: Icons.category);
                  }
                  return Image.file(
                    file,
                    fit: BoxFit.cover,
                    // The file may be a full-res original (see
                    // ImageSync.ensureLocalThumbnail) — decode at display
                    // size, not full resolution.
                    cacheWidth: 96,
                  );
                },
              ),
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
            breadcrumbs: breadcrumbs,
          ),
        ),
      ),
    );
  }
}
