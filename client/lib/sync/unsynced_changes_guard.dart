import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:powersync/powersync.dart';

/// Client-side safeguard for the wipe-and-resync migration strategy (see
/// docs/adr/0004-schema-migration-strategy.md). Runs when the backend
/// rejects this app version's token request as outdated (HTTP 426) — the
/// point at which it would be tempting to just silently discard local
/// data and tell the user to update.
///
/// v0 shows a count of unsynced changes only, not an itemized list of what
/// they are — real complexity, deferred past proving the pipeline.
Future<void> handleUpdateRequired(
  BuildContext context,
  PowerSyncDatabase database,
) async {
  final batch = await database.getCrudBatch();
  final pendingCount = batch?.crud.length ?? 0;

  if (pendingCount == 0) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oppdatering kreves'),
        content: const Text(
          'Denne versjonen av appen er for gammel til å synkronisere med '
          'serveren. Last ned en nyere versjon for å fortsette.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  if (!context.mounted) return;
  final discard = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Oppdatering kreves'),
      content: Text(
        'Du har $pendingCount usynkronisert(e) endring(er) som ikke er '
        'lagret på serveren ennå. Denne versjonen av appen er for gammel '
        'til å synkronisere — hvis du fortsetter nå, går disse endringene '
        'tapt.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Lukk uten å synkronisere'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Forkast og fortsett'),
        ),
      ],
    ),
  );

  if (discard == true) {
    await database.disconnectAndClear();
  } else {
    SystemNavigator.pop();
  }
}
