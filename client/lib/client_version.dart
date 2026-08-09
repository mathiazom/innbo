/// The numeric prefix of the highest-numbered backend migration (see
/// backend/migrations/) that this client's schema.dart has been updated
/// to handle — not a general app version. The backend computes its
/// required version from its own embedded migrations and rejects any
/// client that doesn't match exactly (see
/// docs/adr/0004-schema-migration-strategy.md), so bump this to the
/// matching migration's number whenever a breaking migration ships.
const int kClientVersion = 3;
