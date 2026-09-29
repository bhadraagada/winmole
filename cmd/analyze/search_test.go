//go:build windows

package main

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func searchKey(t *testing.T, m model, key tea.KeyMsg) model {
	t.Helper()
	updated, command := m.Update(key)
	if command != nil {
		t.Fatalf("search key %q scheduled a command", key.String())
	}
	return updated.(model)
}

func TestAnalyzerSearchNavigation(t *testing.T) {
	m := newModel("fixture")
	m.scanning = false
	m.entries = []dirEntry{
		{Name: "Äpfel-one", Path: "one", Size: 40},
		{Name: "other", Path: "other", Size: 30},
		{Name: "ÄPFEL-two", Path: "two", Size: 20},
		{Name: "last", Path: "last", Size: 10},
	}
	m.selected = 1
	m.totalSize = 100
	m.multiSelected["one"] = true
	entries := append([]dirEntry(nil), m.entries...)
	for _, exit := range []tea.KeyType{tea.KeyEsc, tea.KeyEnter} {
		m.selected = 1
		m = searchKey(t, m, navigationKey("/"))
		if !m.searching || m.searchQuery != "" || m.selected != 1 {
			t.Fatal("opening search changed the selection or reused an old query")
		}
		m = searchKey(t, m, navigationKey("äpfel"))
		if m.selected != 2 {
			t.Fatal("search did not find the case-insensitive Unicode substring")
		}
		for _, step := range []struct {
			key  tea.KeyType
			want int
		}{{tea.KeyDown, 0}, {tea.KeyUp, 2}, {tea.KeyUp, 0}} {
			m = searchKey(t, m, tea.KeyMsg{Type: step.key})
			if m.selected != step.want {
				t.Fatalf("match navigation selected %d, want %d", m.selected, step.want)
			}
		}
		m = searchKey(t, m, tea.KeyMsg{Type: exit})
		want := 0
		if exit == tea.KeyEsc {
			want = 1
		}
		if m.searching || m.searchQuery != "" || m.selected != want {
			t.Fatalf("search exit failed: searching=%t query=%q selected=%d", m.searching, m.searchQuery, m.selected)
		}
		if !reflect.DeepEqual(m.entries, entries) || m.totalSize != 100 || !reflect.DeepEqual(m.multiSelected, map[string]bool{"one": true}) {
			t.Fatal("search changed listing order, total, or marked paths")
		}
	}
}

func TestAnalyzerSearchInputAndGuards(t *testing.T) {
	m := newModel("fixture")
	m = searchKey(t, m, navigationKey("/"))
	if m.searching {
		t.Fatal("search opened during a scan")
	}
	m.scanning, m.deleteConfirm = false, true
	m.deleteTarget = "fixture"
	m = searchKey(t, m, navigationKey("/"))
	if m.searching || !m.deleteConfirm {
		t.Fatal("search bypassed delete confirmation")
	}
	m.deleteConfirm = false
	m = searchKey(t, m, navigationKey("/"))
	for _, key := range []string{"q", "d", "D", "r", "s", "o", "f", "g", "G", "h", "j", "k", "l", "/", "space"} {
		m = searchKey(t, m, navigationKey(key))
	}
	if m.searchQuery != "qdDrsofgGhjkl/ " {
		t.Fatalf("shortcut keys did not become search text: %q", m.searchQuery)
	}
	if m.deleteConfirm || m.scanning || m.sortByName || m.showLargeFiles || len(m.history) != 0 || len(m.multiSelected) != 0 {
		t.Fatal("search input dispatched a normal shortcut")
	}
	m.searchQuery = ""
	m = searchKey(t, m, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("Äpfel 👩‍💻e\u0301\x1b\n\r\t\x7f\u202e"), Paste: true})
	if m.searchQuery != "Äpfel 👩‍💻e\u0301" {
		t.Fatalf("paste lost Unicode text or retained control characters: %q", m.searchQuery)
	}
	for _, want := range []string{"Äpfel 👩‍💻", "Äpfel "} {
		m = searchKey(t, m, tea.KeyMsg{Type: tea.KeyBackspace})
		if m.searchQuery != want {
			t.Fatalf("backspace split a displayed character: got %q, want %q", m.searchQuery, want)
		}
	}
	m = searchKey(t, m, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(strings.Repeat("界", 5000)), Paste: true})
	if len([]rune(m.searchQuery)) != 256 {
		t.Fatal("pasted query was not bounded")
	}
	_, command := m.Update(tea.KeyMsg{Type: tea.KeyCtrlC})
	if command == nil {
		t.Fatal("Ctrl+C did not quit search")
	}
	if _, ok := command().(tea.QuitMsg); !ok {
		t.Fatal("Ctrl+C returned a non-quit command")
	}
}

func TestAnalyzerSearchEmptyNoMatchAndLayout(t *testing.T) {
	m := newModel("fixture")
	m.scanning = false
	m.entries = []dirEntry{{Name: "other", Path: "other"}, {Name: "match", Path: "match"}}
	m = searchKey(t, m, navigationKey("/"))
	m = searchKey(t, m, navigationKey("match"))
	m = searchKey(t, m, navigationKey("x"))
	if m.selected != 1 || !strings.Contains(m.View(), "no matches") {
		t.Fatal("no-match query moved the previous selection or hid its status")
	}
	for range 6 {
		m = searchKey(t, m, tea.KeyMsg{Type: tea.KeyBackspace})
	}
	if m.selected != 0 || m.searchQuery != "" {
		t.Fatal("clearing search did not restore its starting selection")
	}
	m = searchKey(t, m, tea.KeyMsg{Type: tea.KeyUp})
	if m.selected != 0 {
		t.Fatal("empty query moved the selection")
	}
	for _, empty := range []bool{false, true} {
		if empty {
			m.entries = nil
		}
		for _, query := range []string{"", "match", strings.Repeat("界e\u0301👩‍💻", 100)} {
			m.searchQuery = query
			for _, size := range []tea.WindowSizeMsg{{Width: 40, Height: 9}, {Width: 60, Height: 15}, {Width: 80, Height: 24}} {
				m.width, m.height = size.Width, size.Height
				m.err = errors.New(strings.Repeat("access denied ", 100))
				m.showLargeFiles = true
				m.largeFiles = []fileEntry{{Path: "large.bin", Size: 128 * 1024 * 1024}}
				view := assertViewFits(t, m)
				if !strings.Contains(view, "↑↓ match") || !strings.Contains(view, "Enter accept") || !strings.Contains(view, "Esc cancel") {
					t.Fatal("search controls are hidden")
				}
			}
		}
		m = searchKey(t, m, tea.KeyMsg{Type: tea.KeyDown})
	}
	m.width, m.height = 39, 8
	if view := assertViewFits(t, m); !strings.Contains(view, "Ctrl+C quits") || strings.Contains(view, "q quits") {
		t.Fatal("small search viewport showed a text key as quit")
	}
}

func TestAnalyzerSearchEndsWhenPendingOperationReplacesListing(t *testing.T) {
	for _, result := range []tea.Msg{scanCompleteMsg{}, scanErrorMsg{err: errors.New("unreadable")}} {
		m := newModel("fixture")
		m.scanning = false
		m.entries = []dirEntry{{Name: "one"}, {Name: "two"}, {Name: "three"}}
		m.selected = 2
		// A prior delete can finish after the user has started a search.
		m = searchKey(t, m, navigationKey("/"))
		m = searchKey(t, m, navigationKey("two"))
		updated, command := m.Update(deleteCompleteMsg{})
		m = updated.(model)
		if command == nil || !m.scanning {
			t.Fatal("pending operation did not start its rescan")
		}
		// Supply the scan result directly; never execute the deletion or scan.
		updated, _ = m.Update(result)
		m = updated.(model)
		m = searchKey(t, m, tea.KeyMsg{Type: tea.KeyEsc})
		if m.searching || m.searchQuery != "" || m.selected != 0 {
			t.Fatal("replaced listing retained a search cursor from the old entries")
		}
		m.width, m.height = 40, 9
		assertViewFits(t, m)
	}
}

func TestAnalyzerSearchUnicodeSimpleFold(t *testing.T) {
	type foldCase struct {
		name, query string
		match       bool
	}
	cases := []foldCase{
		{"ΟΣ", "ος", true},
		{"ος", "ΟΣ", true},
		{"I", "ı", false},
		{"ı", "I", false},
		{"ß", "ss", false},
		{"ss", "ß", false},
	}
	for _, variants := range [][]string{{"Σ", "σ", "ς"}, {"K", "k", "K"}, {"S", "s", "ſ"}} {
		for _, name := range variants {
			for _, query := range variants {
				cases = append(cases, foldCase{name, query, true})
			}
		}
	}
	for _, tc := range cases {
		t.Run(tc.name+"/"+tc.query, func(t *testing.T) {
			m := newModel("fixture")
			m.scanning = false
			m.entries = []dirEntry{{Name: "000", Path: "000"}, {Name: "123" + tc.name + "456", Path: tc.name}}
			m = searchKey(t, m, navigationKey("/"))
			m = searchKey(t, m, navigationKey(tc.query))
			if (m.selected == 1) != tc.match {
				t.Errorf("search selected=%d for name=%q query=%q, want match=%t", m.selected, tc.name, tc.query, tc.match)
			}
			// Test the status with the candidate selected, even when it is not a match.
			m.selected = 1
			if strings.Contains(m.View(), "no matches") == tc.match {
				t.Errorf("search status disagrees for name=%q query=%q, want match=%t", tc.name, tc.query, tc.match)
			}
		})
	}
}
