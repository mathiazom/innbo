import 'package:flutter/material.dart';

/// Muted path trail shown as its own row under an AppBar (not part of the
/// AppBar itself) — used on [ContentsScreen] and item detail to show which
/// room/containers something is nested under. Renders nothing for an empty
/// path (e.g. at room root, where there's no ancestor to show).
class BreadcrumbBar extends StatelessWidget {
  final List<String> path;

  const BreadcrumbBar({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            path.join(' › '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
