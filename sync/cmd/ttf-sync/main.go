// ttf-sync keeps Tax The Fools' SavedVariables in step across devices.
package main

import "os"

// version is set at build time: -ldflags "-X main.version=1.0.0".
var version = "dev"

func main() {
	os.Exit(newApp(os.Stdin, os.Stdout, os.Stderr).run(os.Args[1:]))
}
