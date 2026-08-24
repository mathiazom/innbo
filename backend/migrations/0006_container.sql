-- schema-version: breaking
CREATE TABLE container (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name                 text NOT NULL,
    room_id              uuid REFERENCES room(id),
    parent_container_id  uuid REFERENCES container(id),
    CHECK ((room_id IS NULL) != (parent_container_id IS NULL))
);

ALTER TABLE item ADD COLUMN container_id uuid REFERENCES container(id);

ALTER PUBLICATION powersync ADD TABLE container;
GRANT SELECT ON container TO powersync_repl;
