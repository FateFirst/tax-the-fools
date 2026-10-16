// Package backup keeps the last few copies of the SavedVariables file.
package backup

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Keep is how many backups are retained.
const Keep = 5

const prefix = "TaxTheFools-"

// Dir is the backups folder inside the config folder.
func Dir(configDir string) string { return filepath.Join(configDir, "backups") }

// Create copies src into the backups folder and drops all but the Keep newest.
// It returns the backup's path.
func Create(configDir, src string, now time.Time) (string, error) {
	data, err := os.ReadFile(src)
	if err != nil {
		return "", err
	}
	dir := Dir(configDir)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	t := now
	var dst string
	for {
		dst = filepath.Join(dir, prefix+t.Format("20060102-150405.000")+".lua")
		if _, err := os.Stat(dst); err != nil {
			break
		}
		t = t.Add(time.Millisecond)
	}
	if err := os.WriteFile(dst, data, 0o600); err != nil {
		return "", err
	}
	names, _ := List(configDir)
	for i := Keep; i < len(names); i++ {
		os.Remove(filepath.Join(dir, names[i]))
	}
	return dst, nil
}

// List returns backup file names, newest first.
func List(configDir string) ([]string, error) {
	entries, err := os.ReadDir(Dir(configDir))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasPrefix(e.Name(), prefix) && strings.HasSuffix(e.Name(), ".lua") {
			names = append(names, e.Name())
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(names)))
	return names, nil
}

// Restore copies the named backup over dest.
func Restore(configDir, name, dest string) error {
	if name != filepath.Base(name) {
		return fmt.Errorf("bad backup name %q", name)
	}
	data, err := os.ReadFile(filepath.Join(Dir(configDir), name))
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	return os.WriteFile(dest, data, 0o644)
}
