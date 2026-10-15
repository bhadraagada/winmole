//go:build windows

package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
	"github.com/shirou/gopsutil/v3/host"
)

func TestMissingHostInfoDoesNotReportZeroUptime(t *testing.T) {
	m := newModel()
	updated, _ := m.Update(metricsMsg(MetricsSnapshot{}))
	view := ansi.Strip(updated.(model).content())
	for _, row := range []string{"Host: Unavailable", "OS: Unavailable", "Uptime: Unavailable"} {
		if !strings.Contains(view, row) {
			t.Fatalf("missing host query must show %q:\n%s", row, view)
		}
	}
	if strings.Contains(view, "Uptime: 0m") {
		t.Fatal("missing host query reported a measured zero uptime")
	}
}

func TestHostCollectionFailureAndRecovery(t *testing.T) {
	failure := errors.New("host query failed")
	for _, tc := range []struct {
		name string
		info *host.InfoStat
		err  error
	}{
		{"error", nil, failure},
		{"nil result", nil, nil},
		{"result with error", &host.InfoStat{Hostname: "unusable"}, failure},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := healthyCollector()
			c.hostInfo = func(context.Context) (*host.InfoStat, error) { return tc.info, tc.err }
			m := newModel()
			for _, uptime := range []uint64{0, 90061} {
				snapshot := c.Collect()
				if snapshot.HostAvailable || snapshot.Hostname != "" || snapshot.Platform != "" || snapshot.Uptime != 0 || snapshot.HealthScore != 100 {
					t.Fatalf("failed host query changed health or exposed invalid values: %+v", snapshot)
				}
				updated, _ := m.Update(metricsMsg(snapshot))
				m = updated.(model)
				if !strings.Contains(ansi.Strip(m.content()), "Uptime: Unavailable") {
					t.Fatal("query failure must clear the previous displayed uptime")
				}
				c.hostInfo = func(context.Context) (*host.InfoStat, error) {
					return &host.InfoStat{Hostname: "desktop", OS: "windows", Platform: "Windows", PlatformVersion: "11", Uptime: uptime}, nil
				}
				snapshot = c.Collect()
				if !snapshot.HostAvailable || snapshot.Hostname != "desktop" || snapshot.OS != "windows" || snapshot.Platform != "Windows 11" || snapshot.Uptime != time.Duration(uptime)*time.Second || snapshot.HealthScore != 100 {
					t.Fatalf("valid host query did not recover: %+v", snapshot)
				}
				updated, _ = m.Update(metricsMsg(snapshot))
				m = updated.(model)
				view := ansi.Strip(m.content())
				for _, row := range []string{"Host: desktop", "OS: Windows 11", "Uptime: " + formatDuration(time.Duration(uptime)*time.Second)} {
					if !strings.Contains(view, row) {
						t.Fatalf("recovered query missing %q", row)
					}
				}
				c.hostInfo = func(context.Context) (*host.InfoStat, error) { return tc.info, tc.err }
			}
			c.hostInfo = func(context.Context) (*host.InfoStat, error) {
				t.Error("health-only report must not query host details")
				return nil, nil
			}
			if snapshot := c.collect(false); snapshot.HostAvailable || snapshot.HealthScore != 100 {
				t.Fatal("host availability changed health-only collection")
			}
		})
	}
}

func TestHostAvailabilityFollowsPausedSnapshot(t *testing.T) {
	m := newModel()
	updated, _ := m.Update(metricsMsg(MetricsSnapshot{HostAvailable: true, Hostname: "desktop", Platform: "Windows 11", Uptime: time.Hour}))
	updated, _ = updated.Update(tea.KeyMsg{Type: tea.KeySpace})
	updated, _ = updated.Update(metricsMsg(MetricsSnapshot{}))
	if view := ansi.Strip(updated.(model).content()); !strings.Contains(view, "Host: desktop") || !strings.Contains(view, "Uptime: 1h 0m") {
		t.Fatal("paused display lost the successful host query")
	}
	updated, _ = updated.Update(tea.KeyMsg{Type: tea.KeySpace})
	if !strings.Contains(ansi.Strip(updated.(model).content()), "Uptime: Unavailable") {
		t.Fatal("resume must apply the latest host query failure")
	}
}

func TestMissingHostInfoViewport(t *testing.T) {
	for _, size := range []tea.WindowSizeMsg{{Width: 18, Height: 9}, {Width: 40, Height: 9}, {Width: 80, Height: 24}} {
		t.Run(fmt.Sprintf("%dx%d", size.Width, size.Height), func(t *testing.T) {
			var current tea.Model = newModel()
			current, _ = current.Update(metricsMsg(MetricsSnapshot{}))
			current, _ = current.Update(size)
			lines, _, _ := current.(model).layout()
			var seen strings.Builder
			for range lines {
				rows := strings.Split(ansi.Strip(current.View()), "\n")
				if len(rows) > size.Height {
					t.Fatal("host rows exceed terminal height")
				}
				for _, row := range rows {
					if ansi.StringWidth(row) > size.Width {
						t.Fatalf("host row exceeds terminal width: %q", row)
					}
				}
				seen.WriteString(strings.ReplaceAll(strings.Join(rows, ""), " ", ""))
				current, _ = current.Update(tea.KeyMsg{Type: tea.KeyDown})
			}
			for _, row := range []string{"Host:Unavailable", "OS:Unavailable", "Uptime:Unavailable"} {
				if !strings.Contains(seen.String(), row) {
					t.Fatalf("scrolling did not expose %q", row)
				}
			}
		})
	}
}
