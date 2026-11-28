//go:build windows

package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	commonControls = windows.NewLazySystemDLL("comctl32.dll")
	user32         = windows.NewLazySystemDLL("user32.dll")
	kernel         = windows.NewLazySystemDLL("kernel32.dll")
	gdi32          = windows.NewLazySystemDLL("gdi32.dll")
	shell32        = windows.NewLazySystemDLL("shell32.dll")
	ole32          = windows.NewLazySystemDLL("ole32.dll")
	createWindow   = user32.NewProc("CreateWindowExW")
	sendMessage    = user32.NewProc("SendMessageW")
	showWindow     = user32.NewProc("ShowWindow")
	setText        = user32.NewProc("SetWindowTextW")
	dialogMessage  = user32.NewProc("IsDialogMessageW")
	moveWindow     = user32.NewProc("MoveWindow")
	enableWindow   = user32.NewProc("EnableWindow")
	mainProc       = syscall.NewCallback(windowProc)
	ui             workspace
)

const (
	idStatus = 101 + iota
	idAnalyze
	idPath
	idBrowse
	idRun
	idCancel
	idList
	idParent
	idOpen
)

type point struct{ x, y int32 }
type rect struct{ left, top, right, bottom int32 }
type message struct {
	window         uintptr
	message        uint32
	wparam, lparam uintptr
	time           uint32
	point          point
	private        uint32
}
type wndclass struct {
	size, style                              uint32
	proc                                     uintptr
	classExtra, windowExtra                  int32
	instance, icon, cursor, background, menu uintptr
	className                                *uint16
	iconSmall                                uintptr
}
type browseInfo struct {
	parent, root    uintptr
	display, title  *uint16
	flags           uint32
	callback, param uintptr
	image           int32
}

type result struct {
	status statusReport
	disk   diskReport
	err    error
}

type workspace struct {
	window, instance                                                                                                                        uintptr
	brand, subtitle, statusTab, analyzeTab, heading, summary, pathLabel, path, browse, run, cancel, list, parent, open, detail, bar, footer uintptr
	view                                                                                                                                    string
	results                                                                                                                                 chan result
	stop                                                                                                                                    context.CancelFunc
	entries                                                                                                                                 []entry
	totalBytes                                                                                                                              int64
	reportPath                                                                                                                              string
	packageDir                                                                                                                              string
	dpi                                                                                                                                     int
	largeFont                                                                                                                               uintptr
}

func text(hwnd uintptr, s string) {
	p, _ := syscall.UTF16PtrFromString(strings.ReplaceAll(s, "\x00", "�"))
	setText.Call(hwnd, uintptr(unsafe.Pointer(p)))
	runtime.KeepAlive(p)
}

func windowText(hwnd uintptr) string {
	n, _, _ := user32.NewProc("GetWindowTextLengthW").Call(hwnd)
	if n == 0 || n > 32767 {
		return ""
	}
	buf := make([]uint16, n+1)
	user32.NewProc("GetWindowTextW").Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	return syscall.UTF16ToString(buf)
}

func commandError(hwnd uintptr, message string) {
	p, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("WinMole error")
	user32.NewProc("MessageBoxW").Call(hwnd, uintptr(unsafe.Pointer(p)), uintptr(unsafe.Pointer(title)), 0x10)
	runtime.KeepAlive(p)
	runtime.KeepAlive(title)
}

func newControl(parent, instance, font uintptr, class, label string, id uintptr, style uintptr) uintptr {
	c, _ := syscall.UTF16PtrFromString(class)
	s, _ := syscall.UTF16PtrFromString(label)
	handle, _, _ := createWindow.Call(0, uintptr(unsafe.Pointer(c)), uintptr(unsafe.Pointer(s)), 0x50000000|style,
		0, 0, 0, 0, parent, id, instance, 0)
	runtime.KeepAlive(c)
	runtime.KeepAlive(s)
	if handle != 0 {
		sendMessage.Call(handle, 0x0030, font, 1) // WM_SETFONT
	}
	return handle
}

func (u *workspace) init() error {
	font, _, _ := gdi32.NewProc("GetStockObject").Call(17) // DEFAULT_GUI_FONT
	face, _ := syscall.UTF16PtrFromString("Segoe UI")
	u.largeFont, _, _ = gdi32.NewProc("CreateFontW").Call(uintptr(-int(u.scale(26))), 0, 0, 0, 650, 0, 0, 0, 1, 0, 0, 5, 0, uintptr(unsafe.Pointer(face)))
	runtime.KeepAlive(face)
	brandFont := u.largeFont
	if brandFont == 0 {
		brandFont = font
	}
	button := func(label string, id uintptr) uintptr {
		return newControl(u.window, u.instance, font, "BUTTON", label, id, 0x00010000)
	}
	label := func(s string, font uintptr) uintptr {
		return newControl(u.window, u.instance, font, "STATIC", s, 0, 0x80)
	} // SS_NOPREFIX
	u.brand = label("WinMole", brandFont)
	u.subtitle = label("Windows maintenance  |  Desktop preview", font)
	u.statusTab = button("&Overview", idStatus)
	u.analyzeTab = button("&Storage", idAnalyze)
	u.heading = label("", brandFont)
	u.summary = label("", font)
	u.pathLabel = label("Folder to scan", font)
	u.path = newControl(u.window, u.instance, font, "EDIT", "", idPath, 0x00810080) // border, tab, auto-hscroll
	u.browse = button("&Browse…", idBrowse)
	u.run = button("&Refresh", idRun)
	u.cancel = button("&Cancel", idCancel)
	u.list = newControl(u.window, u.instance, font, "LISTBOX", "", idList, 0x00B10101) // notify, scrollbars, border, no-integral-height
	u.parent = button("&Up one folder", idParent)
	u.open = button("&Scan selected folder", idOpen)
	u.detail = label("", font)
	u.bar = newControl(u.window, u.instance, font, "msctls_progress32", "", 0, 0)
	sendMessage.Call(u.bar, 0x0406, 0, 100) // PBM_SETRANGE32
	visible(u.bar, false)
	u.footer = label("Preview only  |  Clean, Uninstall, Optimize and Purge are not available in this build.", font)
	for _, hwnd := range []uintptr{u.brand, u.subtitle, u.statusTab, u.analyzeTab, u.heading, u.summary, u.pathLabel, u.path,
		u.browse, u.run, u.cancel, u.list, u.parent, u.open, u.detail, u.bar, u.footer} {
		if hwnd == 0 {
			return errors.New("could not create a required native control")
		}
	}
	u.switchView("status")
	return nil
}

func (u *workspace) scale(v int) int { return (v*u.dpi + 48) / 96 }

func (u *workspace) layout() {
	var bounds rect
	if ok, _, _ := user32.NewProc("GetClientRect").Call(u.window, uintptr(unsafe.Pointer(&bounds))); ok == 0 {
		return
	}
	w, h := int(bounds.right)*96/u.dpi, int(bounds.bottom)*96/u.dpi
	place := func(hwnd uintptr, x, y, width, height int) {
		if hwnd != 0 {
			moveWindow.Call(hwnd, uintptr(u.scale(x)), uintptr(u.scale(y)), uintptr(u.scale(max(1, width))), uintptr(u.scale(max(1, height))), 1)
		}
	}
	place(u.brand, 24, 19, w-48, 33)
	place(u.subtitle, 25, 58, w-48, 22)
	place(u.statusTab, 24, 88, 110, 32)
	place(u.analyzeTab, 142, 88, 110, 32)
	place(u.heading, 24, 132, w-48, 36)
	place(u.summary, 25, 175, w-48, 42)
	place(u.pathLabel, 25, 224, w-48, 22)
	place(u.path, 25, 249, w-372, 28)
	place(u.browse, w-335, 247, 108, 32)
	place(u.run, w-217, 247, 94, 32)
	place(u.cancel, w-115, 247, 90, 32)
	top := 292
	if u.view == "status" {
		top = 225
	}
	place(u.list, 25, top, w-50, h-top-113)
	place(u.parent, 25, h-104, 133, 31)
	place(u.open, 167, h-104, 188, 31)
	place(u.detail, 25, h-66, w-50, 32)
	place(u.bar, 25, h-34, w-50, 7)
	place(u.footer, 25, h-24, w-50, 22)
}

func visible(hwnd uintptr, show bool) {
	if show {
		showWindow.Call(hwnd, 5) // SW_SHOW
	} else {
		showWindow.Call(hwnd, 0)
	}
}

func enabled(hwnd uintptr, yes bool) {
	if yes {
		enableWindow.Call(hwnd, 1)
	} else {
		enableWindow.Call(hwnd, 0)
	}
}

func (u *workspace) controls() {
	analyzer := u.view == "analyze"
	for _, h := range []uintptr{u.pathLabel, u.path, u.browse, u.parent, u.open} {
		visible(h, analyzer)
	}
	active := u.stop == nil
	for _, h := range []uintptr{u.statusTab, u.analyzeTab, u.run, u.browse, u.path} {
		enabled(h, active)
	}
	enabled(u.cancel, !active)
	enabled(u.parent, active && analyzer && u.reportPath != "" && filepath.Dir(u.reportPath) != u.reportPath)
	i := u.selected()
	enabled(u.open, active && analyzer && i >= 0 && i < min(len(u.entries), 1000) && u.entries[i].Directory)
}

func (u *workspace) switchView(view string) {
	if u.stop != nil {
		return
	}
	u.view = view
	u.entries, u.reportPath, u.totalBytes = nil, "", 0
	visible(u.bar, false)
	u.populate(nil)
	text(u.detail, "")
	if view == "status" {
		text(u.heading, "System overview")
		text(u.summary, "Read a fresh snapshot of CPU, memory, disks and health.")
		text(u.run, "&Refresh")
	} else {
		text(u.heading, "Storage explorer")
		text(u.summary, "Choose a folder to see the largest items. No files will be changed.")
		text(u.run, "&Scan")
	}
	u.layout()
	u.controls()
	user32.NewProc("SetFocus").Call(u.run)
}

func (u *workspace) populate(lines []string) {
	sendMessage.Call(u.list, 0x000B, 0, 0) // WM_SETREDRAW, false
	sendMessage.Call(u.list, 0x0184, 0, 0) // LB_RESETCONTENT
	// Bound visual rows even when a directory has a very large direct listing.
	const maxRows = 1000
	pending := 0
	if len(lines) > maxRows {
		pending = len(lines) - maxRows
		lines = lines[:maxRows]
	}
	longest := 0
	for _, line := range lines {
		p, _ := syscall.UTF16PtrFromString(strings.ReplaceAll(line, "\x00", "�"))
		sendMessage.Call(u.list, 0x0180, 0, uintptr(unsafe.Pointer(p))) // LB_ADDSTRING
		runtime.KeepAlive(p)
		longest = max(longest, len([]rune(line)))
	}
	if pending > 0 {
		line, _ := syscall.UTF16PtrFromString(fmt.Sprintf("%d more rows not shown in this preview.", pending))
		sendMessage.Call(u.list, 0x0180, 0, uintptr(unsafe.Pointer(line)))
		runtime.KeepAlive(line)
	}
	sendMessage.Call(u.list, 0x0194, uintptr(u.scale(min(longest, 320)*9)), 0) // LB_SETHORIZONTALEXTENT
	sendMessage.Call(u.list, 0x000B, 1, 0)
	user32.NewProc("InvalidateRect").Call(u.list, 0, 1)
}

func (u *workspace) selected() int {
	i, _, _ := sendMessage.Call(u.list, 0x0188, 0, 0) // LB_GETCURSEL
	return int(i)
}

func (u *workspace) describeSelection() {
	i := u.selected()
	if i >= 0 && i < min(len(u.entries), 1000) {
		item := u.entries[i]
		detail := item.Path
		if pct, ok := shareOfObservedBytes(item.Size, u.totalBytes); ok {
			detail = fmt.Sprintf("%.1f%% of observed bytes  |  ", pct) + detail
			sendMessage.Call(u.bar, 0x0402, uintptr(pct+0.5), 0) // PBM_SETPOS
			visible(u.bar, true)
		} else {
			visible(u.bar, false)
		}
		if item.Partial {
			detail = "Partial: " + reasonsText(item.PartialReasons) + "\r\n" + detail
		}
		text(u.detail, detail)
	} else if u.view == "analyze" {
		text(u.detail, "")
		visible(u.bar, false)
	}
	u.controls()
}

func (u *workspace) browseForFolder() {
	if u.stop != nil {
		return
	}
	title, _ := syscall.UTF16PtrFromString("Select the folder to analyze")
	var display [260]uint16 // SHBrowseForFolder display buffer
	info := browseInfo{
		parent: u.window, display: &display[0], title: title,
		flags: 0x0041, // BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE
	}
	selection, _, _ := shell32.NewProc("SHBrowseForFolderW").Call(uintptr(unsafe.Pointer(&info)))
	runtime.KeepAlive(title)
	runtime.KeepAlive(display)
	if selection == 0 {
		return
	}
	defer ole32.NewProc("CoTaskMemFree").Call(selection)
	var path [32768]uint16
	if ok, _, _ := shell32.NewProc("SHGetPathFromIDListEx").Call(selection, uintptr(unsafe.Pointer(&path[0])), uintptr(len(path)), 0); ok != 0 {
		text(u.path, syscall.UTF16ToString(path[:]))
	} else {
		commandError(u.window, "This selection was not a Windows file-system folder.")
	}
}

type cappedOutput struct {
	buf      bytes.Buffer
	limit    int
	overflow bool
}

func (b *cappedOutput) Write(p []byte) (int, error) {
	n := min(len(p), max(0, b.limit-b.buf.Len()))
	if n != len(p) {
		b.overflow = true
	}
	_, _ = b.buf.Write(p[:n])
	return len(p), nil
}

func helperCommand(dir, view, path string) (string, []string, error) {
	switch view {
	case "status":
		return filepath.Join(dir, "bin", "status.exe"), []string{"-json"}, nil
	case "analyze":
		if !filepath.IsAbs(path) {
			return "", nil, errors.New("choose an absolute Windows folder path")
		}
		return filepath.Join(dir, "bin", "analyze.exe"), []string{"-json", "-path", path}, nil
	default:
		return "", nil, errors.New("this preview cannot run maintenance actions")
	}
}

func runHelper(ctx context.Context, directory, view, path string) ([]byte, error) {
	program, args, err := helperCommand(directory, view, path)
	if err != nil {
		return nil, err
	}
	cmd := exec.CommandContext(ctx, program, args...)
	// Run only the bundled native helper, without shell, PATH lookup, or a console flash.
	cmd.Dir = directory
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000} // CREATE_NO_WINDOW
	cmd.Stdin = nil
	cmd.WaitDelay = time.Second
	stdout := cappedOutput{limit: maxReportBytes}
	stderr := cappedOutput{limit: 2048}
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		if errors.Is(err, os.ErrNotExist) {
			return nil, errors.New("the companion helper is missing; use a complete WinMole build")
		}
		msg := strings.Join(strings.Fields(stderr.buf.String()), " ")
		if msg == "" {
			msg = err.Error()
		}
		return nil, errors.New(msg)
	}
	if stdout.overflow {
		return nil, errors.New("report exceeds preview display limit; try a smaller folder")
	}
	return stdout.buf.Bytes(), nil
}

var _ io.Writer = (*cappedOutput)(nil)

func (u *workspace) start() {
	if u.stop != nil {
		return
	}
	view, path := u.view, windowText(u.path)
	if view == "analyze" && !filepath.IsAbs(path) {
		text(u.detail, "Choose an absolute Windows folder path before scanning.")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	u.stop = cancel
	u.entries, u.reportPath, u.totalBytes = nil, "", 0
	visible(u.bar, false)
	u.populate(nil)
	text(u.summary, "Working…")
	text(u.detail, "")
	u.controls()
	user32.NewProc("SetFocus").Call(u.cancel)
	hwnd := u.window
	go func() {
		var r result
		data, err := runHelper(ctx, u.packageDir, view, path)
		if err != nil {
			r.err = err
		} else if view == "status" {
			r.status, r.err = decodeStatus(data)
		} else {
			r.disk, r.err = decodeDisk(data)
		}
		u.results <- r
		user32.NewProc("PostMessageW").Call(hwnd, 0x8001, 0, 0)
	}()
}

func (u *workspace) finish() {
	select {
	case r := <-u.results:
		u.stop()
		u.stop = nil
		switch {
		case errors.Is(r.err, context.Canceled):
			text(u.summary, "Canceled. No data changed.")
		case errors.Is(r.err, context.DeadlineExceeded):
			text(u.summary, "Timed out. Try a smaller folder or refresh again.")
		case r.err != nil:
			text(u.summary, "Could not load the report.")
			text(u.detail, r.err.Error())
		case u.view == "status":
			text(u.summary, "Sampled "+r.status.CollectedAt.Local().Format("2 Jan 2006, 15:04:05"))
			u.populate(statusLines(r.status))
		default:
			msg := fmt.Sprintf("%s observed  ·  %d items", formatBytes(r.disk.Total), len(r.disk.Entries))
			if *r.disk.Partial {
				msg += "  ·  Partial: " + reasonsText(r.disk.PartialReasons)
			}
			if len(r.disk.Entries) == 0 {
				msg += "  ·  No visible items"
			}
			u.entries, u.reportPath, u.totalBytes = r.disk.Entries, r.disk.Path, r.disk.Total
			text(u.summary, msg)
			text(u.path, r.disk.Path)
			u.populate(diskRows(r.disk))
		}
		u.controls()
		user32.NewProc("SetFocus").Call(u.run)
	default:
	}
}

func windowProc(hwnd, msg, wparam, lparam uintptr) uintptr {
	switch msg {
	case 0x0005: // WM_SIZE
		if ui.window != 0 {
			ui.layout()
		}
	case 0x0024: // WM_GETMINMAXINFO
		if lparam != 0 && ui.dpi != 0 {
			// lparam is a pointer to MINMAXINFO supplied by Windows.
			minimum := point{int32(ui.scale(690)), int32(ui.scale(560))}
			kernel.NewProc("RtlMoveMemory").Call(lparam+3*unsafe.Sizeof(point{}), uintptr(unsafe.Pointer(&minimum)), unsafe.Sizeof(minimum))
			return 0
		}
	case 0x0111: // WM_COMMAND
		id, code := wparam&0xffff, wparam>>16
		switch id {
		case idStatus:
			ui.switchView("status")
		case idAnalyze:
			ui.switchView("analyze")
		case idBrowse:
			ui.browseForFolder()
		case idRun:
			ui.start()
		case idCancel:
			if ui.stop != nil {
				ui.stop()
			}
		case idParent:
			if ui.reportPath != "" && ui.stop == nil {
				text(ui.path, filepath.Dir(ui.reportPath))
				ui.start()
			}
		case idList:
			if code == 1 { // LBN_SELCHANGE
				ui.describeSelection()
			}
			if code != 2 { // LBN_DBLCLK
				return 0
			}
			fallthrough
		case idOpen:
			i := ui.selected()
			if i >= 0 && i < min(len(ui.entries), 1000) && ui.entries[i].Directory && ui.stop == nil {
				text(ui.path, ui.entries[i].Path)
				ui.start()
			}
		}
		return 0
	case 0x8001:
		ui.finish()
		return 0
	case 0x0002: // WM_DESTROY
		if ui.stop != nil {
			ui.stop()
		}
		user32.NewProc("PostQuitMessage").Call(0)
		return 0
	}
	r, _, _ := user32.NewProc("DefWindowProcW").Call(hwnd, msg, wparam, lparam)
	return r
}

func main() {
	runtime.LockOSThread() // Win32 HWNDs and the shell dialog's STA belong to this thread.
	exe, err := os.Executable()
	if err != nil {
		commandError(0, err.Error())
		return
	}
	if hr, _, _ := ole32.NewProc("CoInitializeEx").Call(0, 2); int32(hr) >= 0 { // COINIT_APARTMENTTHREADED
		defer ole32.NewProc("CoUninitialize").Call()
	}
	ui.packageDir = filepath.Dir(exe)
	ui.results = make(chan result, 1)
	ui.dpi = 96
	user32.NewProc("SetProcessDPIAware").Call()
	if fn := user32.NewProc("GetDpiForSystem"); fn.Find() == nil {
		if dpi, _, _ := fn.Call(); dpi > 0 {
			ui.dpi = int(dpi)
		}
	}
	classes := struct{ size, flags uint32 }{8, 0x20} // ICC_PROGRESS_CLASS
	commonControls.NewProc("InitCommonControlsEx").Call(uintptr(unsafe.Pointer(&classes)))
	ui.instance, _, _ = kernel.NewProc("GetModuleHandleW").Call(0)
	class, _ := syscall.UTF16PtrFromString("WinMoleDesktopPreview")
	title, _ := syscall.UTF16PtrFromString("WinMole")
	cursor, _, _ := user32.NewProc("LoadCursorW").Call(0, 32512)
	wc := wndclass{
		size: uint32(unsafe.Sizeof(wndclass{})), proc: mainProc, instance: ui.instance, cursor: cursor,
		background: 16, className: class, // COLOR_BTNFACE+1
	}
	atom, _, regErr := user32.NewProc("RegisterClassExW").Call(uintptr(unsafe.Pointer(&wc)))
	if atom == 0 {
		commandError(0, "Could not start WinMole: "+regErr.Error())
		return
	}
	ui.window, _, err = createWindow.Call(0, uintptr(unsafe.Pointer(class)), uintptr(unsafe.Pointer(title)), 0x00CF0000,
		0x80000000, 0x80000000, uintptr(ui.scale(920)), uintptr(ui.scale(690)), 0, 0, ui.instance, 0)
	runtime.KeepAlive(class)
	runtime.KeepAlive(title)
	if ui.window == 0 {
		commandError(0, "Could not open the WinMole window: "+err.Error())
		return
	}
	if err := ui.init(); err != nil {
		commandError(ui.window, err.Error())
		user32.NewProc("DestroyWindow").Call(ui.window)
		return
	}
	if ui.largeFont != 0 {
		defer gdi32.NewProc("DeleteObject").Call(ui.largeFont)
	}
	showWindow.Call(ui.window, 5)
	user32.NewProc("UpdateWindow").Call(ui.window)
	ui.start()
	var m message
	for {
		r, _, _ := user32.NewProc("GetMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		if handled, _, _ := dialogMessage.Call(ui.window, uintptr(unsafe.Pointer(&m))); handled == 0 {
			user32.NewProc("TranslateMessage").Call(uintptr(unsafe.Pointer(&m)))
			user32.NewProc("DispatchMessageW").Call(uintptr(unsafe.Pointer(&m)))
		}
	}
}
