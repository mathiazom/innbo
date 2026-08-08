# Innbo — Home Inventory App — Project Plan

## Goal
A personal home inventory app to track possessions, accessible on iOS,
Android, macOS, and web. Offline-first with sync across devices via a
self-hosted central server. Each device holds a full local replica, so
devices double as backups if the server goes down — see [CONTEXT.md](../CONTEXT.md)
for the full glossary of terms used below (Room, Container, Item, Placement,
Dispose, Delete, Item history, Device pairing, Cover image, Household).

The UI is in Norwegian; all code, schema, and domain vocabulary stay English
(Norwegian exists only as a display-layer translation).

**Guiding principle:** every device holds a full local replica and can act
as a complete backup. Fetching data live from the server, rather than
reading the local replica, is the rare exception — the only current
exception is on-demand full-res image fetch on cellular, and even that gets
cached locally once fetched.

## Core data model

- **`household`**: implicit — one server instance serves exactly one
  household, so there's no `household_id` anywhere in the schema.
- **`room`**: name. Parent to `item` directly, and to `container`. Deleting a
  room that still holds items or containers is blocked.
- **`container`**: name (e.g. "Cupboard", "Drawers", "Bookshelf"), belongs to
  either a `room` or another `container` (nesting allowed, e.g. a drawer
  inside a cupboard) — every container traces back to exactly one room.
  Deleting a container that still holds items or child containers is
  blocked.
- **`item`**: name, `room_id`, `container_id` (nullable), `placement`
  (freeform text, optional, combinable with a container), `acquired_date`,
  `purchase_price` (total for the row, not per-unit, always NOK — no
  currency field), `serial_number` (free text, conventionally blank when
  `quantity` > 1), `quantity`, `disposed_at` (nullable — set on Dispose). No
  category/tag field — browsing is by room/container/name only.
- **`item_history`**: item_id, field name, old value, new value, changed_at,
  device_id (which paired device made the change — there are no user
  accounts to attribute to). Full field-level audit trail, synced via
  PowerSync like any other table so it's browsable offline. Erased entirely
  if the item is Deleted; preserved if the item is Disposed. Conflicting
  concurrent edits from two offline devices resolve last-write-wins on the
  `item` row, but both edits still appear as separate history entries.
- **`image`**: item_id, filename/hash, has_full_local flag. First-uploaded
  image is the implicit cover image — no `is_primary` flag.
- **`paired_device`**: name, platform (mobile/desktop/web), last_sync_at,
  image_completeness_pct, revoked_at (nullable). Synced like any other
  table so every device can see every other paired device's status.

Two distinct delete actions on an item:
- **Dispose** (soft-delete): sets `disposed_at`, item and history stay
  queryable. For real disposals (sold/discarded/lost).
- **Delete** (hard-delete): row and history erased entirely. For correcting
  a mistaken registration.

## Tech stack

- **Frontend:** Flutter (single codebase for iOS, Android, macOS, web).
  - Flutter Web support for the sync SDK is currently beta — fine for this
    project, just worth knowing.
- **Backend:** Self-hosted Postgres.
- **Metadata sync engine:** PowerSync, self-hosted (not just the managed
  cloud option). Syncs Postgres ↔ local SQLite per device via the
  `powersync` Dart/Flutter package.
  - On mobile/desktop this is a real SQLite file on disk.
  - On web it's backed by OPFS (browser-sandboxed, not a real OS file) —
    acceptable since web isn't expected to serve as a backup device.
- See [ADR-0001](adr/0001-powersync-over-couchdb.md) for why PowerSync was
  picked over CouchDB/PouchDB, and [ADR-0002](adr/0002-item-history-audit-trail.md)
  for the item-history design.

## Auth

Lightweight device pairing only — no user accounts or per-person logins. A
device gets a token/pairing code to talk to the server; every paired device
has the same full access.

**Bootstrapping the first device:** a server-side first-run setup step
(CLI, or an admin page reachable only from the server's own network)
generates the first pairing code. Every device after that gets its pairing
code issued from within the app itself.

**Revocation:** a paired device's access can be revoked from the Device
overview (below), invalidating its pairing token — covers a lost/stolen
device.

## Device overview

A household-wide screen, visible from any paired device, listing every
paired device: name, platform, last-sync time, and approximate full-res
image completeness (`image_completeness_pct`). Web devices are visibly
flagged as non-backup candidates, since OPFS storage isn't a durable local
replica. This is the practical way to answer "which device should I use to
restore?" before disaster strikes, and doubles as the UI for revoking a
device's pairing.

## Image storage & sync (separate from metadata sync)

Sync engines like PowerSync handle rows well, not blobs — images need their
own sync path, independent of the PowerSync/SQLite sync loop. Images are
stored as plain files on the server's filesystem (not a separate object
store like MinIO) — one less service to run for a single-household project.

**Pipeline:**
1. On capture/import, generate a thumbnail immediately (e.g.
   `flutter_image_compress` or the `image` package) alongside the full-res
   original. Upload both to the server together.
2. **Thumbnails:** always sync, on any connection (small, cheap).
3. **Full-res images:**
   - Auto-download only on Wi-Fi (check via `connectivity_plus`; run as a
     background job via `workmanager` so it doesn't require the app to be
     open).
   - On cellular: don't proactively fetch, but fetch on-demand when the user
     taps a photo without a local full-res copy — and cache it once fetched
     (don't discard after viewing).
4. **Per-device state tracking** (what full images exist locally) is local
   only — doesn't need to go through PowerSync. A local table or simple
   file-existence check (`images/{id}_full.jpg` on disk) is enough.

**Known trade-off:** backup completeness per device is eventually
consistent — a phone rarely on Wi-Fi may lag behind on full-res images even
though metadata/thumbnails are current. No device is guaranteed to hold a
complete replica of every full-res image, and that's accepted.

## Backup strategy

- Local SQLite replica on each device = de facto metadata backup.
- Full-res image sync (per above) = de facto image backup, per-device,
  eventually consistent.
- The "server and all devices die simultaneously" scenario is explicitly
  out of scope — considered unlikely enough not to design for. No
  server-side `pg_dump`/object-storage snapshot backup is planned; devices
  are the backup.

## Export

CSV/PDF export of currently-owned items (name, room, container, placement,
value, etc.) — e.g. to hand to an insurer without giving them app access.
Disposed items are excluded; export always reflects current holdings.

## Disaster recovery / restore

If the server is lost entirely, it's rebuilt from a single surviving
device's local replica — see [ADR-0003](adr/0003-restore-from-device.md).

- A pairing token is only valid against the server instance that issued it,
  so a fresh server (even at the same URL) requires the device to re-pair
  via the bootstrap first-pairing step, same as a brand-new server.
- When a device re-pairs against an empty server and already holds
  non-empty local data, the app offers a "Restore from this device?"
  action — always an explicit confirmation, never automatic (so a
  deliberate clean slate isn't silently overridden by stale local data).
- Confirmed restore pushes every local row up as new writes (PowerSync CRUD
  uploads), and re-uploads every full-res image file the device holds
  locally.
- Best-effort: any full-res image the device hadn't fully synced before the
  disaster stays missing after restore — consistent with no device being
  guaranteed to hold a complete image replica (see Image storage & sync).

## Schema migration strategy

Breaking Postgres schema changes are acceptable — this is a single
household with a handful of devices under direct control, not a service
with independent users to stay backward-compatible for. See
[ADR-0004](adr/0004-schema-migration-strategy.md).

- **Server:** plain sequential SQL migration files, applied on deploy — no
  migration framework needed at this scale.
- **Client:** an app update that bumps the schema version wipes its local
  PowerSync database and does a full fresh re-sync, rather than writing
  in-place local SQLite migrations.
- **Guardrail against data loss:** before deploying a breaking migration,
  every device is opened once to confirm its local upload queue is fully
  synced. The server also rejects connections from clients reporting an
  outdated schema/app version, so a forgotten device can't silently write
  against a schema it doesn't match.

## Branding

- **Name:** Innbo — capitalized ("Innbo") everywhere user-facing (README,
  app title, listing name, in-app); lowercase ("innbo") in code, schema,
  and package identifiers.
- **Bundle/package namespace:** `be.biku.innbo` (iOS/Android/macOS bundle
  IDs), based on the `biku.be` domain.
- **Logo/icon:** `logo.png` (a cardboard box with a cat on it) is the real
  logo, used wherever a full image fits; falls back to the 📦 emoji for
  tiny/text-only contexts (favicons, terminal, etc).
- **Palette:** warm brown/cream, matching the logo. Light theme only for
  now — no dark mode planned.
- **Tagline/description:** Norwegian-only, even in the README — no English
  marketing copy.

## Client distribution

- **Mobile (iOS/Android):** sideload / direct install only — no app store
  listings.
- **Desktop:** macOS only for now, packaged as a `.dmg` installer,
  distributed manually.
- **Web:** served directly by the self-hosted server as static files.
- **Updates:** fully manual reinstall on every platform — no auto-update
  mechanism.

**v0 walking-skeleton scope:** Android + macOS only. iOS is deferred until
ready to pay for an Apple Developer account — free-provisioning sideloads
expire and need re-signing every 7 days, not worth fighting during initial
pipeline validation.

## v0: walking skeleton

The first milestone is proving the whole pipeline end-to-end, not feature
completeness. Slow and validated beats fast and snowballed — see
[ADR-0005](adr/0005-v0-walking-skeleton.md).

- **Data model:** Room + Item only (name, room_id). No Container,
  Placement, quantity, price, serial number, Dispose/Delete, Item history,
  Export, Device overview, or Restore yet.
- **Platforms:** Android + macOS only. iOS deferred (see Client
  distribution).
- **CI:** GitHub Actions builds the backend Docker image (published to
  GitHub Container Registry) and the Android APK + macOS `.dmg` on
  push/tag. CI only — no auto-deploy.
- **Deploy:** manual — pull the new image and `docker compose up -d` on the
  existing self-hosted machine (already running docker-compose + nginx
  proxy manager as reverse proxy).
- **Client distribution:** built APK/.dmg attached to a GitHub Release;
  download directly onto each device from there.
- **Must work end-to-end before moving on:** device pairing (including the
  server-side bootstrap first-pairing step), PowerSync sync of Room/Item
  between at least two devices, and the manual deploy pipeline.

## Open items / next steps for build
- Design final Postgres schema (singular table names) + PowerSync sync
  rules/streams config, scoped to Room + Item for v0.
- Design the upload/download API for the image sync track (post-v0).
- Flesh out Flutter project structure and package choices (`path_provider`,
  `connectivity_plus`, `workmanager`, `flutter_image_compress`).
- Design the device-pairing flow (token/pairing-code issuance and
  validation), including the server-side bootstrap step.
- Design the server-side client-version gate (minimum supported version
  check) used by the schema migration strategy.
