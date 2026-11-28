//go:build windows

package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func TestHelperDispatchIsReadOnly(t *testing.T) {
	root := `C:\Program Files\WinMole`
	folder := `C:\Case Folder & [1]`
	program, args, err := helperCommand(root, "analyze", folder)
	if err != nil || program != filepath.Join(root, "bin", "analyze.exe") ||
		!reflect.DeepEqual(args, []string{"-json", "-path", folder}) {
		t.Fatalf("expected literal synthetic folder argument: %q %q %v", program, args, err)
	}
	program, args, err = helperCommand(root, "status", "")
	if err != nil || program != filepath.Join(root, "bin", "status.exe") ||
		!reflect.DeepEqual(args, []string{"-json"}) {
		t.Fatalf("unexpected status helper: %q %q %v", program, args, err)
	}
	for _, view := range []string{"clean", "uninstall", "optimize", "purge", "analyze -rm", "powershell"} {
		if _, _, err := helperCommand(root, view, folder); err == nil {
			t.Errorf("unsupported action unexpectedly allowed: %s", view)
		}
	}
	if _, _, err := helperCommand(root, "analyze", `..\relative`); err == nil {
		t.Error("relative analyzer path accepted")
	}
}

func TestCappedOutput(t *testing.T) {
	b := cappedOutput{limit: 4}
	for _, item := range []string{"ab", "cdef", "gh"} {
		n, err := b.Write([]byte(item))
		if n != len(item) || err != nil {
			t.Fatalf("writer broke child output: %d %v", n, err)
		}
	}
	if b.buf.String() != "abcd" || !b.overflow {
		t.Fatalf("capture did not enforce its budget")
	}
}

func TestMissingHelperIsReported(t *testing.T) {
	_, err := runHelper(context.Background(), t.TempDir(), "status", "")
	if err == nil {
		t.Error("missing helper appeared successful")
	}
}

func TestNativeReadOnlyHelpers(t *testing.T) {
	root := os.Getenv("WINMOLE_UI_HELPER_FIXTURE")
	if root == "" {
		t.Skip("set WINMOLE_UI_HELPER_FIXTURE to the absolute staged package root")
	}
	if !filepath.IsAbs(root) {
		t.Fatal("WINMOLE_UI_HELPER_FIXTURE must be an absolute package root")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	fixture := filepath.Join(t.TempDir(), "Space & [1]")
	if err := os.Mkdir(fixture, 0o700); err != nil {
		t.Fatal(err)
	}
	const original = "a b\n"
	item := filepath.Join(fixture, "資料.txt")
	if err := os.WriteFile(item, []byte(original), 0o600); err != nil {
		t.Fatal(err)
	}
	out, err := runHelper(ctx, root, "analyze", fixture)
	if err != nil {
		t.Fatal(err)
	}
	disk, err := decodeDisk(out)
	if err != nil || disk.Partial == nil || *disk.Partial || disk.Total != int64(len(original)) ||
		len(disk.Entries) != 1 || disk.Entries[0].Name != "資料.txt" || disk.Entries[0].Directory {
		t.Fatalf("unexpected native analyzer report: %+v (%v)", disk, err)
	}
	if after, err := os.ReadFile(item); err != nil || string(after) != original {
		t.Fatalf("read-only analyzer touched the sentinel: %v", err)
	}

	out, err = runHelper(ctx, root, "status", "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := decodeStatus(out); err != nil {
		t.Fatal(err)
	}
	stopped, stopNow := context.WithCancel(ctx)
	stopNow()
	if _, err := runHelper(stopped, root, "analyze", fixture); !errors.Is(err, context.Canceled) {
		t.Fatalf("canceled scan returned %v", err)
	}
}
