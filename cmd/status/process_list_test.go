//go:build windows

package main

import (
	"fmt"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func TestShowAllProcesses(t *testing.T) {
	processes := make([]ProcessInfo, 8)
	for i := range processes {
		processes[i] = ProcessInfo{PID: int32(i + 1), Name: fmt.Sprintf("process-%d", i+1), CPUAvailable: true, CPU: float64(8 - i), MemoryAvailable: true, Memory: float32(i + 1)}
	}
	m := newModel()
	updated, _ := m.Update(metricsMsg(MetricsSnapshot{Processes: processes}))
	m = updated.(model)
	if count := strings.Count(m.content(), "(CPU:"); count != 5 || strings.Contains(m.content(), "process-6") {
		t.Fatalf("default process list has %d rows, want only the first five", count)
	}
	key := func(r rune) {
		t.Helper()
		updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
		m = updated.(model)
		if cmd != nil || m.collecting {
			t.Fatalf("%c should change the displayed list without collecting", r)
		}
	}
	key('a')
	if count := strings.Count(m.content(), "(CPU:"); count != 8 || !strings.Contains(m.content(), "Active Processes by CPU") {
		t.Fatalf("expanded process list has %d rows, want all eight active readings", count)
	}
	key('m')
	if !strings.Contains(m.content(), "Active Processes by Memory") || m.metrics.Processes[0].PID != 8 || strings.Count(m.content(), "(CPU:") != 8 {
		t.Fatal("memory sorting must preserve the expanded process list")
	}
	updated, _ = m.Update(metricsMsg(MetricsSnapshot{Processes: append(processes, ProcessInfo{PID: 9, Name: "new-process", MemoryAvailable: true, Memory: 90})}))
	m = updated.(model)
	if strings.Count(m.content(), "(CPU:") != 9 || m.metrics.Processes[0].PID != 9 || !strings.Contains(m.content(), "Active Processes by Memory") {
		t.Fatal("refresh must preserve expansion and memory sorting, including new processes")
	}
	key('m')
	if m.metrics.Processes[0].PID != 1 || strings.Count(m.content(), "(CPU:") != 9 {
		t.Fatal("CPU sorting must preserve the expanded process list")
	}
	key('a')
	if strings.Count(m.content(), "(CPU:") != 5 || !strings.Contains(m.content(), "Top Processes by CPU") {
		t.Fatal("second toggle must restore the top five")
	}
}

func TestShowAllProcessesEmptyAndLoading(t *testing.T) {
	m := newModel()
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}})
	if cmd != nil || !strings.Contains(updated.View(), "Loading") {
		t.Fatal("toggle while loading must not collect or replace the loading message")
	}
	updated, _ = updated.Update(metricsMsg(MetricsSnapshot{}))
	if strings.Contains(updated.View(), "Processes by") {
		t.Fatal("empty snapshots should not render a process list")
	}
	updated, _ = updated.Update(metricsMsg(MetricsSnapshot{Processes: []ProcessInfo{{PID: 1, Name: "only-process", CPUAvailable: true, CPU: 1}}}))
	if !strings.Contains(updated.View(), "Active Processes by CPU") || strings.Count(updated.View(), "(CPU:") != 1 {
		t.Fatal("toggle while loading must persist when the first process arrives")
	}
}

func TestExpandedProcessViewport(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 40, Height: 9}, {Width: 60, Height: 15}, {Width: 80, Height: 24}} {
		t.Run(fmt.Sprintf("%dx%d", size.Width, size.Height), func(t *testing.T) {
			processes := make([]ProcessInfo, 30)
			for i := range processes {
				processes[i] = ProcessInfo{PID: int32(i + 1), Name: fmt.Sprintf("process-%02d", i+1), CPUAvailable: true, CPU: float64(30 - i)}
			}
			var m tea.Model = newModel()
			for _, msg := range []tea.Msg{metricsMsg(MetricsSnapshot{Processes: processes}), size, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}}, tea.KeyMsg{Type: tea.KeyEnd}} {
				m, _ = m.Update(msg)
			}
			view := ansi.Strip(m.View())
			if !strings.Contains(view, "process-30") {
				t.Fatal("end must reach the final expanded process")
			}
			for _, line := range strings.Split(view, "\n") {
				if ansi.StringWidth(line) > size.Width {
					t.Fatalf("expanded row exceeds %d columns: %q", size.Width, line)
				}
			}
			if len(strings.Split(view, "\n")) > size.Height || !strings.Contains(view, "quit") {
				t.Fatal("expanded view must fit the viewport and retain controls")
			}
			if size.Width >= 60 && !strings.Contains(view, "[a] all") {
				t.Fatal("full footer must expose the expansion shortcut")
			}
			m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}})
			collapsed := m.(model)
			lines, _, height := collapsed.layout()
			if collapsed.scroll != max(0, len(lines)-height) || !strings.Contains(collapsed.View(), "process-05") || strings.Contains(collapsed.View(), "process-30") {
				t.Fatal("collapsing at the bottom must clamp scrolling to the remaining five processes")
			}
		})
	}
}
