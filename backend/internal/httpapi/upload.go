package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mathiazom/innbo/backend/internal/auth"
)

// crudOp mirrors PowerSync's client-side CrudEntry shape closely enough
// that the Flutter BackendConnector's uploadData() can serialize it
// directly: op is PUT (upsert), PATCH (partial update), or DELETE.
type crudOp struct {
	Op    string         `json:"op"`
	Table string         `json:"table"`
	ID    string         `json:"id"`
	Data  map[string]any `json:"data,omitempty"`
}

// allowedColumns whitelists which columns a client is allowed to write per
// table, since column names in a PATCH's data map come from client input
// and must never be interpolated into SQL unchecked.
var allowedColumns = map[string][]string{
	"room":  {"name"},
	"item":  {"name", "room_id", "placement"},
	"image": {"item_id", "created_at"},
}

func handleUpload(pool *pgxpool.Pool, storageDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var ops []crudOp
		if err := json.NewDecoder(r.Body).Decode(&ops); err != nil {
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

		var pendingImageDeletes []string
		for _, op := range ops {
			if _, ok := allowedColumns[op.Table]; !ok {
				http.Error(w, fmt.Sprintf("unknown table %q", op.Table), http.StatusBadRequest)
				return
			}
			if err := applyOp(ctx, tx, op, &pendingImageDeletes); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
		}

		if err := tx.Commit(ctx); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		// Best-effort: the row is already gone regardless of whether the
		// blob cleanup below succeeds.
		for _, id := range pendingImageDeletes {
			_ = os.RemoveAll(filepath.Join(storageDir, id))
		}

		w.WriteHeader(http.StatusNoContent)
	}
}

func applyOp(ctx context.Context, tx pgx.Tx, op crudOp, pendingImageDeletes *[]string) error {
	switch op.Op {
	case "PUT":
		return applyPut(ctx, tx, op)
	case "PATCH":
		return applyPatch(ctx, tx, op)
	case "DELETE":
		if _, err := tx.Exec(ctx, fmt.Sprintf(`DELETE FROM %s WHERE id = $1`, op.Table), op.ID); err != nil {
			return err
		}
		if op.Table == "image" {
			*pendingImageDeletes = append(*pendingImageDeletes, op.ID)
		}
		return nil
	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}

func applyPut(ctx context.Context, tx pgx.Tx, op crudOp) error {
	cols := allowedColumns[op.Table]
	values := make([]any, 0, len(cols)+1)
	values = append(values, op.ID)
	placeholders := make([]string, 0, len(cols))
	updateClauses := make([]string, 0, len(cols))
	for i, col := range cols {
		v, ok := op.Data[col]
		if !ok {
			return fmt.Errorf("missing field %q for %s", col, op.Table)
		}
		values = append(values, v)
		placeholders = append(placeholders, fmt.Sprintf("$%d", i+2))
		updateClauses = append(updateClauses, fmt.Sprintf("%s = EXCLUDED.%s", col, col))
	}
	query := fmt.Sprintf(
		`INSERT INTO %s (id, %s) VALUES ($1, %s) ON CONFLICT (id) DO UPDATE SET %s`,
		op.Table, strings.Join(cols, ", "), strings.Join(placeholders, ", "), strings.Join(updateClauses, ", "),
	)
	_, err := tx.Exec(ctx, query, values...)
	return err
}

func applyPatch(ctx context.Context, tx pgx.Tx, op crudOp) error {
	if len(op.Data) == 0 {
		return nil
	}
	allowed := allowedColumns[op.Table]
	values := make([]any, 0, len(op.Data)+1)
	values = append(values, op.ID)
	setClauses := make([]string, 0, len(op.Data))
	for col, v := range op.Data {
		if !contains(allowed, col) {
			return fmt.Errorf("column %q not writable on %s", col, op.Table)
		}
		values = append(values, v)
		setClauses = append(setClauses, fmt.Sprintf("%s = $%d", col, len(values)))
	}
	query := fmt.Sprintf(`UPDATE %s SET %s WHERE id = $1`, op.Table, strings.Join(setClauses, ", "))
	_, err := tx.Exec(ctx, query, values...)
	return err
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

// versionMismatchError distinguishes "the token is valid but the client is
// on the wrong schema version" from an actually-bad credential — see
// writeAuthError and docs/adr/0004-schema-migration-strategy.md. It exists
// because a token can outlive TokenTTL's own re-check: /token only gates
// at mint time, so a device already holding one from before a breaking
// deploy must be re-checked on every subsequent authenticated request, not
// just when it next asks for a fresh token.
type versionMismatchError struct{ required int64 }

func (e *versionMismatchError) Error() string { return "client version mismatch" }

// bearerDeviceID verifies both the bearer token and, on every call, the
// client's current declared schema version (sent as X-Client-Version,
// since the JWT itself carries none) — not just the version it happened
// to report when the token was minted.
func bearerDeviceID(r *http.Request, jwtSecret string, requiredClientVersion int64) (string, error) {
	header := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(header, prefix) {
		return "", fmt.Errorf("missing bearer token")
	}
	deviceID, err := auth.VerifyPowerSyncToken(jwtSecret, strings.TrimPrefix(header, prefix))
	if err != nil {
		return "", err
	}

	clientVersion, err := strconv.ParseInt(r.Header.Get("X-Client-Version"), 10, 64)
	if err != nil || clientVersion != requiredClientVersion {
		return "", &versionMismatchError{required: requiredClientVersion}
	}
	return deviceID, nil
}

// writeAuthError responds to a bearerDeviceID failure: 426 (with the
// current required version) for a version mismatch, 401 for anything else
// (missing/invalid/expired token).
func writeAuthError(w http.ResponseWriter, err error) {
	var versionErr *versionMismatchError
	if errors.As(err, &versionErr) {
		writeJSON(w, http.StatusUpgradeRequired, upgradeRequiredResponse{
			Error:           "please update",
			RequiredVersion: versionErr.required,
		})
		return
	}
	http.Error(w, "unauthorized", http.StatusUnauthorized)
}

// requireClientVersion gates a handler behind bearerDeviceID, so every
// route needing it (all but /healthz, /pairing/exchange, and /token
// itself, which is how a client gets a bearer token in the first place)
// shares one auth check instead of each repeating it.
func requireClientVersion(jwtSecret string, requiredClientVersion int64, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, err := bearerDeviceID(r, jwtSecret, requiredClientVersion); err != nil {
			writeAuthError(w, err)
			return
		}
		next(w, r)
	}
}
