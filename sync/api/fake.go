package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"sync"
	"time"
)

// FakeAnonKey is the anon key the Fake expects.
const FakeAnonKey = "fake-anon-key"

// Fake is an in-memory httptest server implementing the four ttf_* RPCs with
// the same semantics as sync/supabase/001_init.sql (key hashing, atomic
// compare-and-swap). For tests in this and other packages.
type Fake struct {
	srv *httptest.Server

	mu       sync.Mutex
	accounts map[string]*fakeAccount // by sha256 hex of key
	status   int                     // when non-zero, every request fails with it
	hook     func(fn string)         // called (unlocked) before each RPC is handled
}

type fakeAccount struct {
	version   int64
	blob      string
	updatedAt time.Time
	updatedBy string
	devices   map[string]time.Time
}

// NewFake starts a fake server. Call Close when done.
func NewFake() *Fake {
	f := &Fake{accounts: map[string]*fakeAccount{}}
	f.srv = httptest.NewServer(http.HandlerFunc(f.handle))
	return f
}

func (f *Fake) URL() string { return f.srv.URL }
func (f *Fake) Close()      { f.srv.Close() }

// SetStatus makes every request fail with that HTTP status (0 restores normal service).
func (f *Fake) SetStatus(code int) { f.mu.Lock(); f.status = code; f.mu.Unlock() }

// SetHook installs a function run before each RPC is handled, e.g. to make a
// second device push in between a client's pull and push.
func (f *Fake) SetHook(h func(fn string)) { f.mu.Lock(); f.hook = h; f.mu.Unlock() }

// Version returns the stored version for a key (-1 if unknown).
func (f *Fake) Version(key string) int64 {
	f.mu.Lock()
	defer f.mu.Unlock()
	if a := f.accounts[hashKey(key)]; a != nil {
		return a.version
	}
	return -1
}

func hashKey(k string) string { s := sha256.Sum256([]byte(k)); return hex.EncodeToString(s[:]) }

func pgError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"code": code, "message": msg})
}

func (f *Fake) handle(w http.ResponseWriter, r *http.Request) {
	fn := strings.TrimPrefix(r.URL.Path, "/rest/v1/rpc/")
	f.mu.Lock()
	status, hook := f.status, f.hook
	f.mu.Unlock()
	if status != 0 {
		http.Error(w, "fake failure", status)
		return
	}
	if r.Method != "POST" || r.Header.Get("apikey") != FakeAnonKey ||
		r.Header.Get("Authorization") != "Bearer "+FakeAnonKey {
		pgError(w, 401, "PGRST301", "Invalid API key")
		return
	}
	if hook != nil {
		hook(fn)
	}
	body, _ := io.ReadAll(r.Body)
	var args struct {
		Key      string `json:"p_key"`
		Expected int64  `json:"p_expected"`
		Blob     string `json:"p_blob"`
		Device   string `json:"p_device"`
	}
	if err := json.Unmarshal(body, &args); err != nil {
		pgError(w, 400, "PGRST102", "bad json")
		return
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	h := hashKey(args.Key)
	out := func(v any) { w.Header().Set("Content-Type", "application/json"); json.NewEncoder(w).Encode(v) }

	if fn == "ttf_create_account" {
		if len(args.Key) < 32 {
			pgError(w, 400, "P0001", "sync key too short")
			return
		}
		if f.accounts[h] != nil {
			pgError(w, 409, "23505", `duplicate key value violates unique constraint "accounts_key_hash_key"`)
			return
		}
		f.accounts[h] = &fakeAccount{updatedAt: time.Now().UTC(), devices: map[string]time.Time{}}
		w.WriteHeader(204)
		return
	}
	acc := f.accounts[h]
	if len(args.Key) < 32 || acc == nil {
		pgError(w, 400, "P0001", "invalid sync key")
		return
	}
	switch fn {
	case "ttf_pull":
		out([]map[string]any{{"version": acc.version, "blob": acc.blob,
			"updated_at": acc.updatedAt.Format("2006-01-02T15:04:05.999999-07:00"), "updated_by": nullable(acc.updatedBy)}})
	case "ttf_push":
		if acc.version != args.Expected {
			out(-1)
			return
		}
		acc.version++
		acc.blob, acc.updatedAt, acc.updatedBy = args.Blob, time.Now().UTC(), args.Device
		acc.devices[args.Device] = acc.updatedAt
		out(acc.version)
	case "ttf_devices":
		rows := []map[string]any{}
		names := make([]string, 0, len(acc.devices))
		for d := range acc.devices {
			names = append(names, d)
		}
		// Newest first, as the SQL orders them.
		sort.Slice(names, func(i, j int) bool { return acc.devices[names[i]].After(acc.devices[names[j]]) })
		for _, d := range names {
			rows = append(rows, map[string]any{"device": d, "last_sync": acc.devices[d].Format(time.RFC3339Nano)})
		}
		out(rows)
	default:
		pgError(w, 404, "PGRST202", "Could not find the function "+fn)
	}
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}
