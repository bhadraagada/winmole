//go:build windows

package main

import (
	"errors"
	"path/filepath"
	"testing"
)

func TestIncompleteDeletionInvalidatesAllSnapshots(t *testing.T) {
	root := t.TempDir()
	for _, test := range []struct {
		name      string
		attempted bool
		scanError bool
	}{
		{name: "refused before any removal"},
		{name: "attempted partial removal", attempted: true},
		{name: "attempted partial removal with failed rescan", attempted: true, scanError: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			dir := filepath.Join(root, "project")
			m := newModel(dir)
			m.scanning = false
			m.cache[root] = historyEntry{TotalSize: 100}
			m.cache[dir] = historyEntry{TotalSize: 60}
			m.multiSelected[filepath.Join(dir, "stale.bin")] = true
			deleteErr := errors.New("not all fixtures were removed")
			// Deliver the outcome at the execution boundary; no deletion runs.
			next, cmd := m.Update(deleteCompleteMsg{path: dir, err: deleteErr, attempted: test.attempted})
			m = next.(model)
			if !test.attempted {
				if cmd != nil || m.scanning || len(m.cache) != 2 || !errors.Is(m.err, deleteErr) {
					t.Fatal("refusal without a filesystem attempt should preserve snapshots")
				}
				return
			}
			if cmd == nil || !m.scanning || len(m.cache) != 0 || len(m.multiSelected) != 0 {
				t.Fatal("partial deletion must mark every cached listing and selection stale")
			}
			if test.scanError {
				scanErr := errors.New("fixture scan failed")
				next, _ = m.Update(scanErrorMsg{err: scanErr})
				if !errors.Is(next.(model).err, scanErr) {
					t.Fatal("failed rescan lost the scan error")
				}
			} else {
				next, _ = m.Update(scanCompleteMsg{totalSize: 40})
				if next.(model).cache[dir].TotalSize != 40 {
					t.Fatal("new listing did not replace the old size")
				}
			}
			if !errors.Is(next.(model).err, deleteErr) {
				t.Fatal("rescan hid the incomplete-deletion error")
			}
		})
	}
}

func TestPendingDeletionBlocksNavigationUntilCompletion(t *testing.T) {
	root := t.TempDir()
	m := newModel(root)
	m.scanning = false
	m.entries = []dirEntry{{Name: "project", Path: filepath.Join(root, "project"), IsDir: true}}
	next, _ := m.Update(navigationKey("d"))
	next, deletion := next.(model).Update(navigationKey("y"))
	if deletion == nil || !next.(model).deletePending {
		t.Fatal("confirmation did not stage a deletion")
	}
	// The queued command is deliberately not run. A navigation keystroke
	// must not change paths or create an overlapping scan.
	for _, key := range []string{"enter", "r", "d", "y"} {
		updated, command := next.(model).Update(navigationKey(key))
		if command != nil || updated.(model).path != root || updated.(model).deleteConfirm {
			t.Fatalf("%q acted while a deletion was queued", key)
		}
		next = updated
	}
	next, command := next.(model).Update(deleteCompleteMsg{err: errors.New("refused")})
	if command != nil || next.(model).deletePending {
		t.Fatal("refused deletion left navigation blocked")
	}
	_, command = next.(model).Update(navigationKey("enter"))
	if command == nil {
		t.Fatal("navigation did not resume after refusal")
	}
}
