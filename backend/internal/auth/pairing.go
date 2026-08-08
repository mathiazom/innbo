package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
)

// pairingCodeAlphabet excludes visually ambiguous characters (0/O, 1/I/L)
// since a pairing code is meant to be typed by hand on a phone.
const pairingCodeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

// GeneratePairingCode returns an 8-character human-typeable code.
func GeneratePairingCode() (string, error) {
	const length = 8
	buf := make([]byte, length)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	code := make([]byte, length)
	for i, b := range buf {
		code[i] = pairingCodeAlphabet[int(b)%len(pairingCodeAlphabet)]
	}
	return string(code), nil
}

// GenerateDeviceSecret returns a high-entropy secret to hand to a newly
// paired device, and the sha256 hash of it to store server-side. The
// secret itself is never stored — only its hash, same reasoning as a
// password hash, but sha256 (not bcrypt) is enough since this is a
// high-entropy random token an attacker can't dictionary-guess.
func GenerateDeviceSecret() (secret string, hash []byte, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", nil, err
	}
	secret = hex.EncodeToString(buf)
	sum := sha256.Sum256([]byte(secret))
	return secret, sum[:], nil
}

// HashDeviceSecret hashes a client-supplied secret the same way, for
// comparison against the stored hash.
func HashDeviceSecret(secret string) []byte {
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}
