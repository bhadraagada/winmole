//go:build windows

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Styles
var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("205"))

	selectedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("229")).
			Background(lipgloss.Color("57")).
			Bold(true)

	normalStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("252"))

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240"))

	sizeStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("39")).
			Width(10).
			Align(lipgloss.Right)

	barStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("205"))

	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241"))
)

// Entry represents a file or directory
type Entry struct {
	Name  string
	Path  string
	Size  int64
	IsDir bool
}

// Model is the Bubble Tea model
type model struct {
	path         string
	entries      []Entry
	selected     int
	offset       int
	width        int
	height       int
	scanning     bool
	status       string
	totalSize    int64
	history      []historyEntry
	spinner      int
	filesScanned int64
	dirsScanned  int64
}

type historyEntry struct {
	Path     string
	Selected int
	Offset   int
}

// Messages
type scanResultMsg struct {
	entries   []Entry
	totalSize int64
	err       error
}

type tickMsg time.Time

var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

func main() {
	startPath := os.Getenv("WINMOLE_ANALYZE_PATH")
	if startPath == "" && len(os.Args) > 1 {
		startPath = os.Args[1]
	}
	if startPath == "" {
		startPath = os.Getenv("USERPROFILE")
	}

	absPath, err := filepath.Abs(startPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving path: %v\n", err)
		os.Exit(1)
	}

	p := tea.NewProgram(newModel(absPath), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func newModel(path string) model {
	return model{
		path:     path,
		status:   "Scanning...",
		scanning: true,
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(m.scanCmd(), tickCmd())
}

func (m model) scanCmd() tea.Cmd {
	return func() tea.Msg {
		entries, totalSize, err := scanDirectory(m.path, &m.filesScanned, &m.dirsScanned)
		return scanResultMsg{entries: entries, totalSize: totalSize, err: err}
	}
}

func tickCmd() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKey(msg)

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case scanResultMsg:
		m.scanning = false
		if msg.err != nil {
			m.status = fmt.Sprintf("Error: %v", msg.err)
			return m, nil
		}
		m.entries = msg.entries
		m.totalSize = msg.totalSize
		m.selected = 0
		m.offset = 0
		m.status = fmt.Sprintf("Total: %s", humanizeBytes(m.totalSize))
		return m, nil

	case tickMsg:
		if m.scanning {
			m.spinner = (m.spinner + 1) % len(spinnerFrames)
			files := atomic.LoadInt64(&m.filesScanned)
			dirs := atomic.LoadInt64(&m.dirsScanned)
			m.status = fmt.Sprintf("%s Scanning... %d files, %d dirs",
				spinnerFrames[m.spinner], files, dirs)
			return m, tickCmd()
		}
		return m, nil
	}

	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c", "esc":
		if len(m.history) > 0 {
			// Go back
			last := m.history[len(m.history)-1]
			m.history = m.history[:len(m.history)-1]
			m.path = last.Path
			m.selected = last.Selected
			m.offset = last.Offset
			m.scanning = true
			atomic.StoreInt64(&m.filesScanned, 0)
			atomic.StoreInt64(&m.dirsScanned, 0)
			return m, tea.Batch(m.scanCmd(), tickCmd())
		}
		return m, tea.Quit

	case "up", "k":
		if m.selected > 0 {
			m.selected--
			if m.selected < m.offset {
				m.offset = m.selected
			}
		}

	case "down", "j":
		if m.selected < len(m.entries)-1 {
			m.selected++
			viewportHeight := m.height - 6
			if m.selected >= m.offset+viewportHeight {
				m.offset = m.selected - viewportHeight + 1
			}
		}

	case "enter", "right", "l":
		if len(m.entries) > 0 && m.entries[m.selected].IsDir {
			// Save history
			m.history = append(m.history, historyEntry{
				Path:     m.path,
				Selected: m.selected,
				Offset:   m.offset,
			})
			m.path = m.entries[m.selected].Path
			m.scanning = true
			m.status = "Scanning..."
			atomic.StoreInt64(&m.filesScanned, 0)
			atomic.StoreInt64(&m.dirsScanned, 0)
			return m, tea.Batch(m.scanCmd(), tickCmd())
		}

	case "left", "h", "backspace":
		if len(m.history) > 0 {
			last := m.history[len(m.history)-1]
			m.history = m.history[:len(m.history)-1]
			m.path = last.Path
			m.selected = last.Selected
			m.offset = last.Offset
			m.scanning = true
			atomic.StoreInt64(&m.filesScanned, 0)
			atomic.StoreInt64(&m.dirsScanned, 0)
			return m, tea.Batch(m.scanCmd(), tickCmd())
		} else {
			// Go to parent
			parent := filepath.Dir(m.path)
			if parent != m.path {
				m.history = append(m.history, historyEntry{
					Path:     m.path,
					Selected: m.selected,
					Offset:   m.offset,
				})
				m.path = parent
				m.scanning = true
				atomic.StoreInt64(&m.filesScanned, 0)
				atomic.StoreInt64(&m.dirsScanned, 0)
				return m, tea.Batch(m.scanCmd(), tickCmd())
			}
		}

	case "r":
		m.scanning = true
		m.status = "Scanning..."
		atomic.StoreInt64(&m.filesScanned, 0)
		atomic.StoreInt64(&m.dirsScanned, 0)
		return m, tea.Batch(m.scanCmd(), tickCmd())
	}

	return m, nil
}

func (m model) View() string {
	var b strings.Builder

	// Header
	header := titleStyle.Render(fmt.Sprintf("📁 %s", m.path))
	b.WriteString(header)
	b.WriteString("\n\n")

	if m.scanning {
		b.WriteString(statusStyle.Render(m.status))
		b.WriteString("\n")
		return b.String()
	}

	if len(m.entries) == 0 {
		b.WriteString(dimStyle.Render("  (empty directory)"))
		b.WriteString("\n")
	} else {
		viewportHeight := m.height - 6
		if viewportHeight < 5 {
			viewportHeight = 5
		}

		endIdx := m.offset + viewportHeight
		if endIdx > len(m.entries) {
			endIdx = len(m.entries)
		}

		for i := m.offset; i < endIdx; i++ {
			entry := m.entries[i]

			// Size bar
			var barWidth int
			if m.totalSize > 0 {
				barWidth = int(float64(entry.Size) / float64(m.totalSize) * 20)
				if barWidth > 20 {
					barWidth = 20
				}
			}
			bar := strings.Repeat("█", barWidth) + strings.Repeat("░", 20-barWidth)

			// Icon
			icon := "📄"
			if entry.IsDir {
				icon = "📁"
			}

			// Format line
			size := sizeStyle.Render(humanizeBytes(entry.Size))
			barStr := barStyle.Render(bar)
			name := fmt.Sprintf("%s %s", icon, entry.Name)

			line := fmt.Sprintf("%s %s %s", size, barStr, name)

			if i == m.selected {
				b.WriteString(selectedStyle.Render(line))
			} else {
				b.WriteString(normalStyle.Render(line))
			}
			b.WriteString("\n")
		}
	}

	// Status bar
	b.WriteString("\n")
	b.WriteString(statusStyle.Render(m.status))
	b.WriteString("\n")
	b.WriteString(dimStyle.Render("↑/↓ navigate • Enter/→ open • ←/Backspace back • r refresh • q quit"))

	return b.String()
}

// scanDirectory scans a directory and returns entries sorted by size
func scanDirectory(path string, filesScanned, dirsScanned *int64) ([]Entry, int64, error) {
	var entries []Entry
	var totalSize int64
	var mu sync.Mutex

	dirEntries, err := os.ReadDir(path)
	if err != nil {
		return nil, 0, err
	}

	var wg sync.WaitGroup
	sem := make(chan struct{}, 10) // Limit concurrent goroutines

	for _, de := range dirEntries {
		de := de
		wg.Add(1)
		sem <- struct{}{}

		go func() {
			defer wg.Done()
			defer func() { <-sem }()

			fullPath := filepath.Join(path, de.Name())
			var size int64

			if de.IsDir() {
				atomic.AddInt64(dirsScanned, 1)
				size = getDirSize(fullPath, filesScanned, dirsScanned)
			} else {
				atomic.AddInt64(filesScanned, 1)
				if info, err := de.Info(); err == nil {
					size = info.Size()
				}
			}

			mu.Lock()
			entries = append(entries, Entry{
				Name:  de.Name(),
				Path:  fullPath,
				Size:  size,
				IsDir: de.IsDir(),
			})
			totalSize += size
			mu.Unlock()
		}()
	}

	wg.Wait()

	// Sort by size descending
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Size > entries[j].Size
	})

	return entries, totalSize, nil
}

// getDirSize calculates the total size of a directory
func getDirSize(path string, filesScanned, dirsScanned *int64) int64 {
	var size int64

	filepath.WalkDir(path, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return nil // Skip errors
		}

		if d.IsDir() {
			atomic.AddInt64(dirsScanned, 1)
		} else {
			atomic.AddInt64(filesScanned, 1)
			if info, err := d.Info(); err == nil {
				size += info.Size()
			}
		}
		return nil
	})

	return size
}

// humanizeBytes converts bytes to human-readable format
func humanizeBytes(bytes int64) string {
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
