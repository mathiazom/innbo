package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	DatabaseURL      string
	JWTSecret        string
	ListenAddr       string
	MinClientVersion int64
	StorageDir       string
}

func Load() (Config, error) {
	minClientVersion, err := strconv.ParseInt(envOr("MIN_CLIENT_VERSION", "1"), 10, 64)
	if err != nil {
		return Config{}, fmt.Errorf("MIN_CLIENT_VERSION must be an integer: %w", err)
	}

	cfg := Config{
		DatabaseURL:      os.Getenv("DATABASE_URL"),
		JWTSecret:        os.Getenv("JWT_SECRET"),
		ListenAddr:       envOr("LISTEN_ADDR", ":8080"),
		MinClientVersion: minClientVersion,
		StorageDir:       envOr("STORAGE_DIR", "/data/images"),
	}
	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return Config{}, fmt.Errorf("JWT_SECRET is required")
	}
	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
