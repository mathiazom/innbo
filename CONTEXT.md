# Innbo

A personal, self-hosted home-inventory app: tracking possessions across rooms and devices.

Note: the app's UI is in Norwegian, but the canonical domain vocabulary below (and all code/schema) stays English — Norwegian exists only as a display-layer translation.

Branding: the product name is **Innbo** — capitalized as "Innbo" everywhere user-facing (README, app title, store/sideload listing, in-app), lowercase "innbo" in code/schema/package identifiers (e.g. bundle ID `be.biku.innbo`). The tagline/description is Norwegian-only, even in the README.

Principle: every device holds a full local replica and can act as a complete backup. Fetching data live from the server (rather than reading the local replica) is the rare exception, not the norm — the only current exception is on-demand full-res image fetch on cellular, and even that gets cached locally once fetched.

## Language

**Household**:
The single set of people and devices sharing one self-hosted server instance and its full inventory. A server instance serves exactly one household — there is no multi-tenancy.
_Avoid_: Tenant, account, workspace

**Device pairing**:
The act of granting a device access to the household's server via a token/pairing code. There are no user accounts or per-person logins — a paired device has the same full access as any other. A pairing token is only valid against the specific server instance that issued it — a fresh server (even at the same URL) requires re-pairing.
_Avoid_: Login, sign-in, user account

**Paired device**:
A structured, synced record of one device that has completed Device pairing: name, platform (mobile/desktop/web), last-sync time, and approximate full-res image completeness. Synced through the server so every device can see every other paired device's status — the basis for the household-wide Device overview and for judging restore candidates. Can be revoked, which invalidates that device's pairing token.
_Avoid_: Session, client

**Device overview**:
A household-wide view, visible from any paired device, listing every Paired device with its name, last-sync time, and image completeness. Web devices are visibly flagged as non-backup candidates (OPFS storage isn't a durable local replica).

**Restore**:
Rebuilding a destroyed server's data from a single device's local replica, by pushing its rows (and locally-held full-res image files) up to a fresh, empty server as if they were new writes. Offered as an explicit, user-confirmed choice when a device re-pairs against an empty server and already holds non-empty local data — never automatic. Best-effort: whatever full-res images that device hadn't fully synced before the disaster stay missing, since no device is guaranteed complete (see Item history / image sync).
_Avoid_: Recovery, rebuild, re-sync

**Room**:
A structured, reusable entity representing a physical room in the household. Parent to Items directly, and to Containers (which in turn hold Items).

**Container**:
A structured, reusable entity representing a piece of furniture or storage within a Room (e.g. "Cupboard", "Drawers", "Bookshelf") that an Item can optionally be placed in. A Container belongs either directly to a Room, or to another Container (nesting is allowed, e.g. a drawer inside a cupboard) — so every Container traces back to exactly one Room.
_Avoid_: Furniture, storage unit

Deleting a Room or Container that still holds Items or child Containers is blocked — contents must be moved or removed first.

**Placement**:
Freeform text on an Item giving finer-grained detail beyond its Room/Container (e.g. "top shelf" within a Container, or a bare description when there's no Container at all). Not a separate entity, and not versioned — only the current value is kept. Optional and combinable with a Container, not a replacement for one.
_Avoid_: Location (too broad — Room is the location; Placement is the freeform detail within it)

**Cover image**:
The image shown to represent an Item in list/grid views — always the first-uploaded image for that item (earliest `created_at`). Not a separate flag; not user-reorderable.

**Item**:
A row in the inventory representing either a single physical object or a set of identical ones, distinguished by `quantity`. Belongs to a Room, and optionally to a Container within that room. `serial_number` is a free-text field, conventionally left blank when `quantity` > 1 since a serial number identifies one physical unit, not a set — not enforced by the schema. `purchase_price` is always the total paid for the whole row (all units together), not a per-unit price, and always in NOK — no currency field, no multi-currency support. Removing an item is one of two distinct, explicit actions — see Dispose and Delete.

**Dispose**:
Soft-delete of an Item: sets `disposed_at`, keeps the row and its history queryable. Used when an item was actually owned and is now sold/discarded/lost.
_Avoid_: Delete, remove (ambiguous with Delete below)

**Delete**:
Hard-delete of an Item: the row and its history are erased entirely. Used to correct a mistaken registration — an item that was never really owned/entered correctly in the first place, not a real disposal event.
_Avoid_: Dispose, remove

**Item history**:
A full audit trail of every field-level edit on an Item (old value, new value, timestamp, and which paired device made the change), synced across devices through PowerSync like any other table — browsable offline. Erased entirely if the Item is Deleted; preserved if the Item is Disposed. Conflicting concurrent edits from two offline devices resolve last-write-wins on the Item row, but both edits still appear as separate History entries.
_Avoid_: Audit log, changelog
