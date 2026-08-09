package db

import (
	"context"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mathiazom/innbo/backend/migrations"
)

// breakingMarker, as a migration file's first line, means the client must
// declare its own kClientVersion as this migration's numeric prefix
// before the server accepts its connection — see
// docs/adr/0004-schema-migration-strategy.md.
const breakingMarker = "-- schema-version: breaking"

var migrationsFS = migrations.FS

const migrationsDir = "."

// Migrate applies any migration files under migrationsDir that aren't yet
// recorded in schema_migrations, in filename order, each in its own
// transaction.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	if _, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version    text PRIMARY KEY,
			applied_at timestamptz NOT NULL DEFAULT now()
		)
	`); err != nil {
		return fmt.Errorf("creating schema_migrations: %w", err)
	}

	entries, err := fs.ReadDir(migrationsFS, migrationsDir)
	if err != nil {
		return fmt.Errorf("reading embedded migrations: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	for _, name := range names {
		var alreadyApplied bool
		if err := pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = $1)`,
			name,
		).Scan(&alreadyApplied); err != nil {
			return fmt.Errorf("checking migration %s: %w", name, err)
		}
		if alreadyApplied {
			continue
		}

		sqlBytes, err := fs.ReadFile(migrationsFS, name)
		if err != nil {
			return fmt.Errorf("reading migration %s: %w", name, err)
		}

		tx, err := pool.Begin(ctx)
		if err != nil {
			return fmt.Errorf("beginning transaction for %s: %w", name, err)
		}
		if _, err := tx.Exec(ctx, string(sqlBytes)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("applying migration %s: %w", name, err)
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO schema_migrations (version) VALUES ($1)`, name,
		); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("recording migration %s: %w", name, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("committing migration %s: %w", name, err)
		}
	}

	return nil
}

// RequiredClientVersion returns the version number of the highest-numbered
// embedded migration marked breaking — the value clients must exactly
// match for the /token gate to pass. It's a fact of which migrations this
// binary was built with, not a separately maintained setting, so it can't
// drift from the migrations actually applied on startup.
func RequiredClientVersion() (int64, error) {
	return requiredClientVersion(migrationsFS)
}

func requiredClientVersion(fsys fs.FS) (int64, error) {
	entries, err := fs.ReadDir(fsys, migrationsDir)
	if err != nil {
		return 0, fmt.Errorf("reading embedded migrations: %w", err)
	}

	var required int64
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		breaking, err := isBreakingMigration(fsys, e.Name())
		if err != nil {
			return 0, err
		}
		if !breaking {
			continue
		}
		version, err := migrationVersion(e.Name())
		if err != nil {
			return 0, err
		}
		if version > required {
			required = version
		}
	}
	return required, nil
}

func isBreakingMigration(fsys fs.FS, name string) (bool, error) {
	sqlBytes, err := fs.ReadFile(fsys, name)
	if err != nil {
		return false, fmt.Errorf("reading migration %s: %w", name, err)
	}
	firstLine, _, _ := strings.Cut(string(sqlBytes), "\n")
	return strings.TrimSpace(firstLine) == breakingMarker, nil
}

func migrationVersion(name string) (int64, error) {
	prefix, _, ok := strings.Cut(name, "_")
	if !ok {
		return 0, fmt.Errorf("migration %s doesn't follow the NNNN_name.sql convention", name)
	}
	version, err := strconv.ParseInt(prefix, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("migration %s has a non-numeric version prefix: %w", name, err)
	}
	return version, nil
}
