package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/mathiazom/innbo/backend/internal/auth"
	"github.com/mathiazom/innbo/backend/internal/config"
	"github.com/mathiazom/innbo/backend/internal/db"
	"github.com/mdp/qrterminal/v3"
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

	// The app registers an "innbo://pair" intent-filter, so scanning this
	// link (in-app, or via the phone's stock camera app) opens it straight
	// to pairing. The url param is omitted when PUBLIC_URL isn't set, so
	// the code still scans in but the server URL has to be typed by hand.
	query := url.Values{"code": {code}}
	if cfg.PublicURL != "" {
		query.Set("url", cfg.PublicURL)
	}
	payload := "innbo://pair?" + query.Encode()
	// Half-block rendering packs two QR module-rows into one printed
	// terminal row via unicode half-block glyphs — needed because a
	// terminal character cell is roughly twice as tall as it is wide, so
	// one-module-per-character (the package's default) prints a QR
	// stretched vertically instead of square.
	qrterminal.GenerateHalfBlock(payload, qrterminal.L, os.Stdout)

	if cfg.PublicURL != "" {
		fmt.Printf("Server URL: %s\n", cfg.PublicURL)
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
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.Copy(io.Discard, resp.Body)
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
