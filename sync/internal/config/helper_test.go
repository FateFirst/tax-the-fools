package config

import "os"

func osWrite(p, s string) error { return os.WriteFile(p, []byte(s), 0o600) }
