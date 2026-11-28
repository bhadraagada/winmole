//go:build windows

package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/winmole/winmole/cmd/winmole/internal/reportdispatch"
)

func runNativeReport(request reportdispatch.Request) error {
	root, err := packageRoot()
	if err != nil {
		return err
	}

	var exe, label string
	args := []string{"-json"}
	switch request.Kind {
	case reportdispatch.Analyze:
		exe, label = "analyze.exe", "Disk analyzer"
		target := request.Path
		if target == "" {
			target, err = os.Getwd()
			if err != nil {
				return fmt.Errorf("cannot determine the caller's working directory: %w", err)
			}
		}
		if info, err := os.Stat(target); err != nil || !info.IsDir() {
			return fmt.Errorf("Not an existing directory: %s", target)
		}
		// Go's flag parser stops at positional arguments; always pass the
		// already-classified path as the value of -path.
		args = append(args, "-path", target)
	case reportdispatch.Status:
		exe, label = "status.exe", "System monitor"
	default:
		return fmt.Errorf("unknown native report")
	}

	// Do not search PATH, build from source or fall back to PowerShell. The
	// packaged helpers are the only launch targets for these read-only routes.
	binary := filepath.Join(root, "bin", exe)
	if info, err := os.Lstat(binary); err != nil || !info.Mode().IsRegular() {
		return fmt.Errorf("the bundled %s is missing or invalid: %s", exe, binary)
	}
	cmd := exec.Command(binary, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			// The legacy script reports the helper's code, then exits with 1.
			return fmt.Errorf("%s failed with exit code %d.", label, exit.ExitCode())
		}
		return err
	}
	return nil
}
