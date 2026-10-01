//go:build windows

package main

import (
	"context"
	"maps"
	"time"

	"github.com/shirou/gopsutil/v3/process"
)

type processSample struct {
	info    ProcessInfo
	created int64
	total   float64
	at      time.Time
}

func readProcessSamples(ctx context.Context) ([]processSample, error) {
	procs, err := process.ProcessesWithContext(ctx)
	if err != nil {
		return nil, err
	}
	var samples []processSample
	for _, p := range procs {
		if ctx.Err() != nil {
			break
		}
		name, err := p.NameWithContext(ctx)
		if err != nil {
			continue
		}
		sample := processSample{info: ProcessInfo{PID: p.Pid, Name: name}}
		created, err := p.CreateTimeWithContext(ctx)
		if err == nil && created > 0 {
			if times, err := p.TimesWithContext(ctx); err == nil && times != nil {
				sample.created, sample.total, sample.at = created, times.Total(), time.Now()
				sample.info.CPUAvailable = true
			}
		}
		if memory, err := p.MemoryPercentWithContext(ctx); err == nil {
			sample.info.Memory = memory
		}
		samples = append(samples, sample)
	}
	return samples, ctx.Err()
}

func (c *Collector) collectProcesses(ctx context.Context) []ProcessInfo {
	// Keep samples ordered even when manual and scheduled refreshes overlap.
	// A separate lock leaves network sampling independent of process queries.
	c.processMu.Lock()
	defer c.processMu.Unlock()
	samples, err := c.processSamples(ctx)
	current := make(map[int32]processSample, len(samples))
	if err != nil {
		// An interrupted scan says nothing about processes it did not reach.
		maps.Copy(current, c.prevProcesses)
	}
	var infos []ProcessInfo
	for _, sample := range samples {
		info := sample.info
		info.CPU, info.CPUAvailable = 0, false
		delete(current, info.PID)
		if sample.info.CPUAvailable {
			previous, exists := c.prevProcesses[info.PID]
			elapsed := sample.at.Sub(previous.at).Seconds()
			if exists && sample.created == previous.created && elapsed > 0 && sample.total >= previous.total {
				// Like gopsutil, 100% means one logical CPU, not the whole machine.
				info.CPU = 100 * (sample.total - previous.total) / elapsed
				info.CPUAvailable = true
			}
			current[info.PID] = sample
		}
		if info.CPU > 0.1 || info.Memory > 0.1 {
			infos = append(infos, info)
		}
	}
	// Complete scans prune exited processes; failed CPU readings always reset.
	c.prevProcesses = current
	return infos
}
