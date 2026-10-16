package config

import "testing"

func TestRoundTrip(t *testing.T) {
	dir := t.TempDir()
	c, err := Load(dir)
	if err != nil || c.Device == "" || c.SyncKey != "" {
		t.Fatalf("%+v %v", c, err)
	}
	want := Config{"https://x.supabase.co", "anon", "KEYKEYKEY", "Deck", "/w", "ACC"}
	if err := Save(dir, want); err != nil {
		t.Fatal(err)
	}
	got, err := Load(dir)
	if err != nil || got != want {
		t.Fatalf("%+v %v", got, err)
	}
	if MaskKey("ABCDEFGHIJKLMNOP") == "ABCDEFGHIJKLMNOP" || MaskKey("") == "" {
		t.Error("mask")
	}
}

func TestBadJSON(t *testing.T) {
	dir := t.TempDir()
	Save(dir, Config{})
	writeBad(t, dir)
	if _, err := Load(dir); err == nil {
		t.Error("expected an error")
	}
}

func writeBad(t *testing.T, dir string) {
	t.Helper()
	if err := osWrite(Path(dir), "{nope"); err != nil {
		t.Fatal(err)
	}
}
