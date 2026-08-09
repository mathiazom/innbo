package httpapi

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mathiazom/innbo/backend/internal/auth"
)

type pairingExchangeRequest struct {
	Code string `json:"code"`
}

type pairingExchangeResponse struct {
	DeviceID     string `json:"device_id"`
	DeviceSecret string `json:"device_secret"`
	PowerSyncURL string `json:"powersync_url"`
}

func handlePairingExchange(pool *pgxpool.Pool, powerSyncURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req pairingExchangeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Code == "" {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}

		ctx := r.Context()
		tx, err := pool.Begin(ctx)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer func() { _ = tx.Rollback(ctx) }()

		var expiresAt time.Time
		var usedAt *time.Time
		err = tx.QueryRow(ctx,
			`SELECT expires_at, used_at FROM pairing_code WHERE code = $1 FOR UPDATE`,
			req.Code,
		).Scan(&expiresAt, &usedAt)
		if err == pgx.ErrNoRows {
			http.Error(w, "invalid or expired pairing code", http.StatusUnauthorized)
			return
		}
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		if usedAt != nil || time.Now().After(expiresAt) {
			http.Error(w, "invalid or expired pairing code", http.StatusUnauthorized)
			return
		}

		secret, hash, err := auth.GenerateDeviceSecret()
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		var deviceID string
		if err := tx.QueryRow(ctx,
			`INSERT INTO device (secret_hash) VALUES ($1) RETURNING id`,
			hash,
		).Scan(&deviceID); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		if _, err := tx.Exec(ctx,
			`UPDATE pairing_code SET used_at = now() WHERE code = $1`,
			req.Code,
		); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		if err := tx.Commit(ctx); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		writeJSON(w, http.StatusOK, pairingExchangeResponse{
			DeviceID:     deviceID,
			DeviceSecret: secret,
			PowerSyncURL: powerSyncURL,
		})
	}
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
