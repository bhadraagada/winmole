//go:build windows

package main

import (
	"encoding/json"
	"io"
	"time"
)

type statusReport struct {
	CollectedAt   time.Time     `json:"collected_at"`
	Health        healthReading `json:"health"`
	CPU           cpuReading    `json:"cpu"`
	Memory        memoryReading `json:"memory"`
	Swap          memoryReading `json:"swap"`
	DisksComplete bool          `json:"disks_complete"`
	Disks         []diskReading `json:"disks"`
}

type healthReading struct {
	Available bool   `json:"available"`
	Score     *int   `json:"score"`
	Message   string `json:"message"`
}

type cpuReading struct {
	Available bool     `json:"available"`
	Percent   *float64 `json:"percent"`
}

type memoryReading struct {
	Available  bool     `json:"available"`
	TotalBytes *uint64  `json:"total_bytes"`
	UsedBytes  *uint64  `json:"used_bytes"`
	Percent    *float64 `json:"percent"`
}

type diskReading struct {
	Available   bool     `json:"available"`
	Device      string   `json:"device"`
	Mountpoint  string   `json:"mountpoint"`
	TotalBytes  *uint64  `json:"total_bytes"`
	UsedBytes   *uint64  `json:"used_bytes"`
	FreeBytes   *uint64  `json:"free_bytes"`
	UsedPercent *float64 `json:"used_percent"`
}

func writeJSONReport(output io.Writer, s MetricsSnapshot) error {
	report := statusReport{
		CollectedAt:   s.CollectedAt,
		Health:        healthReading{Available: s.HealthScore >= 0, Message: s.HealthMessage},
		CPU:           cpuReading{Available: s.CPUAvailable},
		Memory:        memoryReading{Available: s.MemAvailable},
		Swap:          memoryReading{Available: s.SwapAvailable},
		DisksComplete: s.DisksComplete,
		Disks:         make([]diskReading, 0, len(s.Disks)),
	}
	// Unavailable measurements are null; measured zero remains a usable value.
	if report.Health.Available {
		report.Health.Score = &s.HealthScore
	}
	if s.CPUAvailable {
		report.CPU.Percent = &s.CPUPercent
	}
	if s.MemAvailable {
		report.Memory.TotalBytes = &s.MemTotal
		report.Memory.UsedBytes = &s.MemUsed
		report.Memory.Percent = &s.MemPercent
	}
	if s.SwapAvailable {
		report.Swap.TotalBytes = &s.SwapTotal
		report.Swap.UsedBytes = &s.SwapUsed
		report.Swap.Percent = &s.SwapPercent
	}
	for _, d := range s.Disks {
		reading := diskReading{Available: d.Available, Device: d.Device, Mountpoint: d.Mountpoint}
		if d.Available {
			reading.TotalBytes = &d.Total
			reading.UsedBytes = &d.Used
			reading.FreeBytes = &d.Free
			reading.UsedPercent = &d.UsedPercent
		}
		report.Disks = append(report.Disks, reading)
	}
	return json.NewEncoder(output).Encode(report)
}
