// Package syncer runs one sync: parse local, pull, merge, write local, push.
package syncer

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/FateFirst/tax-the-fools/sync/api"
	"github.com/FateFirst/tax-the-fools/sync/internal/backup"
	"github.com/FateFirst/tax-the-fools/sync/internal/config"
	"github.com/FateFirst/tax-the-fools/sync/internal/paths"
	"github.com/FateFirst/tax-the-fools/sync/luasv"
	"github.com/FateFirst/tax-the-fools/sync/merge"
)

const maxTries = 3

// Deps is everything a sync touches, so tests can swap it.
type Deps struct {
	Client     *api.Client
	Cfg        config.Config
	ConfigDir  string
	WoWRunning func() bool
	Now        func() time.Time
	Version    string
	Out        io.Writer
	// WaitForExit: if WoW is running at write time, poll this long for it to exit
	// before giving up on the write (used after the game, when Proton exits slowly).
	WaitForExit time.Duration
	Sleep       func(time.Duration)
}

// Result describes what a sync did.
type Result struct {
	Pulled  int64
	Pushed  int64
	Wrote   bool
	Skipped bool // the local write was skipped because WoW is running
	Tries   int
}

// ErrUnparseable: the local file can't be read, so nothing was changed anywhere.
var ErrUnparseable = errors.New("local SavedVariables file could not be parsed")

func (d *Deps) printf(f string, a ...any) {
	if d.Out != nil {
		fmt.Fprintf(d.Out, f, a...)
	}
}

// Ago renders a duration since t.
func Ago(now, t time.Time) string {
	s := int(now.Sub(t).Seconds())
	switch {
	case s < 60:
		return "just now"
	case s < 3600:
		return fmt.Sprintf("%dm ago", s/60)
	case s < 86400:
		return fmt.Sprintf("%dh ago", s/3600)
	}
	return fmt.Sprintf("%dd ago", s/86400)
}

// Sync runs the whole flow (spec section 4).
func Sync(d Deps) (Result, error) {
	var res Result
	if d.Now == nil {
		d.Now = time.Now
	}
	if d.Sleep == nil {
		d.Sleep = time.Sleep
	}
	c := d.Cfg
	switch {
	case c.SupabaseURL == "" || c.AnonKey == "":
		return res, errors.New("Supabase URL / anon key not set: run `ttf-sync setup`")
	case c.SyncKey == "":
		return res, errors.New("no sync key: run `ttf-sync init` (first device) or `ttf-sync join <key>`")
	case c.WoWPath == "" || c.Account == "":
		return res, errors.New("WoW folder or account not set: run `ttf-sync setup`")
	}
	path := paths.SavedVars(c.WoWPath, c.Account)

	// After the game: WoW writes its SavedVariables as it exits, so wait for it to be gone
	// before reading anything. If it never goes, do nothing at all; the next sync catches up.
	if d.WaitForExit > 0 && d.wowRunning() {
		d.printf("WoW is still running: waiting up to %s for it to exit...\n", d.WaitForExit)
		deadline := d.Now().Add(d.WaitForExit)
		for d.wowRunning() && d.Now().Before(deadline) {
			d.Sleep(time.Second)
		}
		if d.wowRunning() {
			d.printf("WoW is still running after %s: skipping this sync (nothing read, written or pushed). The next sync will catch up.\n", d.WaitForExit)
			res.Skipped = true
			return res, nil
		}
	}

	// 1. local
	vars := map[string]luasv.Value{}
	haveFile := false
	data, err := os.ReadFile(path)
	switch {
	case err == nil:
		haveFile = true
		vars, err = luasv.Parse(data)
		if err != nil {
			return res, fmt.Errorf("%w: %s: %v. Nothing was changed, on this device or on the server. "+
				"Restore a backup (`ttf-sync restore`), or move the file away and sync again", ErrUnparseable, path, err)
		}
	case errors.Is(err, os.ErrNotExist):
		d.printf("No local file yet (%s): starting from the server copy.\n", path)
	default:
		return res, fmt.Errorf("cannot read %s: %w", path, err)
	}
	local := vars["TaxTheFoolsDB"]

	// 2-5. pull, merge, push with compare-and-swap
	var merged luasv.Value
	var remoteDesc string
	var rep merge.Report
	pushed := false
	var pushErr error
	for try := 1; try <= maxTries; try++ {
		res.Tries = try
		st, err := d.Client.Pull(c.SyncKey)
		if err != nil {
			return res, err
		}
		res.Pulled = st.Version
		var remote luasv.Value
		blob, err := api.DecodeBlob(st.Blob)
		if err != nil {
			return res, fmt.Errorf("the server copy is damaged: %w", err)
		}
		if blob != nil {
			if remote, err = luasv.UnmarshalJSON(blob); err != nil {
				return res, fmt.Errorf("the server copy is damaged: %w", err)
			}
		}
		if st.Version == 0 || blob == nil {
			remoteDesc = fmt.Sprintf("Pulled v%d (server is empty)", st.Version)
		} else {
			by := st.UpdatedBy
			if by == "" {
				by = "?"
			}
			remoteDesc = fmt.Sprintf("Pulled v%d from %s (%s)", st.Version, by, Ago(d.Now(), st.UpdatedAt))
		}
		merged, rep = merge.Merge(local, remote, merge.Options{Now: d.Now().Unix()})
		if merged == nil {
			merged = luasv.NewTable()
		}
		if t, ok := merged.(*luasv.Table); ok {
			t.Delete("sync") // written to the local file only
		}
		js, err := luasv.MarshalJSON(merged)
		if err != nil {
			return res, err
		}
		enc, err := api.EncodeBlob(js)
		if err != nil {
			return res, err
		}
		nv, conflict, err := d.Client.Push(c.SyncKey, st.Version, enc, c.Device)
		if err != nil {
			pushErr = err
			break
		}
		if conflict {
			d.printf("Another device pushed first (v%d was stale): pulling and merging again (try %d of %d)\n", st.Version, try, maxTries)
			continue
		}
		res.Pushed, pushed = nv, true
		break
	}

	// 4/6. write local (after the push attempt, so a conflict re-merge writes once)
	wrote, skipped, werr := d.writeLocal(path, haveFile, vars, merged, pushed)
	res.Wrote, res.Skipped = wrote, skipped
	if werr != nil {
		return res, werr
	}
	if pushErr != nil {
		d.printf("%s · merged%s\n", remoteDesc, localNote(wrote, skipped))
		return res, pushErr
	}
	if !pushed {
		return res, fmt.Errorf("the server changed %d times while syncing; try again", maxTries)
	}
	d.printf("%s · merged%s · pushed v%d\n", remoteDesc, localNote(wrote, skipped), res.Pushed)
	if n := len(rep.Unknown); n > 0 {
		d.printf("Note: %d data path(s) have no merge rule yet and were kept as on this device (e.g. %s)\n", n, rep.Unknown[0])
	}
	return res, nil
}

func localNote(wrote, skipped bool) string {
	switch {
	case wrote:
		return " · wrote local"
	case skipped:
		return " · local file NOT written (WoW is running or could not be checked; it will catch up at the next sync)"
	}
	return ""
}

func (d *Deps) wowRunning() bool { return d.WoWRunning != nil && d.WoWRunning() }

func (d *Deps) writeLocal(path string, haveFile bool, vars map[string]luasv.Value, merged luasv.Value, stamp bool) (wrote, skipped bool, err error) {
	if d.wowRunning() {
		return false, true, nil
	}
	if t, ok := merged.(*luasv.Table); ok && stamp {
		st := luasv.NewTable()
		st.SetS("at", float64(d.Now().Unix()))
		st.SetS("device", d.Cfg.Device)
		st.SetS("version", d.Version)
		t.SetS("sync", st)
	}
	out := map[string]luasv.Value{}
	for k, v := range vars {
		out[k] = v
	}
	out["TaxTheFoolsDB"] = merged
	b, err := luasv.Write(out, nil)
	if err != nil {
		return false, false, err
	}
	if haveFile {
		if _, err := backup.Create(d.ConfigDir, path, d.Now()); err != nil {
			return false, false, fmt.Errorf("backup failed, so the local file was not changed: %w", err)
		}
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, false, err
	}
	tmp := path + ".ttf-sync.tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return false, false, err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return false, false, err
	}
	return true, false, nil
}
