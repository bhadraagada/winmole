//go:build windows

package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func TestProcessScanFailureAndRecovery(t *testing.T) {
	for _, tc := range []struct {
		name    string
		samples []processSample
		err     error
	}{
		{name: "enumeration failed", err: errors.New("process enumeration failed")},
		{name: "deadline after one process", samples: []processSample{{info: ProcessInfo{PID: 7, Name: "sampled-process", MemoryAvailable: true, Memory: 5}}}, err: context.DeadlineExceeded},
		{name: "canceled with no active rows", samples: []processSample{{info: ProcessInfo{PID: 7, Name: "idle-process", MemoryAvailable: true}}}, err: context.Canceled},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := healthyCollector()
			c.processSamples = func(context.Context) ([]processSample, error) { return tc.samples, tc.err }
			snapshot := c.Collect()
			m, _ := newModel().Update(metricsMsg(snapshot))
			view := m.View()
			if !strings.Contains(view, "Process scan incomplete. Some processes may be missing.") {
				t.Fatalf("failed scan lacks warning: %s", view)
			}
			if snapshot.HealthScore != 100 || snapshot.HealthMessage != "Excellent" {
				t.Fatal("process scan failure must not change health scoring")
			}
			if tc.name == "deadline after one process" && !strings.Contains(view, "sampled-process (CPU: Unavailable, Mem: 5.0%)") {
				t.Fatal("interrupted scan lost the collected process")
			}
			if tc.name == "canceled with no active rows" && len(snapshot.Processes) != 0 {
				t.Fatal("scan warning must not change the activity threshold")
			}
			c.processSamples = func(context.Context) ([]processSample, error) { return tc.samples, nil }
			m, _ = m.Update(metricsMsg(c.Collect()))
			if strings.Contains(m.View(), "Process scan incomplete") || len(m.(model).metrics.Processes) != len(snapshot.Processes) {
				t.Fatal("successful scan must clear the warning and keep qualifying rows")
			}
			c.processSamples = func(context.Context) ([]processSample, error) { return nil, nil }
			m, _ = m.Update(metricsMsg(c.Collect()))
			if strings.Contains(m.View(), "Process scan incomplete") || strings.Contains(m.View(), "Processes by") {
				t.Fatal("successful empty scan must clear the warning and keep the list hidden")
			}
		})
	}
}

func TestProcessScanWarningFollowsPausedSnapshot(t *testing.T) {
	c := healthyCollector()
	c.processSamples = func(context.Context) ([]processSample, error) { return nil, context.DeadlineExceeded }
	failed := metricsMsg(c.Collect())
	m, _ := newModel().Update(failed)
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeySpace})
	c.processSamples = func(context.Context) ([]processSample, error) { return nil, nil }
	recovered := metricsMsg(c.Collect())
	m, _ = m.Update(recovered)
	if !strings.Contains(m.View(), "Process scan incomplete") {
		t.Fatal("paused warning must stay with the displayed failed snapshot")
	}
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeySpace})
	if strings.Contains(m.View(), "Process scan incomplete") {
		t.Fatal("resume must show recovery from the latest snapshot")
	}
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeySpace})
	m, _ = m.Update(recovered)
	m, _ = m.Update(failed)
	if strings.Contains(m.View(), "Process scan incomplete") {
		t.Fatal("a pending failure must not change the paused successful snapshot")
	}
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeySpace})
	if !strings.Contains(m.View(), "Process scan incomplete") {
		t.Fatal("resume must show the latest failure")
	}
}

func TestProcessScanWarningViewport(t *testing.T) {
	c := healthyCollector()
	c.processSamples = func(context.Context) ([]processSample, error) { return nil, context.DeadlineExceeded }
	snapshot := metricsMsg(c.Collect())
	snapshot.Networks = nil
	for _, size := range []tea.WindowSizeMsg{{Width: 18, Height: 9}, {Width: 40, Height: 9}, {Width: 80, Height: 24}} {
		t.Run(fmt.Sprintf("%dx%d", size.Width, size.Height), func(t *testing.T) {
			m, _ := newModel().Update(snapshot)
			m, _ = m.Update(size)
			m, _ = m.Update(tea.KeyMsg{Type: tea.KeyEnd})
			view := ansi.Strip(m.View())
			if !strings.Contains(strings.Join(strings.Fields(view), " "), "Process scan incomplete. Some processes may be missing.") {
				t.Fatalf("end must reveal the complete warning: %s", view)
			}
			if len(strings.Split(view, "\n")) > size.Height || !strings.Contains(view, "quit") {
				t.Fatal("warning must fit the viewport and retain quit controls")
			}
			for _, line := range strings.Split(view, "\n") {
				if ansi.StringWidth(line) > size.Width {
					t.Fatalf("warning exceeds %d columns: %q", size.Width, line)
				}
			}
		})
	}
}
