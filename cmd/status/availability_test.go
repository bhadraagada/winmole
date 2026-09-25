//go:build windows

package main

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/mem"
)

func healthyCollector() *Collector {
	c := NewCollector()
	c.cpuPercent = func(context.Context, time.Duration, bool) ([]float64, error) { return []float64{0}, nil }
	c.virtualMemory = func(context.Context) (*mem.VirtualMemoryStat, error) {
		return &mem.VirtualMemoryStat{Total: 1024}, nil
	}
	c.swapMemory = func(context.Context) (*mem.SwapMemoryStat, error) { return &mem.SwapMemoryStat{}, nil }
	c.partitions = func(context.Context, bool) ([]disk.PartitionStat, error) {
		return []disk.PartitionStat{{Device: "C:", Mountpoint: "C:\\"}, {Device: "D:", Mountpoint: "D:\\"}}, nil
	}
	c.diskUsage = func(context.Context, string) (*disk.UsageStat, error) {
		return &disk.UsageStat{Total: 1024, Free: 1024}, nil
	}
	return c
}

func TestCollectionAvailabilityAndRecovery(t *testing.T) {
	failure := errors.New("metrics query failed")
	for _, tc := range []struct {
		name, missing, row string
		fail               func(*Collector)
	}{
		{"CPU error", "CPU", "Usage: Unavailable", func(c *Collector) {
			c.cpuPercent = func(context.Context, time.Duration, bool) ([]float64, error) { return nil, failure }
		}},
		{"memory error", "Memory", "RAM: Unavailable", func(c *Collector) {
			c.virtualMemory = func(context.Context) (*mem.VirtualMemoryStat, error) { return nil, failure }
		}},
		{"swap error", "Swap", "Swap: Unavailable", func(c *Collector) {
			c.swapMemory = func(context.Context) (*mem.SwapMemoryStat, error) { return nil, failure }
		}},
		{"partitions error", "Disks", "Disks\n  Unavailable", func(c *Collector) {
			c.partitions = func(context.Context, bool) ([]disk.PartitionStat, error) { return nil, failure }
		}},
		{"disk error", "Disk C:, Disk D:", "C: Unavailable", func(c *Collector) {
			c.diskUsage = func(context.Context, string) (*disk.UsageStat, error) { return nil, failure }
		}},
		{"empty readings", "CPU, Memory, Disk C:, Disk D:", "C: Unavailable", func(c *Collector) {
			c.cpuPercent = func(context.Context, time.Duration, bool) ([]float64, error) { return nil, nil }
			c.virtualMemory = func(context.Context) (*mem.VirtualMemoryStat, error) { return &mem.VirtualMemoryStat{}, nil }
			c.diskUsage = func(context.Context, string) (*disk.UsageStat, error) { return &disk.UsageStat{}, nil }
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := healthyCollector()
			tc.fail(c)
			snapshot := c.Collect()
			if snapshot.HealthScore != -1 || snapshot.HealthMessage != "Missing metrics: "+tc.missing {
				t.Fatalf("collection failure reported %d, %q", snapshot.HealthScore, snapshot.HealthMessage)
			}
			m := newModel()
			updated, _ := m.Update(metricsMsg(snapshot))
			m = updated.(model)
			view := m.View()
			if !strings.Contains(view, "Health: Unavailable") || !strings.Contains(view, tc.row) || strings.Contains(view, "Excellent") || strings.Contains(view, "-1%") {
				t.Fatalf("missing failure indicator %q:\n%s", tc.row, view)
			}
			// Reuse the collector and model to ensure refresh clears missing state.
			healthy := healthyCollector()
			c.cpuPercent, c.virtualMemory, c.swapMemory = healthy.cpuPercent, healthy.virtualMemory, healthy.swapMemory
			c.partitions, c.diskUsage = healthy.partitions, healthy.diskUsage
			snapshot = c.Collect()
			updated, _ = m.Update(metricsMsg(snapshot))
			view = updated.View()
			if snapshot.HealthScore != 100 || !snapshot.CPUAvailable || !snapshot.MemAvailable || !snapshot.SwapAvailable || strings.Contains(view, "Unavailable") || !strings.Contains(view, "0.0%") || !strings.Contains(view, "Excellent") {
				t.Fatalf("valid idle CPU and no configured swap did not recover:\n%s", view)
			}
		})
	}
}

func TestPartialDiskFailurePreservesKnownWarning(t *testing.T) {
	c := healthyCollector()
	c.diskUsage = func(_ context.Context, path string) (*disk.UsageStat, error) {
		if path == "D:\\" {
			return nil, errors.New("drive unavailable")
		}
		return &disk.UsageStat{Total: 1024, Used: 1024, UsedPercent: 100}, nil
	}
	snapshot := c.Collect()
	if snapshot.HealthScore != -1 || snapshot.HealthMessage != "Missing metrics: Disk D:; Disk C: Critical" {
		t.Fatalf("known warning lost: %d, %q", snapshot.HealthScore, snapshot.HealthMessage)
	}
	m := newModel()
	updated, _ := m.Update(metricsMsg(snapshot))
	view := updated.View()
	if !strings.Contains(view, "C: 1.0 KB / 1.0 KB (100.0%)") || !strings.Contains(view, "D: Unavailable") || strings.Count(view, "Free:") != 1 {
		t.Fatalf("partial disk readings not preserved:\n%s", view)
	}
}

func TestAllUnavailableDoesNotRenderPercentagesOrBars(t *testing.T) {
	snapshot := MetricsSnapshot{}
	snapshot.HealthScore, snapshot.HealthMessage = calculateHealthScore(snapshot)
	m := newModel()
	updated, _ := m.Update(metricsMsg(snapshot))
	view := updated.View()
	if snapshot.HealthMessage != "Missing metrics: CPU, Memory, Swap, Disks" || strings.ContainsAny(view, "%█░") || strings.Contains(view, "0 B") {
		t.Fatalf("missing measurements rendered as values:\n%s", view)
	}
}

func TestPartialDiskEnumerationPreservesReadingsAndRecovers(t *testing.T) {
	c := healthyCollector()
	partitions := c.partitions
	c.partitions = func(ctx context.Context, all bool) ([]disk.PartitionStat, error) {
		readable, err := partitions(ctx, all)
		if err != nil {
			return nil, err
		}
		return readable[:1], errors.New("another drive could not be listed")
	}
	c.diskUsage = func(context.Context, string) (*disk.UsageStat, error) {
		return &disk.UsageStat{Total: 1024, Used: 1024, UsedPercent: 100}, nil
	}
	snapshot := c.Collect()
	if snapshot.DisksComplete || snapshot.HealthScore != -1 || snapshot.HealthMessage != "Missing metrics: Disks (incomplete list); Disk C: Critical" {
		t.Fatalf("partial enumeration lost availability or warning: %+v", snapshot)
	}
	m := newModel()
	updated, _ := m.Update(metricsMsg(snapshot))
	m = updated.(model)
	view := m.View()
	if !strings.Contains(view, "Incomplete disk list") || !strings.Contains(view, "C: 1.0 KB / 1.0 KB (100.0%)") || !strings.Contains(view, "Health: Unavailable") {
		t.Fatalf("partial enumeration lost readable drive:\n%s", view)
	}
	c.partitions = partitions
	snapshot = c.Collect()
	updated, _ = m.Update(metricsMsg(snapshot))
	view = updated.View()
	if !snapshot.DisksComplete || snapshot.HealthScore != 80 || len(snapshot.Disks) != 2 || strings.Contains(view, "Incomplete") || strings.Contains(view, "Unavailable") {
		t.Fatalf("enumeration recovery failed:\n%s", view)
	}
}
