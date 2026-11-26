package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// newGameStaticHandler serves a temporary web export and keeps every request
// on the local cache path by clearing the mirror origin.
func newGameStaticHandler(t *testing.T, files map[string]string) (http.Handler, string) {
	t.Helper()
	t.Setenv("WEB_ORIGIN", "")
	dir := t.TempDir()
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
	}
	return staticGameHandler(dir), dir
}

func getGameFile(handler http.Handler, target string, headers map[string]string) *httptest.ResponseRecorder {
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, target, nil)
	request.Header.Set("Accept-Encoding", "identity")
	for name, value := range headers {
		request.Header.Set(name, value)
	}
	handler.ServeHTTP(recorder, request)
	return recorder
}

func TestGamePackRevalidatesInsteadOfDownloadingAgain(t *testing.T) {
	handler, _ := newGameStaticHandler(t, map[string]string{"index.pck": "pack-v1"})

	first := getGameFile(handler, "/index.pck", nil)
	if first.Code != http.StatusOK {
		t.Fatalf("first GET status = %d, want 200", first.Code)
	}
	if got := first.Header().Get("Cache-Control"); got != "no-cache" {
		t.Fatalf("pck Cache-Control = %q, want no-cache", got)
	}
	etag := first.Header().Get("ETag")
	if etag == "" || strings.HasPrefix(etag, "W/") || !strings.HasPrefix(etag, "\"") {
		t.Fatalf("pck ETag = %q, want a strong quoted validator", etag)
	}
	if got := first.Header().Get("Last-Modified"); got == "" {
		t.Fatalf("pck must send Last-Modified")
	}
	if got := first.Header().Get("Accept-Ranges"); got != "bytes" {
		t.Fatalf("pck Accept-Ranges = %q, want bytes", got)
	}
	if first.Body.String() != "pack-v1" {
		t.Fatalf("first body = %q", first.Body.String())
	}

	second := getGameFile(handler, "/index.pck", map[string]string{"If-None-Match": etag})
	if second.Code != http.StatusNotModified {
		t.Fatalf("revalidated GET status = %d, want 304", second.Code)
	}
	if second.Body.Len() != 0 {
		t.Fatalf("304 must not carry a body, got %d bytes", second.Body.Len())
	}
	if got := second.Header().Get("ETag"); got != etag {
		t.Fatalf("304 ETag = %q, want %q", got, etag)
	}
	if got := second.Header().Get("Cache-Control"); got != "no-cache" {
		t.Fatalf("304 Cache-Control = %q, want no-cache", got)
	}
}

func TestGamePackETagChangesAfterRebuild(t *testing.T) {
	handler, dir := newGameStaticHandler(t, map[string]string{"index.pck": "pack-v1"})
	oldETag := getGameFile(handler, "/index.pck", nil).Header().Get("ETag")

	// A rebuilt pack can have exactly the same length, so mtime alone must
	// invalidate the validator.
	path := filepath.Join(dir, "index.pck")
	if err := os.WriteFile(path, []byte("pack-v2"), 0o644); err != nil {
		t.Fatal(err)
	}
	later := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(path, later, later); err != nil {
		t.Fatal(err)
	}

	fresh := getGameFile(handler, "/index.pck", map[string]string{"If-None-Match": oldETag})
	if fresh.Code != http.StatusOK {
		t.Fatalf("status with a stale ETag = %d, want 200", fresh.Code)
	}
	if fresh.Body.String() != "pack-v2" {
		t.Fatalf("stale revalidation served %q", fresh.Body.String())
	}
	if got := fresh.Header().Get("ETag"); got == "" || got == oldETag {
		t.Fatalf("ETag did not change after rebuild: old %q new %q", oldETag, got)
	}
}

func TestGamePackRangeKeepsTheSameValidator(t *testing.T) {
	handler, _ := newGameStaticHandler(t, map[string]string{"index.pck": "0123456789abcdef"})
	etag := getGameFile(handler, "/index.pck", nil).Header().Get("ETag")

	part := getGameFile(handler, "/index.pck", map[string]string{"Range": "bytes=4-7"})
	if part.Code != http.StatusPartialContent {
		t.Fatalf("range status = %d, want 206", part.Code)
	}
	if part.Body.String() != "4567" {
		t.Fatalf("range body = %q", part.Body.String())
	}
	if got := part.Header().Get("Content-Range"); got != "bytes 4-7/16" {
		t.Fatalf("Content-Range = %q", got)
	}
	if got := part.Header().Get("ETag"); got != etag {
		t.Fatalf("range ETag = %q, want %q", got, etag)
	}

	// A stored range revalidates to a bodyless 304: this is what makes a
	// second launch cheap while the pack is unchanged.
	notModified := getGameFile(handler, "/index.pck", map[string]string{
		"Range":         "bytes=4-7",
		"If-None-Match": etag,
	})
	if notModified.Code != http.StatusNotModified {
		t.Fatalf("revalidated range status = %d, want 304", notModified.Code)
	}
	if notModified.Body.Len() != 0 {
		t.Fatalf("revalidated range body = %d bytes, want 0", notModified.Body.Len())
	}
	if got := notModified.Header().Get("Content-Range"); got != "" {
		t.Fatalf("304 must not send Content-Range, got %q", got)
	}

	// If-Range with a validator from an older build must never splice new
	// bytes into an old range: the whole new pack goes out instead.
	staleIfRange := getGameFile(handler, "/index.pck", map[string]string{
		"Range":    "bytes=4-7",
		"If-Range": "\"stale-1-1\"",
	})
	if staleIfRange.Code != http.StatusOK {
		t.Fatalf("stale If-Range status = %d, want 200", staleIfRange.Code)
	}
	if staleIfRange.Body.String() != "0123456789abcdef" {
		t.Fatalf("stale If-Range body = %q", staleIfRange.Body.String())
	}
}

func TestGameHTMLEntryPointIsRevalidated(t *testing.T) {
	handler, _ := newGameStaticHandler(t, map[string]string{"index.html": "<html>build-1</html>"})

	// The entry point is also served from "/" and must follow the same rule.
	first := getGameFile(handler, "/", nil)
	if first.Code != http.StatusOK || first.Body.String() != "<html>build-1</html>" {
		t.Fatalf("index status = %d body = %q", first.Code, first.Body.String())
	}
	if got := first.Header().Get("Cache-Control"); got != "no-cache" {
		t.Fatalf("html Cache-Control = %q, want no-cache", got)
	}
	etag := first.Header().Get("ETag")
	if etag == "" {
		t.Fatalf("html must send an ETag")
	}

	second := getGameFile(handler, "/index.html", map[string]string{"If-None-Match": etag})
	if second.Code != http.StatusNotModified || second.Body.Len() != 0 {
		t.Fatalf("html revalidation = %d with %d bytes, want 304 with 0", second.Code, second.Body.Len())
	}
}

func TestGameHTMLPicksUpANewBuildStamp(t *testing.T) {
	handler, dir := newGameStaticHandler(t, map[string]string{"index.html": "<html>build-1</html>"})
	oldETag := getGameFile(handler, "/index.html", nil).Header().Get("ETag")

	path := filepath.Join(dir, "index.html")
	if err := os.WriteFile(path, []byte("<html>build-2-new</html>"), 0o644); err != nil {
		t.Fatal(err)
	}

	fresh := getGameFile(handler, "/index.html", map[string]string{"If-None-Match": oldETag})
	if fresh.Code != http.StatusOK || fresh.Body.String() != "<html>build-2-new</html>" {
		t.Fatalf("new build not served: %d %q", fresh.Code, fresh.Body.String())
	}
}

func TestGameEngineAssetsStayCacheableForADay(t *testing.T) {
	handler, _ := newGameStaticHandler(t, map[string]string{
		"index.wasm":                 "wasm-bytes",
		"index.js":                   "loader-bytes",
		"index.audio.worklet.js":     "worklet-bytes",
		"index.apple-touch-icon.png": "png-bytes",
	})
	for _, name := range []string{"/index.wasm", "/index.js", "/index.audio.worklet.js", "/index.apple-touch-icon.png"} {
		recorder := getGameFile(handler, name, nil)
		if recorder.Code != http.StatusOK {
			t.Fatalf("%s status = %d", name, recorder.Code)
		}
		if got := recorder.Header().Get("Cache-Control"); got != "public, max-age=86400" {
			t.Fatalf("%s Cache-Control = %q, want public, max-age=86400", name, got)
		}
		if recorder.Header().Get("ETag") == "" {
			t.Fatalf("%s must send an ETag for revalidation after expiry", name)
		}
	}
}

func TestGameGzipAssetHasItsOwnETag(t *testing.T) {
	handler, _ := newGameStaticHandler(t, map[string]string{
		"index.wasm":    "wasm-bytes",
		"index.wasm.gz": "gz-bytes",
	})

	identity := getGameFile(handler, "/index.wasm", nil)
	compressed := getGameFile(handler, "/index.wasm", map[string]string{"Accept-Encoding": "gzip"})
	if compressed.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("expected the pre-compressed copy, got %q", compressed.Header().Get("Content-Encoding"))
	}
	if identity.Header().Get("ETag") == compressed.Header().Get("ETag") {
		t.Fatalf("identity and gzip representations share an ETag: %q", identity.Header().Get("ETag"))
	}
	// The validator of the representation actually sent is the one that
	// must answer 304.
	again := getGameFile(handler, "/index.wasm", map[string]string{
		"Accept-Encoding": "gzip",
		"If-None-Match":   compressed.Header().Get("ETag"),
	})
	if again.Code != http.StatusNotModified {
		t.Fatalf("gzip revalidation = %d, want 304", again.Code)
	}
}

func TestGamePackStaysRawAndRevalidated(t *testing.T) {
	handler, _ := newGameStaticHandler(t, map[string]string{
		"index.pck":    "pck-bytes",
		"index.pck.gz": "gzipped-pck",
	})
	recorder := getGameFile(handler, "/index.pck", map[string]string{"Accept-Encoding": "gzip"})
	if recorder.Code != http.StatusOK || recorder.Body.String() != "pck-bytes" {
		t.Fatalf("pck should stay raw: %d %q", recorder.Code, recorder.Body.String())
	}
	if got := recorder.Header().Get("Content-Encoding"); got != "" {
		t.Fatalf("pck must not be gzip-encoded, got %q", got)
	}
	if got := recorder.Header().Get("Cache-Control"); got != "no-cache" {
		t.Fatalf("pck Cache-Control = %q, want no-cache", got)
	}
}
