//go:build windows

package main

import (
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
)

// Styles
var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("205")).
			MarginBottom(1)

	cardStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("62")).
			Padding(0, 1).
			MarginRight(1)

	labelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241"))

	valueStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("229")).
			Bold(true)

	barEmptyStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240"))

	barLowStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("42"))

	barMedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("226"))

	barHighStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("196"))

	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241"))
)

// Metrics holds all system metrics
type Metrics struct {
	// CPU
	CPUUsage float64
	CPUCores int
	CPUModel string

	// Memory
	MemTotal   uint64
	MemUsed    uint64
	MemPercent float64

	// Disk
	DiskTotal   uint64
	DiskUsed    uint64
	DiskPercent float64
	DiskPath    string

	// Network
	NetSent     uint64
	NetRecv     uint64
	NetSentRate float64
	NetRecvRate float64

	// System
	Hostname string
	OS       string
	Uptime   time.Duration

	// Timestamp
	CollectedAt time.Time
}

type model struct {
	metrics     Metrics
	prevMetrics Metrics
	width       int
	height      int
	ready       bool
	animFrame   int
}

// Messages
type metricsMsg Metrics
type tickMsg time.Time

func main() {
	p := tea.NewProgram(newModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func newModel() model {
	return model{}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(collectMetrics(), tick())
}

func collectMetrics() tea.Cmd {
	return func() tea.Msg {
		var metrics Metrics
		metrics.CollectedAt = time.Now()

		// CPU
		if cpuPercent, err := cpu.Percent(0, false); err == nil && len(cpuPercent) > 0 {
			metrics.CPUUsage = cpuPercent[0]
		}
		metrics.CPUCores = runtime.NumCPU()
		if cpuInfo, err := cpu.Info(); err == nil && len(cpuInfo) > 0 {
			metrics.CPUModel = cpuInfo[0].ModelName
		}

		// Memory
		if memInfo, err := mem.VirtualMemory(); err == nil {
			metrics.MemTotal = memInfo.Total
			metrics.MemUsed = memInfo.Used
			metrics.MemPercent = memInfo.UsedPercent
		}

		// Disk (system drive)
		systemDrive := os.Getenv("SystemDrive")
		if systemDrive == "" {
			systemDrive = "C:"
		}
		metrics.DiskPath = systemDrive
		if diskInfo, err := disk.Usage(systemDrive + "\\"); err == nil {
			metrics.DiskTotal = diskInfo.Total
			metrics.DiskUsed = diskInfo.Used
			metrics.DiskPercent = diskInfo.UsedPercent
		}

		// Network
		if netInfo, err := net.IOCounters(false); err == nil && len(netInfo) > 0 {
			metrics.NetSent = netInfo[0].BytesSent
			metrics.NetRecv = netInfo[0].BytesRecv
		}

		// System info
		if hostInfo, err := host.Info(); err == nil {
			metrics.Hostname = hostInfo.Hostname
			metrics.OS = fmt.Sprintf("%s %s", hostInfo.Platform, hostInfo.PlatformVersion)
			metrics.Uptime = time.Duration(hostInfo.Uptime) * time.Second
		}

		return metricsMsg(metrics)
	}
}

func tick() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			return m, tea.Quit
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case metricsMsg:
		m.prevMetrics = m.metrics
		m.metrics = Metrics(msg)

		// Calculate network rates
		if !m.prevMetrics.CollectedAt.IsZero() {
			elapsed := m.metrics.CollectedAt.Sub(m.prevMetrics.CollectedAt).Seconds()
			if elapsed > 0 {
				m.metrics.NetSentRate = float64(m.metrics.NetSent-m.prevMetrics.NetSent) / elapsed
				m.metrics.NetRecvRate = float64(m.metrics.NetRecv-m.prevMetrics.NetRecv) / elapsed
			}
		}

		m.ready = true
		return m, nil

	case tickMsg:
		m.animFrame++
		return m, tea.Batch(collectMetrics(), tick())
	}

	return m, nil
}

func (m model) View() string {
	if !m.ready {
		return "\n  Loading..."
	}

	var b strings.Builder

	// Header
	header := titleStyle.Render("📊 WinMole System Status")
	b.WriteString(header)
	b.WriteString("\n")

	// System info line
	sysInfo := fmt.Sprintf("%s • %s • Uptime: %s",
		m.metrics.Hostname,
		m.metrics.OS,
		formatDuration(m.metrics.Uptime))
	b.WriteString(statusStyle.Render(sysInfo))
	b.WriteString("\n\n")

	// Cards
	cpuCard := m.renderCPUCard()
	memCard := m.renderMemoryCard()
	diskCard := m.renderDiskCard()
	netCard := m.renderNetworkCard()

	// Layout cards
	row1 := lipgloss.JoinHorizontal(lipgloss.Top, cpuCard, memCard)
	row2 := lipgloss.JoinHorizontal(lipgloss.Top, diskCard, netCard)

	b.WriteString(row1)
	b.WriteString("\n")
	b.WriteString(row2)

	// Footer
	b.WriteString("\n\n")
	b.WriteString(statusStyle.Render("Press 'q' to quit"))

	return b.String()
}

func (m model) renderCPUCard() string {
	var content strings.Builder

	content.WriteString(valueStyle.Render("CPU"))
	content.WriteString("\n")
	content.WriteString(labelStyle.Render(truncateString(m.metrics.CPUModel, 30)))
	content.WriteString("\n\n")

	// Usage bar
	content.WriteString(labelStyle.Render("Usage: "))
	content.WriteString(renderBar(m.metrics.CPUUsage, 20))
	content.WriteString(fmt.Sprintf(" %.1f%%", m.metrics.CPUUsage))
	content.WriteString("\n")

	// Cores
	content.WriteString(labelStyle.Render(fmt.Sprintf("Cores: %d", m.metrics.CPUCores)))

	return cardStyle.Width(40).Render(content.String())
}

func (m model) renderMemoryCard() string {
	var content strings.Builder

	content.WriteString(valueStyle.Render("Memory"))
	content.WriteString("\n")
	content.WriteString(labelStyle.Render(fmt.Sprintf("%s / %s",
		humanizeBytes(m.metrics.MemUsed),
		humanizeBytes(m.metrics.MemTotal))))
	content.WriteString("\n\n")

	// Usage bar
	content.WriteString(labelStyle.Render("Usage: "))
	content.WriteString(renderBar(m.metrics.MemPercent, 20))
	content.WriteString(fmt.Sprintf(" %.1f%%", m.metrics.MemPercent))

	return cardStyle.Width(40).Render(content.String())
}

func (m model) renderDiskCard() string {
	var content strings.Builder

	content.WriteString(valueStyle.Render("Disk (" + m.metrics.DiskPath + ")"))
	content.WriteString("\n")
	content.WriteString(labelStyle.Render(fmt.Sprintf("%s / %s",
		humanizeBytes(m.metrics.DiskUsed),
		humanizeBytes(m.metrics.DiskTotal))))
	content.WriteString("\n\n")

	// Usage bar
	content.WriteString(labelStyle.Render("Usage: "))
	content.WriteString(renderBar(m.metrics.DiskPercent, 20))
	content.WriteString(fmt.Sprintf(" %.1f%%", m.metrics.DiskPercent))

	return cardStyle.Width(40).Render(content.String())
}

func (m model) renderNetworkCard() string {
	var content strings.Builder

	content.WriteString(valueStyle.Render("Network"))
	content.WriteString("\n")
	content.WriteString(labelStyle.Render("Traffic rates"))
	content.WriteString("\n\n")

	// Upload/Download rates
	content.WriteString(labelStyle.Render("↑ Upload:   "))
	content.WriteString(valueStyle.Render(fmt.Sprintf("%s/s", humanizeBytes(uint64(m.metrics.NetSentRate)))))
	content.WriteString("\n")
	content.WriteString(labelStyle.Render("↓ Download: "))
	content.WriteString(valueStyle.Render(fmt.Sprintf("%s/s", humanizeBytes(uint64(m.metrics.NetRecvRate)))))

	return cardStyle.Width(40).Render(content.String())
}

func renderBar(percent float64, width int) string {
	filled := int(percent / 100.0 * float64(width))
	if filled > width {
		filled = width
	}
	empty := width - filled

	var style lipgloss.Style
	switch {
	case percent >= 90:
		style = barHighStyle
	case percent >= 70:
		style = barMedStyle
	default:
		style = barLowStyle
	}

	bar := style.Render(strings.Repeat("█", filled))
	bar += barEmptyStyle.Render(strings.Repeat("░", empty))
	return bar
}

func humanizeBytes(bytes uint64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := uint64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

func formatDuration(d time.Duration) string {
	days := int(d.Hours() / 24)
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60

	if days > 0 {
		return fmt.Sprintf("%dd %dh %dm", days, hours, minutes)
	}
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}

func truncateString(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-3] + "..."
}
