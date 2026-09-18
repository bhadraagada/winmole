//go:build windows

package main

import (
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/charmbracelet/x/ansi"
)

func TestTruncateStringDisplayWidth(t *testing.T) {
	for _, tc := range []struct {
		name, input, want string
		width             int
	}{
		{"ASCII fits", "Ethernet", "Ethernet", 20},
		{"ASCII overflow", strings.Repeat("a", 21), strings.Repeat("a", 17) + "...", 20},
		{"Chinese fits", "网络连接适配器", "网络连接适配器", 20},
		{"wide overflow", strings.Repeat("界", 11), strings.Repeat("界", 8) + "...", 20},
		{"combining fits", strings.Repeat("e\u0301", 20), strings.Repeat("e\u0301", 20), 20},
		{"combining overflow", strings.Repeat("e\u0301", 21), strings.Repeat("e\u0301", 17) + "...", 20},
		{"emoji fits", strings.Repeat("👩‍💻", 10), strings.Repeat("👩‍💻", 10), 20},
		{"emoji overflow", strings.Repeat("👩‍💻", 11), strings.Repeat("👩‍💻", 8) + "...", 20},
		{"empty", "", "", 20},
		{"no room", "Ethernet", "", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := truncateString(tc.input, tc.width)
			if got != tc.want || !utf8.ValidString(got) || ansi.StringWidth(got) > tc.width {
				t.Fatalf("truncateString(%q, %d) = %q, want %q within %d cells", tc.input, tc.width, got, tc.want, tc.width)
			}
		})
	}
}

func TestViewPreservesUnicodeLabels(t *testing.T) {
	m := newModel()
	updated, _ := m.Update(metricsMsg(MetricsSnapshot{
		CPUModel:  strings.Repeat("界", 26),
		Processes: []ProcessInfo{{PID: 1, Name: "网络连接适配器", CPU: 10}},
		Networks:  []NetworkInfo{{Name: strings.Repeat("👩‍💻", 11)}},
	}))
	view := updated.View()
	if !utf8.ValidString(view) {
		t.Fatal("dashboard contains invalid UTF-8")
	}
	for _, label := range []string{
		strings.Repeat("界", 23) + "...",
		"网络连接适配器",
		strings.Repeat("👩‍💻", 8) + "...:",
	} {
		if !strings.Contains(view, label) {
			t.Errorf("dashboard missing label %q", label)
		}
	}
}
