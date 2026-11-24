//go:build windows

package main

import (
	tea "github.com/charmbracelet/bubbletea"
	"testing"
)

// These tests exercise model messages only. They never confirm or execute deletion.
func selectionModel() model {
	m := newModel(`C:\synthetic-selection`)
	m.scanning = false
	m.entries = []dirEntry{{Name: "one", Path: `C:\synthetic-selection\one`}, {Name: "two", Path: `C:\synthetic-selection\two`}}
	return m
}

func TestSelectionNativeSpaceToggles(t *testing.T) {
	m := selectionModel()
	for _, want := range []bool{true, false} {
		updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeySpace})
		m = updated.(model)
		if cmd != nil || m.multiSelected[m.entries[0].Path] != want {
			t.Fatalf("Space selection = %v, want %v", m.multiSelected, want)
		}
	}
}

func TestSelectionRefreshClearsMarks(t *testing.T) {
	m := selectionModel()
	m.multiSelected[m.entries[0].Path] = true
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("r")})
	m = updated.(model)
	if len(m.multiSelected) != 0 {
		t.Fatal("refresh retained marks from the old listing")
	}
	updated, _ = m.Update(scanCompleteMsg{entries: []dirEntry{m.entries[1]}})
	m = updated.(model)
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("D")})
	if updated.(model).deleteConfirm || cmd != nil {
		t.Fatal("refresh allowed stale batch confirmation")
	}
}

func TestSelectionNewScanClearsMarks(t *testing.T) {
	m := selectionModel()
	m.multiSelected[m.entries[0].Path] = true
	updated, _ := m.Update(scanCompleteMsg{entries: m.entries})
	if len(updated.(model).multiSelected) != 0 {
		t.Fatal("scan completion retained marks, even for a path that could have been replaced")
	}
}

func TestSelectionBatchUsesOnlyVisibleMarkedEntries(t *testing.T) {
	m := selectionModel()
	m.multiSelected[m.entries[1].Path] = true
	m.multiSelected[`C:\synthetic-selection\gone`] = true
	m.multiSelected[m.entries[0].Path] = false
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("D")})
	m = updated.(model)
	if cmd != nil || !m.deleteConfirm || len(m.deleteTargets) != 1 || m.deleteTargets[0] != m.entries[1].Path {
		t.Fatalf("unexpected confirmation targets: %v", m.deleteTargets)
	}
	updated, cmd = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	m = updated.(model)
	if cmd != nil || m.deleteConfirm || len(m.deleteTargets) != 0 {
		t.Fatal("cancel left a pending deletion")
	}
}

func TestSelectionHiddenMarksCannotOpenConfirmation(t *testing.T) {
	m := selectionModel()
	m.multiSelected[`C:\synthetic-selection\gone`] = true
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("D")})
	if cmd != nil || updated.(model).deleteConfirm {
		t.Fatal("hidden mark opened deletion confirmation")
	}
}

func TestSelectionSpaceInSearchDoesNotMark(t *testing.T) {
	m := selectionModel()
	m.searching = true
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeySpace})
	m = updated.(model)
	if cmd != nil || len(m.multiSelected) != 0 || m.searchQuery != " " {
		t.Fatal("search Space was treated as a selection")
	}
}
