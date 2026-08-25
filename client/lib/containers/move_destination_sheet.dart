import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:sqlite3/common.dart' show ResultSet;

import '../device_credentials.dart';
import 'contents_screen.dart'
    show
        ItemThumbnail,
        LeadingBox,
        MoveSelection,
        PlaceholderIcon,
        SelectedItem;

/// A destination is a room (`containerId == null`) or a container nested
/// somewhere under one.
typedef _Destination = (String roomId, String? containerId);

/// Walks the `parent_container_id` chain up from [containerId] to the room
/// root, returning the ids of every container passed through *above* it
/// (not including [containerId] itself). Used once, up front, to know
/// which containers must start expanded so the origin's own row is
/// visible without the user having to open anything.
Future<Set<String>> _ancestorContainerIds(
  PowerSyncDatabase db,
  String? containerId,
) async {
  final ids = <String>{};
  var current = containerId;
  while (current != null) {
    final row = await db.get(
      'SELECT parent_container_id FROM container WHERE id = ?',
      [current],
    );
    final parent = row['parent_container_id'] as String?;
    if (parent == null) break;
    ids.add(parent);
    current = parent;
  }
  return ids;
}

/// Bottom sheet showing the whole room/container tree so a move
/// destination can be picked directly, instead of navigating screen by
/// screen. Only rooms and containers ever appear — items are never a
/// valid destination.
class MoveDestinationSheet extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final MoveSelection selection;

  const MoveDestinationSheet({
    super.key,
    required this.db,
    required this.credentials,
    required this.selection,
  });

  @override
  State<MoveDestinationSheet> createState() => _MoveDestinationSheetState();
}

class _MoveDestinationSheetState extends State<MoveDestinationSheet> {
  _Destination? _destination;
  Set<String>? _expandedContainerIds;

  @override
  void initState() {
    super.initState();
    _ancestorContainerIds(widget.db, widget.selection.originContainerId).then((
      ids,
    ) {
      if (mounted) setState(() => _expandedContainerIds = ids);
    });
  }

  bool get _isNoop =>
      _destination != null &&
      _destination!.$1 == widget.selection.originRoomId &&
      _destination!.$2 == widget.selection.originContainerId;

  Future<void> _performMove() async {
    final destination = _destination;
    if (destination == null) return;
    final (destRoomId, destContainerId) = destination;
    await widget.db.writeTransaction((tx) async {
      for (final containerId in widget.selection.containerIds.keys) {
        await tx.execute(
          'UPDATE container SET room_id = ?, parent_container_id = ? WHERE id = ?',
          [
            destContainerId == null ? destRoomId : null,
            destContainerId,
            containerId,
          ],
        );
        await tx.execute(
          '''
          WITH RECURSIVE sub(id) AS (
            SELECT id FROM container WHERE id = ?
            UNION ALL
            SELECT c.id FROM container c JOIN sub ON c.parent_container_id = sub.id
          )
          UPDATE item SET room_id = ? WHERE container_id IN (SELECT id FROM sub)
          ''',
          [containerId, destRoomId],
        );
      }
      for (final itemId in widget.selection.itemIds.keys) {
        await tx.execute(
          'UPDATE item SET room_id = ?, container_id = ? WHERE id = ?',
          [destRoomId, destContainerId, itemId],
        );
      }
    });
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final expandedContainerIds = _expandedContainerIds;
    final movingContainerIds = widget.selection.containerIds.keys.toSet();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _SelectionSummary(
              selection: widget.selection,
              credentials: widget.credentials,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: expandedContainerIds == null
                ? const Center(child: CircularProgressIndicator())
                : RadioGroup<_Destination>(
                    groupValue: _destination,
                    onChanged: (destination) =>
                        setState(() => _destination = destination),
                    child: StreamBuilder<ResultSet>(
                      stream: widget.db.watch(
                        'SELECT id, name FROM room ORDER BY name',
                      ),
                      builder: (context, snapshot) {
                        final rows = snapshot.data;
                        if (rows == null) return const SizedBox.shrink();
                        return ListView(
                          children: [
                            for (final row in rows)
                              _RoomNode(
                                db: widget.db,
                                roomId: row['id'] as String,
                                name: row['name'] as String,
                                initiallyExpanded:
                                    row['id'] as String ==
                                    widget.selection.originRoomId,
                                expandedContainerIds: expandedContainerIds,
                                movingContainerIds: movingContainerIds,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Avbryt'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _destination == null || _isNoop
                          ? null
                          : _performMove,
                      child: const Text('Flytt hit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _namesThreshold = 3;
const _imageSlotCap = 8;

/// "Flytter: …" header — shows each selected entry as a small icon (a
/// container's generic folder icon, or an item's cover-image thumbnail)
/// next to its name while the selection is small; once it's large enough
/// that a name list would be hard to scan, switches to icons only, capped
/// at [_imageSlotCap] with a "+N" for the rest. Containers always sort
/// first, matching the containers-before-items convention used everywhere
/// else in this app.
class _SelectionSummary extends StatelessWidget {
  final MoveSelection selection;
  final DeviceCredentials credentials;

  const _SelectionSummary({required this.selection, required this.credentials});

  Widget _containerIcon() => const LeadingBox(
    size: 24,
    child: PlaceholderIcon(icon: Icons.inventory_2, size: 12),
  );

  Widget _itemIcon(SelectedItem item) => ItemThumbnail(
    credentials: credentials,
    coverImageId: item.coverImageId,
    size: 24,
  );

  @override
  Widget build(BuildContext context) {
    final containerNames = selection.containerIds.values.toList();
    final items = selection.itemIds.values.toList();
    final total = containerNames.length + items.length;

    if (total <= _namesThreshold) {
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Flytter:'),
          for (final name in containerNames)
            _IconLabel(icon: _containerIcon(), name: name),
          for (final item in items)
            _IconLabel(icon: _itemIcon(item), name: item.name),
        ],
      );
    }

    final icons = [
      for (final _ in containerNames) _containerIcon(),
      for (final item in items) _itemIcon(item),
    ];
    // A lone "+1" would take up as much room as just showing that one
    // extra icon, so never leave exactly one hidden — one fewer icon
    // shows instead, bumping the overflow to a worthwhile "+2". The cap
    // itself never grows past _imageSlotCap.
    final visibleCount = total <= _imageSlotCap
        ? total
        : (total - _imageSlotCap == 1 ? _imageSlotCap - 1 : _imageSlotCap);
    final visible = icons.take(visibleCount).toList();
    final overflow = total - visible.length;
    return Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Text('Flytter:'),
        ),
        for (final icon in visible)
          Padding(padding: const EdgeInsets.only(right: 4), child: icon),
        if (overflow > 0) Text('+$overflow'),
      ],
    );
  }
}

class _IconLabel extends StatelessWidget {
  final Widget icon;
  final String name;

  const _IconLabel({required this.icon, required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [icon, const SizedBox(width: 4), Text(name)],
    );
  }
}

/// A room row at the top of the tree — expands to show its own top-level
/// containers (`container.room_id = this room`).
class _RoomNode extends StatefulWidget {
  final PowerSyncDatabase db;
  final String roomId;
  final String name;
  final bool initiallyExpanded;
  final Set<String> expandedContainerIds;
  final Set<String> movingContainerIds;

  const _RoomNode({
    required this.db,
    required this.roomId,
    required this.name,
    required this.initiallyExpanded,
    required this.expandedContainerIds,
    required this.movingContainerIds,
  });

  @override
  State<_RoomNode> createState() => _RoomNodeState();
}

class _RoomNodeState extends State<_RoomNode> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final destination = (widget.roomId, null);
    return StreamBuilder<ResultSet>(
      stream: widget.db.watch(
        'SELECT id, name FROM container WHERE room_id = ? ORDER BY name',
        parameters: [widget.roomId],
      ),
      builder: (context, snapshot) {
        final rows = snapshot.data;
        final hasChildren = rows != null && rows.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              onTap: () {
                RadioGroup.maybeOf<_Destination>(
                  context,
                )?.onChanged(destination);
                if (hasChildren) setState(() => _expanded = !_expanded);
              },
              leading: hasChildren
                  ? Icon(_expanded ? Icons.expand_more : Icons.chevron_right)
                  : const SizedBox(width: 24),
              title: Text(widget.name),
              trailing: Radio<_Destination>(value: destination),
            ),
            if (_expanded && hasChildren)
              Column(
                children: [
                  for (final row in rows)
                    _ContainerNode(
                      db: widget.db,
                      roomId: widget.roomId,
                      id: row['id'] as String,
                      name: row['name'] as String,
                      depth: 1,
                      expandedContainerIds: widget.expandedContainerIds,
                      movingContainerIds: widget.movingContainerIds,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// A container row anywhere in the tree — expands to show its own nested
/// containers (`container.parent_container_id = this container`), unless
/// it's being moved (or nested under one that is), in which case it's
/// shown for context only: grayed out, not expandable, not selectable.
/// That also blocks every descendant for free, since a container's
/// subtree is only reachable by expanding down through it.
class _ContainerNode extends StatefulWidget {
  final PowerSyncDatabase db;
  final String roomId;
  final String id;
  final String name;
  final int depth;
  final Set<String> expandedContainerIds;
  final Set<String> movingContainerIds;

  const _ContainerNode({
    required this.db,
    required this.roomId,
    required this.id,
    required this.name,
    required this.depth,
    required this.expandedContainerIds,
    required this.movingContainerIds,
  });

  @override
  State<_ContainerNode> createState() => _ContainerNodeState();
}

class _ContainerNodeState extends State<_ContainerNode> {
  late bool _expanded = widget.expandedContainerIds.contains(widget.id);

  @override
  Widget build(BuildContext context) {
    final indent = EdgeInsets.only(left: widget.depth * 16.0);
    final blocked = widget.movingContainerIds.contains(widget.id);

    if (blocked) {
      return Padding(
        padding: indent,
        child: ListTile(
          enabled: false,
          leading: const Icon(Icons.inventory_2),
          title: Text('${widget.name} (flyttes)'),
        ),
      );
    }

    final destination = (widget.roomId, widget.id);
    return StreamBuilder<ResultSet>(
      stream: widget.db.watch(
        'SELECT id, name FROM container WHERE parent_container_id = ? ORDER BY name',
        parameters: [widget.id],
      ),
      builder: (context, snapshot) {
        final rows = snapshot.data;
        final hasChildren = rows != null && rows.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: indent,
              child: ListTile(
                onTap: () {
                  RadioGroup.maybeOf<_Destination>(
                    context,
                  )?.onChanged(destination);
                  if (hasChildren) setState(() => _expanded = !_expanded);
                },
                leading: hasChildren
                    ? Icon(_expanded ? Icons.expand_more : Icons.chevron_right)
                    : const SizedBox(width: 24),
                title: Text(widget.name),
                trailing: Radio<_Destination>(value: destination),
              ),
            ),
            if (_expanded && hasChildren)
              Column(
                children: [
                  for (final row in rows)
                    _ContainerNode(
                      db: widget.db,
                      roomId: widget.roomId,
                      id: row['id'] as String,
                      name: row['name'] as String,
                      depth: widget.depth + 1,
                      expandedContainerIds: widget.expandedContainerIds,
                      movingContainerIds: widget.movingContainerIds,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
