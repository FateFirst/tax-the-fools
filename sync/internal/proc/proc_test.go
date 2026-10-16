package proc

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseTasklist(t *testing.T) {
	yes := "\"System\",\"4\",\"Services\",\"0\",\"1 K\"\r\n\"Wow.exe\",\"1234\",\"Console\",\"1\",\"500,000 K\"\r\n"
	no := "\"notwow.exe\",\"1\",\"Console\",\"1\",\"1 K\"\r\n\"ttf-sync.exe\",\"2\",\"Console\",\"1\",\"1 K\"\r\n"
	if !ParseTasklist(yes) || ParseTasklist(no) || ParseTasklist("") {
		t.Error("ParseTasklist")
	}
	if !ParseTasklist("\"WOW.EXE\",\"1\"\r\n") {
		t.Error("case")
	}
}

func fakeProc(t *testing.T, root, pid, comm, cmdline string) {
	d := filepath.Join(root, pid)
	os.MkdirAll(d, 0o755)
	os.WriteFile(filepath.Join(d, "comm"), []byte(comm+"\n"), 0o644)
	os.WriteFile(filepath.Join(d, "cmdline"), []byte(cmdline), 0o644)
}

func TestScanProc(t *testing.T) {
	root := t.TempDir()
	// ttf-sync itself and the Proton launcher mention WoW.exe only as an argument
	fakeProc(t, root, "10", "ttf-sync", "ttf-sync\x00run\x00--\x00/g/WoW.exe\x00")
	fakeProc(t, root, "11", "python3", "python3\x00proton\x00waitforexitandrun\x00/g/WoW.exe\x00")
	if ScanProc(root, 99) {
		t.Fatal("false positive on arguments")
	}
	fakeProc(t, root, "12", "WoW.exe", "Z:\\games\\WoW.exe\x00")
	if !ScanProc(root, 99) {
		t.Fatal("comm not seen")
	}
	if ScanProc(root, 12) {
		t.Fatal("self pid not skipped")
	}
	root2 := t.TempDir()
	fakeProc(t, root2, "5", "wine64-preload", "Z:\\home\\deck\\Wow.exe\x00-x\x00")
	if !ScanProc(root2, 99) {
		t.Fatal("cmdline argv0 not seen")
	}
}

func TestIsWoWRunningFailsClosed(t *testing.T) {
	orig := Check
	defer func() { Check = orig }()
	Check = func() (bool, error) { return false, os.ErrPermission }
	if !IsWoWRunning() {
		t.Error("an unknown state must count as running")
	}
	Check = func() (bool, error) { return false, nil }
	if IsWoWRunning() {
		t.Error("not running")
	}
}
