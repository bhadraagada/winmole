package main

import (
	"strings"
	"testing"
)

func TestReportViews(t *testing.T) {
	s, err := decodeStatus([]byte(`{"collected_at":"2026-11-28T10:00:00Z","health":{"available":false,"score":null},"cpu":{"available":true,"percent":0},"memory":{"available":false,"percent":null},"disks_complete":false,"disks":[{"available":true,"mountpoint":"C:\\","total_bytes":10240,"free_bytes":0}]}`))
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Join(statusLines(s), "|")
	for _, s := range []string{"CPU  ·  0.0%", "Memory  ·  Unavailable", "0 B free of 10.0 KiB", "Partial disk list"} {
		if !strings.Contains(lines, s) {
			t.Errorf("missing %q in %s", s, lines)
		}
	}

	d, err := decodeDisk([]byte(`{"path":"C:\\Fixture","total_bytes":16384,"partial":true,"partial_reasons":["read_error","timeout"],"entries":[{"name":"資料","path":"C:\\Fixture\\資料","size_bytes":16384,"is_directory":true,"partial":true}]}`))
	if err != nil {
		t.Fatal(err)
	}
	if got := diskRows(d)[0]; got != "資料  ·  16.0 KiB  ·  Folder  ·  Partial" {
		t.Fatalf("unexpected row: %s", got)
	}
	if got := reasonsText(d.PartialReasons); got != "some files could not be read, scan time limit" {
		t.Fatalf("unexpected reasons: %s", got)
	}
}

func TestRejectInvalidOrUnexpectedReports(t *testing.T) {
	for _, malformed := range []string{"null", "{}", "{", `{"path":"x","entries":[]}`, `{"path":"x","partial":false,"entries":[{"name":"a","path":"a","size_bytes":-1}]}`, `{"path":"x","partial":false,"entries":[]} {}`} {
		if _, err := decodeDisk([]byte(malformed)); err == nil {
			t.Errorf("accepted unexpected analyzer output %q", malformed)
		}
	}
	if _, err := decodeStatus([]byte(`{"collected_at":"2026-11-28T10:00:00Z","disks_complete":true}`)); err == nil {
		t.Error("missing disks treated as a success")
	}
	if _, err := decodeDisk([]byte(strings.Repeat(" ", maxReportBytes+1))); err == nil {
		t.Error("oversized report accepted")
	}
}

func TestByteShare(t *testing.T) {
	if p, ok := shareOfObservedBytes(512, 2048); !ok || p != 25 {
		t.Fatalf("unexpected share: %v %v", p, ok)
	}
	if p, ok := shareOfObservedBytes(0, 2048); !ok || p != 0 {
		t.Fatalf("measured zero should hold: %v %v", p, ok)
	}
	for _, values := range [][2]int64{{1, 0}, {3, 2}, {-1, 2}} {
		if _, ok := shareOfObservedBytes(values[0], values[1]); ok {
			t.Fatalf("invalid ratio %v", values)
		}
	}
}
