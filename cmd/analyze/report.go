//go:build windows

package main

import (
	"encoding/json"
	"io"
	"path/filepath"
	"sort"
)

type diskReport struct {
	Path           string        `json:"path"`
	TotalBytes     int64         `json:"total_bytes"`
	Partial        bool          `json:"partial"`
	PartialReasons []string      `json:"partial_reasons,omitempty"`
	Entries        []reportEntry `json:"entries"`
}

type reportEntry struct {
	Name           string   `json:"name"`
	Path           string   `json:"path"`
	SizeBytes      int64    `json:"size_bytes"`
	IsDirectory    bool     `json:"is_directory"`
	Partial        bool     `json:"partial"`
	PartialReasons []string `json:"partial_reasons,omitempty"`
}

func writeJSONReport(output io.Writer, path string) error {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	entries, _, total, err := scanDirectory(absPath)
	if err != nil {
		return err
	}

	return json.NewEncoder(output).Encode(newDiskReport(absPath, entries, total))
}

func newDiskReport(path string, entries []dirEntry, total int64) diskReport {
	report := diskReport{Path: path, TotalBytes: total, Entries: make([]reportEntry, 0, len(entries))}
	var reasons partialReasons
	for _, entry := range entries {
		report.Partial = report.Partial || entry.Partial
		reasons |= entry.PartialReasons
		report.Entries = append(report.Entries, reportEntry{
			Name: entry.Name, Path: entry.Path, SizeBytes: entry.Size,
			IsDirectory: entry.IsDir, Partial: entry.Partial,
			PartialReasons: entry.PartialReasons.codes(),
		})
	}
	report.PartialReasons = reasons.codes()
	// Concurrent scanning has no stable arrival order for equally sized entries.
	sort.Slice(report.Entries, func(i, j int) bool {
		if report.Entries[i].SizeBytes == report.Entries[j].SizeBytes {
			return report.Entries[i].Name < report.Entries[j].Name
		}
		return report.Entries[i].SizeBytes > report.Entries[j].SizeBytes
	})
	return report
}
