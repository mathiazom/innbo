# Innbo

A personal, self-hosted home-inventory app: tracking possessions across rooms and devices.

Note: the app's UI is in Norwegian, but the canonical domain vocabulary below (and all code/schema) stays English.

Branding: **Innbo** capitalized everywhere user-facing, lowercase `innbo` in code/schema/package identifiers.

Principle: every device holds a full local replica and can act as a complete backup. Live server reads are the rare exception, not the norm.

## Language

**Household** — the single set of people/devices sharing one self-hosted server instance. One household per server; no multi-tenancy.
_Avoid_: Tenant, account, workspace

**Device pairing** — granting a device access to the household's server via a token/code. No user accounts or logins; a paired device has full access.
_Avoid_: Login, sign-in, user account

**Paired device** — a synced record of a device that has paired: name, platform, last-sync time, image-sync status. Basis for the Device overview.
_Avoid_: Session, client

**Device overview** — household-wide view of every Paired device and its sync status.

**Room** — a physical room in the household. Parent to Items and Containers.

**Container** — furniture/storage within a Room that an Item can optionally sit in (e.g. "Cupboard", "Drawers"). Containers can nest inside other Containers, always tracing back to one Room.
_Avoid_: Furniture, storage unit

**Placement** — freeform text on an Item for detail beyond Room/Container (e.g. "top shelf"). Not a separate entity, not versioned, optional.
_Avoid_: Location (too broad — Room is the location; Placement is the detail within it)

**Cover image** — the image representing an Item in list/grid views: the first one uploaded. Not user-reorderable.

**Item** — a row in the inventory: name, Room, optional Container, optional Placement. Removing an item today is a plain hard-delete.
