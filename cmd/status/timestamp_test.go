//go:build windows

package main

import (
	"fmt"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func TestSampleTimestampFormatting(t *testing.T) {
	for _, test := range []struct {
		name string
		when time.Time
		want string
	}{
		{"positive offset", time.Date(2026, 10, 13, 23, 59, 58, 0, time.FixedZone("local", 19800)), "2026-10-13 23:59:58 +0530"},
		{"negative offset", time.Date(2026, 10, 12, 1, 2, 3, 0, time.FixedZone("local", -25200)), "2026-10-12 01:02:03 -0700"},
		{"unavailable", time.Time{}, "Unavailable"},
	} {
		t.Run(test.name, func(t *testing.T) {
			m := newModel()
			if strings.Contains(m.View(), "Sample started:") {
				t.Fatal("loading must not claim a snapshot time")
			}
			updated, _ := m.Update(metricsMsg(MetricsSnapshot{CollectedAt: test.when}))
			view := ansi.Strip(updated.View())
			if !strings.Contains(view, "Sample started: "+test.want) || strings.Contains(view, "0001-") {
				t.Fatalf("unexpected sample timestamp: %s", view)
			}
		})
	}
}

func TestSampleTimestampFollowsDisplayedSnapshot(t *testing.T) {
	first := time.Date(2026, 10, 13, 23, 59, 59, 0, time.UTC)
	latest := first.Add(2 * time.Second)
	var current tea.Model = newModel()
	update := func(msg tea.Msg) {
		t.Helper()
		current, _ = current.Update(msg)
	}
	check := func(want time.Time) {
		t.Helper()
		view := ansi.Strip(current.View())
		if !strings.Contains(view, "Sample started: "+want.Format("2006-01-02 15:04:05 -0700")) {
			t.Fatalf("timestamp does not describe displayed snapshot: %s", view)
		}
	}
	update(metricsMsg(MetricsSnapshot{CollectedAt: first}))
	check(first)
	update(tea.KeyMsg{Type: tea.KeySpace})
	for _, msg := range []tea.Msg{
		tickMsg(first.Add(time.Second)),
		tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'r'}},
		metricsMsg(MetricsSnapshot{CollectedAt: first.Add(time.Second)}),
		metricsMsg(MetricsSnapshot{CollectedAt: latest}),
		tickMsg(latest.Add(time.Hour)),
	} {
		update(msg)
		check(first)
	}
	update(tea.KeyMsg{Type: tea.KeySpace})
	check(latest)
	update(metricsMsg(MetricsSnapshot{CollectedAt: latest.Add(time.Second)}))
	check(latest.Add(time.Second))
	update(metricsMsg(MetricsSnapshot{}))
	if !strings.Contains(ansi.Strip(current.View()), "Sample started: Unavailable") {
		t.Fatal("missing timestamp must not retain the previous snapshot time")
	}
}

func TestSampleTimestampViewport(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 18, Height: 9}, {Width: 40, Height: 9}, {Width: 80, Height: 24}} {
		for _, paused := range []bool{false, true} {
			t.Run(fmt.Sprintf("%dx%d/paused=%t", size.Width, size.Height, paused), func(t *testing.T) {
				var current tea.Model = newModel()
				current, _ = current.Update(metricsMsg(MetricsSnapshot{CollectedAt: time.Date(2026, 10, 13, 12, 34, 56, 0, time.UTC)}))
				current, _ = current.Update(size)
				if paused {
					current, _ = current.Update(tea.KeyMsg{Type: tea.KeySpace})
				}
				var seen strings.Builder
				lines, _, _ := current.(model).layout()
				for range lines {
					view := ansi.Strip(current.View())
					rows := strings.Split(view, "\n")
					if len(rows) > size.Height {
						t.Fatal("timestamp overflows terminal height")
					}
					for _, row := range rows {
						if ansi.StringWidth(row) > size.Width {
							t.Fatalf("timestamp overflows terminal width: %q", row)
						}
					}
					seen.WriteString(strings.ReplaceAll(strings.Join(rows, ""), " ", ""))
					current, _ = current.Update(tea.KeyMsg{Type: tea.KeyDown})
				}
				if !strings.Contains(seen.String(), "Samplestarted:2026-10-1312:34:56+0000") {
					t.Fatal("scrolling never exposed the full sample timestamp")
				}
			})
		}
	}
}
