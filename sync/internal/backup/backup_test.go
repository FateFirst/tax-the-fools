package backup

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCreateListRestore(t *testing.T) {
	cfg := t.TempDir()
	src := filepath.Join(t.TempDir(), "TaxTheFools.lua")
	base := time.Unix(1760000000, 0)
	for i := 0; i < 7; i++ {
		os.WriteFile(src, []byte{byte('a' + i)}, 0o644)
		if _, err := Create(cfg, src, base.Add(time.Duration(i)*time.Second)); err != nil {
			t.Fatal(err)
		}
	}
	names, _ := List(cfg)
	if len(names) != Keep {
		t.Fatalf("%v", names)
	}
	dest := filepath.Join(t.TempDir(), "x", "out.lua")
	if err := Restore(cfg, names[0], dest); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(dest); string(b) != "g" {
		t.Errorf("newest first: got %q", b)
	}
	if err := Restore(cfg, "../evil", dest); err == nil {
		t.Error("path escape allowed")
	}
}

func TestSameInstantKeepsBoth(t *testing.T) {
	cfg := t.TempDir()
	src := filepath.Join(t.TempDir(), "f.lua")
	os.WriteFile(src, []byte("x"), 0o644)
	now := time.Unix(1760000000, 0)
	a, _ := Create(cfg, src, now)
	b, _ := Create(cfg, src, now)
	if a == b {
		t.Fatal("overwrote")
	}
}
