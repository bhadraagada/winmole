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
		{"no disks", nil, -1, "Missing metrics: Disks"},
		{"low boundary", []DiskInfo{{Available: true, Device: "C:", UsedPercent: 85}}, 100, "Excellent"},
		{"above low", []DiskInfo{{Available: true, Device: "C:", UsedPercent: 85.01}}, 90, "Disk C: Low"},
		{"critical boundary", []DiskInfo{{Available: true, Device: "C:", UsedPercent: 95}}, 90, "Disk C: Low"},
		{"above critical", []DiskInfo{{Available: true, Device: "C:", UsedPercent: 95.01}}, 80, "Disk C: Critical"},
		{"low before critical", []DiskInfo{{Available: true, Device: "C:", UsedPercent: 90}, {Available: true, Device: "D:", UsedPercent: 99}}, 80, "Disk D: Critical"},
		{"critical before low", []DiskInfo{{Available: true, Device: "D:", UsedPercent: 99}, {Available: true, Device: "C:", UsedPercent: 90}}, 80, "Disk D: Critical"},
		{"only one penalty", []DiskInfo{{Available: true, Device: "C:", UsedPercent: 96}, {Available: true, Device: "D:", UsedPercent: 99}}, 80, "Disk D: Critical"},
		{"equal usage", []DiskInfo{{Available: true, Device: "D:", UsedPercent: 99}, {Available: true, Device: "C:", UsedPercent: 99}}, 80, "Disk C: Critical"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			score, message := calculateHealthScore(MetricsSnapshot{CPUAvailable: true, MemAvailable: true, SwapAvailable: true, Disks: tc.disks})
			if score != tc.score || message != tc.message {
				t.Fatalf("got %d, %q; want %d, %q", score, message, tc.score, tc.message)
			}
		})
	}
}
