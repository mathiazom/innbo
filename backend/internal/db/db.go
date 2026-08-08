package db

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

func Connect(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("creating pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pinging database: %w", err)
	}
	return pool, nil
}

// SetPowersyncReplPassword sets the powersync_repl role's password on every
// startup. Migration 0001 deliberately creates that role with no password,
// so it never ends up committed to a migration file — this is the only
// place the real value (from POWERSYNC_DB_PASSWORD) touches the database.
func SetPowersyncReplPassword(ctx context.Context, pool *pgxpool.Pool, password string) error {
	// ALTER ROLE's password clause is a string literal in Postgres's
	// grammar, not a bindable parameter position, so it can't go through
	// pgx's normal $1 placeholder. The value is our own env var, not user
	// input, but it's still escaped as a standard SQL string literal.
	escaped := strings.ReplaceAll(password, "'", "''")
	_, err := pool.Exec(ctx, fmt.Sprintf(`ALTER ROLE powersync_repl WITH PASSWORD '%s'`, escaped))
	if err != nil {
		return fmt.Errorf("setting powersync_repl password: %w", err)
	}
	return nil
}
