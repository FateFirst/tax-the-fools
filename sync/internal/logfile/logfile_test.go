package logfile

import (
	"os"
	"strings"
	"testing"
	"time"
)

func TestAppendRotateAndLast(t *testing.T) {
	dir := t.TempDir()
	now := time.Date(2026, 10, 16, 9, 0, 0, 0, time.UTC)
	if err := Append(dir, now, "one\n\ntwo\n"); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(Path(dir))
	if string(b) != "2026-10-16 09:00:00  one\n2026-10-16 09:00:00  two\n" {
		t.Fatalf("%q", b)
	}
	os.WriteFile(Path(dir), []byte(strings.Repeat("x", MaxSize)), 0o600)
	Append(dir, now, "fresh")
	old, _ := os.Stat(Path(dir) + ".1")
	cur, _ := os.ReadFile(Path(dir))
	if old == nil || old.Size() != MaxSize || !strings.Contains(string(cur), "fresh") || len(cur) > 100 {
		t.Fatal("rotation")
	}
	if LoadLast(dir) != nil {
		t.Fatal("last should be empty")
	}
	SaveLast(dir, Last{At: 5, OK: false, Message: "paused"})
	if l := LoadLast(dir); l == nil || l.Message != "paused" || l.OK {
		t.Fatalf("%+v", l)
	}
}
