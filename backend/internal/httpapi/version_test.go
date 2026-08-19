package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandleVersion(t *testing.T) {
	old := Version
	Version = "1.2.3"
	defer func() { Version = old }()

	req := httptest.NewRequest("GET", "/version", nil)
	rec := httptest.NewRecorder()
	handleVersion()(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}

	var body struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("json.Unmarshal() error: %v", err)
	}
	if body.Version != "1.2.3" {
		t.Fatalf("version = %q, want %q", body.Version, "1.2.3")
	}
}
