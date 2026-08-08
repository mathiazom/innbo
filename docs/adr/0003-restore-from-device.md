---
status: accepted
---

# Server disaster recovery restores from a single device, not from server-side backups

We explicitly chose not to run server-side backups (pg_dump/object-storage snapshots) — see the plan's Backup strategy. That means the only way to recover from "the server is gone" is to rebuild it from a device's local replica. PowerSync's normal data flow is Postgres → device, with no built-in device → fresh-Postgres path, so this requires a purpose-built in-app "Restore" flow: when a device re-pairs against an empty server and already holds non-empty local data, the app offers (with explicit confirmation, never automatically) to push every local row up as new writes and re-upload its locally-held full-res image files. This is accepted as best-effort — a device that hadn't fully synced every full-res image before the disaster will restore the server with some full-res images still missing, since no device is guaranteed to hold a complete replica (a deliberate earlier trade-off, not revisited here). A pairing token from the dead server is meaningless to the fresh instance regardless of URL, so re-pairing happens before restore in every case.
