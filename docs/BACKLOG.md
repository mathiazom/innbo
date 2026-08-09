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

- [ ] `container` (nesting under room/container)
- [x] `placement` field on item — freeform optional text, captured at creation only (see below). Migration `0003_item_placement.sql`, `upload.go` allowlist, `schema.dart`, `kClientVersion` bump — see [ADR-0004](adr/0004-schema-migration-strategy.md).
- [ ] Editable items — today nothing about an item is editable after creation except images; `name`, `room_id`, and now `placement` are all write-once at creation. Deliberately scoped out of the `placement` slice (see grilling notes) since it'd otherwise become the first item-editing UI ever built, buried inside an unrelated field addition. Needs its own slice: an edit affordance (likely in `item_detail_screen.dart`) covering all three fields, not just whichever field happens to need it next.
- [ ] `quantity`, `purchase_price`, `acquired_date`, `serial_number` on item
- [ ] Dispose action (soft-delete, `disposed_at`)
- [ ] Delete action (hard-delete, erases history)
- [ ] `item_history` audit trail — see [ADR-0002](adr/0002-item-history-audit-trail.md)
- [x] `image` + cover image handling — local attach/view/delete (first slice) plus cross-device sync via the backend (this slice) — see [ADR-0006](adr/0006-image-storage-and-sync.md)

## Platform / infra

- [ ] client and server version in about app page
- [x] Server-side client-version gate for schema migrations — see [ADR-0004](adr/0004-schema-migration-strategy.md). Implemented: required version is computed from embedded, breaking-marked migrations ([migrate.go](../backend/internal/db/migrate.go)); [token.go](../backend/internal/httpapi/token.go) returns HTTP 426 + `required_version` on an exact-match mismatch; client sends `client_version` and handles 426 via [unsynced_changes_guard.dart](../client/lib/sync/unsynced_changes_guard.dart).
- [x] Prod config drift risk (powersync config) — `powersync/config.yaml`/`sync-rules.yaml` now ship baked into a published `innbo-powersync` image instead of being hand-copied onto the host — see [ADR-0007](adr/0007-powersync-config-image.md). `docker-compose.yml`'s remaining hand-maintained bits (external network name, etc.) are still a known, accepted residual risk.
- [x] Revisit ADR-0004's wipe-and-resync strategy against PowerSync's own schema-change guidance — see updated [ADR-0004](adr/0004-schema-migration-strategy.md): decision holds (that guidance targets rolling deploys across uncontrolled client versions, not this app's single-household/few-devices setup), but flagged an uncalled-out risk — PK/replica-identity/table-rename/publication changes trigger blocking full server-side re-replication, stalling sync for all devices, independent of the client wipe strategy.
- [ ] Restore-from-device flow — see [ADR-0003](adr/0003-restore-from-device.md)
- [ ] Device overview screen (paired devices, sync/image status, `paired_device.image_completeness_pct`)
- [ ] Background image sync when the app isn't open (`workmanager`/`connectivity_plus`) — deferred from the image upload/download API slice: full-res currently only fetches on-demand (never proactively, not even on Wi-Fi), and thumbnails only sync via foreground eager-fetch while the app happens to be open. Both were explicitly scoped out to keep that slice small.
- [ ] Persistent retry queue for failed image uploads — currently a failed upload gets a one-shot manual "tap to retry" snackbar (deliberate scope cut, see grilling notes in the image API slice); doesn't survive an app restart, so a failed upload during a closed app session is silently never retried until someone happens to revisit that photo.
- [ ] Orphaned image blob cleanup — the upload API accepts bytes for a client-generated id without confirming the metadata row ever arrives (see ADR-0006's accepted best-effort tradeoff), and there's no sweep for blobs whose row never synced (e.g. an abandoned item-creation flow). Currently accepted as harmless; revisit if storage usage ever becomes a concern.
- [ ] Itemized unsynced-changes list in the update-required guard — [`unsynced_changes_guard.dart`](../client/lib/sync/unsynced_changes_guard.dart) currently shows only a count of pending local writes when a schema-mismatched client is blocked (deliberate v0 scope cut, deferred past proving the pipeline); a user facing "discard and continue" has no way to see *what* they'd be discarding.
- [ ] Export
- [ ] iOS support (blocked on Apple Developer account)
- [ ] Web client

## Open design work (from project plan)

- [ ] Final Postgres schema + PowerSync sync rules beyond Room/Item/Image
- [x] Image upload/download API design — see [ADR-0006](adr/0006-image-storage-and-sync.md)
- [ ] `path_provider` / `connectivity_plus` / `workmanager` / `flutter_image_compress` integration plan
