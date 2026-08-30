import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:powersync/powersync.dart' hide Column;

import 'backup/backup_screen.dart';
import 'device_credentials.dart';
import 'devices/device_overview_screen.dart';
import 'items/upload_queue.dart';
import 'time_format.dart';

/// Shows an "about" dialog with the running client's version (from
/// pubspec.yaml in release builds, a "dev" placeholder otherwise), the
/// paired server's own semver (fetched from GET /version, "utilgjengelig" if
/// unreachable — see backend/internal/httpapi/version.go), and the
/// PowerSync connection/sync status.
Future<void> showAboutAppDialog(
  BuildContext context,
  DeviceCredentials credentials,
  PowerSyncDatabase db,
) async {
  final clientVersion = kReleaseMode
      ? (await PackageInfo.fromPlatform()).version
      : 'dev';
  final serverVersion = _fetchServerVersion(credentials.serverUrl);

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
                      'Sist synkronisert: ${formatRelativeTime(status.lastSyncedAt)}',
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
                    _UploadQueueStatusRow(db: db, credentials: credentials),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SettingsTile(
                    icon: Icons.archive_outlined,
                    label: 'Sikkerhetskopi',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => BackupScreen(db: db)),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SettingsTile(
                    icon: Icons.devices_outlined,
                    label: 'Enheter',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DeviceOverviewScreen(
                            db: db,
                            credentials: credentials,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon), const SizedBox(height: 4), Text(label)],
        ),
      ),
    );
  }
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

/// Shows this device's live pending/failed image-upload counts, with a
/// button to force an immediate retry of every pending image, bypassing
/// UploadQueue's backoff — the only way to tell "genuinely stuck" apart
/// from "still waiting out its backoff" without waiting it out.
class _UploadQueueStatusRow extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;

  const _UploadQueueStatusRow({required this.db, required this.credentials});

  @override
  State<_UploadQueueStatusRow> createState() => _UploadQueueStatusRowState();
}

class _UploadQueueStatusRowState extends State<_UploadQueueStatusRow> {
  late Future<UploadCounts> _counts = UploadQueue.counts(widget.db);
  bool _retrying = false;

  Future<void> _retryNow() async {
    setState(() => _retrying = true);
    await UploadQueue.retryAllNow(widget.db, widget.credentials);
    if (!mounted) return;
    setState(() {
      _retrying = false;
      _counts = UploadQueue.counts(widget.db);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<UploadCounts>(
            future: _counts,
            builder: (context, snapshot) {
              final counts = snapshot.data;
              final text = counts == null
                  ? '…'
                  : '${counts.pending} venter, ${counts.failed} feilet';
              return Text('Bilder som ikke er lastet opp: $text');
            },
          ),
        ),
        IconButton(
          icon: _retrying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          tooltip: 'Prøv å laste opp nå',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: _retrying ? null : _retryNow,
        ),
      ],
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
