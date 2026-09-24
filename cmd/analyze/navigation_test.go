//go:build windows

package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func navigationKey(key string) tea.KeyMsg {
	switch key {
	case "backspace":
		return tea.KeyMsg{Type: tea.KeyBackspace}
	case "left":
		return tea.KeyMsg{Type: tea.KeyLeft}
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "ctrl+c":
		return tea.KeyMsg{Type: tea.KeyCtrlC}
	case "space":
		return tea.KeyMsg{Type: tea.KeySpace}
	case "pgup":
		return tea.KeyMsg{Type: tea.KeyPgUp}
	case "pgdown":
		return tea.KeyMsg{Type: tea.KeyPgDown}
	case "home":
		return tea.KeyMsg{Type: tea.KeyHome}
	case "end":
		return tea.KeyMsg{Type: tea.KeyEnd}
	}
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(key)}
}

func TestScanningOnlyAcceptsQuit(t *testing.T) {
	m := newModel(t.TempDir())
	m.entries = []dirEntry{{Name: "old", Path: filepath.Join(m.path, "old"), IsDir: true}}
	m.multiSelected[m.entries[0].Path] = true
	m.history = []historyEntry{{Path: filepath.Dir(m.path)}}
	for _, key := range []string{"backspace", "left", "h", "enter", "r", "g", "G", "j", "k", "space", "d", "D", "f", "pgup", "pgdown", "home", "end"} {
		t.Run(key, func(t *testing.T) {
			loading := m
			loading.multiSelected = map[string]bool{m.entries[0].Path: true}
			updated, command := loading.Update(navigationKey(key))
			if command != nil || !reflect.DeepEqual(updated.(model), m) {
				t.Fatalf("key %q changed state or scheduled work during a scan", key)
			}
		})
	}
	for _, key := range []string{"q", "ctrl+c"} {
		_, command := m.Update(navigationKey(key))
		if command == nil {
			t.Fatalf("key %q did not quit during a scan", key)
		}
		if _, ok := command().(tea.QuitMsg); !ok {
			t.Fatalf("key %q returned a non-quit command", key)
		}
	}
}

func TestParentNavigationScansParentAndRetainsHistory(t *testing.T) {
	root := t.TempDir()
	child := filepath.Join(root, "child")
	writeFile(t, filepath.Join(child, "inside.bin"), 17)
	writeFile(t, filepath.Join(root, "beside.bin"), 31)
	for _, key := range []string{"backspace", "left", "h"} {
		t.Run(key, func(t *testing.T) {
			m := newModel(child)
			updated, _ := m.Update(m.Init()())
			m = updated.(model)
			m.multiSelected[filepath.Join(child, "inside.bin")] = true
			updated, command := m.Update(navigationKey(key))
			m = updated.(model)
			if m.path != root || !m.scanning || command == nil || len(m.multiSelected) != 0 {
				t.Fatal("parent navigation did not start a clean parent scan")
			}
			updated, _ = m.Update(command())
			m = updated.(model)
			if m.scanning || m.totalSize != 48 || len(m.entries) != 2 {
				t.Fatalf("parent scan returned wrong contents: %+v", m.entries)
			}
			for i, entry := range m.entries {
				if entry.Path == child {
					m.selected = i
				}
			}
			parentSelection := m.selected
			m.err = errors.New("previous operation failed")
			updated, command = m.Update(navigationKey("enter"))
			m = updated.(model)
			if command != nil || m.path != child || m.totalSize != 17 || m.err != nil {
				t.Fatal("enter did not reuse the starting directory's cached scan")
			}
			updated, command = m.Update(navigationKey(key))
			m = updated.(model)
			if command != nil || m.path != root || m.selected != parentSelection || m.totalSize != 48 {
				t.Fatal("back did not restore the parent history and selection")
			}
		})
	}
}

func TestBackFromFailedChildRestoresCleanHistory(t *testing.T) {
	root := t.TempDir()
	child := filepath.Join(root, "child")
	writeFile(t, filepath.Join(child, "file.bin"), 19)
	m := newModel(root)
	updated, _ := m.Update(m.Init()())
	m = updated.(model)
	updated, command := m.Update(navigationKey("enter"))
	m = updated.(model)
	if m.path != child || !m.scanning || command == nil {
		t.Fatal("enter did not start the child scan")
	}
	updated, _ = m.Update(scanErrorMsg{err: errors.New("child unavailable")})
	m = updated.(model)
	updated, command = m.Update(navigationKey("backspace"))
	m = updated.(model)
	if m.path != root || m.err != nil || m.scanning || command != nil || m.totalSize != 19 || len(m.entries) != 1 {
		t.Fatal("back from a failed child scan did not restore clean parent history")
	}
}

func TestParentNavigationStopsAtVolumeRoot(t *testing.T) {
	root := filepath.VolumeName(t.TempDir()) + string(os.PathSeparator)
	m := newModel(root)
	m.scanning = false
	updated, command := m.Update(navigationKey("backspace"))
	if command != nil || updated.(model).path != root || updated.(model).scanning {
		t.Fatal("back at the volume root started another scan")
	}
}

func TestFailedScanClearsOldEntriesAndRefreshRecovers(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "file.bin"), 23)
	m := newModel(root)
	m.entries = []dirEntry{{Name: "stale"}}
	m.largeFiles = []fileEntry{{Name: "stale"}}
	m.totalSize = 999
	m.multiSelected["stale"] = true
	updated, _ := m.Update(scanErrorMsg{err: errors.New("scan failed")})
	m = updated.(model)
	if m.err == nil || m.scanning || len(m.entries) != 0 || len(m.largeFiles) != 0 || m.totalSize != 0 || len(m.multiSelected) != 0 {
		t.Fatal("failed scan kept stale entries actionable")
	}
	updated, command := m.Update(navigationKey("G"))
	m = updated.(model)
	if m.selected != 0 || command != nil {
		t.Fatal("jumping to the last entry in an empty listing changed selection")
	}
	updated, command = m.Update(navigationKey("r"))
	m = updated.(model)
	if command == nil || !m.scanning {
		t.Fatal("refresh did not retry the failed scan")
	}
	updated, _ = m.Update(command())
	m = updated.(model)
	if m.err != nil || m.scanning || m.totalSize != 23 || len(m.entries) != 1 {
		t.Fatal("successful retry did not replace the error with fresh entries")
	}
}

func TestAnalyzerPageNavigation(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 40, Height: 9}, {Width: 60, Height: 15}, {Width: 80, Height: 24}, {Width: 120, Height: 40}} {
		for _, panel := range []bool{false, true} {
			for _, withError := range []bool{false, true} {
				t.Run(fmt.Sprintf("%dx%d/panel=%t/error=%t", size.Width, size.Height, panel, withError), func(t *testing.T) {
					m := newModel("fixture")
					m.scanning = false
					m.width, m.height = size.Width, size.Height
					m.showLargeFiles = panel
					if withError {
						m.err = errors.New(strings.Repeat("unavailable ", 15))
					}
					for i := 0; i < 100; i++ {
						name := fmt.Sprintf("entry-%03d.bin", i)
						m.entries = append(m.entries, dirEntry{Name: name, Path: name, Size: 1})
						m.largeFiles = append(m.largeFiles, fileEntry{Path: "large.bin", Size: 200000000})
					}
					m.totalSize = 100
					for _, resized := range []tea.WindowSizeMsg{size, {Width: 80, Height: 24}, size} {
						updated, _ := m.Update(resized)
						m = updated.(model)
						m.selected = 0
						// Count actual rendered listing rows, independent of the layout calculation.
						page := strings.Count(assertViewFits(t, m), "entry-")
						if page < 1 {
							t.Fatal("no entry rows visible")
						}
						updated, command := m.Update(navigationKey("pgdown"))
						m = updated.(model)
						if command != nil || m.selected != page {
							t.Fatalf("page down selected %d, want %d", m.selected, page)
						}
						view := assertViewFits(t, m)
						if !strings.Contains(view, m.entries[m.selected].Name) {
							t.Fatal("page hid selected entry")
						}
						updated, command = m.Update(navigationKey("pgup"))
						m = updated.(model)
						if command != nil || m.selected != 0 {
							t.Fatal("page up did not return to first entry")
						}
						updated, _ = m.Update(navigationKey("end"))
						m = updated.(model)
						if m.selected != 99 {
							t.Fatal("End did not select last entry")
						}
						updated, _ = m.Update(navigationKey("pgdown"))
						m = updated.(model)
						if m.selected != 99 {
							t.Fatal("page down passed last entry")
						}
						updated, _ = m.Update(navigationKey("home"))
						m = updated.(model)
						updated, _ = m.Update(navigationKey("pgup"))
						m = updated.(model)
						if m.selected != 0 {
							t.Fatal("Home/page up passed first entry")
						}
					}
				})
			}
		}
	}
}

func TestAnalyzerPageNavigationEmptyAndConfirmation(t *testing.T) {
	for _, count := range []int{0, 1, 3} {
		m := newModel("fixture")
		m.scanning = false
		for i := 0; i < count; i++ {
			m.entries = append(m.entries, dirEntry{Name: fmt.Sprint(i)})
		}
		for _, key := range []string{"pgdown", "pgup", "end", "home"} {
			updated, command := m.Update(navigationKey(key))
			m = updated.(model)
			want := 0
			if key == "pgdown" || key == "end" {
				want = max(0, count-1)
			}
			if command != nil || m.selected != want {
				t.Fatalf("%s with %d entries selected %d, want %d", key, count, m.selected, want)
			}
		}
		m.deleteConfirm = true
		m.deleteTarget = "fixture/keep"
		for _, key := range []string{"pgdown", "pgup", "end", "home"} {
			updated, command := m.Update(navigationKey(key))
			if command != nil || !reflect.DeepEqual(updated.(model), m) {
				t.Fatalf("%s changed pending confirmation", key)
			}
		}
	}
}
