import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show ResultSet;

/// Renders a PowerSync-backed list, distinguishing "still syncing" from
/// "confirmed empty" so [emptyText] never flashes before the initial sync
/// (or the query's first emission) has actually completed.
class SyncedListView extends StatelessWidget {
  final PowerSyncDatabase db;
  final Stream<ResultSet> query;
  final String emptyText;
  final Widget Function(BuildContext context, ResultSet rows) itemBuilder;

  const SyncedListView({
    super.key,
    required this.db,
    required this.query,
    required this.emptyText,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: db.statusStream,
      initialData: db.currentStatus,
      builder: (context, statusSnapshot) {
        if (statusSnapshot.data?.hasSynced != true) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<ResultSet>(
          stream: query,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return Center(child: Text(emptyText));
            }
            return itemBuilder(context, rows);
          },
        );
      },
    );
  }
}
