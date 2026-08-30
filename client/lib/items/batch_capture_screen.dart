import 'dart:io';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../containers/breadcrumb_bar.dart';
import '../device_credentials.dart';
import 'image_actions.dart';
import 'item_image_grid.dart';
import 'item_name_text.dart';

const _uuid = Uuid();

/// Camera-first batch flow for adding several items in one go: take one or
/// more photos (or just give a name/placement) for the current item,
/// "Neste gjenstand" to move on, "Ferdig" to close. An item row is only
/// created once its slot has a photo, a name, or a placement — an empty
/// slot leaves nothing behind, so finishing never needs to delete anything.
class BatchCaptureScreen extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String roomId;
  final String? containerId;
  final List<String> breadcrumbs;

  const BatchCaptureScreen({
    super.key,
    required this.db,
    required this.credentials,
    required this.roomId,
    required this.containerId,
    required this.breadcrumbs,
  });

  @override
  State<BatchCaptureScreen> createState() => _BatchCaptureScreenState();
}

class _BatchCaptureScreenState extends State<BatchCaptureScreen> {
  String? _currentItemId;
  String? _currentName;
  String? _currentPlacement;
  bool _autoLaunchedThisSlot = false;

  PowerSyncDatabase get db => widget.db;
  DeviceCredentials get credentials => widget.credentials;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoLaunchCamera();
    });
  }

  /// On Android, a fresh (empty) slot opens the device camera immediately
  /// — no tap needed. Fires at most once per slot: cancelling the camera
  /// or otherwise leaving the slot empty never retries on its own, and a
  /// slot that already has an item never re-triggers it on an unrelated
  /// rebuild.
  void _maybeAutoLaunchCamera() {
    if (!mounted ||
        !Platform.isAndroid ||
        _currentItemId != null ||
        _autoLaunchedThisSlot) {
      return;
    }
    _autoLaunchedThisSlot = true;
    addFromCamera(context, db, credentials, 'item_id', _ensureItemId);
  }

  Future<String> _ensureItemId() async {
    final existing = _currentItemId;
    if (existing != null) return existing;
    final id = _uuid.v4();
    await db.execute(
      'INSERT INTO item (id, name, room_id, container_id) VALUES (?, NULL, ?, ?)',
      [id, widget.roomId, widget.containerId],
    );
    setState(() => _currentItemId = id);
    return id;
  }

  Future<void> _editNameAndPlacement(BuildContext context) async {
    final nameController = TextEditingController(text: _currentName ?? '');
    final placementController = TextEditingController(
      text: _currentPlacement ?? '',
    );
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navn og plassering'),
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

    if (_currentItemId == null) {
      if (newName == null && newPlacement == null) return;
      final id = _uuid.v4();
      await db.execute(
        'INSERT INTO item (id, name, room_id, container_id, placement) VALUES (?, ?, ?, ?, ?)',
        [id, newName, widget.roomId, widget.containerId, newPlacement],
      );
      setState(() {
        _currentItemId = id;
        _currentName = newName;
        _currentPlacement = newPlacement;
      });
      return;
    }

    await db.execute('UPDATE item SET name = ?, placement = ? WHERE id = ?', [
      newName,
      newPlacement,
      _currentItemId,
    ]);
    setState(() {
      _currentName = newName;
      _currentPlacement = newPlacement;
    });
  }

  void _nextItem() {
    setState(() {
      _currentItemId = null;
      _currentName = null;
      _currentPlacement = null;
      _autoLaunchedThisSlot = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoLaunchCamera();
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemId = _currentItemId;
    final placement = _currentPlacement;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: placement == null ? kToolbarHeight : kToolbarHeight + 14,
        title: placement == null
            ? ItemNameText(name: _currentName, overflow: TextOverflow.ellipsis)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ItemNameText(
                    name: _currentName,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    placement,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
      body: Column(
        children: [
          BreadcrumbBar(path: widget.breadcrumbs),
          Expanded(
            child: itemId == null
                ? const Center(
                    child: Text('Ta et bilde eller gi et navn for å starte.'),
                  )
                : ItemImageGrid(
                    db: db,
                    credentials: credentials,
                    itemId: itemId,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Ferdig'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: itemId == null ? null : _nextItem,
                  child: const Text('Neste gjenstand'),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'batch-capture-name',
            onPressed: () => _editNameAndPlacement(context),
            child: const Icon(Icons.edit),
          ),
          const SizedBox(width: 16),
          if (Platform.isAndroid) ...[
            FloatingActionButton(
              heroTag: 'batch-capture-camera',
              onPressed: () => addFromCamera(
                context,
                db,
                credentials,
                'item_id',
                _ensureItemId,
              ),
              child: const Icon(Icons.add_a_photo),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'batch-capture-library',
              onPressed: () => addFromLibrary(
                context,
                db,
                credentials,
                'item_id',
                _ensureItemId,
              ),
              child: const Icon(Icons.photo_library),
            ),
          ] else
            FloatingActionButton(
              heroTag: 'batch-capture-photo',
              onPressed: () => pickAndAddImage(
                context,
                db,
                credentials,
                'item_id',
                _ensureItemId,
              ),
              child: const Icon(Icons.add_a_photo),
            ),
        ],
      ),
    );
  }
}
