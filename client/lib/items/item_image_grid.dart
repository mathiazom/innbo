import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:sqlite3/common.dart' show ResultSet;

import '../device_credentials.dart';
import 'image_store.dart';
import 'image_sync.dart';
import 'upload_queue.dart';

Future<void> _deleteImage(
  BuildContext context,
  PowerSyncDatabase db,
  String id,
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
  await ImageStore.delete(id);
}

/// An item's photo grid: watches `image` rows for [itemId], shown 3-wide,
/// tap to open [ImageViewer], long-press to delete. Shared by
/// `ItemDetailScreen` and `BatchCaptureScreen` — same feature set either
/// way.
class ItemImageGrid extends StatelessWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final String itemId;

  const ItemImageGrid({
    super.key,
    required this.db,
    required this.credentials,
    required this.itemId,
  });

  Future<void> _viewImage(
    BuildContext context,
    List<String> imageIds,
    int initialIndex,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageViewer(
          db: db,
          credentials: credentials,
          imageIds: imageIds,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResultSet>(
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
              onLongPress: () => _deleteImage(context, db, id),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FutureBuilder<File?>(
                      future: ImageSync.ensureLocalThumbnail(credentials, id),
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
                            // The file may be a full-res original (see
                            // ImageSync.ensureLocalThumbnail) — decode at
                            // roughly grid-cell size, not full resolution.
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
    );
  }
}

const _dotsThreshold = 10;

/// Full-screen, swipeable viewer over a set of images, opening at the
/// tapped thumbnail's position.
class ImageViewer extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;
  final List<String> imageIds;
  final int initialIndex;

  const ImageViewer({
    super.key,
    required this.db,
    required this.credentials,
    required this.imageIds,
    required this.initialIndex,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
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

/// Single page of [ImageViewer]: fetches and shows one full-resolution
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
  // forever for it. Fetched once in initState, not build — ImageViewer
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
