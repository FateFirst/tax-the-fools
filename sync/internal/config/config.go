// Package config loads and saves the ttf-sync settings file.
package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Config is the content of config.json.
type Config struct {
	SupabaseURL string `json:"supabaseUrl"`
	AnonKey     string `json:"anonKey"`
	SyncKey     string `json:"syncKey"`
	Device      string `json:"device"`
	WoWPath     string `json:"wowPath"`
	Account     string `json:"account"`
}

// Dir is where the config and the backups live: os.UserConfigDir()/ttf-sync
// (%APPDATA% on Windows, ~/.config on Linux).
func Dir() (string, error) {
	base, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("cannot find the config folder: %w", err)
	}
	return filepath.Join(base, "ttf-sync"), nil
}

// Path is the config file inside dir.
func Path(dir string) string { return filepath.Join(dir, "config.json") }

// Load reads dir/config.json. A missing file gives an empty Config (device
// defaults to the host name) and no error.
func Load(dir string) (Config, error) {
	var c Config
	data, err := os.ReadFile(Path(dir))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			c.Device = hostname()
			return c, nil
		}
		return c, err
	}
	if err := json.Unmarshal(data, &c); err != nil {
		return c, fmt.Errorf("%s is not valid JSON (%v): fix it or delete it and run setup again", Path(dir), err)
	}
	if c.Device == "" {
		c.Device = hostname()
	}
	return c, nil
}

// Save writes dir/config.json (private to the user: it holds the sync key).
func Save(dir string, c Config) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(Path(dir), append(data, '\n'), 0o600)
}

func hostname() string {
	h, err := os.Hostname()
	if err != nil || h == "" {
		return "device"
	}
	return h
}

// MaskKey shows only the start of a sync key, for status output.
func MaskKey(k string) string {
	if k == "" {
		return "(not set)"
	}
	if len(k) <= 6 {
		return strings.Repeat("*", len(k))
	}
	return k[:4] + strings.Repeat("*", 8)
}
