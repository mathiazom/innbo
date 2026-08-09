package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/mathiazom/innbo/backend/internal/config"
	"github.com/mathiazom/innbo/backend/internal/db"
	"github.com/mathiazom/innbo/backend/internal/httpapi"
)

func main() {
	if len(os.Args) > 1 {
		if err := runCLI(os.Args[1], os.Args[2:]); err != nil {
			log.Fatal(err)
		}
		return
	}

	if err := runServer(); err != nil {
		log.Fatal(err)
	}
}

func runServer() error {
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

	if err := db.Migrate(ctx, pool); err != nil {
		return err
	}

	requiredClientVersion, err := db.RequiredClientVersion()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(cfg.StorageDir, 0o755); err != nil {
		return err
	}

	if password := os.Getenv("POWERSYNC_DB_PASSWORD"); password != "" {
		if err := db.SetPowersyncReplPassword(ctx, pool, password); err != nil {
			return err
		}
	}

	router := httpapi.NewRouter(httpapi.Deps{
		Pool:                  pool,
		JWTSecret:             cfg.JWTSecret,
		RequiredClientVersion: requiredClientVersion,
		StorageDir:            cfg.StorageDir,
	})
	log.Printf("listening on %s", cfg.ListenAddr)
	return http.ListenAndServe(cfg.ListenAddr, router)
}
