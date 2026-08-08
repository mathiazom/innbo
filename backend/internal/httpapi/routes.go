package httpapi

import (
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Deps struct {
	Pool             *pgxpool.Pool
	JWTSecret        string
	MinClientVersion int64
}

func NewRouter(deps Deps) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealthz(deps.Pool))
	mux.HandleFunc("POST /pairing/exchange", handlePairingExchange(deps.Pool))
	mux.HandleFunc("POST /token", handleToken(deps.Pool, deps.JWTSecret, deps.MinClientVersion))
	mux.HandleFunc("POST /upload", handleUpload(deps.Pool, deps.JWTSecret))
	return mux
}
