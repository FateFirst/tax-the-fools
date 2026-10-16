package api

import (
	"bytes"
	"crypto/rand"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newClient(t *testing.T) (*Client, *Fake) {
	t.Helper()
	f := NewFake()
	t.Cleanup(f.Close)
	return &Client{URL: f.URL(), AnonKey: FakeAnonKey}, f
}

func TestNewSyncKey(t *testing.T) {
	a, b := NewSyncKey(), NewSyncKey()
	if len(a) < 52 || a == b {
		t.Fatalf("bad keys %q %q", a, b)
	}
}

func TestCreatePullPush(t *testing.T) {
	c, _ := newClient(t)
	key := NewSyncKey()
	if err := c.CreateAccount(key); err != nil {
		t.Fatal(err)
	}
	if err := c.CreateAccount(key); !errors.Is(err, ErrAccountExists) {
		t.Fatalf("want ErrAccountExists, got %v", err)
	}
	st, err := c.Pull(key)
	if err != nil || st.Version != 0 || st.Blob != "" {
		t.Fatalf("pull %+v %v", st, err)
	}
	v, conflict, err := c.Push(key, 0, "hello", "pc")
	if err != nil || conflict || v != 1 {
		t.Fatalf("push %d %v %v", v, conflict, err)
	}
	st, _ = c.Pull(key)
	if st.Version != 1 || st.Blob != "hello" || st.UpdatedBy != "pc" || st.UpdatedAt.IsZero() {
		t.Fatalf("pull2 %+v", st)
	}
	ds, err := c.Devices(key)
	if err != nil || len(ds) != 1 || ds[0].Device != "pc" {
		t.Fatalf("devices %+v %v", ds, err)
	}
}

func TestConflict(t *testing.T) {
	c, _ := newClient(t)
	key := NewSyncKey()
	c.CreateAccount(key)
	if _, _, err := c.Push(key, 0, "a", "pc"); err != nil {
		t.Fatal(err)
	}
	v, conflict, err := c.Push(key, 0, "b", "laptop")
	if err != nil || !conflict || v != -1 {
		t.Fatalf("want conflict, got %d %v %v", v, conflict, err)
	}
	st, _ := c.Pull(key)
	if st.Blob != "a" {
		t.Fatalf("conflicting push overwrote: %q", st.Blob)
	}
	v, conflict, _ = c.Push(key, 1, "b", "laptop")
	if conflict || v != 2 {
		t.Fatalf("retry %d %v", v, conflict)
	}
}

func TestWrongKey(t *testing.T) {
	c, _ := newClient(t)
	c.CreateAccount(NewSyncKey())
	other := NewSyncKey()
	if _, err := c.Pull(other); !errors.Is(err, ErrInvalidKey) {
		t.Fatalf("pull: %v", err)
	}
	if _, _, err := c.Push(other, 0, "x", "d"); !errors.Is(err, ErrInvalidKey) {
		t.Fatalf("push: %v", err)
	}
	if _, err := c.Devices(other); !errors.Is(err, ErrInvalidKey) {
		t.Fatalf("devices: %v", err)
	}
	if _, err := c.Pull("short"); !errors.Is(err, ErrInvalidKey) {
		t.Fatalf("short: %v", err)
	}
}

func TestUnavailable(t *testing.T) {
	for name, h := range map[string]http.HandlerFunc{
		"503":    func(w http.ResponseWriter, r *http.Request) { http.Error(w, "down", 503) },
		"540":    func(w http.ResponseWriter, r *http.Request) { http.Error(w, "x", 540) },
		"paused": func(w http.ResponseWriter, r *http.Request) { http.Error(w, "project is paused", 400) },
	} {
		t.Run(name, func(t *testing.T) {
			s := httptest.NewServer(h)
			defer s.Close()
			c := &Client{URL: s.URL, AnonKey: "k"}
			_, err := c.Pull(NewSyncKey())
			if !errors.Is(err, ErrUnavailable) {
				t.Fatalf("got %v", err)
			}
			if !strings.Contains(err.Error(), "paused") && name != "503" {
				t.Fatalf("message not helpful: %v", err)
			}
		})
	}
	// connection refused
	s := httptest.NewServer(http.NotFoundHandler())
	url := s.URL
	s.Close()
	c := &Client{URL: url, AnonKey: "k"}
	if _, err := c.Pull(NewSyncKey()); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("refused: %v", err)
	}
}

func TestFakeFailMode(t *testing.T) {
	c, f := newClient(t)
	key := NewSyncKey()
	c.CreateAccount(key)
	f.SetStatus(503)
	if _, err := c.Pull(key); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("got %v", err)
	}
	f.SetStatus(0)
	if _, err := c.Pull(key); err != nil {
		t.Fatal(err)
	}
}

func TestSendsHeaders(t *testing.T) {
	for _, tc := range []struct{ key, auth string }{
		{"eyJhbGciOi.legacy.jwt", "Bearer eyJhbGciOi.legacy.jwt"}, // legacy anon key: a JWT, also the bearer token
		{"sb_publishable_abc123", ""},                             // publishable key: apikey only
	} {
		var got http.Header
		var path string
		s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			got, path = r.Header, r.URL.Path
			w.Write([]byte(`[{"version":3,"blob":"b","updated_at":"2026-10-16T01:02:03.123456+00:00","updated_by":"x"}]`))
		}))
		c := &Client{URL: s.URL + "/", AnonKey: tc.key}
		st, err := c.Pull(NewSyncKey())
		s.Close()
		if err != nil || st.Version != 3 || st.UpdatedAt.Year() != 2026 {
			t.Fatalf("%+v %v", st, err)
		}
		if path != "/rest/v1/rpc/ttf_pull" || got.Get("apikey") != tc.key ||
			got.Get("Authorization") != tc.auth || got.Get("Content-Type") != "application/json" {
			t.Fatalf("%s: %s %v", tc.key, path, got)
		}
	}
}

func TestBlobRoundTripLarge(t *testing.T) {
	raw := make([]byte, 5<<20)
	rand.Read(raw)
	raw = append(raw, bytes.Repeat([]byte(`{"a":1}`), 100000)...)
	enc, err := EncodeBlob(raw)
	if err != nil {
		t.Fatal(err)
	}
	c, _ := newClient(t)
	key := NewSyncKey()
	c.CreateAccount(key)
	if _, _, err := c.Push(key, 0, enc, "pc"); err != nil {
		t.Fatal(err)
	}
	st, err := c.Pull(key)
	if err != nil || st.Blob != enc {
		t.Fatalf("blob mismatch %v", err)
	}
	dec, err := DecodeBlob(st.Blob)
	if err != nil || !bytes.Equal(dec, raw) {
		t.Fatalf("decode mismatch %v", err)
	}
	if d, err := DecodeBlob(""); err != nil || len(d) != 0 {
		t.Fatalf("empty blob: %v %v", d, err)
	}
	if _, err := DecodeBlob("!!notbase64"); err == nil {
		t.Fatal("want error")
	}
}

func TestPushRacesAnotherDevice(t *testing.T) {
	c, f := newClient(t)
	key := NewSyncKey()
	c.CreateAccount(key)
	st, _ := c.Pull(key)
	other := &Client{URL: f.URL(), AnonKey: FakeAnonKey}
	if _, _, err := other.Push(key, st.Version, "from-deck", "deck"); err != nil {
		t.Fatal(err)
	}
	_, conflict, err := c.Push(key, st.Version, "from-pc", "pc")
	if err != nil || !conflict {
		t.Fatalf("stale push must conflict: %v %v", conflict, err)
	}
	if got, _ := c.Pull(key); got.Blob != "from-deck" {
		t.Fatalf("overwritten: %q", got.Blob)
	}
}
