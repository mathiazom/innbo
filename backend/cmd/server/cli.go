package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/mathiazom/innbo/backend/internal/auth"
	"github.com/mathiazom/innbo/backend/internal/config"
	"github.com/mathiazom/innbo/backend/internal/db"
)

// pairingCodeTTL is how long a bootstrap pairing code stays valid before a
// device must exchange it.
const pairingCodeTTL = 15 * time.Minute

// runCLI handles subcommands invoked as `./server <command> [args...]`.
// Subcommands are for sensitive/operator-only actions (like pairing
// bootstrap) that should never be reachable over HTTP, plus small
// operational helpers like `healthcheck` (distroless has no shell/curl for
// a normal Docker CMD-SHELL healthcheck).
func runCLI(command string, args []string) error {
	switch command {
	case "healthcheck":
		return runHealthcheck()
	case "bootstrap-pairing":
		return runBootstrapPairing()
	default:
		return fmt.Errorf("unknown command %q", command)
	}
}

// runBootstrapPairing generates a one-time pairing code and prints it to
// stdout for the operator to hand to the first device. This is a CLI
// subcommand rather than an HTTP endpoint precisely because it's a
// sensitive one-time action that shouldn't be network-reachable, even
// behind a reverse proxy.
func runBootstrapPairing() error {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	code, err := auth.GeneratePairingCode()
	if err != nil {
		return err
	}

	if _, err := pool.Exec(ctx,
		`INSERT INTO pairing_code (code, expires_at) VALUES ($1, $2)`,
		code, time.Now().Add(pairingCodeTTL),
	); err != nil {
		return fmt.Errorf("storing pairing code: %w", err)
	}

	fmt.Printf("Pairing code (valid %s): %s\n", pairingCodeTTL, code)
	return nil
}

func runHealthcheck() error {
	addr := envOr("LISTEN_ADDR", ":8080")
	resp, err := http.Get("http://localhost" + addr + "/healthz")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthz returned %d", resp.StatusCode)
	}
	return nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
