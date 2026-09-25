//go:build windows

package main

import (
	"fmt"
	"strings"
	"testing"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func TestDashboardFitsTerminalAndScrolls(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 60, Height: 15}, {Width: 80, Height: 24}} {
		t.Run(fmt.Sprintf("%dx%d", size.Width, size.Height), func(t *testing.T) {
			m := newModel()
			updated, _ := m.Update(metricsMsg(MetricsSnapshot{
				HealthMessage: strings.Repeat("Missing metrics: 界👩‍💻 e\u0301 ", 20) + "warning-tail",
				Networks:      []NetworkInfo{{Name: "last-network", BytesRecv: 1024}},
			}))
			updated, _ = updated.Update(size)
			check := func(view string) {
				t.Helper()
				lines := strings.Split(view, "\n")
				if len(lines) > size.Height || !utf8.ValidString(view) {
					t.Fatalf("view has %d rows; terminal has %d", len(lines), size.Height)
				}
				for _, line := range lines {
					if ansi.StringWidth(line) > size.Width {
						t.Fatalf("line exceeds %d columns: %q", size.Width, line)
					}
				}
				for _, control := range []string{"q", "quit", "scroll", "PgUp/PgDn", "Home/End", "refresh", "sort"} {
					if !strings.Contains(strings.Join(lines[len(lines)-2:], "\n"), control) {
						t.Errorf("footer missing %q", control)
					}
				}
			}
			check(updated.View())
			var seen strings.Builder
			for i := 0; i < 150; i++ {
				seen.WriteString(ansi.Strip(updated.View()))
				updated, _ = updated.Update(tea.KeyMsg{Type: tea.KeyDown})
				check(updated.View())
			}
			for _, metric := range []string{"warning-tail", "System", "CPU", "Memory", "Disks", "last-network"} {
				if !strings.Contains(seen.String(), metric) {
					t.Errorf("scrolling never exposed %q", metric)
				}
			}
		})
	}
}

func TestDashboardNavigationRefreshAndResize(t *testing.T) {
	m := newModel()
	for _, msg := range []tea.Msg{
		metricsMsg(MetricsSnapshot{
			HealthMessage: strings.Repeat("Long warning ", 100),
			Processes: []ProcessInfo{
				{PID: 1, Name: "cpu-process", CPU: 80, Memory: 1},
				{PID: 2, Name: "memory-process", CPU: 1, Memory: 80},
			},
		}),
		tea.WindowSizeMsg{Width: 60, Height: 15},
	} {
		updated, _ := m.Update(msg)
		m = updated.(model)
	}
	key := func(msg tea.KeyMsg) tea.Cmd {
		t.Helper()
		updated, cmd := m.Update(msg)
		m = updated.(model)
		return cmd
	}
	key(tea.KeyMsg{Type: tea.KeyPgDown})
	if m.scroll != 13 {
		t.Fatalf("page down offset = %d, want 13 visible content rows", m.scroll)
	}
	key(tea.KeyMsg{Type: tea.KeyPgUp})
	key(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'j'}})
	if m.scroll != 1 {
		t.Fatal("j should move down one row after page up")
	}
	key(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'k'}})
	key(tea.KeyMsg{Type: tea.KeyUp})
	if m.scroll != 0 {
		t.Fatal("up/k must clamp at the first row")
	}
	key(tea.KeyMsg{Type: tea.KeyEnd})
	bottom := m.View()
	key(tea.KeyMsg{Type: tea.KeyDown})
	if bottom != m.View() || !strings.Contains(bottom, "cpu-process") {
		t.Fatal("end/down must stop at the final content rows")
	}
	key(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'m'}})
	if !strings.Contains(m.View(), "Top Processes by Memory") || m.metrics.Processes[0].PID != 2 {
		t.Fatal("sorting must still work while scrolled")
	}
	if cmd := key(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'r'}}); cmd == nil || !m.collecting {
		t.Fatal("refresh must still request metrics while scrolled")
	}
	updated, _ := m.Update(metricsMsg(MetricsSnapshot{Networks: []NetworkInfo{{Name: "refreshed-network"}}}))
	m = updated.(model)
	if !strings.Contains(m.View(), "refreshed-network") || m.collecting || !m.sortByMemory {
		t.Fatal("shorter refreshed content must clamp scroll and preserve sort mode")
	}
	updated, _ = m.Update(tea.WindowSizeMsg{Width: 100, Height: 100})
	m = updated.(model)
	if m.scroll != 0 || !strings.Contains(m.View(), "WinMole System Status") {
		t.Fatal("growing the terminal must clamp scroll to the first row")
	}
	updated, _ = m.Update(tea.WindowSizeMsg{Width: 60, Height: 15})
	m = updated.(model)
	key(tea.KeyMsg{Type: tea.KeyEnd})
	key(tea.KeyMsg{Type: tea.KeyHome})
	if m.scroll != 0 || !strings.Contains(m.View(), "WinMole System Status") {
		t.Fatal("home must restore the header")
	}
	for _, msg := range []tea.KeyMsg{{Type: tea.KeyRunes, Runes: []rune{'q'}}, {Type: tea.KeyCtrlC}} {
		cmd := key(msg)
		if cmd == nil {
			t.Fatalf("%s did not request quit", msg.String())
		}
		if _, ok := cmd().(tea.QuitMsg); !ok {
			t.Fatalf("%s did not return a quit message", msg.String())
		}
	}
}

func TestDashboardTinyAndLoadingDimensions(t *testing.T) {
	for _, ready := range []bool{false, true} {
		for _, size := range []tea.WindowSizeMsg{
			{Width: 0, Height: 0}, {Width: -1, Height: -1},
			{Width: 1, Height: 1}, {Width: 2, Height: 2},
			{Width: 3, Height: 3}, {Width: 10, Height: 15},
			{Width: 18, Height: 24}, {Width: 60, Height: 1},
			{Width: 80, Height: 2},
			{Width: 41, Height: 15}, {Width: 42, Height: 15},
			{Width: 43, Height: 15}, {Width: 44, Height: 15},
			{Width: 45, Height: 15},
		} {
			m := newModel()
			m.ready = ready
			m.metrics.HealthMessage = strings.Repeat("界👩‍💻e\u0301", 20)
			updated, _ := m.Update(size)
			for _, msg := range []tea.KeyMsg{{Type: tea.KeyHome}, {Type: tea.KeyDown}, {Type: tea.KeyEnd}} {
				updated, _ = updated.Update(msg)
				view := updated.View()
				if size.Width <= 0 || size.Height <= 0 {
					if view != "" {
						t.Fatalf("nonpositive dimensions rendered %q", view)
					}
					continue
				}
				lines := strings.Split(view, "\n")
				if len(lines) > size.Height || !utf8.ValidString(view) {
					t.Fatalf("%+v: invalid view dimensions or UTF-8: %q", size, view)
				}
				for _, line := range lines {
					if ansi.StringWidth(line) > size.Width {
						t.Fatalf("%+v: line overflows: %q", size, line)
					}
				}
			}
		}
	}
}

func TestDashboardWrappedANSIStylesSurviveScrolling(t *testing.T) {
	m := newModel()
	m.ready = true
	m.metrics.HealthMessage = "\x1b[31m" + strings.Repeat("red-warning ", 30) + "\x1b[0m"
	updated, _ := m.Update(tea.WindowSizeMsg{Width: 60, Height: 15})
	for i := 0; i < 4; i++ {
		updated, _ = updated.Update(tea.KeyMsg{Type: tea.KeyDown})
	}
	first := strings.Split(updated.View(), "\n")[0]
	if !strings.Contains(first, "red-warning") || !strings.Contains(first, "\x1b[31m") || !strings.Contains(first, "\x1b[m") && !strings.Contains(first, "\x1b[0m") {
		t.Fatalf("scrolled warning lost its color or reset: %q", first)
	}
}
