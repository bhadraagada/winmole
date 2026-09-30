//go:build windows

package main

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func TestPerCoreToggleAndRefresh(t *testing.T) {
	m := newModel()
	m.sortByMemory = true
	snapshot := MetricsSnapshot{CPUAvailable: true, CPUPercent: 25, CPUPerCore: []float64{0, 100, 12.5}}
	updated, _ := m.Update(metricsMsg(snapshot))
	m = updated.(model)
	if strings.Contains(m.View(), "CPU 0:") {
		t.Fatal("per-core readings should start collapsed")
	}
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'p'}})
	m = updated.(model)
	if cmd != nil || !m.sortByMemory || !reflect.DeepEqual(m.metrics, snapshot) {
		t.Fatal("toggle must use existing metrics without collecting or changing them")
	}
	view := ansi.Strip(m.View())
	for _, want := range []string{"Usage: 25.0%", "Logical processors", "CPU 0:   0.0%", "CPU 1: 100.0%", "CPU 2:  12.5%"} {
		if !strings.Contains(view, want) {
			t.Errorf("expanded view missing %q:\n%s", want, view)
		}
	}
	// Per-core readings are independent of aggregate CPU availability.
	updated, _ = m.Update(metricsMsg(MetricsSnapshot{CPUPerCore: []float64{75}}))
	m = updated.(model)
	view = ansi.Strip(m.View())
	if !strings.Contains(view, "Usage: Unavailable") || !strings.Contains(view, "CPU 0:  75.0%") || strings.Contains(view, "CPU 1:") {
		t.Fatalf("refresh did not retain toggle and replace readings:\n%s", view)
	}
	updated, _ = m.Update(metricsMsg(MetricsSnapshot{CPUAvailable: true}))
	m = updated.(model)
	view = ansi.Strip(m.View())
	if !strings.Contains(view, "Logical processors: Unavailable") || strings.Contains(view, "CPU 0:") {
		t.Fatalf("missing per-core readings retained stale values:\n%s", view)
	}
	updated, cmd = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'p'}})
	if cmd != nil || strings.Contains(updated.View(), "Logical processors") {
		t.Fatal("second toggle must collapse per-core readings without collection")
	}
}

func TestPerCoreLoadingAndScrollableLayout(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 60, Height: 15}, {Width: 24, Height: 9}, {Width: 8, Height: 4}} {
		t.Run(fmt.Sprintf("%dx%d", size.Width, size.Height), func(t *testing.T) {
			m := newModel()
			updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'p'}})
			if cmd != nil || !strings.Contains(updated.View(), "Loading") {
				t.Fatal("toggle while loading must not schedule collection")
			}
			cores := make([]float64, 128)
			cores[127] = 99.9
			updated, _ = updated.Update(metricsMsg(MetricsSnapshot{CPUPerCore: cores}))
			updated, _ = updated.Update(size)
			m = updated.(model)
			var seen strings.Builder
			lines, _, _ := m.layout()
			for i := 0; i <= len(lines); i++ {
				view := m.View()
				rows := strings.Split(view, "\n")
				if len(rows) > size.Height {
					t.Fatalf("view overflows height: %d", len(rows))
				}
				for _, row := range rows {
					if ansi.StringWidth(row) > size.Width {
						t.Fatalf("row overflows width: %q", row)
					}
				}
				seen.WriteString(ansi.Strip(view))
				updated, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
				m = updated.(model)
			}
			// Tiny windows wrap the processor label and reading onto separate rows.
			seenText := strings.Join(strings.Fields(seen.String()), "")
			if !strings.Contains(seenText, "CPU127:") || !strings.Contains(seenText, "99.9%") {
				t.Fatal("last logical processor cannot be reached by scrolling")
			}
			updated, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'p'}})
			m = updated.(model)
			lines, _, height := m.layout()
			if m.scroll > max(0, len(lines)-height) || strings.Contains(m.View(), "CPU 127:") {
				t.Fatal("collapse must clamp the scroll position to remaining content")
			}
		})
	}
}
