//go:build windows

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/shirou/gopsutil/v3/mem"
)

func TestHealthOnlyCollection(t *testing.T) {
	for _, missingMemory := range []bool{false, true} {
		c := healthyCollector()
		if missingMemory {
			c.virtualMemory = func(context.Context) (*mem.VirtualMemoryStat, error) {
				return nil, errors.New("memory unavailable")
			}
		}
		aggregateCalls, perCoreCalls := 0, 0
		c.cpuPercent = func(_ context.Context, _ time.Duration, perCore bool) ([]float64, error) {
			if perCore {
				perCoreCalls++
			} else {
				aggregateCalls++
			}
			return []float64{25}, nil
		}
		health := c.collect(false)
		if aggregateCalls != 1 || perCoreCalls != 0 {
			t.Fatalf("health report sampled CPU %d aggregate/%d per-core times", aggregateCalls, perCoreCalls)
		}
		if health.Hostname != "" || health.OS != "" || health.Platform != "" || health.Uptime != 0 || health.CPUModel != "" || health.CPUCores != 0 || health.CPUPerCore != nil || health.Networks != nil || health.Processes != nil {
			t.Fatalf("health report collected unused details: %+v", health)
		}
		full := c.Collect()
		if aggregateCalls != 2 || perCoreCalls != 1 || len(full.CPUPerCore) != 1 || full.CPUCores < 1 {
			t.Fatal("default collection stopped collecting dashboard details")
		}
		// Both modes must keep the same readings, availability and health rules.
		full.CollectedAt = health.CollectedAt
		var healthJSON, fullJSON bytes.Buffer
		if err := writeJSONReport(&healthJSON, health); err != nil {
			t.Fatal(err)
		}
		if err := writeJSONReport(&fullJSON, full); err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(healthJSON.Bytes(), fullJSON.Bytes()) {
			t.Fatalf("health readings differ:\n%s\n%s", &healthJSON, &fullJSON)
		}
	}
}

func TestJSONReport(t *testing.T) {
	snapshot := MetricsSnapshot{
		CollectedAt:  time.Date(2026, 9, 25, 10, 0, 0, 0, time.UTC),
		CPUAvailable: true, MemAvailable: true, SwapAvailable: true,
		MemTotal: 1000, MemUsed: 250, MemPercent: 25,
		DisksComplete: true,
		Disks: []DiskInfo{
			{Available: true, Device: "C:", Mountpoint: `C:\`, Total: 100, Used: 90, Free: 10, UsedPercent: 90},
			{Available: true, Device: "D:", Mountpoint: `D:\`, Total: 200, Used: 20, Free: 180, UsedPercent: 10},
		},
	}
	snapshot.HealthScore, snapshot.HealthMessage = calculateHealthScore(snapshot)
	var output bytes.Buffer
	if err := writeJSONReport(&output, snapshot); err != nil {
		t.Fatal(err)
	}
	var report statusReport
	decoder := json.NewDecoder(&output)
	if err := decoder.Decode(&report); err != nil {
		t.Fatal(err)
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		t.Fatalf("expected exactly one JSON object, got %v", err)
	}
	if !report.CollectedAt.Equal(snapshot.CollectedAt) || !report.Health.Available || report.Health.Score == nil || *report.Health.Score != 90 {
		t.Fatalf("incorrect timestamp or health: %+v", report)
	}
	if report.CPU.Percent == nil || *report.CPU.Percent != 0 || report.Swap.TotalBytes == nil || *report.Swap.TotalBytes != 0 {
		t.Fatal("idle CPU and absent swap must be measured zero, not null")
	}
	if report.Memory.UsedBytes == nil || *report.Memory.UsedBytes != 250 || !report.DisksComplete || len(report.Disks) != 2 {
		t.Fatalf("incorrect memory or disks: %+v", report)
	}
	if *report.Disks[0].FreeBytes != 10 || *report.Disks[1].FreeBytes != 180 {
		t.Fatal("disk values changed during serialization")
	}
}

func TestJSONReportUnavailableReadings(t *testing.T) {
	snapshot := MetricsSnapshot{
		// Stale values must not leak through a failed measurement.
		CPUPercent: 75, MemTotal: 1000, SwapTotal: 100,
		Disks: []DiskInfo{{Device: "C:", Total: 100}},
	}
	snapshot.HealthScore, snapshot.HealthMessage = calculateHealthScore(snapshot)
	var output bytes.Buffer
	if err := writeJSONReport(&output, snapshot); err != nil {
		t.Fatal(err)
	}
	var report statusReport
	if err := json.Unmarshal(output.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if report.Health.Available || report.Health.Score != nil || !strings.Contains(report.Health.Message, "Missing metrics") {
		t.Fatalf("missing metrics reported healthy: %+v", report.Health)
	}
	if report.CPU.Available || report.CPU.Percent != nil || report.Memory.Available || report.Memory.TotalBytes != nil || report.Memory.UsedBytes != nil || report.Memory.Percent != nil || report.Swap.Available || report.Swap.TotalBytes != nil || report.Swap.UsedBytes != nil || report.Swap.Percent != nil {
		t.Fatal("unavailable CPU/memory/swap readings must be null")
	}
	disk := report.Disks[0]
	if report.DisksComplete || disk.Available || disk.TotalBytes != nil || disk.UsedBytes != nil || disk.FreeBytes != nil || disk.UsedPercent != nil || disk.Device != "C:" {
		t.Fatalf("unavailable disk lost identity or retained measurements: %+v", disk)
	}
	output.Reset()
	snapshot.Disks = nil
	if err := writeJSONReport(&output, snapshot); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), `"disks":[]`) {
		t.Fatal("no disks should produce an empty array")
	}
}

type failedReportWriter struct{}

func (failedReportWriter) Write([]byte) (int, error) { return 0, io.ErrClosedPipe }

func TestJSONReportWriteFailure(t *testing.T) {
	if err := writeJSONReport(failedReportWriter{}, MetricsSnapshot{}); !errors.Is(err, io.ErrClosedPipe) {
		t.Fatalf("expected output error, got %v", err)
	}
}
