---
status: accepted
---

# Item history is a full field-level audit trail, synced via PowerSync, last-write-wins on conflict

Every field edit on an Item is logged (old value, new value, timestamp) in a history table, synced to devices through the normal PowerSync pipeline so history is browsable offline like any other data. When two offline devices edit the same field and both sync later, we don't attempt merge/CRDT resolution — the Item row resolves last-write-wins (PowerSync/Postgres default), but both edits still land as separate history entries, so a conflict is visible even though only one value survives on the row itself. This was chosen over building custom conflict resolution because concurrent edits are expected to be rare in a single-household app, and visibility into "what happened" matters more here than automatic merging. History is erased entirely if an Item is Deleted (mistaken entry), but preserved if an Item is Disposed.
