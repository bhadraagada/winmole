//go:build windows

package main

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestProcessCPUIntervalsAndBaselineRecovery(t *testing.T) {
	now := time.Now()
	c := NewCollector()
	var samples []processSample
	var readErr error
	c.processSamples = func(context.Context) ([]processSample, error) { return samples, readErr }
	for _, tc := range []struct {
		name      string
		created   int64
		total     float64
		second    int
		readable  bool
		present   bool
		failed    bool
		available bool
		want      float64
	}{
		{name: "first", created: 1, total: 100, readable: true, present: true},
		{name: "busy", created: 1, total: 104, second: 2, readable: true, present: true, available: true, want: 200},
		{name: "idle", created: 1, total: 104, second: 4, readable: true, present: true, available: true},
		{name: "missing CPU", created: 1, second: 6, present: true},
		{name: "after missing", created: 1, total: 108, second: 8, readable: true, present: true},
		{name: "recovered", created: 1, total: 109, second: 10, readable: true, present: true, available: true, want: 50},
		{name: "reused PID", created: 2, total: 1, second: 12, readable: true, present: true},
		{name: "new process busy", created: 2, total: 2, second: 14, readable: true, present: true, available: true, want: 50},
		{name: "counter reset", created: 2, total: 0, second: 16, readable: true, present: true},
		{name: "after reset", created: 2, total: 1, second: 18, readable: true, present: true, available: true, want: 50},
		{name: "same timestamp", created: 2, total: 2, second: 18, readable: true, present: true},
		{name: "backward timestamp", created: 2, total: 3, second: 17, readable: true, present: true},
		{name: "exited"},
		{name: "after exit", created: 2, total: 4, second: 20, readable: true, present: true},
		{name: "enumeration error", failed: true},
		{name: "after enumeration error", created: 2, total: 5, second: 22, readable: true, present: true, available: true, want: 50},
	} {
		t.Run(tc.name, func(t *testing.T) {
			samples, readErr = nil, nil
			if tc.present {
				samples = []processSample{{info: ProcessInfo{PID: 7, Name: "app", MemoryAvailable: true, Memory: 5, CPUAvailable: tc.readable}, created: tc.created, total: tc.total, at: now.Add(time.Duration(tc.second) * time.Second)}}
			}
			if tc.failed {
				readErr = errors.New("process enumeration failed")
			}
			got := c.collectProcesses(context.Background())
			if !tc.present {
				if len(got) != 0 || (!tc.failed && len(c.prevProcesses) != 0) {
					t.Fatal("missing processes retained output or baselines")
				}
				return
			}
			if len(got) != 1 || got[0].CPUAvailable != tc.available || got[0].CPU != tc.want || got[0].Memory != 5 {
				t.Fatalf("process readings = %+v, want available=%v CPU=%v and memory retained", got, tc.available, tc.want)
			}
			if !tc.readable && len(c.prevProcesses) != 0 {
				t.Fatal("failed CPU reading retained its baseline")
			}
		})
	}
}

func TestProcessCPUInterruptedScanPreservesUnvisitedBaselines(t *testing.T) {
	c := NewCollector()
	now := time.Now()
	makeSample := func(pid int32, second int, readable bool) processSample {
		return processSample{
			info:    ProcessInfo{PID: pid, MemoryAvailable: true, Memory: 1, CPUAvailable: readable},
			created: 1, total: float64(second), at: now.Add(time.Duration(second) * time.Second),
		}
	}
	samples := []processSample{makeSample(1, 0, true), makeSample(2, 0, true), makeSample(3, 0, true), makeSample(4, 0, true)}
	var readErr error
	c.processSamples = func(context.Context) ([]processSample, error) { return samples, readErr }
	c.collectProcesses(context.Background())

	// PID 1 was sampled, PID 3 failed, and the deadline left 2 and 4 unvisited.
	samples = []processSample{makeSample(1, 2, true), makeSample(3, 2, false)}
	readErr = context.DeadlineExceeded
	got := c.collectProcesses(context.Background())
	if len(got) != 2 || got[0].PID != 1 || !got[0].CPUAvailable || got[0].CPU != 100 || got[1].PID != 3 || got[1].CPUAvailable {
		t.Fatalf("incomplete scan lost fresh samples or returned stale rows: %+v", got)
	}
	if len(c.prevProcesses) != 3 || c.prevProcesses[1].total != 2 || c.prevProcesses[2].total != 0 || c.prevProcesses[4].total != 0 {
		t.Fatalf("interrupted scan discarded unvisited baselines: %+v", c.prevProcesses)
	}
	if _, exists := c.prevProcesses[3]; exists {
		t.Fatal("explicit failed CPU sample retained a baseline")
	}

	// A complete scan recovers PID 2 across the longer interval and prunes PID 4.
	samples = []processSample{makeSample(1, 4, true), makeSample(2, 4, true), makeSample(3, 4, true)}
	readErr = nil
	got = c.collectProcesses(context.Background())
	if len(got) != 3 || !got[0].CPUAvailable || got[0].CPU != 100 || !got[1].CPUAvailable || got[1].CPU != 100 || got[2].CPUAvailable {
		t.Fatalf("complete scan did not recover preserved baselines: %+v", got)
	}
	if _, exists := c.prevProcesses[4]; exists {
		t.Fatal("complete scan retained an exited process")
	}
	samples = []processSample{makeSample(4, 5, true)}
	if got = c.collectProcesses(context.Background()); len(got) != 1 || got[0].CPUAvailable {
		t.Fatalf("reappearing process reused a pruned baseline: %+v", got)
	}
}

func TestReadProcessSamplesReportsCanceledScan(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if samples, err := readProcessSamples(ctx); !errors.Is(err, context.Canceled) || len(samples) != 0 {
		t.Fatalf("canceled scan returned samples=%+v, err=%v", samples, err)
	}
}

func TestProcessCPUUnavailableSortAndView(t *testing.T) {
	processes := []ProcessInfo{
		{PID: 1, Name: "unmeasured", CPU: 999, MemoryAvailable: true, Memory: 80},
		{PID: 2, Name: "idle", CPUAvailable: true, MemoryAvailable: true, Memory: 1},
		{PID: 3, Name: "busy", CPUAvailable: true, CPU: 200, MemoryAvailable: true, Memory: 2},
	}
	sortProcesses(processes, false)
	if processes[0].PID != 3 || processes[1].PID != 2 || processes[2].PID != 1 {
		t.Fatalf("unavailable CPU outranked a measurement: %+v", processes)
	}
	m := newModel()
	m.ready, m.metrics.Processes = true, processes
	view := m.View()
	for _, want := range []string{"unmeasured (CPU: Unavailable, Mem: 80.0%)", "idle (CPU: 0.0%", "busy (CPU: 200.0%"} {
		if !strings.Contains(view, want) {
			t.Fatalf("missing %q in view: %s", want, view)
		}
	}
	sortProcesses(processes, true)
	if processes[0].PID != 1 {
		t.Fatal("unavailable CPU changed memory sorting")
	}
}

func TestProcessCPUKeepsBaselineForFilteredProcesses(t *testing.T) {
	c := NewCollector()
	sample := processSample{info: ProcessInfo{PID: 7, CPUAvailable: true}, created: 1, at: time.Now()}
	c.processSamples = func(context.Context) ([]processSample, error) { return []processSample{sample}, nil }
	if got := c.collectProcesses(context.Background()); len(got) != 0 {
		t.Fatal("idle process without significant memory should remain filtered")
	}
	sample.total, sample.at = 1, sample.at.Add(time.Second)
	got := c.collectProcesses(context.Background())
	if len(got) != 1 || !got[0].CPUAvailable || got[0].CPU != 100 {
		t.Fatalf("filtered process lost its baseline before becoming busy: %+v", got)
	}
}

func TestHealthOnlyCollectionSkipsProcesses(t *testing.T) {
	c := healthyCollector()
	c.processSamples = func(context.Context) ([]processSample, error) {
		t.Error("health-only JSON collection queried processes")
		return nil, nil
	}
	if got := c.collect(false); got.HealthScore != 100 || len(got.Processes) != 0 {
		t.Fatalf("health-only collection changed: %+v", got)
	}
}

func TestProcessCollectionSerializesOverlappingRefreshes(t *testing.T) {
	c := NewCollector()
	entered := make(chan struct{}, 2)
	release := make(chan struct{})
	finished := make(chan struct{}, 2)
	c.processSamples = func(context.Context) ([]processSample, error) {
		entered <- struct{}{}
		<-release
		return nil, nil
	}
	defer close(release)
	go func() { c.collectProcesses(context.Background()); finished <- struct{}{} }()
	<-entered
	go func() { c.collectProcesses(context.Background()); finished <- struct{}{} }()
	select {
	case <-entered:
		t.Fatal("process reads overlapped")
	case <-time.After(50 * time.Millisecond):
	}
	release <- struct{}{}
	<-finished
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("second collection did not resume")
	}
	release <- struct{}{}
	<-finished
}
