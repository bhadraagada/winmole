//go:build windows

package main

import (
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/shirou/gopsutil/v3/net"
)

func TestNetworkRates(t *testing.T) {
	start := time.Unix(1000, 0)
	for _, tt := range []struct {
		name     string
		previous []net.IOCountersStat
		current  []net.IOCountersStat
		elapsed  time.Duration
		sent     float64
		received float64
	}{
		{"first sample", nil, []net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000, BytesRecv: 2000}}, time.Second, 0, 0},
		{"measured interval", []net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000, BytesRecv: 2000}}, []net.IOCountersStat{{Name: "Ethernet", BytesSent: 6000, BytesRecv: 12000}}, 2500 * time.Millisecond, 2000, 4000},
		{"send counter reset", []net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000, BytesRecv: 2000}}, []net.IOCountersStat{{Name: "Ethernet", BytesSent: 10, BytesRecv: 4000}}, time.Second, 0, 2000},
		{"receive counter reset", []net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000, BytesRecv: 2000}}, []net.IOCountersStat{{Name: "Ethernet", BytesSent: 2000, BytesRecv: 10}}, time.Second, 1000, 0},
		{"new interface", []net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000}}, []net.IOCountersStat{{Name: "Wi-Fi", BytesSent: 9000, BytesRecv: 9000}}, time.Second, 0, 0},
		{"idle interface becomes active", []net.IOCountersStat{{Name: "Ethernet"}}, []net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000, BytesRecv: 2000}}, time.Second, 1000, 2000},
		{"same sample time", []net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000}}, []net.IOCountersStat{{Name: "Ethernet", BytesSent: 2000}}, 0, 0, 0},
	} {
		t.Run(tt.name, func(t *testing.T) {
			collector := NewCollector()
			if tt.previous != nil {
				collector.networkSnapshot(tt.previous, start)
			}
			networks := collector.networkSnapshot(tt.current, start.Add(tt.elapsed))
			if len(networks) != 1 {
				t.Fatalf("got %d interfaces, want 1", len(networks))
			}
			if networks[0].SendRate != tt.sent || networks[0].ReceiveRate != tt.received {
				t.Fatalf("rates = %v/%v, want %v/%v", networks[0].SendRate, networks[0].ReceiveRate, tt.sent, tt.received)
			}
			if networks[0].BytesSent != tt.current[0].BytesSent || networks[0].BytesRecv != tt.current[0].BytesRecv {
				t.Fatal("cumulative counters changed")
			}
		})
	}

	collector := NewCollector()
	collector.networkSnapshot([]net.IOCountersStat{{Name: "Ethernet", BytesSent: 1000}}, start)
	collector.networkSnapshot(nil, start.Add(time.Second))
	networks := collector.networkSnapshot([]net.IOCountersStat{{Name: "Ethernet", BytesSent: 10000}}, start.Add(2*time.Second))
	if networks[0].SendRate != 0 {
		t.Fatal("reconnected interface reused a stale baseline")
	}
}

func TestNetworkViewShowsRates(t *testing.T) {
	m := model{ready: true, metrics: MetricsSnapshot{Networks: []NetworkInfo{{Name: "Ethernet", BytesSent: 999999, BytesRecv: 999999, SendRate: 1024, ReceiveRate: 2048}}}}
	view := m.View()
	if !strings.Contains(view, "1.0 KB/s") || !strings.Contains(view, "2.0 KB/s") {
		t.Fatalf("network view does not show byte rates: %s", view)
	}
}

func TestRefreshesDoNotOverlap(t *testing.T) {
	m := newModel()
	refresh := tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'r'}}
	if !m.collecting {
		t.Fatal("initial collection is not marked in flight")
	}
	for _, trigger := range []string{"scheduled", "manual"} {
		// A refresh during either collection must not start another command.
		updated, command := m.Update(refresh)
		if command != nil || !updated.(model).collecting {
			t.Fatal("manual refresh overlaps an active collection")
		}
		updated, _ = m.Update(metricsMsg{})
		m = updated.(model)
		if m.collecting {
			t.Fatal("completed collection did not release the refresh guard")
		}
		if trigger == "scheduled" {
			m.animFrame = 1
			updated, command = m.Update(tickMsg{})
		} else {
			updated, command = m.Update(refresh)
		}
		m = updated.(model)
		if command == nil || !m.collecting {
			t.Fatalf("%s collection did not start with the guard set", trigger)
		}
		updated, command = m.Update(refresh)
		if command != nil || !updated.(model).collecting {
			t.Fatalf("manual refresh overlaps %s collection", trigger)
		}
	}
}
