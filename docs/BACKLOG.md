# Backlog

Slices for post-v0 work, roughly ordered. Check items off as they ship;
append new ones as they're identified. Each slice should be small enough
for one grill → plan → implement → review loop (see
[CLAUDE.md](../CLAUDE.md)).

v0 (the walking skeleton — Room/Item CRUD, pairing, sync, deploy pipeline)
is done; see [ADR-0005](adr/0005-v0-walking-skeleton.md). This is the queue
for everything after it, per the full scope in
[home-inventory-app-plan.md](home-inventory-app-plan.md).

## Data model

- [ ] Editable items — today nothing about an item is editable after creation except images; `name`, `room_id`, and now `placement` are all write-once at creation. Deliberately scoped out of the `placement` slice (see grilling notes) since it'd otherwise become the first item-editing UI ever built, buried inside an unrelated field addition. Needs its own slice: an edit affordance (likely in `item_detail_screen.dart`) covering all three fields, not just whichever field happens to need it next.
- [ ] Dispose action (soft-delete, `disposed_at`)
- [ ] `quantity`, `purchase_price`, `acquired_date`, `serial_number` on item
- [ ] move item between rooms
- [ ] `container` (nesting under room/container)
- [ ] documentation files on item (pdf)
- [ ] timestamped `note` on item (with activity timeline as list view)
- [ ] `item_history` audit trail — see [ADR-0002](adr/0002-item-history-audit-trail.md)
- [ ] Delete action (hard-delete, erases history)
- [x] `placement` field on item — freeform optional text, captured at creation only (see below). Migration `0003_item_placement.sql`, `upload.go` allowlist, `schema.dart`, `kClientVersion` bump — see [ADR-0004](adr/0004-schema-migration-strategy.md).
- [x] `image` + cover image handling — local attach/view/delete (first slice) plus cross-device sync via the backend (this slice) — see [ADR-0006](adr/0006-image-storage-and-sync.md)

## Client

- [ ] selectable text


## Platform / infra
- [ ] Restore-from-device flow — see [ADR-0003](adr/0003-restore-from-device.md)
- [ ] Revoke a paired device's access from the device overview screen — deliberately scoped out of the device overview slice (see grilling notes) to keep it display-only; `paired_device.revoked_at` already exists (unused) and `device.secret_hash` invalidation would need a new backend endpoint, not just a synced-row flag.
- [ ] Background image sync when the app isn't open (`workmanager`/`connectivity_plus`) — deferred from the image upload/download API slice: full-res currently only fetches on-demand (never proactively, not even on Wi-Fi), and thumbnails only sync via foreground eager-fetch while the app happens to be open. Both were explicitly scoped out to keep that slice small.
- [ ] Persistent retry queue for failed image uploads — currently a failed upload gets a one-shot manual "tap to retry" snackbar (deliberate scope cut, see grilling notes in the image API slice); doesn't survive an app restart, so a failed upload during a closed app session is silently never retried until someone happens to revisit that photo.
- [ ] Itemized unsynced-changes list in the update-required guard — [`unsynced_changes_guard.dart`](../client/lib/sync/unsynced_changes_guard.dart) currently shows only a count of pending local writes when a schema-mismatched client is blocked (deliberate v0 scope cut, deferred past proving the pipeline); a user facing "discard and continue" has no way to see *what* they'd be discarding.
- [ ] Export
- [ ] Web client
- [ ] Backend-proxied PowerSync sync — client would talk to the backend only (no direct PowerSync network exposure); deferred out of the "backend url on pairing" slice since it means relaying PowerSync's sync protocol (long-lived streaming, auth passthrough, reconnects) through the Go backend, an ADR-0007-level architecture change, not a pairing UX tweak.
- [ ] Orphaned image blob cleanup — the upload API accepts bytes for a client-generated id without confirming the metadata row ever arrives (see ADR-0006's accepted best-effort tradeoff), and there's no sweep for blobs whose row never synced (e.g. an abandoned item-creation flow). Currently accepted as harmless; revisit if storage usage ever becomes a concern.
- [ ] iOS support (blocked on Apple Developer account)
- [ ] Unpair debug affordance — `DeviceCredentials.clear()` ([device_credentials.dart](../client/lib/device_credentials.dart)) already exists but nothing calls it; today resetting pairing in local dev means manually clearing Keychain/app storage per platform. A button (debug builds only?) to call it and drop back to the pairing screen would save that manual step.
- [x] print QR code for pairing from server cli — `bootstrap-pairing` now renders the pairing code (and, if `PUBLIC_URL` is set, the server URL too) as an `innbo://pair?...` QR code in the terminal via `mdp/qrterminal`, alongside the existing plain-text output. The pairing screen gets a "Skann QR-kode" button (Android only, [pairing_screen.dart](../client/lib/pairing/pairing_screen.dart)) using `mobile_scanner` to prefill the server URL/code fields — no auto-submit, same manual "Koble til" + error handling as before. `app_links` also lets a stock camera app's scan open the app directly via a registered `innbo://pair` intent-filter. Device name now auto-fills from `device_info_plus` on screen load regardless of scan vs. manual entry.
- [x] Server-side client-version gate for schema migrations — see [ADR-0004](adr/0004-schema-migration-strategy.md). Implemented: required version is computed from embedded, breaking-marked migrations ([migrate.go](../backend/internal/db/migrate.go)); [token.go](../backend/internal/httpapi/token.go) returns HTTP 426 + `required_version` on an exact-match mismatch; client sends `client_version` and handles 426 via [unsynced_changes_guard.dart](../client/lib/sync/unsynced_changes_guard.dart).
- [x] Prod config drift risk (powersync config) — `powersync/config.yaml`/`sync-rules.yaml` now ship baked into a published `innbo-powersync` image instead of being hand-copied onto the host — see [ADR-0007](adr/0007-powersync-config-image.md). `docker-compose.yml`'s remaining hand-maintained bits (external network name, etc.) are still a known, accepted residual risk.
- [x] Revisit ADR-0004's wipe-and-resync strategy against PowerSync's own schema-change guidance — see updated [ADR-0004](adr/0004-schema-migration-strategy.md): decision holds (that guidance targets rolling deploys across uncontrolled client versions, not this app's single-household/few-devices setup), but flagged an uncalled-out risk — PK/replica-identity/table-rename/publication changes trigger blocking full server-side re-replication, stalling sync for all devices, independent of the client wipe strategy.
- [x] Device overview screen (paired devices, sync/image status, `paired_device.image_completeness_pct`) — new `paired_device` table (`backend/migrations/0004_paired_device.sql`, backfilled for devices paired before this migration), synced via PowerSync like any other table so every device sees every other device's status. `POST /pairing/exchange` now requires a device name and platform (`android`/`macos`); each device recomputes and writes its own `last_sync_at`/`image_completeness_pct` on app foreground and when [device_overview_screen.dart](../client/lib/devices/device_overview_screen.dart) opens — no background heartbeat. Reached via a "Vis alle enheter" button in the about dialog. Display-only: revocation is deferred (`revoked_at` column exists, unused) — see below.
- [x] only require backend url on pairing, powersync should be known to backend — backend now requires `POWERSYNC_PUBLIC_URL` and returns it in `POST /pairing/exchange`'s response; the pairing screen no longer asks for a PowerSync URL.
- [x] client and server version in about app page — Innbo logo replaces the "Rom" AppBar title ([room_list_screen.dart](../client/lib/rooms/room_list_screen.dart)); tapping it opens an about dialog ([about_dialog.dart](../client/lib/about_dialog.dart)) showing the client's `pubspec.yaml` version (`package_info_plus`, "dev" in debug builds) and the server's git-commit version (new unauthenticated `GET /version`, `-ldflags`-injected). PowerSync's own version was considered and dropped — its self-hosted service has no version-reporting HTTP endpoint, so a real "server-side PowerSync version" isn't cheaply achievable; see the sync status slice below instead.
- [x] PowerSync sync status in the about app page (or elsewhere) — surface whether the client is actively connected/synced to PowerSync (e.g. connection state, last sync time, pending upload count). Split out while grilling the version slice above: a real version number for the self-hosted PowerSync service isn't available over HTTP, but a live sync/connection status is a more useful and achievable signal anyway.


## Open design work (from project plan)

- [ ] Final Postgres schema + PowerSync sync rules beyond Room/Item/Image
- [ ] `path_provider` / `connectivity_plus` / `workmanager` / `flutter_image_compress` integration plan
- [x] Image upload/download API design — see [ADR-0006](adr/0006-image-storage-and-sync.md)
