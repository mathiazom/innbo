import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;

import '../device_credentials.dart';
import '../powersync/synced_list_view.dart';
import '../time_format.dart';
import 'device_status_sync.dart';

/// Lists every paired_device row (see backend/migrations/0004_paired_device.sql)
/// — every device in the household can see every other device's sync/image
/// status, to help decide which device to restore from before disaster
/// strikes. Display-only: no revoke affordance yet.
class DeviceOverviewScreen extends StatefulWidget {
  final PowerSyncDatabase db;
  final DeviceCredentials credentials;

  const DeviceOverviewScreen({
    super.key,
    required this.db,
    required this.credentials,
  });

  @override
  State<DeviceOverviewScreen> createState() => _DeviceOverviewScreenState();
}

class _DeviceOverviewScreenState extends State<DeviceOverviewScreen> {
  @override
  void initState() {
    super.initState();
    refreshDeviceStatus(widget.db, widget.credentials);
  }

  Future<void> _rename(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Endre enhetsnavn'),
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
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(value.text.trim()),
              child: const Text('Lagre'),
            ),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    await widget.db.execute(
      'UPDATE paired_device SET name = ? WHERE device_id = ?',
      [name, widget.credentials.deviceId],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enheter')),
      body: SyncedListView(
        db: widget.db,
        query: widget.db.watch(
          'SELECT device_id, name, platform, last_sync_at, '
          'image_completeness_pct FROM paired_device '
          'ORDER BY last_sync_at DESC',
        ),
        emptyText: 'Ingen parede enheter ennå.',
        itemBuilder: (context, rows) => ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final deviceId = row['device_id'] as String;
            final name = row['name'] as String;
            final platform = row['platform'] as String?;
            final lastSyncAtMillis = row['last_sync_at'] as int?;
            final completenessPct = row['image_completeness_pct'] as int?;
            final isThisDevice = deviceId == widget.credentials.deviceId;

            return ListTile(
              leading: Icon(switch (platform) {
                'android' => Icons.phone_android,
                'macos' => Icons.laptop_mac,
                _ => Icons.devices_other,
              }),
              title: Row(
                children: [
                  Flexible(child: Text(name)),
                  if (isThisDevice) ...[
                    const SizedBox(width: 8),
                    const Chip(
                      label: Text('denne enheten'),
                      labelStyle: TextStyle(color: Colors.black, fontSize: 9),
                      backgroundColor: Color.fromARGB(255, 255, 225, 203),
                      visualDensity: VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.symmetric(
                        horizontal: -4,
                        vertical: -4,
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                'Sist synkronisert: ${formatRelativeTime(lastSyncAtMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(lastSyncAtMillis))} · '
                'Bilder lagret lokalt: ${completenessPct ?? 0}%',
              ),
              onTap: isThisDevice ? () => _rename(name) : null,
            );
          },
        ),
      ),
    );
  }
}
