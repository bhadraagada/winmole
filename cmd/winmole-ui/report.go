package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"strings"
	"time"
)

const maxReportBytes = 8 << 20

type reading struct {
	Available bool     `json:"available"`
	Percent   *float64 `json:"percent"`
	Score     *int     `json:"score"`
	Message   string   `json:"message"`
}

type diskReading struct {
	Available  bool   `json:"available"`
	Mountpoint string `json:"mountpoint"`
	Free       *int64 `json:"free_bytes"`
	Total      *int64 `json:"total_bytes"`
}

type statusReport struct {
	CollectedAt   time.Time     `json:"collected_at"`
	Health        reading       `json:"health"`
	CPU           reading       `json:"cpu"`
	Memory        reading       `json:"memory"`
	Swap          reading       `json:"swap"`
	DisksComplete *bool         `json:"disks_complete"`
	Disks         []diskReading `json:"disks"`
}

type entry struct {
	Name           string   `json:"name"`
	Path           string   `json:"path"`
	Size           int64    `json:"size_bytes"`
	Directory      bool     `json:"is_directory"`
	Partial        bool     `json:"partial"`
	PartialReasons []string `json:"partial_reasons"`
}

type diskReport struct {
	Path           string   `json:"path"`
	Total          int64    `json:"total_bytes"`
	Partial        *bool    `json:"partial"`
	PartialReasons []string `json:"partial_reasons"`
	Entries        []entry  `json:"entries"`
}

func decodeReport(data []byte, dest any) error {
	if len(data) > maxReportBytes {
		return errors.New("report exceeds display limit; try a smaller folder")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	if err := decoder.Decode(dest); err != nil {
		return fmt.Errorf("unreadable report: %w", err)
	}
	if err := decoder.Decode(new(json.RawMessage)); err != io.EOF {
		return errors.New("expected one report with no extra output")
	}
	return nil
}

func decodeStatus(data []byte) (statusReport, error) {
	var r statusReport
	if err := decodeReport(data, &r); err != nil {
		return r, err
	}
	if r.CollectedAt.IsZero() || r.DisksComplete == nil || r.Disks == nil {
		return r, errors.New("status helper returned an incomplete report")
	}
	return r, nil
}

func decodeDisk(data []byte) (diskReport, error) {
	var r diskReport
	if err := decodeReport(data, &r); err != nil {
		return r, err
	}
	if strings.TrimSpace(r.Path) == "" || r.Total < 0 || r.Partial == nil || r.Entries == nil {
		return r, errors.New("analyzer returned an incomplete report")
	}
	for _, item := range r.Entries {
		if item.Name == "" || item.Path == "" || item.Size < 0 {
			return r, errors.New("analyzer returned an invalid entry")
		}
	}
	return r, nil
}

func formatBytes(n int64) string {
	const unit = 1024
	value := float64(n)
	for _, label := range []string{"B", "KiB", "MiB", "GiB", "TiB", "PiB"} {
		if label == "B" && n < unit {
			return fmt.Sprintf("%d B", n)
		}
		if value < unit || label == "PiB" {
			return fmt.Sprintf("%.1f %s", value, label)
		}
		value /= unit
	}
	return ""
}

func shareOfObservedBytes(size, total int64) (float64, bool) {
	if total <= 0 || size < 0 || size > total {
		return 0, false
	}
	return float64(size) / float64(total) * 100, true
}

func utilization(v reading) string {
	if !v.Available || v.Percent == nil || math.IsNaN(*v.Percent) || math.IsInf(*v.Percent, 0) || *v.Percent < 0 || *v.Percent > 100 {
		return "Unavailable"
	}
	return fmt.Sprintf("%.1f%%", *v.Percent)
}

func reasonsText(reasons []string) string {
	seen := make(map[string]bool)
	labels := make([]string, 0, len(reasons))
	for _, why := range reasons {
		switch why {
		case "timeout":
			why = "scan time limit"
		case "file_limit":
			why = "file count limit"
		case "read_error":
			why = "some files could not be read"
		default:
			why = "other scan limit"
		}
		if !seen[why] {
			labels = append(labels, why)
			seen[why] = true
		}
	}
	if len(labels) == 0 {
		return "reason unavailable"
	}
	return strings.Join(labels, ", ")
}

func diskRows(r diskReport) []string {
	lines := make([]string, 0, len(r.Entries))
	for _, item := range r.Entries {
		kind := "File"
		if item.Directory {
			kind = "Folder"
		}
		var qualifier string
		if item.Partial {
			qualifier = "  ·  Partial"
		}
		lines = append(lines, fmt.Sprintf("%s  ·  %s  ·  %s%s", item.Name, formatBytes(item.Size), kind, qualifier))
	}
	return lines
}

func statusLines(r statusReport) []string {
	lines := []string{
		"CPU  ·  " + utilization(r.CPU),
		"Memory  ·  " + utilization(r.Memory),
		"Swap  ·  " + utilization(r.Swap),
	}
	if r.Health.Available && r.Health.Score != nil {
		lines = append(lines, fmt.Sprintf("Health  ·  %d/100  ·  %s", *r.Health.Score, r.Health.Message))
	} else {
		lines = append(lines, "Health  ·  Unavailable")
	}
	for _, d := range r.Disks {
		detail := "Unavailable"
		if d.Available && d.Free != nil && d.Total != nil && *d.Free >= 0 && *d.Total >= *d.Free {
			detail = formatBytes(*d.Free) + " free of " + formatBytes(*d.Total)
		}
		lines = append(lines, d.Mountpoint+"  ·  "+detail)
	}
	if r.DisksComplete != nil && !*r.DisksComplete {
		lines = append(lines, "Partial disk list  ·  Some drives could not be read.")
	}
	return lines
}
