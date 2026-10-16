// Package paths finds the WoW folder and the TaxTheFools SavedVariables file.
package paths

import (
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

// SavedVars is <wow>/WTF/Account/<account>/SavedVariables/TaxTheFools.lua.
func SavedVars(wowPath, account string) string {
	return filepath.Join(wowPath, "WTF", "Account", account, "SavedVariables", "TaxTheFools.lua")
}

// IsWoWFolder: the folder holds WoW.exe (any case) and a WTF folder.
func IsWoWFolder(dir string) bool {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	exe, wtf := false, false
	for _, e := range entries {
		n := strings.ToLower(e.Name())
		if n == "wow.exe" && !e.IsDir() {
			exe = true
		}
		if n == "wtf" && e.IsDir() {
			wtf = true
		}
	}
	return exe && wtf
}

// Accounts lists the account folders under <wow>/WTF/Account (SavedVariables excluded).
func Accounts(wowPath string) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(wowPath, "WTF", "Account"))
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() && !strings.EqualFold(e.Name(), "SavedVariables") {
			out = append(out, e.Name())
		}
	}
	sort.Strings(out)
	return out, nil
}

// Root is a place to search and how deep to go below it.
type Root struct {
	Dir   string
	Depth int
}

var skipDirs = map[string]bool{"windows": true, "$recycle.bin": true, "system volume information": true,
	"programdata": true, "users": true, "proc": true, "dosdevices": true}

// Search walks the roots (not following symlinks) to the given depth and returns
// every WoW folder found, without going inside one. Results are sorted and unique.
func Search(roots []Root) []string {
	seen := map[string]bool{}
	var out []string
	for _, r := range roots {
		base := filepath.Clean(r.Dir)
		if st, err := os.Stat(base); err != nil || !st.IsDir() {
			continue
		}
		filepath.WalkDir(base, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				if d != nil && d.IsDir() {
					return fs.SkipDir
				}
				return nil
			}
			if !d.IsDir() {
				return nil
			}
			rel, _ := filepath.Rel(base, p)
			depth := 0
			if rel != "." {
				depth = len(strings.Split(rel, string(filepath.Separator)))
			}
			if depth > r.Depth {
				return fs.SkipDir
			}
			if depth > 0 && skipDirs[strings.ToLower(d.Name())] {
				return fs.SkipDir
			}
			if IsWoWFolder(p) {
				key := p
				if real, err := filepath.EvalSymlinks(p); err == nil {
					key = real
				}
				if !seen[key] {
					seen[key] = true
					out = append(out, p)
				}
				return fs.SkipDir
			}
			return nil
		})
	}
	sort.Strings(out)
	return out
}

// DefaultRoots are the usual install places for this OS.
func DefaultRoots() []Root {
	home, _ := os.UserHomeDir()
	var roots []Root
	if runtime.GOOS == "windows" {
		for _, drive := range []string{"C", "D", "E", "F"} {
			d := drive + `:\`
			roots = append(roots,
				Root{filepath.Join(d, "Program Files (x86)"), 3},
				Root{filepath.Join(d, "Program Files"), 3},
				Root{filepath.Join(d, "Games"), 3},
				Root{filepath.Join(d, "Turtle WoW"), 1},
				Root{filepath.Join(d, "TurtleWoW"), 1},
				Root{filepath.Join(d, "Ravencraft"), 1},
				Root{filepath.Join(d, "WoW"), 1},
				Root{filepath.Join(d, "WoW 1.12"), 1})
		}
		return roots
	}
	if home == "" {
		return nil
	}
	for _, pat := range []string{
		filepath.Join(home, ".steam", "steam", "steamapps", "compatdata", "*", "pfx", "drive_c"),
		filepath.Join(home, ".local", "share", "Steam", "steamapps", "compatdata", "*", "pfx", "drive_c"),
		filepath.Join(home, "Games", "*", "drive_c"),
	} {
		matches, _ := filepath.Glob(pat)
		for _, m := range matches {
			roots = append(roots, Root{m, 5})
		}
	}
	// Steam Deck SD card: /run/media/mmcblk0p1 or /run/media/<user>/<label>.
	for _, pat := range []string{"/run/media/*", "/run/media/*/*"} {
		matches, _ := filepath.Glob(pat)
		for _, m := range matches {
			roots = append(roots, Root{m, 4})
		}
	}
	roots = append(roots, Root{filepath.Join(home, "Games"), 5})
	return roots
}

// Discover searches the default places.
func Discover() []string { return Search(DefaultRoots()) }
