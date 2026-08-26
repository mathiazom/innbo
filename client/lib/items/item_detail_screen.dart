import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:sqlite3/common.dart' show ResultSet;
import 'package:uuid/uuid.dart';

import '../containers/breadcrumb_bar.dart';
import '../device_credentials.dart';
import 'image_store.dart';
import 'image_sync.dart';
import 'upload_queue.dart';

const _uuid = Uuid();
final _picker = ImagePicker();

class ItemDetailScreen extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String itemId;
  final String itemName;
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
  late String _name = widget.itemName;
  late String? _placement = widget.itemPlacement;

  PowerSyncDatabase get db => widget.db;
  DeviceCredentials get credentials => widget.credentials;
  String get itemId => widget.itemId;

  Future<void> _editItem(BuildContext context) async {
    final nameController = TextEditingController(text: _name);
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

    if (result == null || result.$1.isEmpty) return;
    final (name, placement) = result;
    await db.execute('UPDATE item SET name = ?, placement = ? WHERE id = ?', [
      name,
      placement.isEmpty ? null : placement,
      itemId,
    ]);
    setState(() {
      _name = name;
      _placement = placement.isEmpty ? null : placement;
    });
  }

  Future<void> _addPickedImage(BuildContext context, XFile picked) async {
    final id = _uuid.v4();
    await ImageStore.saveFull(id, File(picked.path));
    await db.execute(
      'INSERT INTO image (id, item_id, created_at) VALUES (?, ?, ?)',
      [id, itemId, DateTime.now().millisecondsSinceEpoch],
    );
    final uploaded = await ImageSync.uploadFull(credentials, id);
    if (!uploaded) {
      await UploadQueue.enqueue(db, id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Kunne ikke laste opp bildet.'),
            action: SnackBarAction(
              label: 'Prøv igjen',
              onPressed: () => UploadQueue.retryDue(db, credentials),
            ),
          ),
        );
      }
    }
  }

  Future<void> _addFromCamera(BuildContext context) async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    // ignore: use_build_context_synchronously
    await _addPickedImage(context, picked);
  }

  Future<void> _addFromLibrary(BuildContext context) async {
    final picked = await _picker.pickMultiImage();
    for (final file in picked) {
      // ignore: use_build_context_synchronously
      await _addPickedImage(context, file);
    }
  }

  Future<void> _pickAndAddImage(BuildContext context) async {
    if (!Platform.isAndroid) {
      await _addFromLibrary(context);
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
    if (source == ImageSource.camera) {
      await _addFromCamera(context);
    } else {
      await _addFromLibrary(context);
    }
  }

  Future<void> _viewImage(
    BuildContext context,
    List<String> imageIds,
    int initialIndex,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ImageViewer(
          db: db,
          credentials: credentials,
          imageIds: imageIds,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _deleteImage(BuildContext context, String id) async {
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
    await ImageStore.delete(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: _placement == null
            ? kToolbarHeight
            : kToolbarHeight + 14,
        title: _placement == null
            ? Text(_name, overflow: TextOverflow.ellipsis)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_name, overflow: TextOverflow.ellipsis),
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
            child: StreamBuilder<ResultSet>(
              stream: db.watch(
                'SELECT id FROM image WHERE item_id = ? ORDER BY created_at ASC',
                parameters: [itemId],
              ),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? ResultSet([], null, []);
                if (rows.isEmpty) {
                  return const Center(child: Text('Ingen bilder ennå.'));
                }
                final ids = rows.map((r) => r['id'] as String).toList();
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final id = ids[index];
                    return GestureDetector(
                      onTap: () => _viewImage(context, ids, index),
                      onLongPress: () => _deleteImage(context, id),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: FutureBuilder<File?>(
                              future: ImageSync.ensureLocalThumbnail(
                                credentials,
                                id,
                              ),
                              builder: (context, snapshot) {
                                final file = snapshot.data;
                                if (file == null) {
                                  return const SizedBox.shrink();
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    // The file may be a full-res original
                                    // (see ImageSync.ensureLocalThumbnail)
                                    // — decode at roughly grid-cell size,
                                    // not full resolution.
                                    cacheWidth: 300,
                                  ),
                                );
                              },
                            ),
                          ),
                          _UploadStatusBadge(db: db, imageId: id),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAndAddImage(context),
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}

const _dotsThreshold = 10;

/// Full-screen, swipeable viewer over an item's images, opening at the
/// tapped thumbnail's position.
class _ImageViewer extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final List<String> imageIds;
  final int initialIndex;

  const _ImageViewer({
    required this.db,
    required this.credentials,
    required this.imageIds,
    required this.initialIndex,
  });

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_currentIndex < widget.imageIds.length - 1) {
        _controller.nextPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_currentIndex > 0) {
        _controller.previousPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final currentId = widget.imageIds[_currentIndex];
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _controller,
          // Swiping to change page conflicts with panning a zoomed-in
          // image, so freeze paging while the current page is zoomed —
          // programmatic navigation (keyboard arrows) still works,
          // since PageController.nextPage/previousPage ignore physics.
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.imageIds.length,
          onPageChanged: (index) => setState(() {
            _currentIndex = index;
            _zoomed = false;
          }),
          itemBuilder: (context, index) => _ImagePage(
            imageId: widget.imageIds[index],
            credentials: widget.credentials,
            onZoomChanged: (zoomed) => setState(() => _zoomed = zoomed),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.imageIds.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: widget.imageIds.length <= _dotsThreshold
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < widget.imageIds.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: CircleAvatar(
                                  radius: 4,
                                  backgroundColor: i == _currentIndex
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                          ],
                        )
                      : Text(
                          '${_currentIndex + 1} / ${widget.imageIds.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                ),
              StreamBuilder<UploadStatus>(
                stream: UploadQueue.statusStream(widget.db, currentId),
                builder: (context, snapshot) {
                  if (snapshot.data != UploadStatus.failed) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () async {
                        await UploadQueue.resetForManualRetry(
                          widget.db,
                          currentId,
                        );
                        await UploadQueue.retryDue(
                          widget.db,
                          widget.credentials,
                        );
                      },
                      child: const Text('Prøv å laste opp igjen'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single page of [_ImageViewer]: fetches and shows one full-resolution
/// image, pinch-zoomable, tap-to-close.
class _ImagePage extends StatefulWidget {
  final String imageId;
  final DeviceCredentials credentials;
  final ValueChanged<bool> onZoomChanged;

  const _ImagePage({
    required this.imageId,
    required this.credentials,
    required this.onZoomChanged,
  });

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage> {
  // Backstop: whatever ImageSync does internally, the UI must never wait
  // forever for it. Fetched once in initState, not build — _ImageViewer
  // rebuilds this widget on every page swipe, and a fresh future each
  // build would make FutureBuilder re-fetch and re-flash the spinner for
  // pages that are already loaded.
  late final Future<File?> _future = ImageSync.ensureLocalFull(
    widget.credentials,
    widget.imageId,
  ).timeout(const Duration(seconds: 20), onTimeout: () => null);

  final _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    widget.onZoomChanged(
      _transformationController.value.getMaxScaleOnAxis() > 1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(
            child: Text(
              'Kunne ikke hente bildet.',
              style: TextStyle(color: Colors.white),
            ),
          );
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 2.5,
            child: SizedBox.expand(
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }
}

/// Small overlay on a grid tile showing whether its upload is pending
/// retry or has permanently failed (see UploadQueue) — invisible once the
/// upload has succeeded and its upload_queue row is gone. Purely a status
/// indicator: a manual retry, when needed, lives in the full-screen image
/// view instead — a small overlaid icon is not a reliable tap target on
/// mobile, since it competes in the same gesture arena as the tile's own
/// tap-to-view handler.
class _UploadStatusBadge extends StatelessWidget {
  final PowerSyncDatabase db;
  final String imageId;

  const _UploadStatusBadge({required this.db, required this.imageId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UploadStatus>(
      stream: UploadQueue.statusStream(db, imageId),
      builder: (context, snapshot) {
        final status = snapshot.data ?? UploadStatus.none;
        if (status == UploadStatus.none) return const SizedBox.shrink();
        final failed = status == UploadStatus.failed;
        return Positioned(
          top: 4,
          right: 4,
          child: CircleAvatar(
            radius: 10,
            backgroundColor: failed ? Colors.red : Colors.amber,
            child: Icon(
              failed ? Icons.priority_high : Icons.schedule,
              size: 12,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
