//go:build windows

package main

import (
	"fmt"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func BenchmarkAnalyzerSort(b *testing.B) {
	for _, count := range []int{100, 100000} {
		for _, mode := range []struct {
			name   string
			byName bool
			unique bool
		}{
			{name: "size-ties"},
			{name: "size-unique", unique: true},
			{name: "name", byName: true},
		} {
			b.Run(fmt.Sprintf("entries=%d/%s", count, mode.name), func(b *testing.B) {
				entries := make([]dirEntry, count)
				for i := range entries {
					name := fmt.Sprintf("PrOjEcT-%06d-ÄPFEL-世界.bin", i*7919%count)
					size := int64(i % 32)
					if mode.unique {
						size = int64(count - i)
					}
					entries[i] = dirEntry{Name: name, Path: name, Size: size}
				}
				m := model{sortByName: mode.byName}
				b.ReportAllocs()
				b.ResetTimer()
				for i := 0; i < b.N; i++ {
					m.entries = entries
					m.selected = count / 2
					m.sortEntries()
				}
			})
		}
	}
}

func TestAnalyzerSortToggle(t *testing.T) {
	entries := []dirEntry{
		{Name: "zebra", Path: "zebra", Size: 30},
		{Name: "äpfel", Path: "äpfel", Size: 10},
		{Name: "beta", Path: "beta", Size: 20},
		{Name: "Alpha", Path: "Alpha", Size: 20},
		{Name: "Äpfel", Path: "Äpfel", Size: 10},
		{Name: "alpha", Path: "alpha", Size: 20},
	}
	m := newModel("fixture")
	m.scanning = false
	m.entries = entries
	m.selected = 2
	m.multiSelected["Alpha"] = true
	m.cache[m.path] = historyEntry{Entries: entries}
	m.history = []historyEntry{{Entries: entries, Selected: 2}}
	for _, tc := range []struct {
		name bool
		want []string
	}{
		{true, []string{"Alpha", "alpha", "beta", "zebra", "Äpfel", "äpfel"}},
		{false, []string{"zebra", "Alpha", "alpha", "beta", "Äpfel", "äpfel"}},
	} {
		updated, command := m.Update(navigationKey("s"))
		m = updated.(model)
		var got []string
		for _, entry := range m.entries {
			got = append(got, entry.Name)
		}
		if command != nil || m.sortByName != tc.name || !reflect.DeepEqual(got, tc.want) {
			t.Fatalf("sortByName=%t got %v, want %v", tc.name, got, tc.want)
		}
		if m.entries[m.selected].Path != "beta" || !reflect.DeepEqual(m.multiSelected, map[string]bool{"Alpha": true}) {
			t.Fatal("sorting moved the highlighted path or changed marked paths")
		}
		if entries[0].Name != "zebra" || entries[2].Name != "beta" || !reflect.DeepEqual(m.cache[m.path].Entries, entries) || !reflect.DeepEqual(m.history[0].Entries, entries) {
			t.Fatal("sorting mutated the shared cached/history listing")
		}
	}
}

func TestAnalyzerSortPersistsThroughNavigationAndRefresh(t *testing.T) {
	root := t.TempDir()
	child := filepath.Join(root, "Alpha")
	writeFile(t, filepath.Join(root, "z.bin"), 50)
	writeFile(t, filepath.Join(child, "z.bin"), 20)
	writeFile(t, filepath.Join(child, "a.bin"), 10)
	m := newModel(root)
	updated, _ := m.Update(m.Init()())
	m = updated.(model)
	m.selected = 1
	updated, _ = m.Update(navigationKey("s"))
	m = updated.(model)
	if m.entries[m.selected].Path != child || m.selected != 0 {
		t.Fatal("name sort did not retain selected child")
	}
	updated, command := m.Update(navigationKey("enter"))
	m = updated.(model)
	if command == nil {
		t.Fatal("first child visit did not scan")
	}
	updated, _ = m.Update(command())
	m = updated.(model)
	if !m.sortByName || m.entries[0].Name != "a.bin" || m.selected != 0 {
		t.Fatal("fresh child scan lost name sorting")
	}
	m.selected = 1
	updated, _ = m.Update(navigationKey("s"))
	m = updated.(model)
	if m.selected != 0 || m.entries[m.selected].Name != "z.bin" {
		t.Fatal("size sort lost child selection")
	}
	updated, command = m.Update(navigationKey("backspace"))
	m = updated.(model)
	if command != nil || m.sortByName || m.selected != 1 || m.entries[m.selected].Path != child {
		t.Fatal("history restore lost size order or selected child path")
	}
	updated, command = m.Update(navigationKey("enter"))
	m = updated.(model)
	if command != nil || m.entries[0].Name != "z.bin" || m.sortByName || m.selected != 0 {
		t.Fatal("cached child visit lost size order")
	}
	updated, _ = m.Update(navigationKey("s"))
	m = updated.(model)
	updated, command = m.Update(navigationKey("r"))
	m = updated.(model)
	if command == nil {
		t.Fatal("refresh did not scan")
	}
	updated, _ = m.Update(command())
	m = updated.(model)
	if !m.sortByName || m.entries[0].Name != "a.bin" || m.selected != 0 {
		t.Fatal("refresh lost name sorting or first-row selection")
	}
	updated, command = m.Update(navigationKey("backspace"))
	m = updated.(model)
	if command == nil || !m.scanning {
		t.Fatal("back reused history from before refresh")
	}
	updated, _ = m.Update(command())
	m = updated.(model)
	if !m.sortByName || m.selected != 0 || m.entries[m.selected].Path != child {
		t.Fatal("restored size-sorted history lost current name order or selected path")
	}
}

func TestAnalyzerSortEmptyAndGuards(t *testing.T) {
	for _, state := range []string{"empty", "scanning", "confirmation"} {
		t.Run(state, func(t *testing.T) {
			m := newModel("fixture")
			m.scanning = state == "scanning"
			m.deleteConfirm = state == "confirmation"
			updated, command := m.Update(navigationKey("s"))
			got := updated.(model)
			if command != nil || got.sortByName != (state == "empty") || got.selected != 0 {
				t.Fatal("sort did not respect state guard or empty selection")
			}
			if state != "empty" && !reflect.DeepEqual(got, m) {
				t.Fatal("sort changed guarded state")
			}
		})
	}
}

func TestAnalyzerSortLayout(t *testing.T) {
	for _, width := range []int{40, 60, 80} {
		for _, byName := range []bool{false, true} {
			m := newModel("fixture")
			m.scanning = false
			m.width, m.height = width, 9
			m.sortByName = byName
			m.entries = []dirEntry{{Name: "partial.bin", Size: 1024*1024 - 1, Partial: true}}
			m.totalSize = m.entries[0].Size
			view := assertViewFits(t, m)
			mode := "size"
			if byName {
				mode = "name"
			}
			for _, text := range []string{"sort: " + mode, "s sort", "+ = partial", "partial.bin"} {
				if !strings.Contains(view, text) {
					t.Fatalf("%dx9 layout hides %q:\n%s", width, text, view)
				}
			}
		}
	}
}
