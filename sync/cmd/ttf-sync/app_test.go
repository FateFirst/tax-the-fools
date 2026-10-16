package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/FateFirst/tax-the-fools/sync/api"
	"github.com/FateFirst/tax-the-fools/sync/internal/backup"
	"github.com/FateFirst/tax-the-fools/sync/internal/config"
	"github.com/FateFirst/tax-the-fools/sync/internal/paths"
)

// TestHelperGame is the fake game: it records that it ran and exits with a chosen code.
func TestHelperGame(t *testing.T) {
	if os.Getenv("TTF_HELPER_GAME") != "1" {
		return
	}
	if f := os.Getenv("TTF_HELPER_LOG"); f != "" {
		fh, _ := os.OpenFile(f, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		fmt.Fprintln(fh, "game")
		fh.Close()
	}
	code := 0
	fmt.Sscan(os.Getenv("TTF_HELPER_CODE"), &code)
	os.Exit(code)
}

func testApp(t *testing.T, stdin string) (*app, *bytes.Buffer, *bytes.Buffer) {
	var out, errb bytes.Buffer
	a := newApp(strings.NewReader(stdin), &out, &errb)
	a.configDir = t.TempDir()
	a.wowRunning = func() bool { return false }
	a.discover = func() []string { return nil }
	return a, &out, &errb
}

func TestRunOrderAndExitCode(t *testing.T) {
	log := filepath.Join(t.TempDir(), "log")
	t.Setenv("TTF_HELPER_GAME", "1")
	t.Setenv("TTF_HELPER_LOG", log)
	t.Setenv("TTF_HELPER_CODE", "7")
	a, _, errb := testApp(t, "")
	var events []string
	a.syncFn = func(post bool) error {
		b, _ := os.ReadFile(log)
		events = append(events, fmt.Sprintf("sync(post=%v) after %q", post, strings.TrimSpace(string(b))))
		return nil
	}
	code := a.run([]string{"run", "--", os.Args[0], "-test.run=TestHelperGame"})
	if code != 7 {
		t.Fatalf("exit code %d (%s)", code, errb)
	}
	want := []string{`sync(post=false) after ""`, `sync(post=true) after "game"`}
	if strings.Join(events, "|") != strings.Join(want, "|") {
		t.Fatalf("events %v", events)
	}
}

func TestRunStartsGameWhenPreSyncFails(t *testing.T) {
	a, _, errb := testApp(t, "")
	var calls []string
	a.syncFn = func(post bool) error {
		calls = append(calls, fmt.Sprint("sync", post))
		if !post {
			return errors.New("project paused")
		}
		return nil
	}
	a.startGame = func(args []string) (int, error) {
		calls = append(calls, "game:"+strings.Join(args, " "))
		return 3, nil
	}
	if code := a.run([]string{"run", "--", "wow", "-x"}); code != 3 {
		t.Fatalf("code %d", code)
	}
	if strings.Join(calls, ",") != "syncfalse,game:wow -x,synctrue" {
		t.Fatalf("%v", calls)
	}
	if !strings.Contains(errb.String(), "Starting the game anyway") {
		t.Errorf("stderr %q", errb)
	}
}

func TestRunNeedsCommand(t *testing.T) {
	a, _, _ := testApp(t, "")
	a.syncFn = func(bool) error { t.Error("synced"); return nil }
	if a.run([]string{"run", "--"}) != 1 {
		t.Error("expected 1")
	}
}

func TestSetupInitJoinStatusSyncRestore(t *testing.T) {
	fake := api.NewFake()
	defer fake.Close()
	wow := filepath.Join(t.TempDir(), "WoW")
	os.MkdirAll(filepath.Join(wow, "WTF", "Account", "ACC", "SavedVariables"), 0o755)
	os.MkdirAll(filepath.Join(wow, "WTF", "Account", "SavedVariables"), 0o755)
	os.WriteFile(filepath.Join(wow, "WoW.exe"), nil, 0o644)

	a, out, errb := testApp(t, "1\n"+fake.URL()+"\n"+api.FakeAnonKey+"\nPC\n")
	a.discover = func() []string { return []string{wow} }
	if code := a.run([]string{"setup"}); code != 0 {
		t.Fatalf("setup %d %s", code, errb)
	}
	c, _ := config.Load(a.configDir)
	if c.WoWPath != wow || c.Account != "ACC" || c.Device != "PC" || c.SupabaseURL != fake.URL() {
		t.Fatalf("%+v", c)
	}

	out.Reset()
	if code := a.run([]string{"init"}); code != 0 {
		t.Fatalf("init %d %s", code, errb)
	}
	c, _ = config.Load(a.configDir)
	if len(c.SyncKey) < 32 || !strings.Contains(out.String(), c.SyncKey) || !strings.Contains(out.String(), "Keep this safe") {
		t.Fatalf("init output %q", out)
	}
	if a.run([]string{"init"}) != 1 { // second init refuses
		t.Error("init twice")
	}

	// local data, sync, status never shows the whole key
	sv := paths.SavedVars(wow, "ACC")
	os.WriteFile(sv, []byte("TaxTheFoolsDB = { realms = { R = { scan = { lastFull = 5 } } } }\n"), 0o644)
	out.Reset()
	if code := a.run([]string{"sync"}); code != 0 {
		t.Fatalf("sync %d %s", code, errb)
	}
	if !strings.Contains(out.String(), "pushed v1") {
		t.Errorf("sync output %q", out)
	}
	out.Reset()
	if a.run([]string{"status"}) != 0 {
		t.Fatal(errb)
	}
	if strings.Contains(out.String(), c.SyncKey) || !strings.Contains(out.String(), "Server:      v1") ||
		!strings.Contains(out.String(), "PC") || !strings.Contains(out.String(), "last synced") {
		t.Errorf("status %q", out)
	}

	// a second device joins; a wrong key is refused
	b, bout, _ := testApp(t, "")
	config.Save(b.configDir, config.Config{SupabaseURL: fake.URL(), AnonKey: api.FakeAnonKey})
	if b.run([]string{"join", strings.Repeat("Z", 40)}) != 1 {
		t.Error("wrong key accepted")
	}
	if cc, _ := config.Load(b.configDir); cc.SyncKey != "" {
		t.Error("wrong key saved")
	}
	if b.run([]string{"join", c.SyncKey}) != 0 || !strings.Contains(bout.String(), "v1") {
		t.Errorf("join %q", bout)
	}

	// restore: a backup exists after the second sync wrote the file
	a.now = func() time.Time { return time.Now().Add(time.Hour) }
	a.run([]string{"sync"})
	names, _ := backup.List(a.configDir)
	if len(names) == 0 {
		t.Fatal("no backup")
	}
	os.WriteFile(sv, []byte("garbage"), 0o644)
	a.in.Reset(strings.NewReader("1\n"))
	if code := a.run([]string{"restore"}); code != 0 {
		t.Fatalf("restore %d %s", code, errb)
	}
	got, _ := os.ReadFile(sv)
	if !strings.Contains(string(got), "lastFull") {
		t.Errorf("restored %q", got)
	}
	// refuses while WoW runs
	a.wowRunning = func() bool { return true }
	a.in.Reset(strings.NewReader("1\n"))
	if a.run([]string{"restore"}) != 1 {
		t.Error("restore while running")
	}
}

func TestVersionAndUsage(t *testing.T) {
	a, out, _ := testApp(t, "")
	version = "1.2.3"
	if a.run([]string{"version"}) != 0 || !strings.Contains(out.String(), "1.2.3") {
		t.Error(out)
	}
	if a.run([]string{"bogus"}) != 1 || a.run(nil) != 1 {
		t.Error("exit codes")
	}
}
