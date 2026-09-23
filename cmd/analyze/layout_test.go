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
