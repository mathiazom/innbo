---
status: accepted
---

# Use PowerSync (Postgres ↔ SQLite) instead of CouchDB/PouchDB for sync

We need offline-first sync of a Postgres-backed self-hosted server to per-device SQLite replicas. CouchDB/PouchDB was considered: it offers native multi-master replication and built-in binary attachment sync, which would have handled images without a second sync path. We chose PowerSync instead, because the metadata model (rooms, items, images-as-rows) fits a relational schema naturally, and Postgres is a better fit for the kind of ad-hoc querying a personal inventory benefits from (filtering, reporting) than a document store. This means images need their own sync pipeline, separate from PowerSync — accepted as the cost of this choice, not a temporary gap to revisit.
