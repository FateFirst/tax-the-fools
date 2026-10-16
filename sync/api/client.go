// Package api is the client for the Tax The Fools Supabase backend
// (sync/supabase/001_init.sql). Every call is a PostgREST RPC.
package api

import (
	"bytes"
	"compress/gzip"
	"crypto/rand"
	"encoding/base32"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

var (
	// ErrInvalidKey: the sync key is unknown, malformed or too short.
	ErrInvalidKey = errors.New("invalid sync key")
	// ErrAccountExists: CreateAccount was called with a key that already exists.
	ErrAccountExists = errors.New("an account with this sync key already exists")
	// ErrUnavailable: the backend can't be reached, errored (5xx) or is paused.
	ErrUnavailable = errors.New("sync server unavailable")
)

// State is the merged blob held by the server.
type State struct {
	Version   int64     `json:"version"`
	Blob      string    `json:"blob"`
	UpdatedAt time.Time `json:"updated_at"`
	UpdatedBy string    `json:"updated_by"`
}

// Device is one row of the device log.
type Device struct {
	Device   string    `json:"device"`
	LastSync time.Time `json:"last_sync"`
}

// Client talks to a Supabase project. HTTP may be nil (30s timeout default).
type Client struct {
	URL     string
	AnonKey string
	HTTP    *http.Client
}

// Two minutes: a push carries a few MB, which can take a while on a slow link.
var defaultHTTP = &http.Client{Timeout: 120 * time.Second}

func (c *Client) rpc(fn string, args map[string]any) ([]byte, error) {
	body, err := json.Marshal(args)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("POST", strings.TrimRight(c.URL, "/")+"/rest/v1/rpc/"+fn, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("bad Supabase URL %q: %w", c.URL, err)
	}
	req.Header.Set("apikey", c.AnonKey)
	// New projects hand out a publishable key (sb_publishable_...), which is not a JWT and must
	// only go in apikey; the legacy anon key is a JWT and is also sent as the bearer token.
	if strings.HasPrefix(c.AnonKey, "eyJ") {
		req.Header.Set("Authorization", "Bearer "+c.AnonKey)
	}
	req.Header.Set("Content-Type", "application/json")
	h := c.HTTP
	if h == nil {
		h = defaultHTTP
	}
	resp, err := h.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: could not reach Supabase (%v). Check the network and the URL in the config", ErrUnavailable, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("%w: reading response: %v", ErrUnavailable, err)
	}
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return data, nil
	}
	return nil, mapError(resp.StatusCode, data)
}

func mapError(status int, data []byte) error {
	var pg struct {
		Message string `json:"message"`
	}
	json.Unmarshal(data, &pg)
	msg := pg.Message
	if msg == "" {
		msg = strings.TrimSpace(string(data))
	}
	low := strings.ToLower(msg + " " + string(data))
	switch {
	case strings.Contains(low, "paused"):
		return fmt.Errorf("%w: your Supabase project is paused: open the dashboard and resume it", ErrUnavailable)
	case status >= 500:
		return fmt.Errorf("%w: HTTP %d from Supabase. If the project is paused, open the dashboard and resume it", ErrUnavailable, status)
	case strings.Contains(low, "invalid sync key"):
		return ErrInvalidKey
	case strings.Contains(low, "sync key too short"):
		return fmt.Errorf("%w: key too short", ErrInvalidKey)
	case status == 409 || strings.Contains(low, "duplicate key"):
		return ErrAccountExists
	case status == 404:
		return fmt.Errorf("Supabase returned 404 for %q: is the URL right and has 001_init.sql been run?", msg)
	case status == 401 || status == 403:
		return fmt.Errorf("Supabase rejected the anon key (HTTP %d): %s", status, msg)
	}
	return fmt.Errorf("Supabase error (HTTP %d): %s", status, msg)
}

// CreateAccount registers a new sync key.
func (c *Client) CreateAccount(key string) error {
	_, err := c.rpc("ttf_create_account", map[string]any{"p_key": key})
	return err
}

// Pull returns the current server state.
func (c *Client) Pull(key string) (State, error) {
	data, err := c.rpc("ttf_pull", map[string]any{"p_key": key})
	if err != nil {
		return State{}, err
	}
	var rows []State
	if err := json.Unmarshal(data, &rows); err != nil || len(rows) != 1 {
		return State{}, fmt.Errorf("unexpected ttf_pull response: %.200s", data)
	}
	return rows[0], nil
}

// Push writes blob if the server is still at version expected. On a version
// mismatch it returns conflict=true (and newVersion -1): pull, merge, retry.
func (c *Client) Push(key string, expected int64, blob, device string) (newVersion int64, conflict bool, err error) {
	data, err := c.rpc("ttf_push", map[string]any{
		"p_key": key, "p_expected": expected, "p_blob": blob, "p_device": device,
	})
	if err != nil {
		return 0, false, err
	}
	if err := json.Unmarshal(bytes.TrimSpace(data), &newVersion); err != nil {
		return 0, false, fmt.Errorf("unexpected ttf_push response: %.200s", data)
	}
	if newVersion < 0 {
		return -1, true, nil
	}
	return newVersion, false, nil
}

// Devices lists the devices that have pushed.
func (c *Client) Devices(key string) ([]Device, error) {
	data, err := c.rpc("ttf_devices", map[string]any{"p_key": key})
	if err != nil {
		return nil, err
	}
	var ds []Device
	if err := json.Unmarshal(data, &ds); err != nil {
		return nil, fmt.Errorf("unexpected ttf_devices response: %.200s", data)
	}
	return ds, nil
}

// NewSyncKey returns a fresh key: 32 random bytes, base32 (52 chars).
func NewSyncKey() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b)
}

// EncodeBlob gzips and base64-encodes JSON bytes.
func EncodeBlob(jsonBytes []byte) (string, error) {
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(jsonBytes); err != nil {
		return "", err
	}
	if err := zw.Close(); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(buf.Bytes()), nil
}

// DecodeBlob reverses EncodeBlob. An empty blob (a fresh account) decodes to nil.
func DecodeBlob(blob string) ([]byte, error) {
	if blob == "" {
		return nil, nil
	}
	raw, err := base64.StdEncoding.DecodeString(blob)
	if err != nil {
		return nil, fmt.Errorf("blob is not base64: %w", err)
	}
	zr, err := gzip.NewReader(bytes.NewReader(raw))
	if err != nil {
		return nil, fmt.Errorf("blob is not gzip: %w", err)
	}
	defer zr.Close()
	return io.ReadAll(zr)
}
