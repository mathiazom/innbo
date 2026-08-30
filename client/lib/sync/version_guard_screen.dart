import 'package:flutter/material.dart';

/// Describes a client-side block on further app use — see
/// docs/adr/0004-schema-migration-strategy.md and lib/main.dart's
/// `_connect`/`_finishConnecting`.
///
/// [mustUpdate]: the server currently rejects this device's app version
/// (HTTP 426) — a dead end once anything pending is discarded, since
/// there's nothing useful left to do until the app is updated and
/// reopened.
///
/// `!mustUpdate`: this device already has the current version, but has a
/// stale leftover queue from before it was updated — discarding it lets
/// startup continue normally.
class VersionGuard {
  final bool mustUpdate;
  final int pendingCount;

  /// Null when there's nothing to discard (mustUpdate with an empty
  /// queue) — the screen then shows a plain dead-end message with no
  /// button. Discarding is always an explicit tap; nothing here
  /// auto-discards.
  final Future<void> Function()? onDiscard;

  /// Null when there's nothing worth backing up (mirrors [onDiscard]'s
  /// null case). Lets the user export the not-yet-synced local data
  /// before it's discarded — entirely independent of [onDiscard]: running
  /// it does not discard anything, and discarding still needs its own tap.
  final Future<void> Function()? onBackup;

  const VersionGuard({
    required this.mustUpdate,
    required this.pendingCount,
    this.onDiscard,
    this.onBackup,
  });
}

/// Full-page block shown in place of the rest of the app (see
/// lib/main.dart's `build()`) while a [VersionGuard] is active — nothing
/// else in the app builds until it clears itself.
class VersionGuardScreen extends StatefulWidget {
  final VersionGuard guard;

  const VersionGuardScreen({super.key, required this.guard});

  @override
  State<VersionGuardScreen> createState() => _VersionGuardScreenState();
}

class _VersionGuardScreenState extends State<VersionGuardScreen> {
  bool _discarding = false;
  bool _backingUp = false;

  String get _message {
    final guard = widget.guard;
    if (guard.pendingCount == 0) {
      return 'Denne versjonen av appen er for gammel til å synkronisere '
          'med serveren. Last ned en nyere versjon for å fortsette.';
    }
    if (guard.mustUpdate) {
      return 'Du har ${guard.pendingCount} usynkronisert(e) endring(er) '
          'som ikke er lagret på serveren ennå. Denne versjonen av appen '
          'er for gammel til å synkronisere, og endringene kan ikke tas '
          'vare på. Forkast endringene og installer en nyere versjon for '
          'å fortsette.';
    }
    return 'Denne enheten ble oppdatert til en nyere versjon mens '
        '${guard.pendingCount} usynkronisert(e) endring(er) fortsatt lå '
        'igjen fra før oppdateringen. De er ikke kompatible med den nye '
        'versjonen og må forkastes.';
  }

  @override
  Widget build(BuildContext context) {
    final onDiscard = widget.guard.onDiscard;
    final onBackup = widget.guard.onBackup;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Oppdatering kreves',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(_message, textAlign: TextAlign.center),
                if (onBackup != null || onDiscard != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onBackup != null) ...[
                        OutlinedButton(
                          onPressed: _backingUp
                              ? null
                              : () async {
                                  setState(() => _backingUp = true);
                                  await onBackup();
                                  if (mounted) {
                                    setState(() => _backingUp = false);
                                  }
                                },
                          child: _backingUp
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sikkerhetskopier'),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (onDiscard != null)
                        FilledButton(
                          onPressed: _discarding
                              ? null
                              : () async {
                                  setState(() => _discarding = true);
                                  await onDiscard();
                                },
                          child: Text(
                            widget.guard.mustUpdate
                                ? 'Forkast endringene'
                                : 'Forkast',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
