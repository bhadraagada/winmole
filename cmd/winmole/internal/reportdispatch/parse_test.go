package reportdispatch

import "testing"

func TestParseNativeReports(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want Request
	}{
		{"default CWD", []string{"analyze", "--json"}, Request{Analyze, ""}},
		{"positional before JSON", []string{"analyze", ".", "--json"}, Request{Analyze, "."}},
		{"positional after JSON", []string{"AnAlYzE", "-JsOn", "folder [Ω] & punctuation"}, Request{Analyze, "folder [Ω] & punctuation"}},
		{"relative directory starting with dash", []string{"analyze", `.\-existing`, "--json"}, Request{Analyze, `.\-existing`}},
		{"named path equals", []string{"analyze", "--PaTh=C:\\dir with spaces", "--JSON"}, Request{Analyze, "C:\\dir with spaces"}},
		{"named path colon", []string{"analyze", "-Path:..\\foreign=directory", "--json"}, Request{Analyze, "..\\foreign=directory"}},
		{"UNC path", []string{"analyze", `\\server\share\a`, "-Json"}, Request{Analyze, `\\server\share\a`}},
		{"status JSON", []string{"StAtUs", "--JSON"}, Request{Status, ""}},
		{"repeated true switch", []string{"status", "-Json", "--JSON"}, Request{Status, ""}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := Parse(tc.args)
			if !ok || got != tc.want {
				t.Fatalf("Parse(%q) = %+v, %v; want %+v, true", tc.args, got, ok, tc.want)
			}
		})
	}
}

func TestParseKeepsLegacyAndAmbiguousCalls(t *testing.T) {
	for _, args := range [][]string{
		nil, {"analyze"}, {"analyze", "."}, {"status"}, {"clean", "--json"}, {"purge", "--json"},
		{"uninstall", "--json"}, {"optimize", "--json"}, {"help", "--json"},
		{"analyze", "--help", "--json"}, {"status", "-Help", "-Json"},
		{"analyze", "-Json:false"}, {"status", "--json=true"}, {"status", "--json=false", "--json"},
		{"analyze", "--json", "--delete"}, {"analyze", "--json", "--dry-run"},
		{"analyze", "one", "two", "--json"}, {"analyze", "-Path", ".", "--json"},
		{"analyze", "-Path=one", "--path:two", "--json"}, {"analyze", "-Path=", "--json"},
		{"analyze", "'quoted'", "--json"}, {"analyze", "FileSystem::C:\\a", "--json"},
		{"analyze", "env:TEST", "--json"}, {"analyze", "C:relative", "--json"},
		{"analyze", "--", "-file", "--json"}, {"status", "extra", "--json"},
	} {
		if got, ok := Parse(args); ok {
			t.Errorf("Parse(%q) unexpectedly dispatched %+v", args, got)
		}
	}
}
