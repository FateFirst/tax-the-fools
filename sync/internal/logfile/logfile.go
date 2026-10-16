// Package logfile keeps ttf-sync's own log and the result of the last sync, in the
// config folder. Under Steam's launch options and Windows shortcuts nobody sees the
// console, so this is where results and errors can be found.
package logfile

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// MaxSize is when the log rotates (one old file is kept as ttf-sync.log.1).
const MaxSize = 1 << 20

func Path(dir string) string { return filepath.Join(dir, "ttf-sync.log") }

// Append writes each non-empty line of text, timestamped.
func Append(dir string, now time.Time, text string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	p := Path(dir)
	if st, err := os.Stat(p); err == nil && st.Size() >= MaxSize {
		os.Remove(p + ".1")
		os.Rename(p, p+".1")
	}
	f, err := os.OpenFile(p, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	stamp := now.Format("2006-01-02 15:04:05")
	for _, l := range strings.Split(text, "\n") {
		if l = strings.TrimRight(l, "\r"); l != "" {
			if _, err := f.WriteString(stamp + "  " + l + "\n"); err != nil {
				return err
			}
		}
	}
	return nil
}

// Last is the outcome of the most recent sync.
type Last struct {
	At      int64  `json:"at"`
	OK      bool   `json:"ok"`
	Message string `json:"message"`
}

func lastPath(dir string) string { return filepath.Join(dir, "last-sync.json") }

func SaveLast(dir string, l Last) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	b, _ := json.Marshal(l)
	return os.WriteFile(lastPath(dir), b, 0o600)
}

// LoadLast returns nil if there is no record yet.
func LoadLast(dir string) *Last {
	b, err := os.ReadFile(lastPath(dir))
	if err != nil {
		return nil
	}
	var l Last
	if json.Unmarshal(b, &l) != nil {
		return nil
	}
	return &l
}
