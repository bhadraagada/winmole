//go:build windows

package main

import (
	"bytes"
	"slices"
	"strings"
	"testing"
)

func TestPowerShellArgs(t *testing.T) {
	const script = `C:\Package With Spaces\winmole.ps1`
	tests := []struct {
		name string
		in   []string
		want []string
	}{
		{name: "menu", in: nil, want: nil},
		{name: "help", in: []string{"--help"}, want: []string{"--help"}},
		{name: "version", in: []string{"--VeRsIoN"}, want: []string{"--VeRsIoN"}},
		{name: "subcommand help", in: []string{"analyze", "--help"}, want: []string{"analyze", "--help"}},
		{name: "space and shell punctuation", in: []string{"analyze", `C:\Folder & [fixture]`, "--json"}, want: []string{"analyze", `C:\Folder & [fixture]`, "--json"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := powerShellArgs(script, tc.in)
			want := append([]string{"-NoLogo", "-NoProfile", "-File", script}, tc.want...)
			if !slices.Equal(got, want) {
				t.Fatalf("powerShellArgs(%q) = %q, want %q", tc.in, got, want)
			}
		})
	}
}

func TestWriteMetadata(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
	}{
		{name: "help with no package lookup", args: []string{"--help"}, want: "Windows System Maintenance Toolkit"},
		{name: "version with no package lookup", args: []string{"--version"}, want: "WinMole v" + version},
		{name: "no arguments use legacy menu", args: nil},
		{name: "subcommand help is not top-level help", args: []string{"analyze", "--help"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			handled, err := writeMetadata(&out, tc.args)
			if err != nil || handled != (tc.want != "") || !strings.Contains(out.String(), tc.want) ||
				!handled && out.Len() != 0 {
				t.Fatalf("handled = %v, out = %q, err = %v", handled, out.String(), err)
			}
		})
	}
}
