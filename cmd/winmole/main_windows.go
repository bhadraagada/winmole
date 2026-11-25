//go:build windows

package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/winmole/winmole/cmd/winmole/internal/reportdispatch"
	"golang.org/x/sys/windows"
)

func powerShellArgs(script string, args []string) []string {
	return append([]string{"-NoLogo", "-NoProfile", "-File", script}, args...)
}

func packageRoot() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	// WinGet's portable command alias can be a symlink outside the package.
	target, err := filepath.EvalSymlinks(executable)
	if err != nil {
		return "", err
	}
	return filepath.Dir(target), nil
}

func launch(args []string) error {
	root, err := packageRoot()
	if err != nil {
		return err
	}
	systemDir, err := windows.GetSystemDirectory()
	if err != nil {
		return err
	}
	powershell := filepath.Join(systemDir, "WindowsPowerShell", "v1.0", "powershell.exe")
	script := filepath.Join(root, "winmole.ps1")
	if info, err := os.Stat(script); err != nil || !info.Mode().IsRegular() {
		return fmt.Errorf("the WinMole script is missing or invalid: %s", script)
	}
	// Leave the working directory and execution policy untouched.
	cmd := exec.Command(powershell, powerShellArgs(script, args)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

func main() {
	args := os.Args[1:]
	if handled, err := writeMetadata(os.Stdout, args); handled {
		if err != nil {
			fmt.Fprintln(os.Stderr, "WinMole:", err)
			os.Exit(1)
		}
		return
	}
	if request, ok := reportdispatch.Parse(args); ok {
		if err := runNativeReport(request); err != nil {
			fmt.Fprintln(os.Stderr, "An error occurred:", err)
			os.Exit(1)
		}
		return
	}
	if err := launch(args); err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			os.Exit(exit.ExitCode())
		}
		fmt.Fprintln(os.Stderr, "WinMole:", err)
		os.Exit(1)
	}
}
