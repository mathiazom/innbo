package httpapi

import (
	"log"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Deps struct {
	Pool                  *pgxpool.Pool
	JWTSecret             string
	RequiredClientVersion int64
	StorageDir            string
}

func NewRouter(deps Deps) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealthz(deps.Pool))
	mux.HandleFunc("POST /pairing/exchange", handlePairingExchange(deps.Pool))
	mux.HandleFunc("POST /token", handleToken(deps.Pool, deps.JWTSecret, deps.RequiredClientVersion))
	mux.HandleFunc("POST /upload", handleUpload(deps.Pool, deps.JWTSecret, deps.StorageDir))
	mux.HandleFunc("PUT /images/{id}", handleImageUpload(deps.Pool, deps.JWTSecret, deps.StorageDir))
	mux.HandleFunc("GET /images/{id}/full", handleImageDownload(deps.Pool, deps.JWTSecret, deps.StorageDir, "full"))
	mux.HandleFunc("GET /images/{id}/thumbnail", handleImageDownload(deps.Pool, deps.JWTSecret, deps.StorageDir, "thumb"))
	return logRequests(deps.JWTSecret, mux)
}

// logRequests is the only access logging this server has — there was
// previously none at all, which made diagnosing "did the request even
// arrive" questions impossible from the container logs alone. Including
// the device id (best-effort — /token and /pairing/exchange requests
// don't have a bearer token yet) is what makes multi-device debugging
// possible from these logs at all.
func logRequests(jwtSecret string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		deviceID, err := bearerDeviceID(r, jwtSecret)
		if err != nil {
			deviceID = "-"
		}
		log.Printf("%s %s -> %d (%s) device=%s", r.Method, r.URL.Path, sw.status, time.Since(start), deviceID)
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}
