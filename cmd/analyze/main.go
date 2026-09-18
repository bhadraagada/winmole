//go:build windows

package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rivo/uniseg"
)

// Scanning limits. These are runaway guards, not accuracy trade-offs: a
// directory is walked to its full depth so reported sizes match Explorer.
// Sibling directories are sized concurrently, so the timeout below bounds
// wall-clock time for the whole listing, not the sum of its entries.
const (
	dirSizeTimeout = 15 * time.Second // Max time to size a single directory
	maxFilesPerDir = 2000000          // Runaway guard on files per directory tree
)

// ANSI color codes
const (
	colorReset      = "\033[0m"
	colorBold       = "\033[1m"
	colorDim        = "\033[2m"
	colorPurple     = "\033[35m"
	colorPurpleBold = "\033[1;35m"
	colorCyan       = "\033[36m"
	colorCyanBold   = "\033[1;36m"
	colorYellow     = "\033[33m"
	colorGreen      = "\033[32m"
	colorRed        = "\033[31m"
	colorGray       = "\033[90m"
	colorWhite      = "\033[97m"
)

// Icons
const (
	iconFolder   = "📁"
	iconFile     = "📄"
	iconDisk     = "💾"
	iconClean    = "🧹"
	iconTrash    = "🗑️"
	iconBack     = "⬅️"
	iconSelected = "✓"
	iconArrow    = "➤"
)

// Cleanable directory patterns
var cleanablePatterns = map[string]bool{
	"node_modules":  true,
	"vendor":        true,
	".venv":         true,
	"venv":          true,
	"__pycache__":   true,
	".pytest_cache": true,
	"target":        true,
	"build":         true,
	"dist":          true,
	".next":         true,
	".nuxt":         true,
	".turbo":        true,
	".parcel-cache": true,
	"bin":           true,
	"obj":           true,
	".gradle":       true,
	".idea":         true,
	".vs":           true,
}

// Skip patterns for scanning
var skipPatterns = map[string]bool{
	"$Recycle.Bin":              true,
	"System Volume Information": true,
	"Windows":                   true,
	"Program Files":             true,
	"Program Files (x86)":       true,
	"ProgramData":               true,
	"Recovery":                  true,
	"Config.Msi":                true,
}

// Protected paths that should NEVER be deleted
var protectedPaths = []string{
	`C:\Windows`,
	`C:\Program Files`,
	`C:\Program Files (x86)`,
	`C:\ProgramData`,
	`C:\Users\Default`,
	`C:\Users\Public`,
	`C:\Recovery`,
	`C:\System Volume Information`,
}

// isProtectedPath checks if a path is protected from deletion
func isProtectedPath(path string) bool {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return true // If we can't resolve the path, treat it as protected
	}
	absPath = strings.ToLower(absPath)

	// Check against protected paths
	for _, protected := range protectedPaths {
		protectedLower := strings.ToLower(protected)
		if absPath == protectedLower || strings.HasPrefix(absPath, protectedLower+`\`) {
			return true
		}
	}

	// Check against skip patterns (system directories)
	baseName := strings.ToLower(filepath.Base(absPath))
	for pattern := range skipPatterns {
		if strings.ToLower(pattern) == baseName {
			// Only protect if it's at a root level (e.g., C:\Windows, not C:\Projects\Windows)
			parent := filepath.Dir(absPath)
			if len(parent) <= 3 { // e.g., "C:\"
				return true
			}
		}
	}

	// Protect Windows directory itself
	winDir := strings.ToLower(os.Getenv("WINDIR"))
	sysRoot := strings.ToLower(os.Getenv("SYSTEMROOT"))
	if winDir != "" && (absPath == winDir || strings.HasPrefix(absPath, winDir+`\`)) {
		return true
	}
	if sysRoot != "" && (absPath == sysRoot || strings.HasPrefix(absPath, sysRoot+`\`)) {
		return true
	}

	return false
}

// Entry types
type dirEntry struct {
	Name        string
	Path        string
	Size        int64
	IsDir       bool
	LastAccess  time.Time
	IsCleanable bool
	Partial     bool // Size is a lower bound: the walk hit the timeout or an unreadable subtree
}

type fileEntry struct {
	Name string
	Path string
	Size int64
}

type historyEntry struct {
	Path       string
	Entries    []dirEntry
	LargeFiles []fileEntry
	TotalSize  int64
	Selected   int
}

// Model for Bubble Tea
type model struct {
	path           string
	entries        []dirEntry
	largeFiles     []fileEntry
	history        []historyEntry
	selected       int
	totalSize      int64
	scanning       bool
	showLargeFiles bool
	multiSelected  map[string]bool
	deleteConfirm  bool
	deleteTarget   string   // Display name for confirmation
	deleteTargets  []string // Actual paths to delete (for multi-delete)
	scanProgress   int64
	scanTotal      int64
	width          int
	height         int
	err            error
	cache          map[string]historyEntry
}

// Messages
type scanCompleteMsg struct {
	entries    []dirEntry
	largeFiles []fileEntry
	totalSize  int64
}

type scanProgressMsg struct {
	current int64
	total   int64
}

type scanErrorMsg struct {
	err error
}

type deleteCompleteMsg struct {
	path string
	err  error
}

func newModel(startPath string) model {
	return model{
		path:          startPath,
		entries:       []dirEntry{},
		largeFiles:    []fileEntry{},
		history:       []historyEntry{},
		selected:      0,
		scanning:      true,
		multiSelected: make(map[string]bool),
		cache:         make(map[string]historyEntry),
	}
}

func (m model) Init() tea.Cmd {
	return m.scanPath(m.path)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKeyPress(msg)
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case scanCompleteMsg:
		m.err = nil
		m.entries = msg.entries
		m.largeFiles = msg.largeFiles
		m.totalSize = msg.totalSize
		m.scanning = false
		m.selected = 0
		// Cache result
		m.cache[m.path] = historyEntry{
			Path:       m.path,
			Entries:    msg.entries,
			LargeFiles: msg.largeFiles,
			TotalSize:  msg.totalSize,
		}
		return m, nil
	case scanProgressMsg:
		m.scanProgress = msg.current
		m.scanTotal = msg.total
		return m, nil
	case scanErrorMsg:
		m.err = msg.err
		m.scanning = false
		m.entries = nil
		m.largeFiles = nil
		m.totalSize = 0
		m.selected = 0
		m.multiSelected = make(map[string]bool)
		return m, nil
	case deleteCompleteMsg:
		m.deleteConfirm = false
		m.deleteTarget = ""
		if msg.err != nil {
			m.err = msg.err
		} else {
			// Rescan after delete
			m.scanning = true
			delete(m.cache, m.path)
			return m, m.scanPath(m.path)
		}
		return m, nil
	}
	return m, nil
}

func (m model) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Keep the displayed path and its entries together until the scan finishes.
	if m.scanning {
		if msg.String() == "q" || msg.String() == "ctrl+c" {
			return m, tea.Quit
		}
		return m, nil
	}

	// Handle delete confirmation
	if m.deleteConfirm {
		switch msg.String() {
		case "y", "Y":
			m.deleteConfirm = false
			if len(m.deleteTargets) > 0 {
				// Multi-delete
				targets := m.deleteTargets
				m.deleteTargets = nil
				m.deleteTarget = ""
				return m, m.deletePaths(targets)
			}
			// Single delete
			target := m.deleteTarget
			m.deleteTarget = ""
			return m, m.deletePath(target)
		case "n", "N", "esc":
			m.deleteConfirm = false
			m.deleteTarget = ""
			m.deleteTargets = nil
			return m, nil
		}
		return m, nil
	}

	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "up", "k":
		if m.selected > 0 {
			m.selected--
		}
	case "down", "j":
		if m.selected < len(m.entries)-1 {
			m.selected++
		}
	case "enter", "right", "l":
		if !m.scanning && len(m.entries) > 0 {
			entry := m.entries[m.selected]
			if entry.IsDir {
				// Save current state to history
				m.history = append(m.history, historyEntry{
					Path:       m.path,
					Entries:    m.entries,
					LargeFiles: m.largeFiles,
					TotalSize:  m.totalSize,
					Selected:   m.selected,
				})
				m.path = entry.Path
				m.selected = 0
				m.multiSelected = make(map[string]bool)

				// Check cache
				if cached, ok := m.cache[entry.Path]; ok {
					m.err = nil
					m.entries = cached.Entries
					m.largeFiles = cached.LargeFiles
					m.totalSize = cached.TotalSize
					return m, nil
				}

				m.scanning = true
				return m, m.scanPath(entry.Path)
			}
		}
	case "left", "h", "backspace":
		if len(m.history) > 0 {
			m.err = nil
			last := m.history[len(m.history)-1]
			m.history = m.history[:len(m.history)-1]
			m.path = last.Path
			m.entries = last.Entries
			m.largeFiles = last.LargeFiles
			m.totalSize = last.TotalSize
			m.selected = last.Selected
			m.multiSelected = make(map[string]bool)
			m.scanning = false
		} else if parent := filepath.Dir(m.path); parent != m.path {
			m.path = parent
			m.selected = 0
			m.multiSelected = make(map[string]bool)
			m.scanning = true
			return m, m.scanPath(parent)
		}
	case "space":
		if len(m.entries) > 0 {
			entry := m.entries[m.selected]
			if m.multiSelected[entry.Path] {
				delete(m.multiSelected, entry.Path)
			} else {
				m.multiSelected[entry.Path] = true
			}
		}
	case "d", "delete":
		if len(m.entries) > 0 {
			entry := m.entries[m.selected]
			m.deleteConfirm = true
			m.deleteTarget = entry.Path
		}
	case "D":
		// Delete all selected
		if len(m.multiSelected) > 0 {
			m.deleteConfirm = true
			// Collect paths for deletion
			var paths []string
			for path := range m.multiSelected {
				paths = append(paths, path)
			}
			m.deleteTargets = paths
			m.deleteTarget = fmt.Sprintf("%d items", len(paths))
		}
	case "f":
		m.showLargeFiles = !m.showLargeFiles
	case "r":
		// Refresh
		delete(m.cache, m.path)
		m.scanning = true
		return m, m.scanPath(m.path)
	case "o":
		// Open in Explorer
		if len(m.entries) > 0 {
			entry := m.entries[m.selected]
			openInExplorer(entry.Path)
		}
	case "g":
		m.selected = 0
	case "G":
		if len(m.entries) > 0 {
			m.selected = len(m.entries) - 1
		}
	}
	return m, nil
}

func (m model) View() string {
	var b strings.Builder

	// Header
	b.WriteString(fmt.Sprintf("%s%s WinMole Disk Analyzer %s\n", colorPurpleBold, iconDisk, colorReset))
	b.WriteString(fmt.Sprintf("%s%s%s\n", colorGray, m.path, colorReset))
	b.WriteString("\n")

	// Show delete confirmation
	if m.deleteConfirm {
		b.WriteString(fmt.Sprintf("%s%s Delete %s? (y/n)%s\n", colorRed, iconTrash, m.deleteTarget, colorReset))
		return b.String()
	}

	// Scanning indicator
	if m.scanning {
		b.WriteString(fmt.Sprintf("%s⠋ Scanning...%s\n", colorCyan, colorReset))
		if m.scanTotal > 0 {
			b.WriteString(fmt.Sprintf("%s  %d / %d items%s\n", colorGray, m.scanProgress, m.scanTotal, colorReset))
		}
		return b.String()
	}

	// Error display
	if m.err != nil {
		b.WriteString(fmt.Sprintf("%sError: %v%s\n", colorRed, m.err, colorReset))
		b.WriteString("\n")
	}

	// Total size. Flag it as a lower bound when any child was truncated, so an
	// under-count is visible rather than silently wrong.
	anyPartial := false
	for _, e := range m.entries {
		if e.Partial {
			anyPartial = true
			break
		}
	}
	if anyPartial {
		b.WriteString(fmt.Sprintf("  Total: %s≥ %s%s %s(+ = partial: timed out or unreadable)%s\n",
			colorYellow, formatBytes(m.totalSize), colorReset, colorGray, colorReset))
	} else {
		b.WriteString(fmt.Sprintf("  Total: %s%s%s\n", colorYellow, formatBytes(m.totalSize), colorReset))
	}
	b.WriteString("\n")

	// Large files toggle
	if m.showLargeFiles && len(m.largeFiles) > 0 {
		b.WriteString(fmt.Sprintf("%s%s Large Files (>100MB):%s\n", colorCyanBold, iconFile, colorReset))
		for i, f := range m.largeFiles {
			if i >= 10 {
				b.WriteString(fmt.Sprintf("  %s... and %d more%s\n", colorGray, len(m.largeFiles)-10, colorReset))
				break
			}
			b.WriteString(fmt.Sprintf("  %s%s%s %s\n", colorYellow, formatBytes(f.Size), colorReset, truncatePath(f.Path, 60)))
		}
		b.WriteString("\n")
	}

	// Directory entries
	visibleEntries := m.height - 12
	if visibleEntries < 5 {
		visibleEntries = 20
	}

	start := 0
	if m.selected >= visibleEntries {
		start = m.selected - visibleEntries + 1
	}

	for i := start; i < len(m.entries) && i < start+visibleEntries; i++ {
		entry := m.entries[i]
		prefix := "  "

		// Selection indicator
		if i == m.selected {
			prefix = fmt.Sprintf("%s%s%s ", colorCyan, iconArrow, colorReset)
		} else if m.multiSelected[entry.Path] {
			prefix = fmt.Sprintf("%s%s%s ", colorGreen, iconSelected, colorReset)
		}

		// Icon
		icon := iconFile
		if entry.IsDir {
			icon = iconFolder
		}
		if entry.IsCleanable {
			icon = iconClean
		}

		// Size and percentage
		pct := float64(0)
		if m.totalSize > 0 {
			pct = float64(entry.Size) / float64(m.totalSize) * 100
		}

		// Bar
		barWidth := 20
		filled := int(pct / 100 * float64(barWidth))
		bar := strings.Repeat("█", filled) + strings.Repeat("░", barWidth-filled)

		// Color based on selection
		nameColor := colorReset
		if i == m.selected {
			nameColor = colorCyanBold
		}

		sizeText := formatBytes(entry.Size)
		if entry.Partial {
			sizeText += "+"
		}

		b.WriteString(fmt.Sprintf("%s%s %s%8s%s %s%s%s %s%.1f%%%s %s\n",
			prefix,
			icon,
			colorYellow, sizeText, colorReset,
			colorGray, bar, colorReset,
			colorDim, pct, colorReset,
			nameColor+entry.Name+colorReset,
		))
	}

	// Footer with keybindings
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("%s↑↓%s navigate  %s↵%s enter  %s←%s back  %sf%s files  %sd%s delete  %sr%s refresh  %sq%s quit%s\n",
		colorCyan, colorReset,
		colorCyan, colorReset,
		colorCyan, colorReset,
		colorCyan, colorReset,
		colorCyan, colorReset,
		colorCyan, colorReset,
		colorCyan, colorReset,
		colorReset,
	))

	return b.String()
}

// scanPath scans a directory and returns entries
func (m model) scanPath(path string) tea.Cmd {
	return func() tea.Msg {
		entries, largeFiles, totalSize, err := scanDirectory(path)
		if err != nil {
			return scanErrorMsg{err: err}
		}
		return scanCompleteMsg{
			entries:    entries,
			largeFiles: largeFiles,
			totalSize:  totalSize,
		}
	}
}

// checkDeletionMode runs when the command executes, including after confirmation.
func checkDeletionMode() error {
	if os.Getenv("WINMOLE_DRY_RUN") == "1" {
		return fmt.Errorf("deletion disabled while WINMOLE_DRY_RUN=1; no files were deleted")
	}
	return nil
}

// deletePath deletes a file or directory with protection checks
func (m model) deletePath(path string) tea.Cmd {
	return func() tea.Msg {
		if err := checkDeletionMode(); err != nil {
			return deleteCompleteMsg{path: path, err: err}
		}
		// Safety check: never delete protected paths
		if isProtectedPath(path) {
			return deleteCompleteMsg{
				path: path,
				err:  fmt.Errorf("cannot delete protected system path: %s", path),
			}
		}

		err := os.RemoveAll(path)
		return deleteCompleteMsg{path: path, err: err}
	}
}

// deletePaths deletes multiple files or directories with protection checks
func (m model) deletePaths(paths []string) tea.Cmd {
	return func() tea.Msg {
		if err := checkDeletionMode(); err != nil {
			return deleteCompleteMsg{path: fmt.Sprintf("%d items", len(paths)), err: err}
		}
		var errors []string
		for _, path := range paths {
			// Safety check: never delete protected paths
			if isProtectedPath(path) {
				errors = append(errors, fmt.Sprintf("protected: %s", path))
				continue
			}
			if err := os.RemoveAll(path); err != nil {
				errors = append(errors, fmt.Sprintf("%s: %v", path, err))
			}
		}
		if len(errors) > 0 {
			return deleteCompleteMsg{
				path: fmt.Sprintf("%d items", len(paths)),
				err:  fmt.Errorf("failed to delete some items: %s", strings.Join(errors, "; ")),
			}
		}
		return deleteCompleteMsg{path: fmt.Sprintf("%d items", len(paths)), err: nil}
	}
}

// scanDirectory scans a directory concurrently
func scanDirectory(path string) ([]dirEntry, []fileEntry, int64, error) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, nil, 0, err
	}

	var (
		dirEntries []dirEntry
		largeFiles []fileEntry
		totalSize  int64
		mu         sync.Mutex
		wg         sync.WaitGroup
	)

	numWorkers := runtime.NumCPU() * 2
	if numWorkers > 32 {
		numWorkers = 32
	}

	sem := make(chan struct{}, numWorkers)
	var processedCount int64

	for _, entry := range entries {
		name := entry.Name()
		entryPath := filepath.Join(path, name)

		// System directories are listed and measured like any other. Excluding
		// them here made the reported total fall far below what Explorer shows;
		// deletion is guarded separately by isProtectedPath.

		wg.Add(1)
		sem <- struct{}{}

		go func(name, entryPath string, isDir bool) {
			defer wg.Done()
			defer func() { <-sem }()

			var size int64
			var lastAccess time.Time
			var isCleanable bool
			var partial bool

			if isDir {
				size, partial = calculateDirSize(entryPath)
				isCleanable = cleanablePatterns[name]
			} else {
				info, err := os.Stat(entryPath)
				if err == nil {
					size = info.Size()
					lastAccess = info.ModTime()
				} else {
					partial = true
				}
			}

			mu.Lock()
			defer mu.Unlock()

			dirEntries = append(dirEntries, dirEntry{
				Name:        name,
				Path:        entryPath,
				Size:        size,
				IsDir:       isDir,
				LastAccess:  lastAccess,
				IsCleanable: isCleanable,
				Partial:     partial,
			})

			totalSize += size

			// Track large files
			if !isDir && size >= 100*1024*1024 {
				largeFiles = append(largeFiles, fileEntry{
					Name: name,
					Path: entryPath,
					Size: size,
				})
			}

			atomic.AddInt64(&processedCount, 1)
		}(name, entryPath, entry.IsDir())
	}

	wg.Wait()

	// Sort by size descending
	sort.Slice(dirEntries, func(i, j int) bool {
		return dirEntries[i].Size > dirEntries[j].Size
	})

	sort.Slice(largeFiles, func(i, j int) bool {
		return largeFiles[i].Size > largeFiles[j].Size
	})

	return dirEntries, largeFiles, totalSize, nil
}

// isReparsePoint reports whether info describes a junction, symlink or other
// reparse point. Recursing into these double-counts space and can loop forever:
// %LOCALAPPDATA%\Application Data is a junction back to its own parent.
func isReparsePoint(info os.FileInfo) bool {
	if d, ok := info.Sys().(*syscall.Win32FileAttributeData); ok {
		return d.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0
	}
	// Fall back to the portable bit if the Windows attributes are unavailable.
	return info.Mode()&os.ModeSymlink != 0
}

// calculateDirSize returns the total size of a directory tree. The second
// result reports whether the walk was cut short by the timeout or the file
// guard, in which case the size is a lower bound rather than the real total.
func calculateDirSize(path string) (int64, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), dirSizeTimeout)
	defer cancel()

	var size int64
	var fileCount int64
	var truncated atomic.Bool

	// Use a channel to signal completion
	done := make(chan struct{})

	go func() {
		defer close(done)
		walkDirSize(ctx, path, &size, &fileCount, &truncated)
	}()

	select {
	case <-done:
		// Completed normally
	case <-ctx.Done():
		// Timeout - return partial size (already accumulated)
		truncated.Store(true)
	}

	return atomic.LoadInt64(&size), truncated.Load()
}

// walkDirSize sums every file in a directory tree. It walks to full depth and
// does not filter by name: skipPatterns exists to keep the *delete* path away
// from system directories, and applying it here was hiding real space (for
// example AppData\Local\Microsoft\Windows, which matched the bare name
// "Windows" at every level). Dot-directories are counted too; .gradle, .nuget
// and friends are often the largest thing in a user profile.
func walkDirSize(ctx context.Context, path string, size *int64, fileCount *int64, truncated *atomic.Bool) {
	// Check context cancellation
	select {
	case <-ctx.Done():
		truncated.Store(true)
		return
	default:
	}

	// Limit total files scanned
	if atomic.LoadInt64(fileCount) > maxFilesPerDir {
		truncated.Store(true)
		return
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		// Unreadable subtree (permissions, locked file): its contents are
		// missing from the total, so the caller must not trust the number.
		truncated.Store(true)
		return
	}

	for _, entry := range entries {
		// Check cancellation
		select {
		case <-ctx.Done():
			truncated.Store(true)
			return
		default:
		}

		if atomic.LoadInt64(fileCount) > maxFilesPerDir {
			truncated.Store(true)
			return
		}

		entryPath := filepath.Join(path, entry.Name())

		info, err := entry.Info()
		if err != nil {
			truncated.Store(true)
			continue
		}

		if entry.IsDir() {
			if isReparsePoint(info) {
				continue
			}
			walkDirSize(ctx, entryPath, size, fileCount, truncated)
		} else {
			atomic.AddInt64(size, info.Size())
			atomic.AddInt64(fileCount, 1)
		}
	}
}

// formatBytes formats bytes to human readable string
func formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

// truncatePath keeps the filename suffix within maxLen display cells without
// splitting wide characters, combining marks, or joined emoji.
func truncatePath(path string, maxLen int) string {
	if maxLen <= 0 {
		return ""
	}
	width := uniseg.StringWidth(path)
	if width <= maxLen {
		return path
	}
	if maxLen <= 3 {
		return strings.Repeat(".", maxLen)
	}
	graphemes := uniseg.NewGraphemes(path)
	start := 0
	for width > maxLen-3 && graphemes.Next() {
		width -= graphemes.Width()
		_, start = graphemes.Positions()
	}
	return "..." + path[start:]
}

// openInExplorer opens a path in Windows Explorer
func openInExplorer(path string) {
	// Use explorer.exe to open the path
	go func() {
		exec.Command("explorer.exe", "/select,", path).Run()
	}()
}

func main() {
	var startPath string
	var jsonOutput bool

	flag.StringVar(&startPath, "path", "", "Path to analyze")
	flag.BoolVar(&jsonOutput, "json", false, "Print a read-only JSON disk usage report")
	flag.Parse()

	// Check environment variable
	if startPath == "" {
		startPath = os.Getenv("WINMOLE_ANALYZE_PATH")
	}

	// Use command line argument
	if startPath == "" && len(flag.Args()) > 0 {
		startPath = flag.Args()[0]
	}

	// Default to user profile
	if startPath == "" {
		startPath = os.Getenv("USERPROFILE")
	}

	// Resolve to absolute path
	absPath, err := filepath.Abs(startPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if jsonOutput {
		if err := writeJSONReport(os.Stdout, absPath); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	// Check if path exists
	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "Error: Path does not exist: %s\n", absPath)
		os.Exit(1)
	}

	p := tea.NewProgram(newModel(absPath), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
