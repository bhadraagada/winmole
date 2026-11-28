//go:build !windows

package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "WinMole Desktop runs on Windows.")
	os.Exit(1)
}
