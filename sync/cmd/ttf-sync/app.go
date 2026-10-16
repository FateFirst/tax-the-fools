package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/FateFirst/tax-the-fools/sync/api"
	"github.com/FateFirst/tax-the-fools/sync/internal/backup"
	"github.com/FateFirst/tax-the-fools/sync/internal/config"
	"github.com/FateFirst/tax-the-fools/sync/internal/paths"
	"github.com/FateFirst/tax-the-fools/sync/internal/proc"
	"github.com/FateFirst/tax-the-fools/sync/internal/syncer"
	"github.com/FateFirst/tax-the-fools/sync/luasv"
)

// postGameWait is how long the after-game sync waits for a slow-exiting client
// (Proton) before it gives up on the local write. The push happens either way.
const postGameWait = 30 * time.Second

type app struct {
	in         *bufio.Reader
	out, err   io.Writer
	configDir  string
	wowRunning func() bool
	now        func() time.Time
	discover   func() []string
	// syncFn runs one sync; tests replace it to record ordering.
	syncFn func(post bool) error
	// startGame runs the game command and returns its exit code.
	startGame func(args []string) (int, error)
}

func newApp(in io.Reader, out, errw io.Writer) *app {
	a := &app{in: bufio.NewReader(in), out: out, err: errw, now: time.Now, discover: paths.Discover}
	a.wowRunning = func() bool { return proc.IsWoWRunning() }
	a.startGame = runCommand
	a.syncFn = a.sync
	return a
}

func (a *app) dir() (string, error) {
	if a.configDir != "" {
		return a.configDir, nil
	}
	if d := os.Getenv("TTF_SYNC_CONFIG_DIR"); d != "" {
		return d, nil
	}
	return config.Dir()
}

func (a *app) load() (string, config.Config, error) {
	dir, err := a.dir()
	if err != nil {
		return "", config.Config{}, err
	}
	c, err := config.Load(dir)
	return dir, c, err
}

func (a *app) println(s ...any) { fmt.Fprintln(a.out, s...) }

const usage = `ttf-sync: keeps Tax The Fools data in step across your devices

  ttf-sync setup                 find WoW and enter the Supabase details
  ttf-sync init                  first device: create the sync account and print the key
  ttf-sync join <key>            other devices: use an existing sync key
  ttf-sync sync                  run one sync now
  ttf-sync run -- cmd args...    sync, start the game, sync again
  ttf-sync status                show the setup, the last sync and the devices
  ttf-sync restore               put back an earlier copy of the SavedVariables file
  ttf-sync version
`

func (a *app) run(args []string) int {
	if len(args) == 0 {
		fmt.Fprint(a.err, usage)
		return 1
	}
	var err error
	switch args[0] {
	case "setup":
		err = a.setup()
	case "init":
		err = a.init()
	case "join":
		if len(args) != 2 {
			err = errors.New("usage: ttf-sync join <key>")
		} else {
			err = a.join(args[1])
		}
	case "sync":
		err = a.syncFn(false)
	case "run":
		return a.runGame(args[1:])
	case "status":
		err = a.status()
	case "restore":
		err = a.restore()
	case "version", "-v", "--version":
		a.println("ttf-sync " + version)
	case "help", "-h", "--help":
		fmt.Fprint(a.out, usage)
	default:
		fmt.Fprintf(a.err, "unknown command %q\n\n%s", args[0], usage)
		return 1
	}
	if err != nil {
		fmt.Fprintln(a.err, "Error:", err)
		return 1
	}
	return 0
}

func (a *app) ask(prompt, def string) string {
	if def != "" {
		fmt.Fprintf(a.out, "%s [%s]: ", prompt, def)
	} else {
		fmt.Fprintf(a.out, "%s: ", prompt)
	}
	line, _ := a.in.ReadString('\n')
	line = strings.TrimSpace(line)
	if line == "" {
		return def
	}
	return line
}

// choose lists options and returns the picked one (by number, or a typed value when allowTyped).
func (a *app) choose(title string, opts []string, allowTyped bool) string {
	for i, o := range opts {
		fmt.Fprintf(a.out, "  %d) %s\n", i+1, o)
	}
	def := ""
	if len(opts) > 0 {
		def = "1"
	}
	for {
		ans := a.ask(title, def)
		if n, err := strconv.Atoi(ans); err == nil && n >= 1 && n <= len(opts) {
			return opts[n-1]
		}
		if allowTyped && ans != "" {
			return ans
		}
		if ans == "" {
			return ""
		}
		fmt.Fprintln(a.out, "Please type one of the numbers.")
	}
}

func (a *app) setup() error {
	dir, c, err := a.load()
	if err != nil {
		return err
	}
	a.println("Looking for World of Warcraft folders...")
	found := a.discover()
	var wow string
	if len(found) > 0 {
		a.println("Found:")
		wow = a.choose("Pick a number, or type the folder path", found, true)
	} else {
		a.println("Nothing found automatically.")
		wow = a.ask("WoW folder (the one with WoW.exe and WTF)", c.WoWPath)
	}
	if wow == "" {
		return errors.New("no WoW folder given")
	}
	if !paths.IsWoWFolder(wow) {
		a.println("Warning: that folder has no WoW.exe + WTF folder next to each other. Continuing anyway.")
	}
	c.WoWPath = wow
	accts, err := paths.Accounts(wow)
	switch {
	case err != nil || len(accts) == 0:
		c.Account = a.ask("Account folder name (under WTF/Account)", c.Account)
	case len(accts) == 1:
		c.Account = accts[0]
		a.println("Account folder: " + c.Account)
	default:
		a.println("Several account folders:")
		c.Account = a.choose("Which one holds your Tax The Fools data?", accts, false)
	}
	if c.Account == "" {
		return errors.New("no account folder given")
	}
	c.SupabaseURL = a.ask("Supabase project URL (https://xxxx.supabase.co)", c.SupabaseURL)
	c.AnonKey = a.ask("Supabase anon key", c.AnonKey)
	c.Device = a.ask("Name for this device", c.Device)
	if err := config.Save(dir, c); err != nil {
		return err
	}
	a.println("Saved " + config.Path(dir))
	a.println("Next: `ttf-sync init` on the first device, or `ttf-sync join <key>` on the others.")
	return nil
}

func (a *app) client(c config.Config) (*api.Client, error) {
	if c.SupabaseURL == "" || c.AnonKey == "" {
		return nil, errors.New("Supabase URL / anon key not set: run `ttf-sync setup` first")
	}
	return &api.Client{URL: c.SupabaseURL, AnonKey: c.AnonKey}, nil
}

func (a *app) init() error {
	dir, c, err := a.load()
	if err != nil {
		return err
	}
	cl, err := a.client(c)
	if err != nil {
		return err
	}
	if c.SyncKey != "" {
		return errors.New("this device already has a sync key. To start a new account, delete syncKey from " + config.Path(dir) + " first")
	}
	key := api.NewSyncKey()
	if err := cl.CreateAccount(key); err != nil {
		return err
	}
	c.SyncKey = key
	if err := config.Save(dir, c); err != nil {
		return err
	}
	a.println("Sync account created. Your sync key is:")
	a.println()
	a.println("    " + key)
	a.println()
	a.println("Keep this safe: anyone with it can read and change your synced data, and it can't be recovered.")
	a.println("Put it in a password manager. Other devices join with: ttf-sync join <key>")
	return nil
}

func (a *app) join(key string) error {
	dir, c, err := a.load()
	if err != nil {
		return err
	}
	cl, err := a.client(c)
	if err != nil {
		return err
	}
	key = strings.TrimSpace(key)
	st, err := cl.Pull(key)
	if err != nil {
		if errors.Is(err, api.ErrInvalidKey) {
			return errors.New("that sync key was not accepted: check it was copied whole, and that setup used the same Supabase project")
		}
		return err
	}
	c.SyncKey = key
	if err := config.Save(dir, c); err != nil {
		return err
	}
	a.println(fmt.Sprintf("Joined. The server copy is at v%d.", st.Version))
	return nil
}

// sync is the real syncFn. post is true for the after-game sync.
func (a *app) sync(post bool) error {
	dir, c, err := a.load()
	if err != nil {
		return err
	}
	cl, err := a.client(c)
	if err != nil {
		return err
	}
	d := syncer.Deps{Client: cl, Cfg: c, ConfigDir: dir, WoWRunning: a.wowRunning,
		Now: a.now, Version: version, Out: a.out}
	if post {
		d.WaitForExit = postGameWait
	}
	_, err = syncer.Sync(d)
	return err
}

func runCommand(args []string) (int, error) {
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Start(); err != nil {
		return 1, err
	}
	err := cmd.Wait()
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return ee.ExitCode(), nil
	}
	if err != nil {
		return 1, err
	}
	return 0, nil
}

// runGame: sync, start the game, wait, sync. The game starts even if the first sync fails.
func (a *app) runGame(args []string) int {
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}
	if len(args) == 0 {
		fmt.Fprintln(a.err, "Error: usage: ttf-sync run -- <game command> [args...]")
		return 1
	}
	if err := a.syncFn(false); err != nil {
		fmt.Fprintln(a.err, "Sync before the game failed:", err)
		fmt.Fprintln(a.err, "Starting the game anyway.")
	}
	code, err := a.startGame(args)
	if err != nil {
		fmt.Fprintln(a.err, "Error: could not run the game:", err)
		return 1
	}
	if err := a.syncFn(true); err != nil {
		fmt.Fprintln(a.err, "Sync after the game failed:", err)
	}
	return code
}

func (a *app) status() error {
	dir, c, err := a.load()
	if err != nil {
		return err
	}
	a.println("ttf-sync " + version)
	a.println("Config:      " + config.Path(dir))
	a.println("Device:      " + c.Device)
	a.println("Supabase:    " + orNone(c.SupabaseURL))
	a.println("Sync key:    " + config.MaskKey(c.SyncKey))
	a.println("WoW folder:  " + orNone(c.WoWPath))
	a.println("Account:     " + orNone(c.Account))
	if c.WoWPath != "" && c.Account != "" {
		p := paths.SavedVars(c.WoWPath, c.Account)
		if data, err := os.ReadFile(p); err != nil {
			a.println("Local file:  not found (" + p + ")")
		} else {
			a.println("Local file:  " + p + localSyncInfo(data, a.now()))
		}
	}
	names, _ := backup.List(dir)
	a.println(fmt.Sprintf("Backups:     %d (in %s)", len(names), backup.Dir(dir)))
	if a.wowRunning() {
		a.println("WoW:         running")
	}
	cl, err := a.client(c)
	if err != nil || c.SyncKey == "" {
		a.println("Server:      not configured yet")
		return nil
	}
	st, err := cl.Pull(c.SyncKey)
	if err != nil {
		return err
	}
	a.println(fmt.Sprintf("Server:      v%d, last pushed by %s (%s)", st.Version, orNone(st.UpdatedBy), syncer.Ago(a.now(), st.UpdatedAt)))
	devs, err := cl.Devices(c.SyncKey)
	if err != nil {
		return err
	}
	a.println("Devices:")
	for _, d := range devs {
		a.println(fmt.Sprintf("  %s  (last sync %s)", d.Device, syncer.Ago(a.now(), d.LastSync)))
	}
	return nil
}

func localSyncInfo(data []byte, now time.Time) string {
	vars, err := luasv.Parse(data)
	if err != nil {
		return "  (cannot be parsed: " + err.Error() + ")"
	}
	db, _ := vars["TaxTheFoolsDB"].(*luasv.Table)
	if db == nil {
		return "  (no data yet)"
	}
	sv, _ := db.GetS("sync")
	st, _ := sv.(*luasv.Table)
	if st == nil {
		return "  (never synced)"
	}
	at, _ := st.GetS("at")
	dev, _ := st.GetS("device")
	f, _ := at.(float64)
	ds, _ := dev.(string)
	return fmt.Sprintf("  (last synced %s from %s)", syncer.Ago(now, time.Unix(int64(f), 0)), orNone(ds))
}

func orNone(s string) string {
	if s == "" {
		return "(not set)"
	}
	return s
}

func (a *app) restore() error {
	dir, c, err := a.load()
	if err != nil {
		return err
	}
	if c.WoWPath == "" || c.Account == "" {
		return errors.New("WoW folder or account not set: run `ttf-sync setup`")
	}
	names, err := backup.List(dir)
	if err != nil {
		return err
	}
	if len(names) == 0 {
		return errors.New("no backups yet: one is made before each time ttf-sync writes the file")
	}
	if a.wowRunning() {
		return errors.New("WoW is running: close it first, or it will overwrite the restored file when you log out")
	}
	a.println("Backups, newest first:")
	pick := a.choose("Restore which one? (Enter to cancel)", names, false)
	if pick == "" {
		a.println("Cancelled.")
		return nil
	}
	dest := paths.SavedVars(c.WoWPath, c.Account)
	// Read the pick first: backing up the current file can rotate the oldest one away.
	chosen, err := os.ReadFile(filepath.Join(backup.Dir(dir), pick))
	if err != nil {
		return err
	}
	if _, err := os.Stat(dest); err == nil {
		if _, err := backup.Create(dir, dest, a.now()); err != nil {
			return fmt.Errorf("could not back up the current file first: %w", err)
		}
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(dest, chosen, 0o644); err != nil {
		return err
	}
	a.println("Restored " + pick + " to " + dest)
	a.println("The next sync will merge it with the server copy again.")
	return nil
}
