---
status: accepted
---

# Client schema migrations wipe and re-sync, guarded by a manual pre-migration sync check, a server-side version gate, and a client-side unsynced-changes guard

Given a single household with a handful of devices under direct control and no auto-update, we accept breaking Postgres schema changes rather than designing for mixed old-client/new-schema compatibility — devices are simply kept up to date together. Rather than writing in-place local SQLite migrations, an app update that bumps the schema version wipes its local PowerSync database and does a full fresh re-sync from the server, since the server is the source of truth and a home inventory's data volume is small. The risk this creates — an old-version device with unsynced local writes losing them on wipe — is handled two ways: operationally, before deploying a breaking migration, every device is opened once to confirm its PowerSync upload queue is empty; and in code, as a safety net for a forgotten device — the server rejects connections from clients reporting a schema/app version other than what it currently requires (HTTP 426) rather than letting them silently write against a schema they don't match, and the client (`lib/sync/unsynced_changes_guard.dart`) reacts to that rejection by checking its own local upload queue and, if non-empty, blocking with an explicit "discard and continue" vs. "close without syncing" choice rather than ever wiping data without the user knowing.

## Release checklist for a breaking migration

The server never has a manually-set version to forget to bump.
`backend/migrations/*.sql` are `go:embed`'d into the backend binary and
applied automatically on startup (`internal/db.Migrate`) — deploying a
new backend image *is* applying the migration, not a separate step. So
the server's required version is computed from those same embedded
files (`internal/db.RequiredClientVersion`): a migration's first line
marks it breaking with `-- schema-version: breaking`, and the required
version is the numeric prefix of the highest-numbered migration so
marked. The gate is an exact match (`client_version == required`), not a
minimum threshold — the wipe-and-resync strategy keeps every device in
lockstep by design, so there's no "ahead" or "behind" version that's
still meant to work.

`client/lib/client_version.dart`'s `kClientVersion` stays a manually-set
constant, on purpose — it's the client codebase's own declaration ("my
schema.dart has been updated to handle migration N"), made by whoever
writes the client change. Auto-deriving it from the same migrations the
server reads would make the gate tautological: it'd only ever reflect
which commit each side was built from, never catch a real "client code
wasn't actually updated" mismatch.

Run through these steps top-to-bottom during a breaking migration:

1. Write the Postgres migration under `backend/migrations/`, with
   `-- schema-version: breaking` as its first line, and update PowerSync
   sync rules / the client's `schema.dart` as needed.
2. Manual pre-migration sync check: open every reachable device once
   (still on the old build) and confirm its PowerSync upload queue is
   empty. If a device can't be reached, proceed anyway — the
   server-side gate below is exactly the safety net for that case.
3. Tell every household user: **stop using the app now** until step 6.
   This isn't optional — the sync check in step 2 only proves the queue
   was empty at that moment, not that it stays empty until cutover.
4. Deploy the new backend/PowerSync images (`docker compose up -d`).
   This applies the migration and makes the new required version live in
   the same step — every device still on the old client now gets `426`
   on its next `/token` request.
5. Sanity-check the deploy actually picked up the new required version,
   using any already-paired device's real credentials (the version
   check in `handleToken` runs *after* credential validation, so a
   made-up device ID just gets `401` regardless of the gate):
   ```
   curl -s <server-url>/token -H 'Content-Type: application/json' \
     -d '{"device_id":"<real-device-id>","device_secret":"<real-secret>","client_version":0}'
   ```
   Expect `426` with `"required_version":<N>` matching the new
   migration's number. This mainly catches "forgot the marker comment,"
   since the value itself can't drift from what was just deployed.
6. Bump `kClientVersion` in `client/lib/client_version.dart` to match the
   new migration's number, cut a client release (`scripts/release.sh`),
   tell users it's safe to use the app again, and update each device.

## Re-checking version past token-mint time

`/token`'s gate only runs when a token is minted, and the resulting JWT
(`TokenTTL` = 1 hour) carries no version of its own — so a device already
holding a valid token from before a breaking deploy could otherwise keep
writing for up to an hour after the mismatch, regardless of the gate.
Closed by re-checking on every authenticated request, not just at mint
time: the client sends its current `kClientVersion` as an
`X-Client-Version` header on every call, and `bearerDeviceID` (shared by
`/upload` and both `/images/*` handlers) rejects a mismatch with `426`
just like `/token` does. Delivered as a plain header rather than a JWT
claim — avoids touching `auth/jwt.go` or restructuring `/upload`'s body
(a bare JSON array, not an object) — and trusted the same way `/token`
already trusts a client-reported `client_version`: this app's threat
model is a single household's own devices, not an adversarial one.

Accepted residual risk: PowerSync's own sync stream (the bucket-based
download/upload of replicated Postgres data) is authenticated once with
the same JWT, verified independently by PowerSync itself — it isn't
mediated by our backend per-request, so it stays ungated by
`client_version` for the life of the token no matter what we do to
`/upload`. Accepted because this ADR's actual concern is writes ("don't
let them silently write against a schema they don't match"), which is
now fully closed; reads are lower-risk by comparison — additive schema
changes are harmless to an old client, and destructive ones already
stall sync for everyone via the re-replication cost described below,
independent of any one device's version.

Revisited against [PowerSync's own schema-change guidance](https://docs.powersync.com/maintenance-ops/implementing-schema-changes), which pushes towards backwards-compatible changes and versioned sync streams instead of wiping clients. That guidance is aimed at rolling deploys across many uncontrolled client versions in the wild — the problem this app doesn't have, given a single household's handful of devices under direct control and no auto-update. Wipe-and-resync stays the right call here. The one gap worth carrying forward: some Postgres-side schema changes (primary key/replica identity changes, table renames, adding a table to the publication) make PowerSync's *server* re-replicate the whole table from Postgres, blocking sync for everyone until it finishes — a cost that exists independently of the client wipe strategy and isn't currently called out anywhere. When making a breaking migration of that shape, expect sync to stall for all connected devices during re-replication, not just the device being upgraded.
