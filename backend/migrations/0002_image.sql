-- schema-version: breaking
CREATE TABLE image (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id    uuid NOT NULL REFERENCES item(id),
    created_at bigint NOT NULL
);

ALTER PUBLICATION powersync ADD TABLE image;
GRANT SELECT ON image TO powersync_repl;
