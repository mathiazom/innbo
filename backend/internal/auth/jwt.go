package auth

import (
	"encoding/base64"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// TokenTTL is how long an issued PowerSync JWT is valid. PowerSync requires
// exp - iat <= 24h; short-lived tokens minted on demand (rather than one
// long-lived credential) keep the blast radius small if one leaks.
const TokenTTL = time.Hour

// PowerSyncAudience must match the `client_auth` audience configured in
// powersync/config.yaml.
const PowerSyncAudience = "innbo-powersync"

// PowerSyncKeyID must match the `kid` of the HS256 key in powersync/
// config.yaml's client_auth.jwks — PowerSync selects a key from its JWKS
// by matching this header, so a token signed without it is unverifiable
// even with the right secret (PSYNC_S2101, "no key matched the token KID").
const PowerSyncKeyID = "innbo-hs256"

// decodeHS256Secret turns the JWT_SECRET env value into raw key bytes.
// JWT_SECRET is stored base64url-encoded (no padding) specifically so it
// can be dropped as-is into PowerSync's client_auth JWK (`kty: oct`, whose
// `k` field is defined as base64url-encoded key bytes) — decoding here
// guarantees both sides sign/verify with the exact same bytes.
func decodeHS256Secret(secret string) ([]byte, error) {
	key, err := base64.RawURLEncoding.DecodeString(secret)
	if err != nil {
		return nil, fmt.Errorf("JWT_SECRET must be base64url-encoded: %w", err)
	}
	return key, nil
}

// SignPowerSyncToken issues a short-lived HS256 JWT for the given device,
// verified by PowerSync via the same shared secret.
func SignPowerSyncToken(secret, deviceID string) (string, error) {
	key, err := decodeHS256Secret(secret)
	if err != nil {
		return "", err
	}
	now := time.Now()
	claims := jwt.RegisteredClaims{
		Subject:   deviceID,
		Audience:  jwt.ClaimStrings{PowerSyncAudience},
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(TokenTTL)),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	token.Header["kid"] = PowerSyncKeyID
	signed, err := token.SignedString(key)
	if err != nil {
		return "", fmt.Errorf("signing token: %w", err)
	}
	return signed, nil
}

// VerifyPowerSyncToken validates a token minted by SignPowerSyncToken (the
// same one the client sends to PowerSync is reused as this device's bearer
// credential against our own /upload endpoint) and returns the device ID
// from its subject claim.
func VerifyPowerSyncToken(secret, tokenString string) (deviceID string, err error) {
	key, err := decodeHS256Secret(secret)
	if err != nil {
		return "", err
	}
	token, err := jwt.ParseWithClaims(tokenString, &jwt.RegisteredClaims{},
		func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return key, nil
		},
		jwt.WithAudience(PowerSyncAudience),
		jwt.WithValidMethods([]string{"HS256"}),
	)
	if err != nil {
		return "", fmt.Errorf("parsing token: %w", err)
	}
	claims, ok := token.Claims.(*jwt.RegisteredClaims)
	if !ok || !token.Valid || claims.Subject == "" {
		return "", fmt.Errorf("invalid token claims")
	}
	return claims.Subject, nil
}
