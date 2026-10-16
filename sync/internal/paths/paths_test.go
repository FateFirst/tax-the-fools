package paths

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func mk(t *testing.T, p string, files ...string) {
	t.Helper()
	os.MkdirAll(p, 0o755)
	for _, f := range files {
		os.WriteFile(filepath.Join(p, f), nil, 0o644)
	}
}

func TestDiscoverAndAccounts(t *testing.T) {
	root := t.TempDir()
	steam := filepath.Join(root, "compatdata", "123", "pfx", "drive_c", "Games", "Turtle WoW")
	mk(t, filepath.Join(steam, "WTF", "Account", "MYACC", "SavedVariables"))
	mk(t, filepath.Join(steam, "WTF", "Account", "OTHER"))
	os.WriteFile(filepath.Join(steam, "Wow.exe"), nil, 0o644)
	lutris := filepath.Join(root, "Games", "x", "drive_c", "WoW")
	mk(t, filepath.Join(lutris, "WTF"))
	mk(t, lutris, "WoW.exe")
	mk(t, filepath.Join(root, "Games", "nope"), "WoW.exe") // no WTF
	deep := filepath.Join(root, "a", "b", "c", "d", "e", "f", "g")
	mk(t, filepath.Join(deep, "WTF"))
	mk(t, deep, "WoW.exe") // too deep

	got := Search([]Root{{filepath.Join(root, "compatdata", "123", "pfx", "drive_c"), 4}, {filepath.Join(root, "Games"), 5}, {filepath.Join(root, "a"), 3}, {filepath.Join(root, "missing"), 3}})
	want := []string{lutris, steam}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	if !IsWoWFolder(steam) || IsWoWFolder(filepath.Join(root, "Games", "nope")) {
		t.Error("IsWoWFolder")
	}
	accts, err := Accounts(steam)
	if err != nil || !reflect.DeepEqual(accts, []string{"MYACC", "OTHER"}) {
		t.Fatalf("%v %v", accts, err)
	}
	if p := SavedVars("/w", "A"); filepath.ToSlash(p) != "/w/WTF/Account/A/SavedVariables/TaxTheFools.lua" {
		t.Error(p)
	}
}
