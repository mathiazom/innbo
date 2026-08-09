package httpapi

import (
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mathiazom/innbo/backend/internal/auth"
)

func TestBearerDeviceID(t *testing.T) {
	secret := base64.RawURLEncoding.EncodeToString([]byte("0123456789abcdef0123456789abcdef"))
	token, err := auth.SignPowerSyncToken(secret, "device-1")
	if err != nil {
		t.Fatalf("SignPowerSyncToken() error: %v", err)
	}

	req := func(headerValue string, setHeader bool) *http.Request {
		r := httptest.NewRequest("POST", "/upload", nil)
		r.Header.Set("Authorization", "Bearer "+token)
		if setHeader {
			r.Header.Set("X-Client-Version", headerValue)
		}
		return r
	}

	t.Run("matching version succeeds", func(t *testing.T) {
		deviceID, err := bearerDeviceID(req("3", true), secret, 3)
		if err != nil {
			t.Fatalf("bearerDeviceID() error: %v", err)
		}
		if deviceID != "device-1" {
			t.Fatalf("bearerDeviceID() = %q, want %q", deviceID, "device-1")
		}
	})

	t.Run("missing header is a version mismatch", func(t *testing.T) {
		_, err := bearerDeviceID(req("", false), secret, 3)
		var versionErr *versionMismatchError
		if !errors.As(err, &versionErr) {
			t.Fatalf("bearerDeviceID() error = %v, want *versionMismatchError", err)
		}
		if versionErr.required != 3 {
			t.Fatalf("versionMismatchError.required = %d, want 3", versionErr.required)
		}
	})

	t.Run("mismatched version is a version mismatch", func(t *testing.T) {
		_, err := bearerDeviceID(req("2", true), secret, 3)
		var versionErr *versionMismatchError
		if !errors.As(err, &versionErr) {
			t.Fatalf("bearerDeviceID() error = %v, want *versionMismatchError", err)
		}
	})
}
