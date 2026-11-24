//go:build windows

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func pressSpace(m model) model {
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeySpace})
	return next.(model)
}

func TestConfirmedDeletionChecksDryRunAtExecution(t *testing.T) {
	for _, test := range []struct {
		name  string
		batch bool
	}{
		{name: "single"},
		{name: "batch", batch: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("WINMOLE_DRY_RUN", "")
			root := t.TempDir()
			dir := filepath.Join(root, "project")
			file := filepath.Join(root, "ordinary.txt")
			child := filepath.Join(dir, "nested", "keep.txt")
			payload := []byte("preserve fixture contents")
			if err := os.MkdirAll(filepath.Dir(child), 0700); err != nil {
				t.Fatal(err)
			}
			for _, path := range []string{child, file} {
				if err := os.WriteFile(path, payload, 0600); err != nil {
					t.Fatal(err)
				}
			}

			m := newModel(root)
			m.scanning = false
			m.entries = []dirEntry{
				{Name: "project", Path: dir, IsDir: true},
				{Name: "ordinary.txt", Path: file},
			}
			updated, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: 35})
			m = updated.(model)
			key := func(key string) tea.Cmd {
				next, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(key)})
				m = next.(model)
				return cmd
			}
			if test.batch {
				m = pressSpace(m)
				key("j")
				m = pressSpace(m)
				key("D")
				if len(m.deleteTargets) != 2 {
					t.Fatalf("expected two batch targets, got %v", m.deleteTargets)
				}
			} else {
				key("d")
				if m.deleteTarget != dir {
					t.Fatalf("expected project as single target, got %q", m.deleteTarget)
				}
			}
			if !m.deleteConfirm {
				t.Fatal("expected confirmation")
			}
			cmd := key("y")
			if cmd == nil {
				t.Fatal("confirmation did not queue a deletion command")
			}

			// The command is already queued. The filesystem mutation must still
			// be refused if dry-run is enabled before the command executes.
			t.Setenv("WINMOLE_DRY_RUN", "1")
			updated, followup := m.Update(cmd())
			m = updated.(model)
			if m.err == nil || !strings.Contains(m.err.Error(), "WINMOLE_DRY_RUN=1") ||
				m.deleteConfirm || m.scanning || followup != nil {
				t.Fatalf("expected refusal without rescan, got state error %v", m.err)
			}
			for _, path := range []string{child, file} {
				data, err := os.ReadFile(path)
				if err != nil || !bytes.Equal(data, payload) {
					t.Fatalf("dry-run changed %s: %v", path, err)
				}
			}
		})
	}
}
