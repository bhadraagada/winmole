//go:build windows

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestJSONReport(t *testing.T) {
	root := filepath.Join(t.TempDir(), "space [literal]")
	writeFile(t, filepath.Join(root, "z.bin"), 3)
	writeFile(t, filepath.Join(root, "a.bin"), 3)
	writeFile(t, filepath.Join(root, "nested", "deep", "data.bin"), 7)
	want := diskReport{Path: root, TotalBytes: 13, Entries: []reportEntry{
		{Name: "nested", Path: filepath.Join(root, "nested"), SizeBytes: 7, IsDirectory: true},
		{Name: "a.bin", Path: filepath.Join(root, "a.bin"), SizeBytes: 3},
		{Name: "z.bin", Path: filepath.Join(root, "z.bin"), SizeBytes: 3},
	}}
	var previous string
	for range 5 {
		var output bytes.Buffer
		if err := writeJSONReport(&output, filepath.Join(root, ".")); err != nil {
			t.Fatal(err)
		}
		var got diskReport
		if err := json.Unmarshal(output.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("report = %#v, want %#v", got, want)
		}
		roundTrip, err := json.Marshal(got)
		if err != nil {
			t.Fatal(err)
		}
		if string(roundTrip)+"\n" != output.String() {
			t.Fatalf("JSON schema did not round-trip: %s", output.String())
		}
		if previous != "" && previous != output.String() {
			t.Fatal("report changed between identical scans")
		}
		previous = output.String()
	}
	if !strings.Contains(previous, `"partial":false`) || !strings.Contains(previous, `"is_directory":false`) {
		t.Fatalf("false values must be explicit: %s", previous)
	}
	if strings.Contains(previous, `"partial_reasons"`) {
		t.Fatalf("complete report must omit partial reasons: %s", previous)
	}
}

func TestJSONReportPartialReasons(t *testing.T) {
	entries := []dirEntry{
		{Name: "read", Size: 2, Partial: true, PartialReasons: partialReadError},
		{Name: "complete", Size: 1},
		{Name: "limited", Size: 4, Partial: true, PartialReasons: partialReadError | partialFileLimit},
		{Name: "timed", Size: 3, Partial: true, PartialReasons: partialTimeout},
	}
	data, err := json.Marshal(newDiskReport("fixture", entries, 10))
	if err != nil {
		t.Fatal(err)
	}
	var got diskReport
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	want := []string{"timeout", "file_limit", "read_error"}
	if !got.Partial || got.TotalBytes != 10 || !reflect.DeepEqual(got.PartialReasons, want) {
		t.Fatalf("report lost sizes or stable deduplicated causes: %s", data)
	}
	wantEntries := []reportEntry{
		{Name: "limited", SizeBytes: 4, Partial: true, PartialReasons: []string{"file_limit", "read_error"}},
		{Name: "timed", SizeBytes: 3, Partial: true, PartialReasons: []string{"timeout"}},
		{Name: "read", SizeBytes: 2, Partial: true, PartialReasons: []string{"read_error"}},
		{Name: "complete", SizeBytes: 1},
	}
	if !reflect.DeepEqual(got.Entries, wantEntries) {
		t.Fatalf("entry reasons/sorting = %#v, want %#v", got.Entries, wantEntries)
	}
	if !reflect.DeepEqual(entries[0].PartialReasons.codes(), []string{"read_error"}) {
		t.Fatal("report aggregation mutated an entry's causes")
	}
}

func TestJSONReportEmptyAndErrors(t *testing.T) {
	root := t.TempDir()
	var output bytes.Buffer
	if err := writeJSONReport(&output, root); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), `"entries":[]`) {
		t.Fatalf("empty entries must be an array: %s", output.String())
	}
	file := filepath.Join(root, "file.bin")
	writeFile(t, file, 1)
	for _, path := range []string{file, filepath.Join(root, "missing")} {
		output.Reset()
		if err := writeJSONReport(&output, path); err == nil {
			t.Fatalf("expected an error for %q", path)
		}
		if output.Len() != 0 {
			t.Fatalf("failed scan emitted JSON: %s", output.String())
		}
	}
	closed, err := os.CreateTemp(root, "output")
	if err != nil {
		t.Fatal(err)
	}
	if err := closed.Close(); err != nil {
		t.Fatal(err)
	}
	if err := writeJSONReport(closed, root); err == nil {
		t.Fatal("expected output write error")
	}
}

func TestJSONReportMarksUnreadableEntryPartial(t *testing.T) {
	root := t.TempDir()
	link := filepath.Join(root, "missing-target")
	target := filepath.Join(t.TempDir(), "does-not-exist")
	if output, err := exec.Command("cmd", "/c", "mklink", "/J", link, target).CombinedOutput(); err != nil {
		t.Skipf("junction creation unavailable: %v: %s", err, output)
	}
	var output bytes.Buffer
	if err := writeJSONReport(&output, root); err != nil {
		t.Fatal(err)
	}
	var got diskReport
	if err := json.Unmarshal(output.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if !got.Partial || len(got.Entries) != 1 || !got.Entries[0].Partial {
		t.Fatalf("unreadable entry must mark both entry and report partial: %s", output.String())
	}
	if !reflect.DeepEqual(got.PartialReasons, []string{"read_error"}) || !reflect.DeepEqual(got.Entries[0].PartialReasons, []string{"read_error"}) {
		t.Fatalf("unreadable entry must explain both partial flags: %s", output.String())
	}
}

func TestAnalyzerJSONCLI(t *testing.T) {
	binary := filepath.Join(t.TempDir(), "analyze.exe")
	if output, err := exec.Command("go", "build", "-o", binary, ".").CombinedOutput(); err != nil {
		t.Fatalf("build analyzer: %v: %s", err, output)
	}
	root := filepath.Join(t.TempDir(), "space [literal]")
	writeFile(t, filepath.Join(root, "file.bin"), 11)
	other := t.TempDir()
	for _, tc := range []struct {
		name string
		args []string
		env  string
		want string
		fail bool
	}{
		{name: "flag", args: []string{"-json", "-path", root}, want: root},
		{name: "positional", args: []string{"-json", root}, want: root},
		{name: "environment", args: []string{"-json", other}, env: root, want: root},
		{name: "flag precedence", args: []string{"-json", "-path", root, other}, env: other, want: root},
		{name: "profile", args: []string{"-json"}, want: root},
		{name: "missing", args: []string{"-json", "-path", filepath.Join(root, "missing")}, fail: true},
		{name: "file", args: []string{"-json", "-path", filepath.Join(root, "file.bin")}, fail: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, binary, tc.args...)
			cmd.Env = append(os.Environ(), "WINMOLE_ANALYZE_PATH="+tc.env, "USERPROFILE="+root)
			var stdout, stderr bytes.Buffer
			cmd.Stdout, cmd.Stderr = &stdout, &stderr
			err := cmd.Run()
			if ctx.Err() != nil {
				t.Fatal("JSON mode did not exit without a terminal")
			}
			if tc.fail {
				if err == nil || stdout.Len() != 0 || stderr.Len() == 0 {
					t.Fatalf("want nonzero exit, empty stdout and error stderr; got %v, %q, %q", err, stdout.String(), stderr.String())
				}
				return
			}
			if err != nil || stderr.Len() != 0 {
				t.Fatalf("JSON command failed: %v: %s", err, stderr.String())
			}
			var got diskReport
			if err := json.Unmarshal(stdout.Bytes(), &got); err != nil {
				t.Fatalf("stdout is not a single JSON report: %v: %q", err, stdout.String())
			}
			if got.Path != tc.want || got.TotalBytes != 11 || got.Partial {
				t.Fatalf("unexpected report: %s", stdout.String())
			}
		})
	}
}
