CREATE TABLE paired_device (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id              uuid NOT NULL REFERENCES device(id),
    name                   text NOT NULL,
    platform               text CHECK (platform IS NULL OR platform IN ('android', 'macos')),
    last_sync_at           bigint, -- epoch millis, matching image.created_at's convention
    image_completeness_pct integer,
    revoked_at             timestamptz
);

-- Backfill a row for every device paired before this migration existed.
-- Placeholder name is renameable from the device overview screen.
INSERT INTO paired_device (device_id, name, platform)
SELECT id, 'Device ' || substr(replace(id::text, '-', ''), 1, 8), NULL
FROM device;

ALTER PUBLICATION powersync ADD TABLE paired_device;
GRANT SELECT ON paired_device TO powersync_repl;
