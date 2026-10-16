//go:build windows

package main

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func assertViewFits(t *testing.T, m model) string {
	t.Helper()
	view := ansi.Strip(m.View())
	if !utf8.ValidString(view) {
		t.Fatal("view contains invalid UTF-8")
	}
	lines := strings.Split(view, "\n")
	if len(lines) > m.height {
		t.Fatalf("view has %d rows in %dx%d terminal:\n%s", len(lines), m.width, m.height, view)
	}
	for _, line := range lines {
		if ansi.StringWidth(line) > m.width {
			t.Fatalf("line exceeds %d columns: %q", m.width, line)
		}
	}
	return view
}

func TestAnalyzerPartialReasonStatus(t *testing.T) {
	for _, tc := range []struct {
		name     string
		reasons  partialReasons
		partial  bool
		selected int
		scanning bool
		want     string
	}{
		{name: "timeout", reasons: partialTimeout, partial: true, want: "Partial: timeout"},
		{name: "file limit", reasons: partialFileLimit, partial: true, want: "Partial: file limit"},
		{name: "read error", reasons: partialReadError, partial: true, want: "Partial: read error"},
		{name: "combined", reasons: partialTimeout | partialFileLimit | partialReadError, partial: true, want: "Partial: timeout, file limit, read error"},
		{name: "legacy", partial: true, want: "Partial: scan incomplete"},
		{name: "complete"},
		{name: "scanning", reasons: partialTimeout, partial: true, scanning: true},
		{name: "negative selection", partial: true, selected: -1},
		{name: "past last selection", partial: true, selected: 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := newModel("fixture")
			m.width, m.height = 40, 9
			m.scanning, m.selected = tc.scanning, tc.selected
			m.entries = []dirEntry{{Name: "entry", Partial: tc.partial, PartialReasons: tc.reasons}}
			view := assertViewFits(t, m)
			if tc.want == "" {
				if strings.Contains(view, "Partial:") {
					t.Fatalf("unexpected partial status:\n%s", view)
				}
			} else if !strings.Contains(view, "\n"+tc.want+"\n") {
				t.Fatalf("missing status %q:\n%s", tc.want, view)
			}
			m.entries = nil
			if strings.Contains(assertViewFits(t, m), "Partial:") {
				t.Fatal("empty listing retained partial status")
			}
		})
	}
}

func TestAnalyzerPartialReasonFollowsSelection(t *testing.T) {
	m := newModel("fixture")
	m.width, m.height, m.scanning = 40, 9, false
	m.entries = []dirEntry{
		{Name: "zeta", Path: "zeta", Partial: true, PartialReasons: partialTimeout},
		{Name: "alpha", Path: "alpha", Partial: true, PartialReasons: partialReadError},
		{Name: "complete", Path: "complete"},
	}
	for _, step := range []struct {
		key, want string
	}{
		{"j", "read error"},
		{"s", "read error"},
		{"/", "read error"},
		{"zeta", "timeout"},
		{"enter", "timeout"},
		{"k", ""},
	} {
		m = searchKey(t, m, navigationKey(step.key))
		view := assertViewFits(t, m)
		if step.want == "" {
			if strings.Contains(view, "Partial:") {
				t.Fatal("complete selection retained partial status")
			}
		} else if !strings.Contains(view, "\nPartial: "+step.want+"\n") {
			t.Fatalf("key %q did not display selected reason %q:\n%s", step.key, step.want, view)
		}
	}
}

func TestAnalyzerPartialReasonPreservesPageSize(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 40, Height: 9}, {Width: 60, Height: 15}, {Width: 80, Height: 24}} {
		for _, panel := range []bool{false, true} {
			for _, withError := range []bool{false, true} {
				m := newModel("fixture")
				m.width, m.height, m.scanning = size.Width, size.Height, false
				m.showLargeFiles = panel
				if withError {
					m.err = errors.New(strings.Repeat("operation failed ", 30))
				}
				for i := 0; i < 40; i++ {
					m.entries = append(m.entries, dirEntry{Name: fmt.Sprintf("entry-%02d", i), Size: 1})
					m.largeFiles = append(m.largeFiles, fileEntry{Path: "large.bin", Size: 128 * 1024 * 1024})
				}
				m.totalSize = 40
				page := strings.Count(assertViewFits(t, m), "entry-")
				for i := range m.entries {
					m.entries[i].Partial = true
					m.entries[i].PartialReasons = partialTimeout | partialFileLimit | partialReadError
				}
				view := assertViewFits(t, m)
				if strings.Count(view, "entry-") != page || !strings.Contains(view, "Partial: timeout, file limit, read error") {
					t.Fatalf("partial status changed page size or was hidden:\n%s", view)
				}
				m = searchKey(t, m, navigationKey("pgdown"))
				if m.selected != page || !strings.Contains(assertViewFits(t, m), m.entries[m.selected].Name) {
					t.Fatal("partial status changed paging or hid selection")
				}
			}
		}
	}
}

func TestAnalyzerLayoutNavigationAndResize(t *testing.T) {
	m := newModel(`C:\` + strings.Repeat("long-path\\", 20))
	m.scanning = false
	for i := 0; i < 40; i++ {
		name := strings.Repeat("界e\u0301👩‍💻", 15) + fmt.Sprintf("-%02d.bin", i)
		m.entries = append(m.entries, dirEntry{Name: name, Path: name, Size: 128 * 1024 * 1024, Partial: true})
		m.largeFiles = append(m.largeFiles, fileEntry{Path: name, Size: 128 * 1024 * 1024})
		m.totalSize += 128 * 1024 * 1024
	}
	for _, files := range []bool{false, true} {
		m.showLargeFiles = files
		for _, size := range []tea.WindowSizeMsg{{Width: 60, Height: 15}, {Width: 80, Height: 24}, {Width: 40, Height: 10}, {Width: 120, Height: 40}} {
			updated, _ := m.Update(size)
			m = updated.(model)
			for _, key := range []string{"g", strings.Repeat("j", 39), strings.Repeat("k", 39), "G"} {
				for _, press := range key {
					updated, _ = m.Update(navigationKey(string(press)))
					m = updated.(model)
					view := assertViewFits(t, m)
					selected := ""
					for _, line := range strings.Split(view, "\n") {
						if strings.HasPrefix(line, iconArrow) {
							selected = line
						}
					}
					if !strings.Contains(selected, fmt.Sprintf("-%02d.bin", m.selected)) || !strings.Contains(selected, "128.0 MB+") {
						t.Fatalf("selected row or partial size hidden: %q", selected)
					}
					for _, control := range []string{"q quit", "d delete", "r refresh", "f files"} {
						if !strings.Contains(view, control) {
							t.Fatalf("missing control %q", control)
						}
					}
					if files && size.Height >= 15 && (!strings.Contains(view, "Large Files") || !strings.Contains(view, "... and ")) {
						t.Fatal("large-file panel or remaining count hidden")
					}
				}
			}
		}
	}
}

func TestAnalyzerLayoutStates(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 40, Height: 9}, {Width: 60, Height: 15}, {Width: 80, Height: 24}} {
		m := newModel(`C:\` + strings.Repeat("界", 100))
		m.width, m.height = size.Width, size.Height
		m.scanProgress, m.scanTotal = 123, 456
		view := assertViewFits(t, m)
		if !strings.Contains(view, "123 / 456") || !strings.Contains(view, "q quit") {
			t.Fatal("scan progress or quit hidden")
		}
		m.scanning = false
		m.err = errors.New(strings.Repeat("access denied ", 100))
		view = assertViewFits(t, m)
		if !strings.Contains(view, "Error:") || !strings.Contains(view, "r refresh") {
			t.Fatal("error or retry hidden")
		}
		m.entries = []dirEntry{{Name: "retained.bin", Size: 512, Partial: true}}
		m.largeFiles = []fileEntry{{Path: "large.bin", Size: 128 * 1024 * 1024}}
		m.showLargeFiles = true
		view = assertViewFits(t, m)
		if !strings.Contains(view, "retained.bin") || !strings.Contains(view, "+ = partial") {
			t.Fatal("operation error hid retained entry or partial legend")
		}
	}
	m := newModel("fixture")
	m.scanning = false
	for _, size := range []tea.WindowSizeMsg{{Width: 1, Height: 1}, {Width: 20, Height: 3}, {Width: 80, Height: 24}} {
		updated, _ := m.Update(size)
		m = updated.(model)
		view := assertViewFits(t, m)
		if size.Width == 80 && !strings.Contains(view, "WinMole Disk Analyzer") {
			t.Fatal("view did not recover after growth")
		}
	}
}

func TestAnalyzerConfirmationRequiresVisibleTarget(t *testing.T) {
	m := newModel("fixture")
	m.scanning, m.deleteConfirm = false, true
	m.width, m.height = 60, 15
	m.deleteTarget = `C:\` + strings.Repeat("long directory\\", 20) + "target.bin"
	view := assertViewFits(t, m)
	if !strings.Contains(strings.ReplaceAll(view, "\n", ""), m.deleteTarget) || !strings.Contains(view, "y/n") {
		t.Fatal("confirmation truncated the target or controls")
	}
	m.height = 4
	view = assertViewFits(t, m)
	if !strings.Contains(strings.ToLower(view), "resize") {
		t.Fatal("small confirmation lacks resize instruction")
	}
	updated, command := m.Update(navigationKey("y"))
	if command != nil || !updated.(model).deleteConfirm {
		t.Fatal("invisible target could be confirmed")
	}
	m.height = 15
	updated, command = m.Update(navigationKey("y"))
	if command == nil || updated.(model).deleteConfirm {
		t.Fatal("visible target could not be confirmed")
	}
	// Never execute a deletion command in layout tests.
	m.height = 4
	updated, command = m.Update(navigationKey("n"))
	if command != nil || updated.(model).deleteConfirm {
		t.Fatal("small confirmation could not be cancelled")
	}
	m.width, m.height = 40, 9
	m.deleteTarget = "2 items"
	m.deleteTargets = []string{
		`C:\fixture\` + strings.Repeat("long folder\\", 20) + "two.bin",
		`C:\fixture\` + strings.Repeat("long folder\\", 20) + "one.bin",
	}
	view = assertViewFits(t, m)
	if !strings.Contains(view, "Resize") {
		t.Fatal("multi-delete confirmation hid actual target paths")
	}
	updated, command = m.Update(navigationKey("y"))
	if command != nil || !updated.(model).deleteConfirm {
		t.Fatal("invisible multi-delete targets could be confirmed")
	}
	updated, command = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if command != nil || updated.(model).deleteConfirm {
		t.Fatal("small multi-delete confirmation could not be cancelled")
	}
	m.height = 24
	view = assertViewFits(t, m)
	if !strings.Contains(view, "2 items") || !strings.Contains(view, "y/n") {
		t.Fatal("multi-delete confirmation lost its count or controls")
	}
	for _, path := range m.deleteTargets {
		if !strings.Contains(strings.ReplaceAll(view, "\n", ""), path) {
			t.Fatal("multi-delete confirmation truncated a target")
		}
	}
	if !strings.HasSuffix(m.deleteTargets[0], "two.bin") {
		t.Fatal("rendering changed the actual deletion target order")
	}
	updated, command = m.Update(navigationKey("y"))
	if command == nil || updated.(model).deleteConfirm || len(updated.(model).deleteTargets) != 0 {
		t.Fatal("multi-delete confirmation did not schedule the existing delete command")
	}
}
