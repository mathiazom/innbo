package httpapi

import (
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Deps struct {
	Pool                  *pgxpool.Pool
	JWTSecret             string
	RequiredClientVersion int64
	StorageDir            string
	PowerSyncURL          string
}

func NewRouter(deps Deps) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealthz(deps.Pool))
	mux.HandleFunc("GET /version", handleVersion())
	mux.HandleFunc("POST /pairing/exchange", handlePairingExchange(deps.Pool, deps.PowerSyncURL))
	mux.HandleFunc("POST /token", handleToken(deps.Pool, deps.JWTSecret, deps.RequiredClientVersion))
	mux.HandleFunc("POST /upload", requireClientVersion(deps.JWTSecret, deps.RequiredClientVersion,
		handleUpload(deps.Pool, deps.StorageDir)))
	mux.HandleFunc("PUT /images/{id}", requireClientVersion(deps.JWTSecret, deps.RequiredClientVersion,
		handleImageUpload(deps.Pool, deps.StorageDir)))
	mux.HandleFunc("GET /images/{id}/full", requireClientVersion(deps.JWTSecret, deps.RequiredClientVersion,
		handleImageDownload(deps.Pool, deps.StorageDir, "full")))
	mux.HandleFunc("GET /images/{id}/thumbnail", requireClientVersion(deps.JWTSecret, deps.RequiredClientVersion,
		handleImageDownload(deps.Pool, deps.StorageDir, "thumb")))
	return logRequests(deps.JWTSecret, deps.RequiredClientVersion, mux)
}

// logRequests is the only access logging this server has — there was
// previously none at all, which made diagnosing "did the request even
// arrive" questions impossible from the container logs alone. Including
// the device id (best-effort — /token and /pairing/exchange requests
// don't have a bearer token yet) is what makes multi-device debugging
// possible from these logs at all.
func logRequests(jwtSecret string, requiredClientVersion int64, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		deviceID, err := bearerDeviceID(r, jwtSecret, requiredClientVersion)
		if err != nil {
			deviceID = "-"
		}
		if sw.status >= http.StatusBadRequest && sw.errBody != "" {
			log.Printf("%s %s -> %d (%s) device=%s error=%q", r.Method, r.URL.Path, sw.status, time.Since(start), deviceID, strings.TrimSpace(sw.errBody))
		} else {
			log.Printf("%s %s -> %d (%s) device=%s", r.Method, r.URL.Path, sw.status, time.Since(start), deviceID)
		}
	})
}

type statusWriter struct {
	http.ResponseWriter
	status  int
	errBody string
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

// Write captures the response body for error statuses so it lands in the
// access log
func (w *statusWriter) Write(b []byte) (int, error) {
	if w.status >= http.StatusBadRequest {
		w.errBody += string(b)
	}
	return w.ResponseWriter.Write(b)
}
