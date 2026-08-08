/// A plain increasing integer (like Android's versionCode), not semver —
/// the backend only ever needs `>=` comparisons against MIN_CLIENT_VERSION
/// (see docs/adr/0004-schema-migration-strategy.md).
const int kClientVersion = 1;
