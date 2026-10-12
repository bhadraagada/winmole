//go:build windows

package main

import (
	"fmt"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func TestPauseRetainsDisplayAndResumesLatestSnapshot(t *testing.T) {
	m := newModel()
	update := func(msg tea.Msg) tea.Cmd {
		t.Helper()
		updated, cmd := m.Update(msg)
		m = updated.(model)
		return cmd
	}
	update(metricsMsg(MetricsSnapshot{Hostname: "original", Processes: []ProcessInfo{
		{PID: 1, Name: "cpu", CPUAvailable: true, CPU: 80, MemoryAvailable: true, Memory: 1},
		{PID: 2, Name: "memory", CPUAvailable: true, CPU: 1, MemoryAvailable: true, Memory: 80},
	}}))
	if cmd := update(tea.KeyMsg{Type: tea.KeySpace}); cmd != nil {
		t.Fatal("pausing the display must not schedule collection")
	}
	if !strings.Contains(m.content(), "Display paused") {
		t.Fatal("paused display must identify the frozen readings")
	}
	if cmd := update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'r'}}); cmd == nil || !m.collecting {
		t.Fatal("manual collection must remain available while display is paused")
	}
	update(metricsMsg(MetricsSnapshot{Hostname: "intermediate"}))
	if m.metrics.Hostname != "original" || m.collecting {
		t.Fatal("in-flight result must finish collecting without replacing the frozen display")
	}
	update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'m'}})
	update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}})
	update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'p'}})
	if m.metrics.Processes[0].PID != 2 || !m.showAllProcs || !m.showPerCore {
		t.Fatal("sorting and display toggles must work on the frozen snapshot")
	}
	update(metricsMsg(MetricsSnapshot{Hostname: "latest", Processes: []ProcessInfo{
		{PID: 3, MemoryAvailable: true, Memory: 1},
		{PID: 4, MemoryAvailable: true, Memory: 90},
	}}))
	if m.metrics.Hostname != "original" {
		t.Fatal("later collections must not replace the frozen snapshot")
	}
	if cmd := update(tea.KeyMsg{Type: tea.KeySpace}); cmd != nil {
		t.Fatal("resuming must use the latest collected snapshot without collecting again")
	}
	if m.metrics.Hostname != "latest" || m.metrics.Processes[0].PID != 4 || !m.sortByMemory || !m.showAllProcs || !m.showPerCore {
		t.Fatal("resume must apply the latest result and current display choices")
	}
	if strings.Contains(m.View(), "paused") {
		t.Fatal("resume must clear the paused indication")
	}
	update(metricsMsg(MetricsSnapshot{Hostname: "live"}))
	if m.metrics.Hostname != "live" {
		t.Fatal("resumed display must continue applying new snapshots")
	}
	for i := 0; i < 4; i++ {
		update(tea.KeyMsg{Type: tea.KeySpace})
	}
	if m.metrics.Hostname != "live" || strings.Contains(m.View(), "paused") {
		t.Fatal("toggling without a new result must not restore an old pending snapshot")
	}
}

func TestPauseLoadingAndQuit(t *testing.T) {
	m := newModel()
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeySpace})
	if cmd != nil || !strings.Contains(updated.View(), "Loading") || strings.Contains(updated.View(), "paused") {
		t.Fatal("pause before the first snapshot must leave the loading display active")
	}
	updated, _ = updated.Update(metricsMsg(MetricsSnapshot{Hostname: "first"}))
	if updated.(model).metrics.Hostname != "first" || strings.Contains(updated.View(), "paused") {
		t.Fatal("space while loading must not prevent the first result appearing")
	}
	updated, _ = updated.Update(tea.KeyMsg{Type: tea.KeySpace})
	for _, key := range []tea.KeyMsg{{Type: tea.KeyCtrlC}, {Type: tea.KeyRunes, Runes: []rune{'q'}}} {
		_, cmd = updated.Update(key)
		if cmd == nil {
			t.Fatalf("%s must quit while paused", key.String())
		}
		if _, ok := cmd().(tea.QuitMsg); !ok {
			t.Fatalf("%s did not return a quit message", key.String())
		}
	}
}

func TestPauseKeepsScheduledSampling(t *testing.T) {
	m := newModel()
	updated, _ := m.Update(metricsMsg(MetricsSnapshot{Hostname: "frozen"}))
	updated, _ = updated.Update(tea.KeyMsg{Type: tea.KeySpace})
	m = updated.(model)
	m.animFrame = 1
	updated, cmd := m.Update(tickMsg{})
	if cmd == nil {
		t.Fatal("paused display must preserve the sampling timer")
	}
	if batch, ok := cmd().(tea.BatchMsg); !ok || len(batch) != 2 {
		t.Fatal("scheduled collection and timer must continue while display is paused")
	}
	if updated.(model).metrics.Hostname != "frozen" {
		t.Fatal("timer must not change frozen metrics")
	}
}

func TestPausedViewportAndResumeClamp(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 40, Height: 9}, {Width: 60, Height: 15}, {Width: 80, Height: 24}, {Width: 10, Height: 3}, {Width: 1, Height: 1}, {Width: 0, Height: 0}} {
		t.Run(fmt.Sprintf("%dx%d", size.Width, size.Height), func(t *testing.T) {
			processes := make([]ProcessInfo, 30)
			for i := range processes {
				processes[i] = ProcessInfo{PID: int32(i + 1), Name: fmt.Sprintf("process-%02d", i+1), CPUAvailable: true, CPU: float64(30 - i)}
			}
			var current tea.Model = newModel()
			for _, msg := range []tea.Msg{metricsMsg(MetricsSnapshot{Processes: processes}), size, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}}, tea.KeyMsg{Type: tea.KeySpace}, tea.KeyMsg{Type: tea.KeyEnd}, metricsMsg(MetricsSnapshot{Hostname: "shorter"})} {
				current, _ = current.Update(msg)
			}
			m := current.(model)
			view := ansi.Strip(m.View())
			if size.Width > 0 && size.Height > 0 {
				if len(strings.Split(view, "\n")) > size.Height {
					t.Fatal("paused view exceeds terminal height")
				}
				for _, line := range strings.Split(view, "\n") {
					if ansi.StringWidth(line) > size.Width {
						t.Fatal("paused view exceeds terminal width")
					}
				}
			} else if view != "" {
				t.Fatal("zero-sized terminal must remain empty")
			}
			if size.Width >= 40 {
				_, footer, _ := m.layout()
				controls := ansi.Strip(strings.Join(footer, "\n"))
				for _, text := range []string{"paused", "Space", "quit", "scroll"} {
					if !strings.Contains(controls, text) {
						t.Fatalf("scrolled paused footer lacks %q: %s", text, controls)
					}
				}
				if !strings.Contains(view, "process-30") || m.metrics.Hostname == "shorter" {
					t.Fatal("paused scrolling must retain the original process list")
				}
			}
			current, _ = current.Update(tea.KeyMsg{Type: tea.KeySpace})
			m = current.(model)
			lines, _, height := m.layout()
			if m.metrics.Hostname != "shorter" || m.scroll != max(0, len(lines)-height) {
				t.Fatal("resume must apply latest snapshot and clamp the old scroll position")
			}
		})
	}
}
