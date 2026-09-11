//go:build windows

package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestProcessSortingToggle(t *testing.T) {
	processes := []ProcessInfo{
		{PID: 6, Name: "memory-heavy", CPU: 0, Memory: 80},
		{PID: 5, Name: "cpu-fifth", CPU: 1, Memory: 1},
		{PID: 4, Name: "cpu-fourth", CPU: 2, Memory: 1},
		{PID: 3, Name: "cpu-third", CPU: 3, Memory: 1},
		{PID: 2, Name: "cpu-second", CPU: 4, Memory: 1},
		{PID: 1, Name: "cpu-first", CPU: 5, Memory: 1},
	}
	m := newModel()
	updated, cmd := m.Update(metricsMsg(MetricsSnapshot{Processes: processes}))
	m = updated.(model)
	if cmd != nil || m.sortByMemory || len(m.metrics.Processes) != 6 {
		t.Fatal("CPU mode should retain every process without scheduling another collection")
	}
	view := m.View()
	if !strings.Contains(view, "Top Processes by CPU") || !strings.Contains(view, "cpu-fifth") || strings.Contains(view, "memory-heavy") {
		t.Fatalf("default view should show the five busiest CPU processes: %s", view)
	}
	if strings.Index(view, "cpu-first") > strings.Index(view, "cpu-second") {
		t.Fatal("CPU processes must appear in descending usage order")
	}

	updated, cmd = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'m'}})
	m = updated.(model)
	view = m.View()
	if cmd != nil || !m.sortByMemory || !strings.Contains(view, "Top Processes by Memory") || !strings.Contains(view, "memory-heavy") || strings.Contains(view, "cpu-fifth") {
		t.Fatalf("memory toggle should immediately reveal the RAM-heavy process without collecting: %s", view)
	}
	if m.metrics.Processes[0].PID != 6 || m.metrics.Processes[1].PID != 1 {
		t.Fatal("memory sorting must rank by usage, then PID for ties")
	}

	// A refreshed snapshot must preserve the user's chosen ordering.
	updated, _ = m.Update(metricsMsg(MetricsSnapshot{Processes: []ProcessInfo{
		{PID: 1, Name: "cpu-first", CPU: 90, Memory: 1},
		{PID: 6, Name: "memory-heavy", Memory: 80},
	}}))
	m = updated.(model)
	if m.metrics.Processes[0].PID != 6 {
		t.Fatal("refresh reverted memory ordering")
	}
	updated, cmd = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'m'}})
	m = updated.(model)
	if cmd != nil || m.sortByMemory || m.metrics.Processes[0].PID != 1 {
		t.Fatal("second toggle should restore CPU ordering without collecting")
	}
}

func TestProcessSortingEmptyAndCPUTies(t *testing.T) {
	processes := []ProcessInfo{{PID: 20, CPU: 5}, {PID: 10, CPU: 5}}
	sortProcesses(processes, false)
	if processes[0].PID != 10 {
		t.Fatal("equal CPU usage should sort by PID")
	}
	m := newModel()
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'m'}})
	m = updated.(model)
	if cmd != nil || !m.sortByMemory {
		t.Fatal("sorting an empty/loading dashboard should toggle without collecting")
	}
	updated, _ = m.Update(metricsMsg(MetricsSnapshot{}))
	if strings.Contains(updated.View(), "Top Processes by") {
		t.Fatal("empty snapshots should not render a process list")
	}
}
