package httpapi

import (
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
)

func handleHealthz(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var ok int
		if err := pool.QueryRow(r.Context(), "SELECT 1").Scan(&ok); err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	}
}
