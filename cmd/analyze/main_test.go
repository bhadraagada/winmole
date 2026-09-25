//go:build windows

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rivo/uniseg"
)

func TestTruncatePath(t *testing.T) {
	for _, tt := range []struct {
		name, path string
		width      int
		want       string
	}{
		{"empty", "", 8, ""},
		{"negative", "abc", -1, ""},
		{"zero", "abc", 0, ""},
		{"one", "abcdef", 1, "."},
		{"two", "abcdef", 2, ".."},
		{"three", "abcdef", 3, "..."},
		{"short", "ab", 3, "ab"},
		{"ASCII", `C:\folder\file.bin`, 11, "...file.bin"},
		{"CJK fits", "中文", 4, "中文"},
		{"CJK suffix", "abcdef中文.txt", 11, "...中文.txt"},
		{"wide boundary", "abc界x", 5, "...x"},
		{"combining suffix", "abcdefe\u0301xy", 6, "...e\u0301xy"},
		{"combining boundary", "abcdefe\u0301xy", 5, "...xy"},
		{"emoji suffix", "abcdef👩‍💻xy", 7, "...👩‍💻xy"},
		{"emoji boundary", "abcdef👩‍💻x", 5, "...x"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got := truncatePath(tt.path, tt.width)
			if got != tt.want {
				t.Errorf("truncatePath(%q, %d) = %q, want %q", tt.path, tt.width, got, tt.want)
			}
			if !utf8.ValidString(got) || uniseg.StringWidth(got) > max(tt.width, 0) {
				t.Errorf("invalid UTF-8 or display width exceeded: %q", got)
			}
		})
	}
}

func TestLargeFilesViewPreservesUnicodeSuffix(t *testing.T) {
	m := newModel(`C:\fixture`)
	m.scanning = false
	m.showLargeFiles = true
	m.largeFiles = []fileEntry{{Path: `C:\` + strings.Repeat("界", 40) + ".bin", Size: 128 * 1024 * 1024}}
	view := m.View()
	want := " ..." + strings.Repeat("界", 26) + ".bin\n"
	if !utf8.ValidString(view) || !strings.Contains(view, want) {
		t.Errorf("large-file view lost the 60-column Unicode suffix: %q", view)
	}
}

// writeFile creates a file of exactly size bytes, making parents as needed.
func writeFile(t *testing.T, path string, size int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, make([]byte, size), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

// TestCalculateDirSizeCountsDeepTree covers the primary cause of issue #13:
// sizes were computed with a depth cap of 3, so anything deeper was invisible.
// A real profile nests much deeper than that (AppData\Local\Packages\<app>\...).
func TestCalculateDirSizeCountsDeepTree(t *testing.T) {
	root := t.TempDir()

	// One file at each level, 1 KiB each, well past the old shallow cap.
	want := 0
	path := root
	for depth := 0; depth < 12; depth++ {
		path = filepath.Join(path, "level")
		writeFile(t, filepath.Join(path, "f.bin"), 1024)
		want += 1024
	}

	got, partial := calculateDirSize(root)
	if partial {
		t.Errorf("scan reported partial for a small tree")
	}
	if got != int64(want) {
		t.Errorf("size = %d, want %d (deep files were skipped)", got, want)
	}
}

// TestCalculateDirSizeCountsSystemNamedDirs covers the second cause: skipPatterns
// was matched on the bare directory name at every depth, so a nested directory
// called "Windows" was dropped. %LOCALAPPDATA%\Microsoft\Windows is exactly this
// case and holds INetCache, WebCache and Explorer thumbnails.
func TestCalculateDirSizeCountsSystemNamedDirs(t *testing.T) {
	root := t.TempDir()

	writeFile(t, filepath.Join(root, "Microsoft", "Windows", "INetCache", "a.bin"), 4096)
	writeFile(t, filepath.Join(root, "Program Files", "b.bin"), 2048)
	writeFile(t, filepath.Join(root, "ProgramData", "c.bin"), 1024)

	got, _ := calculateDirSize(root)
	if want := int64(4096 + 2048 + 1024); got != want {
		t.Errorf("size = %d, want %d (system-named subdirectories were skipped)", got, want)
	}
}

// TestCalculateDirSizeCountsDotDirs covers the third cause: directories starting
// with "." were skipped as "hidden", but .gradle/.nuget/.cache are frequently
// the largest thing in a user profile.
func TestCalculateDirSizeCountsDotDirs(t *testing.T) {
	root := t.TempDir()

	writeFile(t, filepath.Join(root, ".gradle", "caches", "big.bin"), 8192)
	writeFile(t, filepath.Join(root, "visible", "small.bin"), 512)

	got, _ := calculateDirSize(root)
	if want := int64(8192 + 512); got != want {
		t.Errorf("size = %d, want %d (dot-directories were skipped)", got, want)
	}
}

// TestCalculateDirSizeSkipsJunctionLoop guards the change that made a full-depth
// walk safe. %LOCALAPPDATA%\Application Data is a junction pointing at its own
// parent; without the reparse-point check, removing the depth cap would recurse
// until the path length limit. The old depth cap was masking this.
func TestCalculateDirSizeSkipsJunctionLoop(t *testing.T) {
	root := t.TempDir()

	real := filepath.Join(root, "real")
	writeFile(t, filepath.Join(real, "f.bin"), 2048)

	// Junctions (unlike symlinks) do not require elevation.
	link := filepath.Join(root, "loop")
	if err := exec.Command("cmd", "/c", "mklink", "/J", link, root).Run(); err != nil {
		t.Skipf("could not create junction (needed for this test): %v", err)
	}

	got, _ := calculateDirSize(root)
	if want := int64(2048); got != want {
		t.Errorf("size = %d, want %d (junction was followed and double-counted)", got, want)
	}
}

// TestScanDirectoryListsSystemDirs covers the reported symptom that whole
// directories were missing from the listing: scanDirectory dropped any entry
// matching skipPatterns, so analyzing C:\ omitted Windows and Program Files
// from both the list and the total.
func TestScanDirectoryListsSystemDirs(t *testing.T) {
	root := t.TempDir()

	writeFile(t, filepath.Join(root, "Windows", "a.bin"), 1024)
	writeFile(t, filepath.Join(root, "Program Files", "b.bin"), 1024)
	writeFile(t, filepath.Join(root, "AppData", "c.bin"), 1024)

	entries, _, total, err := scanDirectory(root)
	if err != nil {
		t.Fatalf("scanDirectory: %v", err)
	}

	seen := make(map[string]bool, len(entries))
	for _, e := range entries {
		seen[e.Name] = true
	}
	for _, name := range []string{"Windows", "Program Files", "AppData"} {
		if !seen[name] {
			t.Errorf("entry %q missing from listing", name)
		}
	}
	if want := int64(3072); total != want {
		t.Errorf("total = %d, want %d", total, want)
	}
}

// TestIsProtectedPathStillGuardsSystemDirs pins the safety boundary: measuring
// system directories is now allowed, but deleting them must still be refused.
func TestIsProtectedPathStillGuardsSystemDirs(t *testing.T) {
	for _, p := range []string{
		`C:\Windows`,
		`C:\Windows\System32`,
		`C:\Program Files`,
		`C:\Program Files (x86)\Something`,
		`C:\ProgramData`,
		`C:\Users\Default`,
	} {
		if !isProtectedPath(p) {
			t.Errorf("isProtectedPath(%q) = false, want true", p)
		}
	}

	// A user directory that merely shares a system name must stay deletable.
	unprotected := filepath.Join(t.TempDir(), "project", "build")
	if isProtectedPath(unprotected) {
		t.Errorf("isProtectedPath(%q) = true, want false", unprotected)
	}
}

func TestDeleteCommandsRespectDryRun(t *testing.T) {
	root := t.TempDir()
	file := filepath.Join(root, "ordinary.txt")
	directory := filepath.Join(root, "project")
	child := filepath.Join(directory, "nested", "keep.txt")
	writeFile(t, file, 32)
	writeFile(t, child, 64)
	m := newModel(root)
	m.scanning = false

	// Create commands before enabling preview to cover delayed confirmation.
	single := m.deletePath(directory)
	batch := m.deletePaths([]string{file, directory})
	t.Setenv("WINMOLE_DRY_RUN", "1")
	for _, command := range []struct {
		name string
		run  tea.Cmd
	}{
		{"single", single},
		{"batch", batch},
	} {
		t.Run(command.name, func(t *testing.T) {
			result := command.run().(deleteCompleteMsg)
			if result.err == nil || !strings.Contains(result.err.Error(), "WINMOLE_DRY_RUN=1") {
				t.Fatalf("expected an explicit dry-run refusal, got %v", result.err)
			}
			updated, next := m.Update(result)
			if next != nil || updated.(model).scanning {
				t.Fatal("dry-run refusal was treated as a successful deletion")
			}
			for path, size := range map[string]int{file: 32, child: 64} {
				content, err := os.ReadFile(path)
				if err != nil || len(content) != size {
					t.Fatalf("dry-run changed %s: %v", path, err)
				}
			}
		})
	}
}
