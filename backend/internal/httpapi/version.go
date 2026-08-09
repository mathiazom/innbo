package httpapi

import "net/http"

// Version is set at build time via -ldflags (see Dockerfile); "dev" when
// built without that flag (e.g. local docker-compose builds).
var Version = "dev"

func handleVersion() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		v := Version
		if len(v) > 7 {
			v = v[:7]
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"version":"` + v + `"}`))
	}
}
