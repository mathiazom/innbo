import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:powersync/powersync.dart' hide Column;

/// Shows an "about" dialog with the running client's version (from
/// pubspec.yaml in release builds, a "dev" placeholder otherwise — matching
/// the server's own fallback in backend/internal/httpapi/version.go), the
/// paired server's version (fetched from GET /version, "utilgjengelig" if
/// unreachable), and the PowerSync connection/sync status.
Future<void> showAboutAppDialog(
  BuildContext context,
  String serverUrl,
  PowerSyncDatabase db,
) async {
  final clientVersion = kReleaseMode
      ? (await PackageInfo.fromPlatform()).version
      : 'dev';
  final serverVersion = _fetchServerVersion(serverUrl);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Om Innbo'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<SyncStatus>(
              stream: db.statusStream,
              initialData: db.currentStatus,
              builder: (context, snapshot) {
                final status = snapshot.data;
                if (status == null) return const SizedBox.shrink();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ConnectionStateRow(status: status),
                    Text(
                      'Sist synkronisert: ${_formatRelative(status.lastSyncedAt)}',
                    ),
                    FutureBuilder<UploadQueueStats>(
                      future: db.getUploadQueueStats(),
                      builder: (context, pendingSnapshot) {
                        final text = pendingSnapshot.hasData
                            ? '${pendingSnapshot.data!.count}'
                            : '…';
                        return Text('Ulagrede endringer: $text');
                      },
                    ),
                    if (status.anyError != null) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Synkroniseringsfeil:',
                        style: TextStyle(color: Colors.red),
                      ),
                      _ErrorCodeBlock(error: status.anyError!),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text('Klientversjon: $clientVersion'),
            FutureBuilder<String>(
              future: serverVersion,
              builder: (context, snapshot) {
                final text = switch (snapshot.connectionState) {
                  ConnectionState.done => snapshot.data ?? 'utilgjengelig',
                  _ => 'laster …',
                };
                return Text('Serverversjon: $text');
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Lukk'),
        ),
      ],
    ),
  );
}

class _ErrorCodeBlock extends StatelessWidget {
  final Object error;

  const _ErrorCodeBlock({required this.error});

  @override
  Widget build(BuildContext context) {
    final text = error.toString();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.red.shade900,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Kopier feilmelding',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStateRow extends StatelessWidget {
  final SyncStatus status;

  const _ConnectionStateRow({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      SyncStatus(connected: true) => (
        Icons.check_circle,
        Colors.green,
        'Tilkoblet',
      ),
      SyncStatus(connecting: true) => (
        Icons.sync,
        Colors.amber,
        'Kobler til …',
      ),
      _ => (Icons.cloud_off, Colors.red, 'Frakoblet'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

String _formatRelative(DateTime? lastSyncedAt) {
  if (lastSyncedAt == null) return 'Aldri';
  final diff = DateTime.now().difference(lastSyncedAt);
  if (diff.inMinutes < 1) return 'nå nettopp';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'for $m ${m == 1 ? 'minutt' : 'minutter'} siden';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'for $h ${h == 1 ? 'time' : 'timer'} siden';
  }
  final d = diff.inDays;
  return 'for $d ${d == 1 ? 'dag' : 'dager'} siden';
}

Future<String> _fetchServerVersion(String serverUrl) async {
  try {
    final uri = Uri.parse(serverUrl).resolve('/version');
    final response = await http.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw Exception('bad status');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['version'] as String;
  } catch (_) {
    return 'utilgjengelig';
  }
}
