-- schema-version: breaking
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE room (
    id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL
);

CREATE TABLE item (
    id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name    text NOT NULL,
    room_id uuid NOT NULL REFERENCES room(id)
);

-- Server-internal only. Deliberately not part of the `powersync`
-- publication below — never synced to clients.
CREATE TABLE pairing_code (
    code       text PRIMARY KEY,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz
);

CREATE TABLE device (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    secret_hash bytea NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE PUBLICATION powersync FOR TABLE room, item;

-- LOGIN with no password: the password is set separately at startup from
-- POWERSYNC_DB_PASSWORD (see internal/db.SetPowersyncReplPassword), so it
-- never ends up committed in a migration file.
CREATE ROLE powersync_repl WITH REPLICATION LOGIN;
GRANT SELECT ON room, item TO powersync_repl;
