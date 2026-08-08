# Backlog

Slices for post-v0 work, roughly ordered. Check items off as they ship;
append new ones as they're identified. Each slice should be small enough
for one grill → plan → implement → review loop (see project workflow).

v0 (the walking skeleton — Room/Item CRUD, pairing, sync, deploy pipeline)
is done; see [ADR-0005](adr/0005-v0-walking-skeleton.md). This is the queue
for everything after it, per the full scope in
[home-inventory-app-plan.md](home-inventory-app-plan.md).

## Data model

- [ ] `container` (nesting under room/container)
- [ ] `placement` field on item
- [ ] `quantity`, `purchase_price`, `acquired_date`, `serial_number` on item
- [ ] Dispose action (soft-delete, `disposed_at`)
- [ ] Delete action (hard-delete, erases history)
- [ ] `item_history` audit trail — see [ADR-0002](adr/0002-item-history-audit-trail.md)
- [x] `image` + cover image handling — local attach/view/delete (first slice) plus cross-device sync via the backend (this slice) — see [ADR-0006](adr/0006-image-storage-and-sync.md)

## Platform / infra

- [ ] Server-side client-version gate for schema migrations — see [ADR-0004](adr/0004-schema-migration-strategy.md)
- [ ] Prod config drift risk: `docker-compose.yml`/`powersync/config.yaml`/`powersync/sync-rules.yaml` on the production host are hand-maintained, not a git checkout — a real deploy already missed the `image` sync rule this way (silent, no error, just data that never synced). Candidate fix: clone this repo on the prod host and point the powersync volume mount at that checkout's `powersync/` directory, so `git pull` is what keeps config current instead of manual copying; `docker-compose.yml` itself can stay separately maintained for host-specific bits (external network name, etc).
- [ ] Revisit ADR-0004's wipe-and-resync strategy against PowerSync's own schema-change guidance (https://docs.powersync.com/maintenance-ops/implementing-schema-changes — recommends backwards-compatible client schema changes via versioned streams instead of wipe/resync; also notes column defaults/removals need an explicit per-row update since they don't auto-propagate, and some changes trigger blocking full re-replication)
- [ ] Restore-from-device flow — see [ADR-0003](adr/0003-restore-from-device.md)
- [ ] Device overview screen (paired devices, sync/image status, `paired_device.image_completeness_pct`)
- [ ] Wi-Fi auto-background full-res image download (`workmanager`/`connectivity_plus`) — deferred from the image upload/download API slice, which only does on-demand full-res fetch
- [ ] Export
- [ ] iOS support (blocked on Apple Developer account)
- [ ] Web client

## Open design work (from project plan)

- [ ] Final Postgres schema + PowerSync sync rules beyond Room/Item/Image
- [x] Image upload/download API design — see [ADR-0006](adr/0006-image-storage-and-sync.md)
- [ ] `path_provider` / `connectivity_plus` / `workmanager` / `flutter_image_compress` integration plan
