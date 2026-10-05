//go:build windows

package main

import (
	"context"
	"strings"
	"testing"
	"time"
)

func TestProcessMemoryFailureZeroAndRecovery(t *testing.T) {
	c := NewCollector()
	sample := processSample{info: ProcessInfo{PID: 7, Name: "app", CPUAvailable: true}, created: 1, at: time.Now()}
	c.processSamples = func(context.Context) ([]processSample, error) { return []processSample{sample}, nil }
	c.collectProcesses(context.Background())
	for _, tc := range []struct {
		name      string
		available bool
		memory    float32
		want      string
	}{
		{"measured", true, 5, "5.0%"},
		{"failed", false, 0, "Unavailable"},
		{"measured zero", true, 0, "0.0%"},
		{"recovered", true, 8, "8.0%"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			sample.at, sample.total = sample.at.Add(time.Second), sample.total+1
			sample.info.Memory, sample.info.MemoryAvailable = tc.memory, tc.available
			got := c.collectProcesses(context.Background())
			if len(got) != 1 || got[0].MemoryAvailable != tc.available || got[0].Memory != tc.memory || !got[0].CPUAvailable || got[0].CPU != 100 {
				t.Fatalf("memory state changed CPU sampling or retained stale memory: %+v", got)
			}
			m := newModel()
			m.ready, m.metrics.Processes = true, got
			if view := m.View(); !strings.Contains(view, "app (CPU: 100.0%, Mem: "+tc.want+")") {
				t.Fatalf("memory reading not rendered as %q: %s", tc.want, view)
			}
		})
	}
}

func TestProcessMemoryAvailabilitySorting(t *testing.T) {
	processes := []ProcessInfo{
		{PID: 5, Memory: 999},
		{PID: 4, MemoryAvailable: true},
		{PID: 3, MemoryAvailable: true, Memory: 2},
		{PID: 2, MemoryAvailable: true, Memory: 2},
		{PID: 1, CPUAvailable: true, CPU: 100},
	}
	sortProcesses(processes, true)
	for i, want := range []int32{2, 3, 4, 1, 5} {
		if processes[i].PID != want {
			t.Fatalf("memory sorting should rank measured usage, then PID: %+v", processes)
		}
	}
	sortProcesses(processes, false)
	if processes[0].PID != 1 {
		t.Fatal("unavailable memory changed CPU sorting")
	}
}

func TestProcessEligibilityRequiresAvailableMemory(t *testing.T) {
	c := NewCollector()
	c.processSamples = func(context.Context) ([]processSample, error) {
		return []processSample{
			{info: ProcessInfo{PID: 1, Memory: 99}},
			{info: ProcessInfo{PID: 2, MemoryAvailable: true, Memory: 0.1}},
			{info: ProcessInfo{PID: 3, MemoryAvailable: true, Memory: 0.2}},
			{info: ProcessInfo{PID: 4, CPU: 99}},
		}, nil
	}
	got := c.collectProcesses(context.Background())
	if len(got) != 1 || got[0].PID != 3 || !got[0].MemoryAvailable || got[0].CPUAvailable {
		t.Fatalf("eligibility must require available CPU or memory over 0.1%%: %+v", got)
	}
}
