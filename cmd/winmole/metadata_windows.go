//go:build windows

package main

import (
	"fmt"
	"io"
	"strings"
)

// The packager sets this from the existing PowerShell version definition.
var version = "development"

const helpText = `WinMole - Windows System Maintenance Toolkit

Usage: winmole [command] [options]

Commands:
  analyze [path]   Inspect disk usage (--json for a read-only report)
  status           Inspect system health (--json for a read-only report)
  clean            Clean Windows and application caches
  uninstall        Uninstall applications
  optimize         Run system maintenance
  purge            Clean developer artifacts

Run without a command for the interactive menu. Commands and the menu use
Windows PowerShell and respect the host's script execution policy.
`

// Metadata is available even when PowerShell cannot execute the bundled scripts.
func writeMetadata(out io.Writer, args []string) (bool, error) {
	if len(args) != 1 {
		return false, nil
	}
	switch strings.ToLower(args[0]) {
	case "help", "--help", "-help", "-h", "-showhelp", "/?":
		_, err := fmt.Fprint(out, helpText)
		return true, err
	case "--version", "-version", "-v":
		_, err := fmt.Fprintf(out, "WinMole v%s\n", version)
		return true, err
	default:
		return false, nil
	}
}
