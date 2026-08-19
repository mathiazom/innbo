package httpapi

import (
	_ "embed"
	"net/http"
	"strings"
)

//go:embed VERSION
var versionFile string

// Version is the backend's own semver, bumped by scripts/release.sh and
// tagged api-vX.Y.Z — see backend/internal/httpapi/VERSION.
var Version = strings.TrimSpace(versionFile)

func handleVersion() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"version":"` + Version + `"}`))
	}
}
