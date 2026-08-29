import 'dart:io';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

import '../device_credentials.dart';
import '../items/batch_capture_screen.dart';
import '../items/image_sync.dart';
import '../items/item_detail_screen.dart';
import '../items/item_name_text.dart';
import '../powersync/synced_list_view.dart';
import 'breadcrumb_bar.dart';
import 'move_destination_sheet.dart';

const _uuid = Uuid();

/// A selected item's display data, carried alongside its id so the move
/// destination sheet's summary can show a thumbnail, not just a name.
typedef SelectedItem = ({String? name, String? coverImageId});

/// A held item/container multiselect that's being moved to a new room or
/// container.
class MoveSelection {
  final Map<String, SelectedItem> itemIds; // id -> display data
  final Map<String, String> containerIds; // id -> name
  final String originRoomId;
  final String? originContainerId;

  MoveSelection({
    required this.itemIds,
    required this.containerIds,
    required this.originRoomId,
    required this.originContainerId,
  });
}

/// Folder-like browsing of a room's or a container's direct contents —
/// child containers first, then items. Reused recursively: tapping a
/// container pushes another [ContentsScreen] scoped one level deeper.
///
/// Also doubles as the multiselect UI: a long-press on a tile enters
/// selection mode (confined to this screen); tapping "Flytt" there opens a
/// [MoveDestinationSheet] to pick where the selection goes.
class ContentsScreen extends StatefulWidget {
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

  @override
  State<ContentsScreen> createState() => _ContentsScreenState();
}

class _ContentsScreenState extends State<ContentsScreen> {
  late String _title = widget.title;
  final Map<String, SelectedItem> _selectedItems = {};
  final Map<String, String> _selectedContainers = {};

  bool get _selecting =>
      _selectedItems.isNotEmpty || _selectedContainers.isNotEmpty;

  void _toggleItem(String id, SelectedItem item) {
    setState(() {
      if (_selectedItems.containsKey(id)) {
        _selectedItems.remove(id);
      } else {
        _selectedItems[id] = item;
      }
    });
  }

  void _toggleContainer(String id, String name) {
    setState(() {
      if (_selectedContainers.containsKey(id)) {
        _selectedContainers.remove(id);
      } else {
        _selectedContainers[id] = name;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItems.clear();
      _selectedContainers.clear();
    });
  }

  Future<void> _selectAll() async {
    final containers = await _containersQuery.first;
    final items = await _itemsQuery.first;
    setState(() {
      for (final row in containers) {
        _selectedContainers[row['id'] as String] = row['name'] as String;
      }
      for (final row in items) {
        _selectedItems[row['id'] as String] = (
          name: row['name'] as String?,
          coverImageId: row['cover_image_id'] as String?,
        );
      }
    });
  }

  Future<void> _startMove() async {
    final selection = MoveSelection(
      itemIds: Map.of(_selectedItems),
      containerIds: Map.of(_selectedContainers),
      originRoomId: widget.roomId,
      originContainerId: widget.containerId,
    );
    final moved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MoveDestinationSheet(
        db: widget.db,
        credentials: widget.credentials,
        selection: selection,
      ),
    );
    if (moved == true && mounted) {
      _clearSelection();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Flyttet.')));
    }
  }

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
    await widget.db.execute(
      'INSERT INTO container (id, name, room_id, parent_container_id) VALUES (?, ?, ?, ?)',
      [
        _uuid.v4(),
        name,
        widget.containerId == null ? widget.roomId : null,
        widget.containerId,
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: _title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.containerId == null
              ? 'Endre navn på rom'
              : 'Endre navn på beholder',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Navn'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    final table = widget.containerId == null ? 'room' : 'container';
    final id = widget.containerId ?? widget.roomId;
    await widget.db.execute('UPDATE $table SET name = ? WHERE id = ?', [
      name,
      id,
    ]);
    setState(() => _title = name);
  }

  void _addItem(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BatchCaptureScreen(
          db: widget.db,
          credentials: widget.credentials,
          roomId: widget.roomId,
          containerId: widget.containerId,
          breadcrumbs: [...widget.breadcrumbs, widget.title],
        ),
      ),
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
      _addItem(context);
    }
  }

  Stream<ResultSet> get _containersQuery => widget.containerId == null
      ? widget.db.watch(
          'SELECT id, name FROM container WHERE room_id = ? ORDER BY name',
          parameters: [widget.roomId],
        )
      : widget.db.watch(
          'SELECT id, name FROM container WHERE parent_container_id = ? ORDER BY name',
          parameters: [widget.containerId],
        );

  Stream<ResultSet> get _itemsQuery => widget.containerId == null
      ? widget.db.watch(
          '''
          SELECT item.id, item.name, item.placement,
            (SELECT id FROM image WHERE item_id = item.id ORDER BY created_at ASC LIMIT 1) AS cover_image_id
          FROM item WHERE room_id = ? AND container_id IS NULL ORDER BY name
          ''',
          parameters: [widget.roomId],
        )
      : widget.db.watch(
          '''
          SELECT item.id, item.name, item.placement,
            (SELECT id FROM image WHERE item_id = item.id ORDER BY created_at ASC LIMIT 1) AS cover_image_id
          FROM item WHERE container_id = ? ORDER BY name
          ''',
          parameters: [widget.containerId],
        );

  /// Subscribes to this screen's containers and items together, rebuilding
  /// [builder] whenever either emits — shared by the body's list and the
  /// "Velg alle" button's enabled state, so both agree on what "everything"
  /// currently means.
  Widget _watchContents(
    Widget Function(BuildContext context, ResultSet containers, ResultSet items)
    builder,
  ) {
    return StreamBuilder<ResultSet>(
      stream: _containersQuery,
      builder: (context, containerSnapshot) {
        final containers = containerSnapshot.data;
        if (containers == null) return const SizedBox.shrink();
        return StreamBuilder<ResultSet>(
          stream: _itemsQuery,
          builder: (context, itemSnapshot) {
            final items = itemSnapshot.data;
            if (items == null) return const SizedBox.shrink();
            return builder(context, containers, items);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final childBreadcrumbs = [...widget.breadcrumbs, _title];

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                ),
                title: Text(
                  '${_selectedItems.length + _selectedContainers.length} valgt',
                ),
                actions: [
                  _watchContents((context, containers, items) {
                    final allSelected =
                        containers.every(
                          (r) => _selectedContainers.containsKey(
                            r['id'] as String,
                          ),
                        ) &&
                        items.every(
                          (r) => _selectedItems.containsKey(r['id'] as String),
                        ) &&
                        (containers.isNotEmpty || items.isNotEmpty);
                    return IconButton(
                      icon: const Icon(Icons.select_all),
                      tooltip: 'Velg alle',
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: allSelected ? null : _selectAll,
                    );
                  }),
                  TextButton(onPressed: _startMove, child: const Text('Flytt')),
                ],
              )
            : AppBar(
                title: Text(_title),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _rename(context),
                  ),
                ],
              ),
        body: Column(
          children: [
            BreadcrumbBar(path: widget.breadcrumbs),
            Expanded(
              child: SyncGate(
                db: widget.db,
                builder: (context) => _watchContents(
                  (context, containers, items) => _ContentsList(
                    db: widget.db,
                    credentials: widget.credentials,
                    roomId: widget.roomId,
                    containers: containers,
                    items: items,
                    childBreadcrumbs: childBreadcrumbs,
                    selecting: _selecting,
                    selectedItems: _selectedItems,
                    selectedContainers: _selectedContainers,
                    onToggleItem: _toggleItem,
                    onToggleContainer: _toggleContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
                onPressed: () => _pickAddType(context),
                child: const Icon(Icons.add),
              ),
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
  final bool selecting;
  final Map<String, SelectedItem> selectedItems;
  final Map<String, String> selectedContainers;
  final void Function(String id, SelectedItem item) onToggleItem;
  final void Function(String id, String name) onToggleContainer;

  const _ContentsList({
    required this.db,
    required this.credentials,
    required this.roomId,
    required this.containers,
    required this.items,
    required this.childBreadcrumbs,
    required this.selecting,
    required this.selectedItems,
    required this.selectedContainers,
    required this.onToggleItem,
    required this.onToggleContainer,
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
          final id = row['id'] as String;
          final name = row['name'] as String;
          return _ContainerTile(
            db: db,
            credentials: credentials,
            roomId: roomId,
            id: id,
            name: name,
            childBreadcrumbs: childBreadcrumbs,
            selecting: selecting,
            selected: selectedContainers.containsKey(id),
            onToggle: () => onToggleContainer(id, name),
          );
        }
        final row = items[index - containers.length];
        final id = row['id'] as String;
        final name = row['name'] as String?;
        final coverImageId = row['cover_image_id'] as String?;
        return _ItemTile(
          db: db,
          credentials: credentials,
          id: id,
          name: name,
          placement: row['placement'] as String?,
          coverImageId: coverImageId,
          breadcrumbs: childBreadcrumbs,
          selecting: selecting,
          selected: selectedItems.containsKey(id),
          onToggle: () =>
              onToggleItem(id, (name: name, coverImageId: coverImageId)),
        );
      },
    );
  }
}

/// Fixed-size (matches [_ItemTile]'s thumbnail) box for a list tile's
/// leading visual, so containers and items line up regardless of whether
/// an item has a cover image.
class LeadingBox extends StatelessWidget {
  final Widget child;
  final double size;

  const LeadingBox({super.key, required this.child, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: child),
    );
  }
}

/// Placeholder fill for [LeadingBox] when there's no real image to show —
/// a container (which never has one) or an item that hasn't got a cover
/// image yet.
class PlaceholderIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const PlaceholderIcon({super.key, required this.icon, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerHighest,
      child: Icon(icon, size: size, color: colors.onSurfaceVariant),
    );
  }
}

/// An item's cover-image thumbnail (falling back to [PlaceholderIcon] while
/// it loads or if there isn't one), wrapped in a [LeadingBox] of [size].
/// Shared by [_ItemTile] and the move-destination sheet's selection
/// summary — same thumbnail, different sizes.
class ItemThumbnail extends StatelessWidget {
  final DeviceCredentials credentials;
  final String? coverImageId;
  final double size;

  const ItemThumbnail({
    super.key,
    required this.credentials,
    required this.coverImageId,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return LeadingBox(
      size: size,
      child: coverImageId == null
          ? PlaceholderIcon(icon: Icons.category, size: size / 2)
          : FutureBuilder<File?>(
              future: ImageSync.ensureLocalThumbnail(
                credentials,
                coverImageId!,
              ),
              builder: (context, snapshot) {
                final file = snapshot.data;
                if (file == null) {
                  return PlaceholderIcon(icon: Icons.category, size: size / 2);
                }
                return Image.file(
                  file,
                  fit: BoxFit.cover,
                  // The file may be a full-res original (see
                  // ImageSync.ensureLocalThumbnail) — decode at display
                  // size, not full resolution.
                  cacheWidth: (size * 2).round(),
                );
              },
            ),
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
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;

  const _ContainerTile({
    required this.db,
    required this.credentials,
    required this.roomId,
    required this.id,
    required this.name,
    required this.childBreadcrumbs,
    required this.selecting,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const LeadingBox(
        child: PlaceholderIcon(icon: Icons.inventory_2),
      ),
      title: Text(name),
      trailing: selecting
          ? Checkbox(value: selected, onChanged: (_) => onToggle())
          : null,
      onLongPress: selecting ? null : onToggle,
      onTap: selecting
          ? onToggle
          : () => Navigator.of(context).push(
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
  final String? name;
  final String? placement;
  final String? coverImageId;
  final List<String> breadcrumbs;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;

  const _ItemTile({
    required this.db,
    required this.credentials,
    required this.id,
    required this.name,
    required this.placement,
    required this.coverImageId,
    required this.breadcrumbs,
    required this.selecting,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ItemThumbnail(
        credentials: credentials,
        coverImageId: coverImageId,
      ),
      title: ItemNameText(name: name),
      trailing: selecting
          ? Checkbox(value: selected, onChanged: (_) => onToggle())
          : null,
      onLongPress: selecting ? null : onToggle,
      onTap: selecting
          ? onToggle
          : () => Navigator.of(context).push(
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
