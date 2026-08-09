package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mathiazom/innbo/backend/internal/auth"
)

type tokenRequest struct {
	DeviceID      string `json:"device_id"`
	DeviceSecret  string `json:"device_secret"`
	ClientVersion int64  `json:"client_version"`
}

type tokenResponse struct {
	Token string `json:"token"`
}

type upgradeRequiredResponse struct {
	Error           string `json:"error"`
	RequiredVersion int64  `json:"required_version"`
}

func handleToken(pool *pgxpool.Pool, jwtSecret string, requiredClientVersion int64) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req tokenRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.DeviceID == "" || req.DeviceSecret == "" {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}

		ctx := r.Context()
		var storedHash []byte
		err := pool.QueryRow(ctx,
			`SELECT secret_hash FROM device WHERE id = $1`,
			req.DeviceID,
		).Scan(&storedHash)
		if err == pgx.ErrNoRows {
			http.Error(w, "invalid device credential", http.StatusUnauthorized)
			return
		}
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		if !bytes.Equal(storedHash, auth.HashDeviceSecret(req.DeviceSecret)) {
			http.Error(w, "invalid device credential", http.StatusUnauthorized)
			return
		}

		if req.ClientVersion != requiredClientVersion {
			writeJSON(w, http.StatusUpgradeRequired, upgradeRequiredResponse{
				Error:           "please update",
				RequiredVersion: requiredClientVersion,
			})
			return
		}

		token, err := auth.SignPowerSyncToken(jwtSecret, req.DeviceID)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		writeJSON(w, http.StatusOK, tokenResponse{Token: token})
	}
}
