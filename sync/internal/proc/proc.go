// Package proc tells whether the WoW client is running.
package proc

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

// IsWoWRunning is a variable so callers and tests can swap it.
var IsWoWRunning = detect

func detect() bool {
	if runtime.GOOS == "windows" {
		out, err := exec.Command("tasklist", "/FO", "CSV", "/NH").Output()
		if err != nil {
			return false
		}
		return ParseTasklist(string(out))
	}
	return ScanProc("/proc", os.Getpid())
}

func isWoWName(s string) bool { return strings.EqualFold(s, "wow.exe") }

// ParseTasklist reads `tasklist /FO CSV /NH` output.
func ParseTasklist(out string) bool {
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, "\"") {
			continue
		}
		name := strings.SplitN(line[1:], "\"", 2)[0]
		if isWoWName(name) {
			return true
		}
	}
	return false
}

// ScanProc looks through a /proc tree for a process whose name (comm) or program
// (first command-line word, Windows or Unix path) is wow.exe. Only the program
// counts, not later arguments: ttf-sync's own command line and the Proton launcher
// both mention WoW.exe as an argument. selfPid is skipped.
func ScanProc(root string, selfPid int) bool {
	dirs, _ := filepath.Glob(filepath.Join(root, "[0-9]*"))
	for _, d := range dirs {
		if filepath.Base(d) == strconv.Itoa(selfPid) {
			continue
		}
		if b, err := os.ReadFile(filepath.Join(d, "comm")); err == nil && isWoWName(strings.TrimSpace(string(b))) {
			return true
		}
		if b, err := os.ReadFile(filepath.Join(d, "cmdline")); err == nil {
			argv0 := strings.SplitN(string(b), "\x00", 2)[0]
			if i := strings.LastIndexAny(argv0, `/\`); i >= 0 {
				argv0 = argv0[i+1:]
			}
			if isWoWName(argv0) {
				return true
			}
		}
	}
	return false
}
