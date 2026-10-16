package syncer

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/FateFirst/tax-the-fools/sync/api"
	"github.com/FateFirst/tax-the-fools/sync/internal/backup"
	"github.com/FateFirst/tax-the-fools/sync/internal/config"
	"github.com/FateFirst/tax-the-fools/sync/internal/paths"
	"github.com/FateFirst/tax-the-fools/sync/luasv"
)

type rig struct {
	t    *testing.T
	fake *api.Fake
	key  string
	base time.Time
}

type device struct {
	r       *rig
	name    string
	cfgDir  string
	cfg     config.Config
	running bool
	now     time.Time
	out     bytes.Buffer
}

func newRig(t *testing.T) *rig {
	f := api.NewFake()
	t.Cleanup(f.Close)
	key := api.NewSyncKey()
	cl := &api.Client{URL: f.URL(), AnonKey: api.FakeAnonKey}
	if err := cl.CreateAccount(key); err != nil {
		t.Fatal(err)
	}
	return &rig{t: t, fake: f, key: key, base: time.Unix(1760000000, 0)}
}

func (r *rig) device(name string) *device {
	wow := filepath.Join(r.t.TempDir(), "WoW")
	os.MkdirAll(filepath.Join(wow, "WTF", "Account", "ACC", "SavedVariables"), 0o755)
	return &device{r: r, name: name, cfgDir: r.t.TempDir(), now: r.base,
		cfg: config.Config{SupabaseURL: r.fake.URL(), AnonKey: api.FakeAnonKey, SyncKey: r.key,
			Device: name, WoWPath: wow, Account: "ACC"}}
}

func (d *device) file() string { return paths.SavedVars(d.cfg.WoWPath, d.cfg.Account) }

func (d *device) write(lua string) {
	d.r.t.Helper()
	if err := os.WriteFile(d.file(), []byte(lua), 0o644); err != nil {
		d.r.t.Fatal(err)
	}
}

func (d *device) deps() Deps {
	return Deps{Client: &api.Client{URL: d.cfg.SupabaseURL, AnonKey: d.cfg.AnonKey}, Cfg: d.cfg,
		ConfigDir: d.cfgDir, WoWRunning: func() bool { return d.running },
		Now: func() time.Time { return d.now }, Version: "1.0.0", Out: &d.out,
		Sleep: func(x time.Duration) { d.now = d.now.Add(x) }}
}

func (d *device) sync() (Result, error) {
	d.now = d.now.Add(time.Minute)
	return Sync(d.deps())
}

func (d *device) db() *luasv.Table {
	d.r.t.Helper()
	data, err := os.ReadFile(d.file())
	if err != nil {
		d.r.t.Fatal(err)
	}
	vars, err := luasv.Parse(data)
	if err != nil {
		d.r.t.Fatal(err)
	}
	return vars["TaxTheFoolsDB"].(*luasv.Table)
}

func tget(v luasv.Value, keys ...string) luasv.Value {
	for _, k := range keys {
		t, ok := v.(*luasv.Table)
		if !ok {
			return nil
		}
		v, _ = t.GetS(k)
	}
	return v
}

func n(v luasv.Value) int {
	if t, ok := v.(*luasv.Table); ok {
		return t.Len()
	}
	return 0
}

const (
	scanA = `TaxTheFoolsDB = { realms = { R = { scan = { lastFull = 1759900000 },
 history = { ["4306:0"] = { days = { [20369] = { n = 4, p25 = 100 } } } },
 chars = { Al = { sales = {} } } } } }
TaxTheFoolsCharDB = { win = 1 }
`
	saleB = `TaxTheFoolsDB = { realms = { R = {
 chars = { Al = { sales = { { name = "Silk Cloth", key = "4306:0", outcome = "sold", money = 900, at = 1759950000 } } } } } } }
`
)

func TestTwoDevicesBothSurvive(t *testing.T) {
	r := newRig(t)
	a, b := r.device("PC"), r.device("Laptop")
	a.write(scanA)
	res, err := a.sync()
	if err != nil || res.Pushed != 1 || !res.Wrote {
		t.Fatalf("A: %+v %v", res, err)
	}
	b.write(saleB)
	res, err = b.sync()
	if err != nil || res.Pulled != 1 || res.Pushed != 2 {
		t.Fatalf("B: %+v %v", res, err)
	}
	if !strings.Contains(b.out.String(), "Pulled v1 from PC") || !strings.Contains(b.out.String(), "pushed v2") {
		t.Fatalf("output: %q", b.out.String())
	}
	if _, err := a.sync(); err != nil {
		t.Fatal(err)
	}
	for _, d := range []*device{a, b} {
		db := d.db()
		if n(tget(db, "realms", "R", "chars", "Al", "sales")) != 1 {
			t.Errorf("%s lost the sale", d.name)
		}
		if tget(db, "realms", "R", "history", "4306:0", "days") == nil {
			t.Errorf("%s lost the scan history", d.name)
		}
		if tget(db, "sync", "device") != d.name {
			t.Errorf("%s sync stamp: %v", d.name, tget(db, "sync"))
		}
		if tget(db, "sync", "version") != "1.0.0" {
			t.Errorf("sync version missing")
		}
	}
	// the other SavedVariables is kept
	data, _ := os.ReadFile(a.file())
	if !strings.Contains(string(data), "TaxTheFoolsCharDB") {
		t.Error("TaxTheFoolsCharDB was dropped from the file")
	}
	// syncing again changes nothing in the data
	before := n(tget(a.db(), "realms", "R", "chars", "Al", "sales"))
	a.sync()
	if n(tget(a.db(), "realms", "R", "chars", "Al", "sales")) != before {
		t.Error("sales duplicated")
	}
}

func TestMissingLocalFileStartsFromServer(t *testing.T) {
	r := newRig(t)
	a, b := r.device("PC"), r.device("Laptop")
	a.write(scanA)
	a.sync()
	if _, err := b.sync(); err != nil {
		t.Fatal(err)
	}
	if tget(b.db(), "realms", "R", "scan", "lastFull") == nil {
		t.Error("B did not get the server data")
	}
}

func TestConflictRetry(t *testing.T) {
	r := newRig(t)
	a, b := r.device("PC"), r.device("Laptop")
	a.write(scanA)
	b.write(saleB)
	raced := false
	r.fake.SetHook(func(fn string) {
		if fn == "ttf_push" && !raced {
			raced = true
			if _, err := b.sync(); err != nil { // lands between A's pull and push
				t.Error(err)
			}
		}
	})
	res, err := a.sync()
	if err != nil {
		t.Fatal(err)
	}
	if res.Tries != 2 || res.Pushed != 2 {
		t.Fatalf("%+v", res)
	}
	if n(tget(a.db(), "realms", "R", "chars", "Al", "sales")) != 1 || tget(a.db(), "realms", "R", "scan", "lastFull") == nil {
		t.Error("A's file is missing data after the retry")
	}
	if !strings.Contains(a.out.String(), "Another device pushed first") {
		t.Errorf("output: %q", a.out.String())
	}
}

func TestConflictGivesUpAfterThree(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	a.write(scanA)
	other := &api.Client{URL: r.fake.URL(), AnonKey: api.FakeAnonKey}
	racing := false
	r.fake.SetHook(func(fn string) {
		if fn == "ttf_push" && !racing {
			racing = true
			st, _ := other.Pull(r.key)
			enc, _ := api.EncodeBlob([]byte(`{}`))
			other.Push(r.key, st.Version, enc, "x")
			racing = false
		}
	})
	_, err := a.sync()
	if err == nil {
		t.Fatal("expected an error")
	}
}

func TestWoWRunningNoWriteButPush(t *testing.T) {
	r := newRig(t)
	a, b := r.device("PC"), r.device("Laptop")
	a.write(scanA)
	a.sync()
	b.write(saleB)
	b.running = true
	before, _ := os.ReadFile(b.file())
	res, err := b.sync()
	if err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(b.file())
	if !bytes.Equal(before, after) {
		t.Error("file written while WoW was running")
	}
	if res.Wrote || !res.Skipped || res.Pushed != 2 {
		t.Fatalf("%+v", res)
	}
	if names, _ := backup.List(b.cfgDir); len(names) != 0 {
		t.Error("backup made without a write")
	}
	if !strings.Contains(b.out.String(), "NOT written") {
		t.Errorf("output: %q", b.out.String())
	}
	// the push carried the sale
	a.sync()
	if n(tget(a.db(), "realms", "R", "chars", "Al", "sales")) != 1 {
		t.Error("the sale was not pushed")
	}
}

// Review Focus 4 regression: WoW writes its logout save while ttf-sync waits for it to exit.
// The sync must read the file only after the wait, so that save is merged and pushed, not lost.
func TestWaitForExitReadsAfterTheWait(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	a.write(scanA)
	d := a.deps()
	d.WaitForExit = 60 * time.Second
	running := true
	d.WoWRunning = func() bool { return running }
	d.Sleep = func(x time.Duration) {
		a.now = a.now.Add(x)
		a.write(scanA + saleB) // the logout save lands during the wait; later variable wins
		running = false
	}
	res, err := Sync(d)
	if err != nil || !res.Wrote || res.Pushed != 1 {
		t.Fatalf("%+v %v", res, err)
	}
	if n(tget(a.db(), "realms", "R", "chars", "Al", "sales")) != 1 {
		t.Error("the logout save was overwritten")
	}
	b := r.device("Laptop")
	b.sync()
	if n(tget(b.db(), "realms", "R", "chars", "Al", "sales")) != 1 {
		t.Error("the logout save was never pushed")
	}
}

func TestStillRunningAfterWaitSkipsEverything(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	a.write(scanA)
	d := a.deps()
	d.WaitForExit = 5 * time.Second
	d.WoWRunning = func() bool { return true }
	res, err := Sync(d)
	if err != nil || res.Wrote || !res.Skipped || res.Pushed != 0 || r.fake.Version(r.key) != 0 {
		t.Fatalf("%+v %v", res, err)
	}
	if got, _ := os.ReadFile(a.file()); string(got) != scanA {
		t.Error("file changed")
	}
	if !strings.Contains(a.out.String(), "skipping this sync") {
		t.Errorf("output %q", a.out.String())
	}
}

func TestNoStampWhenPushFails(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	a.write(scanA)
	r.fake.SetHook(func(fn string) {
		if fn == "ttf_pull" {
			r.fake.SetStatus(503) // applies from the next request: the push fails
		}
	})
	if _, err := a.sync(); err == nil {
		t.Fatal("expected error")
	}
	if tget(a.db(), "sync") != nil {
		t.Error("stamped although the push failed")
	}
	// a later failure keeps the earlier stamp
	r.fake.SetHook(nil)
	r.fake.SetStatus(0)
	if _, err := a.sync(); err != nil {
		t.Fatal(err)
	}
	stamp := tget(a.db(), "sync", "at")
	if stamp == nil {
		t.Fatal("no stamp after a good sync")
	}
	r.fake.SetHook(func(fn string) {
		if fn == "ttf_pull" {
			r.fake.SetStatus(503)
		}
	})
	if _, err := a.sync(); err == nil {
		t.Fatal("expected error")
	}
	if tget(a.db(), "sync", "at") != stamp {
		t.Error("the previous stamp was dropped")
	}
}

func TestUnparseableNeverOverwritten(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	junk := "TaxTheFoolsDB = { realms = { oops\n"
	a.write(junk)
	_, err := a.sync()
	if !errors.Is(err, ErrUnparseable) {
		t.Fatalf("err = %v", err)
	}
	got, _ := os.ReadFile(a.file())
	if string(got) != junk {
		t.Error("the file was changed")
	}
	if r.fake.Version(r.key) != 0 {
		t.Error("something was pushed")
	}
	if names, _ := backup.List(a.cfgDir); len(names) != 0 {
		t.Error("a backup was made")
	}
}

func TestBackupRotation(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	a.write(scanA)
	for i := 0; i < 8; i++ {
		if _, err := a.sync(); err != nil {
			t.Fatal(err)
		}
	}
	names, _ := backup.List(a.cfgDir)
	if len(names) != backup.Keep {
		t.Fatalf("%d backups: %v", len(names), names)
	}
}

func TestIncompleteConfig(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	a.cfg.SyncKey = ""
	if _, err := a.sync(); err == nil || !strings.Contains(err.Error(), "sync key") {
		t.Fatalf("err = %v", err)
	}
}

func TestPausedProjectReported(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	a.write(scanA)
	r.fake.SetStatus(503)
	_, err := a.sync()
	if !errors.Is(err, api.ErrUnavailable) {
		t.Fatalf("err = %v", err)
	}
	got, _ := os.ReadFile(a.file())
	if string(got) != scanA {
		t.Error("local file changed with no server")
	}
}

func TestAgo(t *testing.T) {
	now := time.Unix(100000, 0)
	for d, want := range map[time.Duration]string{5 * time.Second: "just now", 5 * time.Minute: "5m ago",
		3 * time.Hour: "3h ago", 49 * time.Hour: "2d ago"} {
		if got := Ago(now, now.Add(-d)); got != want {
			t.Errorf("%v: %s", d, got)
		}
	}
}

func TestSyncOfTheFixtureHasNoUnknownPaths(t *testing.T) {
	r := newRig(t)
	a := r.device("PC")
	data, err := os.ReadFile("../../luasv/testdata/big.lua")
	if err != nil {
		t.Fatal(err)
	}
	a.write(string(data))
	a.now = time.Unix(1760000000+1000, 0)
	if _, err := Sync(a.deps()); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(a.out.String(), "no merge rule") {
		t.Errorf("unknown paths: %s", a.out.String())
	}
}
