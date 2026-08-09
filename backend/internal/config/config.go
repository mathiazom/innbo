package config

import (
	"fmt"
	"os"
)

type Config struct {
	DatabaseURL  string
	JWTSecret    string
	ListenAddr   string
	StorageDir   string
	PowerSyncURL string
}

func Load() (Config, error) {
	cfg := Config{
		DatabaseURL:  os.Getenv("DATABASE_URL"),
		JWTSecret:    os.Getenv("JWT_SECRET"),
		ListenAddr:   envOr("LISTEN_ADDR", ":8080"),
		StorageDir:   envOr("STORAGE_DIR", "/data/images"),
		PowerSyncURL: os.Getenv("POWERSYNC_PUBLIC_URL"),
	}
	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return Config{}, fmt.Errorf("JWT_SECRET is required")
	}
	if cfg.PowerSyncURL == "" {
		return Config{}, fmt.Errorf("POWERSYNC_PUBLIC_URL is required")
	}
	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
