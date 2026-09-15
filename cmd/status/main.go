//go:build windows

package main

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	"github.com/shirou/gopsutil/v3/process"
)

// Styles
var (
	titleStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#C79FD7")).Bold(true)
	headerStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#87CEEB")).Bold(true)
	labelStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#888888"))
	valueStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	okStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("#A5D6A7"))
	warnStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFD75F"))
	dangerStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5F5F")).Bold(true)
	dimStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("#666666"))
	cardStyle   = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("#444444")).Padding(0, 1)
)

// Metrics snapshot
type MetricsSnapshot struct {
	CollectedAt   time.Time
	HealthScore   int
	HealthMessage string

	// Hardware
	Hostname string
	OS       string
	Platform string
	Uptime   time.Duration

	// CPU
	CPUModel   string
	CPUCores   int
	CPUPercent float64
	CPUPerCore []float64

	// Memory
	MemTotal    uint64
	MemUsed     uint64
	MemPercent  float64
	SwapTotal   uint64
	SwapUsed    uint64
	SwapPercent float64

	// Disk
	Disks []DiskInfo

	// Network
	Networks []NetworkInfo

	// Processes
	Processes []ProcessInfo
}

type DiskInfo struct {
	Device      string
	Mountpoint  string
	Total       uint64
	Used        uint64
	Free        uint64
	UsedPercent float64
	Fstype      string
}

type NetworkInfo struct {
	Name        string
	BytesSent   uint64
	BytesRecv   uint64
	PacketsSent uint64
	PacketsRecv uint64
}

type ProcessInfo struct {
	PID    int32
	Name   string
	CPU    float64
	Memory float32
}

// Collector
type Collector struct {
	prevNet     map[string]net.IOCountersStat
	prevNetTime time.Time
	mu          sync.Mutex
}

func NewCollector() *Collector {
	return &Collector{
		prevNet: make(map[string]net.IOCountersStat),
	}
}

func (c *Collector) Collect() MetricsSnapshot {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var (
		snapshot MetricsSnapshot
		wg       sync.WaitGroup
		mu       sync.Mutex
	)

	snapshot.CollectedAt = time.Now()

	// Host info
	wg.Add(1)
	go func() {
		defer wg.Done()
		if info, err := host.InfoWithContext(ctx); err == nil {
			mu.Lock()
			snapshot.Hostname = info.Hostname
			snapshot.OS = info.OS
			snapshot.Platform = fmt.Sprintf("%s %s", info.Platform, info.PlatformVersion)
			snapshot.Uptime = time.Duration(info.Uptime) * time.Second
			mu.Unlock()
		}
	}()

	// CPU info
	wg.Add(1)
	go func() {
		defer wg.Done()
		if cpuInfo, err := cpu.InfoWithContext(ctx); err == nil && len(cpuInfo) > 0 {
			mu.Lock()
			snapshot.CPUModel = cpuInfo[0].ModelName
			snapshot.CPUCores = runtime.NumCPU()
			mu.Unlock()
		}
		if percent, err := cpu.PercentWithContext(ctx, 500*time.Millisecond, false); err == nil && len(percent) > 0 {
			mu.Lock()
			snapshot.CPUPercent = percent[0]
			mu.Unlock()
		}
		if perCore, err := cpu.PercentWithContext(ctx, 500*time.Millisecond, true); err == nil {
			mu.Lock()
			snapshot.CPUPerCore = perCore
			mu.Unlock()
		}
	}()

	// Memory
	wg.Add(1)
	go func() {
		defer wg.Done()
		if memInfo, err := mem.VirtualMemoryWithContext(ctx); err == nil {
			mu.Lock()
			snapshot.MemTotal = memInfo.Total
			snapshot.MemUsed = memInfo.Used
			snapshot.MemPercent = memInfo.UsedPercent
			mu.Unlock()
		}
		if swapInfo, err := mem.SwapMemoryWithContext(ctx); err == nil {
			mu.Lock()
			snapshot.SwapTotal = swapInfo.Total
			snapshot.SwapUsed = swapInfo.Used
			snapshot.SwapPercent = swapInfo.UsedPercent
			mu.Unlock()
		}
	}()

	// Disk
	wg.Add(1)
	go func() {
		defer wg.Done()
		if partitions, err := disk.PartitionsWithContext(ctx, false); err == nil {
			var disks []DiskInfo
			for _, p := range partitions {
				// Include physical drives (drive letter format like "C:", "D:", etc.)
				// Skip network drives and special mount points
				if len(p.Device) >= 2 && p.Device[1] == ':' {
					// It's a drive letter (A: through Z:)
					if usage, err := disk.UsageWithContext(ctx, p.Mountpoint); err == nil {
						disks = append(disks, DiskInfo{
							Device:      p.Device,
							Mountpoint:  p.Mountpoint,
							Total:       usage.Total,
							Used:        usage.Used,
							Free:        usage.Free,
							UsedPercent: usage.UsedPercent,
							Fstype:      p.Fstype,
						})
					}
				}
			}
			mu.Lock()
			snapshot.Disks = disks
			mu.Unlock()
		}
	}()

	// Network
	wg.Add(1)
	go func() {
		defer wg.Done()
		if netIO, err := net.IOCountersWithContext(ctx, true); err == nil {
			var networks []NetworkInfo
			for _, io := range netIO {
				// Skip loopback and inactive interfaces
				if io.Name == "Loopback Pseudo-Interface 1" || (io.BytesSent == 0 && io.BytesRecv == 0) {
					continue
				}
				networks = append(networks, NetworkInfo{
					Name:        io.Name,
					BytesSent:   io.BytesSent,
					BytesRecv:   io.BytesRecv,
					PacketsSent: io.PacketsSent,
					PacketsRecv: io.PacketsRecv,
				})
			}
			mu.Lock()
			snapshot.Networks = networks
			mu.Unlock()
		}
	}()

	// Top Processes
	wg.Add(1)
	go func() {
		defer wg.Done()
		procs, err := process.ProcessesWithContext(ctx)
		if err != nil {
			return
		}

		var procInfos []ProcessInfo
		for _, p := range procs {
			name, err := p.NameWithContext(ctx)
			if err != nil {
				continue
			}
			cpuPercent, _ := p.CPUPercentWithContext(ctx)
			memPercent, _ := p.MemoryPercentWithContext(ctx)

			if cpuPercent > 0.1 || memPercent > 0.1 {
				procInfos = append(procInfos, ProcessInfo{
					PID:    p.Pid,
					Name:   name,
					CPU:    cpuPercent,
					Memory: memPercent,
				})
			}
		}

		mu.Lock()
		snapshot.Processes = procInfos
		mu.Unlock()
	}()

	wg.Wait()

	// Calculate health score
	snapshot.HealthScore, snapshot.HealthMessage = calculateHealthScore(snapshot)

	return snapshot
}

func calculateHealthScore(s MetricsSnapshot) (int, string) {
	score := 100
	var issues []string

	// CPU penalty (30% weight)
	if s.CPUPercent > 90 {
		score -= 30
		issues = append(issues, "High CPU")
	} else if s.CPUPercent > 70 {
		score -= 15
		issues = append(issues, "Elevated CPU")
	}

	// Memory penalty (25% weight)
	if s.MemPercent > 90 {
		score -= 25
		issues = append(issues, "High Memory")
	} else if s.MemPercent > 80 {
		score -= 12
		issues = append(issues, "Elevated Memory")
	}

	// Apply one disk penalty, based on the fullest drive.
	var fullest DiskInfo
	for _, d := range s.Disks {
		if d.UsedPercent > fullest.UsedPercent || (d.UsedPercent == fullest.UsedPercent && d.Device < fullest.Device) {
			fullest = d
		}
	}
	if fullest.UsedPercent > 95 {
		score -= 20
		issues = append(issues, fmt.Sprintf("Disk %s Critical", fullest.Device))
	} else if fullest.UsedPercent > 85 {
		score -= 10
		issues = append(issues, fmt.Sprintf("Disk %s Low", fullest.Device))
	}

	// Swap penalty (10% weight)
	if s.SwapPercent > 80 {
		score -= 10
		issues = append(issues, "High Swap")
	}

	if score < 0 {
		score = 0
	}

	msg := "Excellent"
	if len(issues) > 0 {
		msg = strings.Join(issues, ", ")
	} else if score >= 90 {
		msg = "Excellent"
	} else if score >= 70 {
		msg = "Good"
	} else if score >= 50 {
		msg = "Fair"
	} else {
		msg = "Poor"
	}

	return score, msg
}

// Model for Bubble Tea
type model struct {
	collector    *Collector
	metrics      MetricsSnapshot
	animFrame    int
	catHidden    bool
	sortByMemory bool
	ready        bool
	collecting   bool
	width        int
	height       int
}

// Messages
type tickMsg time.Time
type metricsMsg MetricsSnapshot

func newModel() model {
	return model{
		collector: NewCollector(),
		animFrame: 0,
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.collectMetrics(),
		tickCmd(),
	)
}

func tickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m model) collectMetrics() tea.Cmd {
	return func() tea.Msg {
		return metricsMsg(m.collector.Collect())
	}
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "c":
			m.catHidden = !m.catHidden
		case "m":
			m.sortByMemory = !m.sortByMemory
			sortProcesses(m.metrics.Processes, m.sortByMemory)
		case "r":
			m.collecting = true
			return m, m.collectMetrics()
		}
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case tickMsg:
		m.animFrame++
		if m.animFrame%2 == 0 && !m.collecting {
			return m, tea.Batch(
				m.collectMetrics(),
				tickCmd(),
			)
		}
		return m, tickCmd()
	case metricsMsg:
		m.metrics = MetricsSnapshot(msg)
		sortProcesses(m.metrics.Processes, m.sortByMemory)
		m.ready = true
		m.collecting = false
	}
	return m, nil
}

func (m model) View() string {
	if !m.ready {
		return "\n  Loading system metrics..."
	}

	var b strings.Builder

	// Header with winmole animation
	winmoleFrame := getWinMoleFrame(m.animFrame, m.catHidden)

	b.WriteString("\n")
	b.WriteString(titleStyle.Render("  🐹 WinMole System Status"))
	b.WriteString("  ")
	b.WriteString(winmoleFrame)
	b.WriteString("\n\n")

	// Health score
	healthColor := okStyle
	if m.metrics.HealthScore < 50 {
		healthColor = dangerStyle
	} else if m.metrics.HealthScore < 70 {
		healthColor = warnStyle
	}
	b.WriteString(fmt.Sprintf("  Health: %s  %s\n\n",
		healthColor.Render(fmt.Sprintf("%d%%", m.metrics.HealthScore)),
		dimStyle.Render(m.metrics.HealthMessage),
	))

	// System info
	b.WriteString(headerStyle.Render("  📍 System"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %s %s\n", labelStyle.Render("Host:"), valueStyle.Render(m.metrics.Hostname)))
	b.WriteString(fmt.Sprintf("  %s %s\n", labelStyle.Render("OS:"), valueStyle.Render(m.metrics.Platform)))
	b.WriteString(fmt.Sprintf("  %s %s\n", labelStyle.Render("Uptime:"), valueStyle.Render(formatDuration(m.metrics.Uptime))))
	b.WriteString("\n")

	// CPU
	b.WriteString(headerStyle.Render("  ⚡ CPU"))
	b.WriteString("\n")
	cpuColor := getPercentColor(m.metrics.CPUPercent)
	b.WriteString(fmt.Sprintf("  %s %s\n", labelStyle.Render("Model:"), valueStyle.Render(truncateString(m.metrics.CPUModel, 50))))
	b.WriteString(fmt.Sprintf("  %s %s (%d cores)\n",
		labelStyle.Render("Usage:"),
		cpuColor.Render(fmt.Sprintf("%.1f%%", m.metrics.CPUPercent)),
		m.metrics.CPUCores,
	))
	b.WriteString(fmt.Sprintf("  %s\n", renderProgressBar(m.metrics.CPUPercent, 30)))
	b.WriteString("\n")

	// Memory
	b.WriteString(headerStyle.Render("  🧠 Memory"))
	b.WriteString("\n")
	memColor := getPercentColor(m.metrics.MemPercent)
	b.WriteString(fmt.Sprintf("  %s %s / %s %s\n",
		labelStyle.Render("RAM:"),
		memColor.Render(formatBytes(m.metrics.MemUsed)),
		valueStyle.Render(formatBytes(m.metrics.MemTotal)),
		memColor.Render(fmt.Sprintf("(%.1f%%)", m.metrics.MemPercent)),
	))
	b.WriteString(fmt.Sprintf("  %s\n", renderProgressBar(m.metrics.MemPercent, 30)))
	if m.metrics.SwapTotal > 0 {
		b.WriteString(fmt.Sprintf("  %s %s / %s\n",
			labelStyle.Render("Swap:"),
			valueStyle.Render(formatBytes(m.metrics.SwapUsed)),
			valueStyle.Render(formatBytes(m.metrics.SwapTotal)),
		))
	}
	b.WriteString("\n")

	// Disk
	b.WriteString(headerStyle.Render("  💾 Disks"))
	b.WriteString("\n")
	for _, d := range m.metrics.Disks {
		diskColor := getPercentColor(d.UsedPercent)
		b.WriteString(fmt.Sprintf("  %s %s / %s %s\n",
			labelStyle.Render(d.Device),
			diskColor.Render(formatBytes(d.Used)),
			valueStyle.Render(formatBytes(d.Total)),
			diskColor.Render(fmt.Sprintf("(%.1f%%)", d.UsedPercent)),
		))
		b.WriteString(fmt.Sprintf("  %s  %s %s\n",
			renderProgressBar(d.UsedPercent, 30),
			labelStyle.Render("Free:"),
			valueStyle.Render(formatBytes(d.Free)),
		))
	}
	b.WriteString("\n")

	// Top Processes
	if len(m.metrics.Processes) > 0 {
		order := "CPU"
		if m.sortByMemory {
			order = "Memory"
		}
		b.WriteString(headerStyle.Render("  📊 Top Processes by " + order))
		b.WriteString("\n")
		for i, p := range m.metrics.Processes {
			if i >= 5 {
				break
			}
			b.WriteString(fmt.Sprintf("  %s %s (CPU: %.1f%%, Mem: %.1f%%)\n",
				dimStyle.Render(fmt.Sprintf("[%d]", p.PID)),
				valueStyle.Render(truncateString(p.Name, 20)),
				p.CPU,
				p.Memory,
			))
		}
		b.WriteString("\n")
	}

	// Network
	if len(m.metrics.Networks) > 0 {
		b.WriteString(headerStyle.Render("  🌐 Network"))
		b.WriteString("\n")
		for i, n := range m.metrics.Networks {
			if i >= 3 {
				break
			}
			b.WriteString(fmt.Sprintf("  %s ↑%s ↓%s\n",
				labelStyle.Render(truncateString(n.Name, 20)+":"),
				valueStyle.Render(formatBytes(n.BytesSent)),
				valueStyle.Render(formatBytes(n.BytesRecv)),
			))
		}
		b.WriteString("\n")
	}

	// Footer
	b.WriteString(dimStyle.Render("  [q] quit  [r] refresh  [m] CPU/memory sort  [c] toggle winmole"))
	b.WriteString("\n")

	return b.String()
}

func sortProcesses(processes []ProcessInfo, byMemory bool) {
	sort.Slice(processes, func(i, j int) bool {
		if byMemory {
			if processes[i].Memory != processes[j].Memory {
				return processes[i].Memory > processes[j].Memory
			}
		} else if processes[i].CPU != processes[j].CPU {
			return processes[i].CPU > processes[j].CPU
		}
		return processes[i].PID < processes[j].PID
	})
}

func getWinMoleFrame(frame int, hidden bool) string {
	if hidden {
		return ""
	}
	frames := []string{
		"🐹",
		"🐹.",
		"🐹..",
		"🐹...",
	}
	return frames[frame%len(frames)]
}

func renderProgressBar(percent float64, width int) string {
	filled := int(percent / 100 * float64(width))
	if filled > width {
		filled = width
	}
	if filled < 0 {
		filled = 0
	}

	color := okStyle
	if percent > 85 {
		color = dangerStyle
	} else if percent > 70 {
		color = warnStyle
	}

	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
	return color.Render(bar)
}

func getPercentColor(percent float64) lipgloss.Style {
	if percent > 85 {
		return dangerStyle
	} else if percent > 70 {
		return warnStyle
	}
	return okStyle
}

func formatBytes(bytes uint64) string {
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

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

func main() {
	p := tea.NewProgram(newModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
