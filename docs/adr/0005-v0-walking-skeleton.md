---
status: accepted
---

# v0 is a deliberately minimal walking skeleton, not a feature-complete first release

A prior attempt at this app snowballed in complexity and accumulated bad technical decisions before anything was validated end-to-end on real devices. To avoid repeating that, v0 deliberately strips the data model down to just Room + Item (skipping Container, Placement details, quantity/price/serial, Dispose/Delete, Item history, Export, Device overview, and Restore — all already designed, just not built yet) and targets only Android + macOS (skipping iOS's recurring free-signing cost). The goal of v0 is proving the full pipeline works — device pairing, PowerSync sync across devices, CI builds, and manual deploy to the self-hosted server — validated manually on real hardware, before adding scope. Every deferred feature is intentionally deferred, not forgotten.
