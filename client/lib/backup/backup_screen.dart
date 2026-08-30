import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;

import 'backup_export.dart';

/// Lets the user export the current household's rooms/containers/items and
/// full-res images as a single zip, then hand it off via the OS share
/// sheet — a manual, standalone backup independent of PowerSync sync.
class BackupScreen extends StatefulWidget {
  final PowerSyncDatabase db;

  const BackupScreen({super.key, required this.db});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await exportAndShareBackup(widget.db);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eksport feilet. Prøv igjen.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sikkerhetskopi')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lag en sikkerhetskopi av rom, beholdere, gjenstander og '
              'bilder som en zip-fil du kan lagre et sted utenfor Innbo.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: const Text('Eksporter'),
            ),
          ],
        ),
      ),
    );
  }
}
