//go:build windows

package main

import "testing"

func TestDiskHealthUsesFullestDrive(t *testing.T) {
	for _, tc := range []struct {
		name    string
		disks   []DiskInfo
		score   int
		message string
	}{
		{"no disks", nil, 100, "Excellent"},
		{"low boundary", []DiskInfo{{Device: "C:", UsedPercent: 85}}, 100, "Excellent"},
		{"above low", []DiskInfo{{Device: "C:", UsedPercent: 85.01}}, 90, "Disk C: Low"},
		{"critical boundary", []DiskInfo{{Device: "C:", UsedPercent: 95}}, 90, "Disk C: Low"},
		{"above critical", []DiskInfo{{Device: "C:", UsedPercent: 95.01}}, 80, "Disk C: Critical"},
		{"low before critical", []DiskInfo{{Device: "C:", UsedPercent: 90}, {Device: "D:", UsedPercent: 99}}, 80, "Disk D: Critical"},
		{"critical before low", []DiskInfo{{Device: "D:", UsedPercent: 99}, {Device: "C:", UsedPercent: 90}}, 80, "Disk D: Critical"},
		{"only one penalty", []DiskInfo{{Device: "C:", UsedPercent: 96}, {Device: "D:", UsedPercent: 99}}, 80, "Disk D: Critical"},
		{"equal usage", []DiskInfo{{Device: "D:", UsedPercent: 99}, {Device: "C:", UsedPercent: 99}}, 80, "Disk C: Critical"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			score, message := calculateHealthScore(MetricsSnapshot{Disks: tc.disks})
			if score != tc.score || message != tc.message {
				t.Fatalf("got %d, %q; want %d, %q", score, message, tc.score, tc.message)
			}
		})
	}
}
