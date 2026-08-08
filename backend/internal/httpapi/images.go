package httpapi

import (
	"bytes"
	"image"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/disintegration/imaging"
	"github.com/jackc/pgx/v5/pgxpool"
)

// maxImageUploadBytes caps a single image upload to guard disk usage —
// generous enough for an unedited phone photo.
const maxImageUploadBytes = 25 << 20

// maxThumbnailDim is the longest edge, in pixels, of a generated thumbnail.
const maxThumbnailDim = 512

// fullJPEGQuality re-encodes the (already orientation-corrected) full-res
// image at high quality — not the original bytes verbatim, since those
// carry whatever EXIF orientation the camera wrote, and not every client
// renders that consistently (see docs/adr/0006 update). Re-encoding once,
// server-side, means every consumer just sees already-correct pixels.
const fullJPEGQuality = 92

// handleImageUpload accepts a full-resolution image's raw bytes for an
// `image` row's id (see migrations/0002_image.sql). The row itself syncs
// separately through the ordinary PowerSync /upload path — this endpoint
// only ever sees bytes for an id, and doesn't require that row to have
// arrived in Postgres yet (metadata sync is async relative to this
// request), so it accepts unconditionally under the authenticated
// device's id: an orphaned blob if the row never arrives is harmless,
// matching ADR-0003's already-accepted best-effort character.
func handleImageUpload(pool *pgxpool.Pool, jwtSecret, storageDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, err := bearerDeviceID(r, jwtSecret); err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		id := r.PathValue("id")
		if id == "" {
			http.Error(w, "missing id", http.StatusBadRequest)
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, maxImageUploadBytes)
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "image too large", http.StatusRequestEntityTooLarge)
			return
		}

		// Decoding doubles as validation: reject anything that isn't a
		// real, supported image before writing it to disk. AutoOrientation
		// applies the EXIF orientation tag (phones commonly store portrait
		// photos as landscape pixels + a rotation tag) so every image
		// we store and serve already has correct pixel orientation baked
		// in — no consumer needs to interpret EXIF itself.
		img, err := imaging.Decode(bytes.NewReader(body), imaging.AutoOrientation(true))
		if err != nil {
			http.Error(w, "invalid image", http.StatusBadRequest)
			return
		}

		dir := filepath.Join(storageDir, id)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		// imaging.Save infers format from the filename extension, which
		// these extensionless files (see handleImageDownload) don't have —
		// use Encode directly with an explicit format instead.
		if err := encodeTo(filepath.Join(dir, "full"), img, imaging.JPEGQuality(fullJPEGQuality)); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		thumb := imaging.Fit(img, maxThumbnailDim, maxThumbnailDim, imaging.Lanczos)
		if err := encodeTo(filepath.Join(dir, "thumb"), thumb); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusNoContent)
	}
}

func encodeTo(path string, img image.Image, opts ...imaging.EncodeOption) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	return imaging.Encode(f, img, imaging.JPEG, opts...)
}

// handleImageDownload serves either variant ("full" or "thumb") of an
// already-uploaded image. http.ServeContent sniffs content-type from the
// bytes (files are stored without an extension — Flutter's Image.file and
// this both decode by content, not name) and handles range requests for
// free.
func handleImageDownload(pool *pgxpool.Pool, jwtSecret, storageDir, variant string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, err := bearerDeviceID(r, jwtSecret); err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		id := r.PathValue("id")
		if id == "" {
			http.Error(w, "missing id", http.StatusBadRequest)
			return
		}

		f, err := os.Open(filepath.Join(storageDir, id, variant))
		if err != nil {
			http.NotFound(w, r)
			return
		}
		defer func() { _ = f.Close() }()

		http.ServeContent(w, r, variant, time.Time{}, f)
	}
}
