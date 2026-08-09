package db

import (
	"testing"
	"testing/fstest"
)

func TestRequiredClientVersion(t *testing.T) {
	fsys := fstest.MapFS{
		"0001_init.sql":      &fstest.MapFile{Data: []byte("-- schema-version: breaking\nCREATE TABLE room ();\n")},
		"0002_add_index.sql": &fstest.MapFile{Data: []byte("CREATE INDEX idx_room_name ON room (name);\n")},
		"0003_image.sql":     &fstest.MapFile{Data: []byte("-- schema-version: breaking\nCREATE TABLE image ();\n")},
	}

	got, err := requiredClientVersion(fsys)
	if err != nil {
		t.Fatalf("requiredClientVersion() error: %v", err)
	}
	// 0002 isn't marked breaking, so the highest breaking migration is
	// 0003, not 0002 — this is the branch a real-embedded-migrations test
	// can't exercise while every real migration happens to be breaking.
	const want = 3
	if got != want {
		t.Fatalf("requiredClientVersion() = %d, want %d", got, want)
	}
}

func TestRequiredClientVersion_RealMigrations(t *testing.T) {
	if _, err := RequiredClientVersion(); err != nil {
		t.Fatalf("RequiredClientVersion() error against the real embedded migrations: %v", err)
	}
}

func TestMigrationVersion(t *testing.T) {
	if _, err := migrationVersion("no-underscore.sql"); err == nil {
		t.Fatal("migrationVersion(\"no-underscore.sql\") should error, got nil")
	}
	got, err := migrationVersion("0003_container.sql")
	if err != nil {
		t.Fatalf("migrationVersion() error: %v", err)
	}
	if got != 3 {
		t.Fatalf("migrationVersion() = %d, want 3", got)
	}
}
