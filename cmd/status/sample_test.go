//go:build windows

package main

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestStatusSchedulesOnlyOneSample(t *testing.T) {
	m := newModel()
	update := func(msg tea.Msg) tea.Cmd {
		next, cmd := m.Update(msg)
		m = next.(model)
		return cmd
	}
	refresh := tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'r'}}
	pause := tea.KeyMsg{Type: tea.KeySpace}
	if !m.collecting {
		t.Fatal("startup must reserve the sample scheduled by Init")
	}
	if batch, ok := m.Init()().(tea.BatchMsg); !ok || len(batch) != 2 {
		t.Fatal("Init must schedule collection and its timer")
	}
	assertBusy := func() {
		t.Helper()
		for i := 0; i < 2; i++ {
			if cmd := update(refresh); cmd != nil {
				t.Fatal("refresh queued an overlapping sample")
			}
		}
		// Bubble Tea's Tick command delivers a tick, while Batch immediately
		// returns a BatchMsg. Evaluate only the scheduler command, never a sample.
		m.animFrame = 1
		cmd := update(tickMsg{})
		if cmd == nil {
			t.Fatal("busy tick stopped the timer")
		}
		if _, ok := cmd().(tickMsg); !ok {
			t.Fatal("busy due tick queued more than the timer")
		}
	}
	assertBusy()
	update(metricsMsg(MetricsSnapshot{Hostname: "first"}))
	if m.collecting || !m.ready || m.metrics.Hostname != "first" {
		t.Fatal("startup completion did not release the slot and update the display")
	}
	m.animFrame = 1
	cmd := update(tickMsg{})
	if cmd == nil || !m.collecting {
		t.Fatal("due tick did not reserve the next sample")
	}
	if batch, ok := cmd().(tea.BatchMsg); !ok || len(batch) != 2 {
		t.Fatal("due tick must schedule one sample and one timer")
	}
	assertBusy()
	update(pause)
	update(metricsMsg(MetricsSnapshot{Hostname: "pending"}))
	if m.collecting || m.metrics.Hostname != "first" || m.pending == nil || m.pending.Hostname != "pending" {
		t.Fatal("paused completion must release the slot without changing the display")
	}
	if cmd := update(refresh); cmd == nil || !m.collecting {
		t.Fatal("manual refresh must work again while paused")
	}
	assertBusy()
	if cmd := update(pause); cmd != nil || m.paused || !m.collecting || m.metrics.Hostname != "pending" || m.pending != nil {
		t.Fatal("resuming must apply the pending snapshot without rescheduling")
	}
	update(metricsMsg(MetricsSnapshot{Hostname: "live"}))
	if m.collecting || m.metrics.Hostname != "live" || update(refresh) == nil || !m.collecting {
		t.Fatal("completion must release the slot for the next refresh")
	}
}
