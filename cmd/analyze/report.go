//go:build windows

package main

import (
	"encoding/json"
	"io"
	"path/filepath"
	"sort"
)

type diskReport struct {
	Path       string        `json:"path"`
	TotalBytes int64         `json:"total_bytes"`
	Partial    bool          `json:"partial"`
	Entries    []reportEntry `json:"entries"`
}

type reportEntry struct {
	Name        string `json:"name"`
	Path        string `json:"path"`
	SizeBytes   int64  `json:"size_bytes"`
	IsDirectory bool   `json:"is_directory"`
	Partial     bool   `json:"partial"`
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

	report := diskReport{Path: absPath, TotalBytes: total, Entries: make([]reportEntry, 0, len(entries))}
	for _, entry := range entries {
		report.Partial = report.Partial || entry.Partial
		report.Entries = append(report.Entries, reportEntry{
			Name: entry.Name, Path: entry.Path, SizeBytes: entry.Size,
			IsDirectory: entry.IsDir, Partial: entry.Partial,
		})
	}
	// Concurrent scanning has no stable arrival order for equally sized entries.
	sort.Slice(report.Entries, func(i, j int) bool {
		if report.Entries[i].SizeBytes == report.Entries[j].SizeBytes {
			return report.Entries[i].Name < report.Entries[j].Name
		}
		return report.Entries[i].SizeBytes > report.Entries[j].SizeBytes
	})
	return json.NewEncoder(output).Encode(report)
}
