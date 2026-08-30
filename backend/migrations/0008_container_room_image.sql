-- schema-version: breaking
ALTER TABLE image ALTER COLUMN item_id DROP NOT NULL;
ALTER TABLE image ADD COLUMN container_id uuid REFERENCES container(id);
ALTER TABLE image ADD COLUMN room_id uuid REFERENCES room(id);
ALTER TABLE image ADD CONSTRAINT image_owner_xor
  CHECK (num_nonnulls(item_id, container_id, room_id) = 1);
