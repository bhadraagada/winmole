//go:build windows

package main

import (
	"errors"
	"path/filepath"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestRefreshInvalidatesNestedHistoryAndSiblingCache(t *testing.T) {
	for _, trigger := range []string{"refresh", "successful delete", "failed refresh"} {
		t.Run(trigger, func(t *testing.T) {
			root := t.TempDir()
			child := filepath.Join(root, "child")
			leaf := filepath.Join(child, "leaf")
			sibling := filepath.Join(root, "sibling")
			writeFile(t, filepath.Join(leaf, "file.bin"), 30)
			writeFile(t, filepath.Join(sibling, "file.bin"), 10)
			m := newModel(root)
			updated, _ := m.Update(m.Init()())
			m = updated.(model)
			visit := func(path string, wantScan bool) {
				t.Helper()
				found := false
				for i, entry := range m.entries {
					if entry.Path == path {
						m.selected = i
						found = true
					}
				}
				if !found {
					t.Fatalf("missing directory %s", path)
				}
				updated, command := m.Update(navigationKey("enter"))
				m = updated.(model)
				if (command != nil) != wantScan {
					t.Fatalf("enter %s scan=%t, want %t", path, command != nil, wantScan)
				}
				if command != nil {
					updated, _ = m.Update(command())
					m = updated.(model)
				}
			}
			back := func(path string, wantScan bool) {
				t.Helper()
				selectedPath := m.path
				updated, command := m.Update(navigationKey("backspace"))
				m = updated.(model)
				if m.path != path || (command != nil) != wantScan {
					t.Fatalf("back path=%s scan=%t, want %s scan=%t", m.path, command != nil, path, wantScan)
				}
				if command != nil {
					updated, _ = m.Update(command())
					m = updated.(model)
				}
				if m.entries[m.selected].Path != selectedPath {
					t.Fatalf("back lost highlighted directory %s", selectedPath)
				}
			}
			visit(sibling, true)
			back(root, false)
			visit(sibling, false)
			back(root, false)
			visit(child, true)
			visit(leaf, true)
			writeFile(t, filepath.Join(leaf, "file.bin"), 20)
			writeFile(t, filepath.Join(sibling, "file.bin"), 40)
			var message tea.Msg = navigationKey("r")
			if trigger == "successful delete" {
				// Deliver the completion only; never execute a deletion command.
				message = deleteCompleteMsg{path: filepath.Join(leaf, "removed.bin")}
			}
			updated, command := m.Update(message)
			m = updated.(model)
			if command == nil || !m.scanning {
				t.Fatal("refresh did not schedule a scan")
			}
			if trigger == "failed refresh" {
				updated, _ = m.Update(scanErrorMsg{err: errors.New("unavailable")})
			} else {
				updated, _ = m.Update(command())
			}
			m = updated.(model)
			back(child, true)
			if m.totalSize != 20 || m.err != nil {
				t.Fatalf("stale child total or error: %d, %v", m.totalSize, m.err)
			}
			back(root, true)
			if m.totalSize != 60 {
				t.Fatalf("stale root total %d, want 60", m.totalSize)
			}
			visit(sibling, true)
			if m.totalSize != 40 {
				t.Fatalf("stale sibling total %d, want 40", m.totalSize)
			}
		})
	}
}

func TestParentRefreshInvalidatesDescendantCache(t *testing.T) {
	root := t.TempDir()
	child := filepath.Join(root, "child")
	writeFile(t, filepath.Join(child, "old.bin"), 10)
	m := newModel(root)
	updated, _ := m.Update(m.Init()())
	m = updated.(model)
	updated, command := m.Update(navigationKey("enter"))
	m = updated.(model)
	updated, _ = m.Update(command())
	m = updated.(model)
	updated, _ = m.Update(navigationKey("backspace"))
	m = updated.(model)
	writeFile(t, filepath.Join(child, "new.bin"), 20)
	updated, command = m.Update(navigationKey("r"))
	m = updated.(model)
	updated, _ = m.Update(command())
	m = updated.(model)
	updated, command = m.Update(navigationKey("enter"))
	m = updated.(model)
	if command == nil || !m.scanning {
		t.Fatal("enter reused a child snapshot from before its parent refresh")
	}
	updated, _ = m.Update(command())
	m = updated.(model)
	if m.totalSize != 30 || len(m.entries) != 2 {
		t.Fatalf("stale child contents: total=%d entries=%v", m.totalSize, m.entries)
	}
}

func TestStaleHistorySelectionFallsBackAfterRemovalOrError(t *testing.T) {
	for _, failed := range []bool{false, true} {
		root := t.TempDir()
		child := filepath.Join(root, "child")
		m := newModel(child)
		m.scanning = false
		m.history = []historyEntry{{Path: root, Entries: []dirEntry{{Path: child, IsDir: true}}}}
		updated, command := m.Update(navigationKey("backspace"))
		m = updated.(model)
		if command == nil || !m.scanning {
			t.Fatal("stale history did not schedule a scan")
		}
		entries := []dirEntry{{Name: "other", Path: filepath.Join(root, "other"), Size: 20}}
		if failed {
			updated, _ = m.Update(scanErrorMsg{err: errors.New("unavailable")})
			m = updated.(model)
			updated, _ = m.Update(navigationKey("r"))
			m = updated.(model)
			entries = append(entries, dirEntry{Name: "child", Path: child, Size: 10, IsDir: true})
		}
		updated, _ = m.Update(scanCompleteMsg{entries: entries})
		m = updated.(model)
		if m.selected != 0 || m.err != nil {
			t.Fatalf("failed=%t: unavailable history highlight did not reset: selected=%d err=%v", failed, m.selected, m.err)
		}
	}
}
