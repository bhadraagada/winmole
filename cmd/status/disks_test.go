//go:build windows

package main

import (
	"strings"
	"testing"
)

func TestDiskFreeSpaceRenderingAndRefresh(t *testing.T) {
	const gb = 1024 * 1024 * 1024
	m := newModel()
	for _, tc := range []struct {
		name  string
		disks []DiskInfo
		rows  []string
	}{
		{
			name: "multiple drives with collected free space and a full drive",
			disks: []DiskInfo{
				{Device: "C:", Total: 100 * gb, Used: 75 * gb, Free: 20 * gb, UsedPercent: 75},
				{Device: "D:", Total: 2 * gb, Used: 2 * gb, Free: 0, UsedPercent: 100},
			},
			rows: []string{
				"C: 75.0 GB / 100.0 GB (75.0%)\n  " + strings.Repeat("█", 22) + strings.Repeat("░", 8) + "  Free: 20.0 GB",
				"D: 2.0 GB / 2.0 GB (100.0%)\n  " + strings.Repeat("█", 30) + "  Free: 0 B",
			},
		},
		{
			name: "refreshed metrics",
			disks: []DiskInfo{
				{Device: "C:", Total: 100 * gb, Used: 50 * gb, Free: 45 * gb, UsedPercent: 50},
				{Device: "D:", Total: 2 * gb, Used: gb, Free: gb, UsedPercent: 50},
			},
			rows: []string{
				"C: 50.0 GB / 100.0 GB (50.0%)\n  " + strings.Repeat("█", 15) + strings.Repeat("░", 15) + "  Free: 45.0 GB",
				"D: 1.0 GB / 2.0 GB (50.0%)\n  " + strings.Repeat("█", 15) + strings.Repeat("░", 15) + "  Free: 1.0 GB",
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			updated, _ := m.Update(metricsMsg(MetricsSnapshot{Disks: tc.disks}))
			m = updated.(model)
			view := m.View()
			for _, row := range tc.rows {
				if !strings.Contains(view, row) {
					t.Errorf("view is missing disk usage, bar, or collected free space %q:\n%s", row, view)
				}
			}
			if got := strings.Count(view, "Free:"); got != len(tc.disks) {
				t.Errorf("got %d free-space values, want one per drive (%d)", got, len(tc.disks))
			}
		})
	}
}
