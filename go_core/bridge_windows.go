//go:build windows

package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"
	"unsafe"

	"github.com/getlantern/systray"
	"github.com/xtls/libxray/xray"
	"golang.org/x/sys/windows"
)

var procMap sync.Map
var instMu sync.Mutex
var runtimeStatsMu sync.Mutex
var lastCPUProcessTime uint64
var lastCPUWallTime time.Time

func startXrayInternal(cfgData []byte) error {
	if xray.GetXrayState() {
		return errors.New("already running")
	}
	return xray.RunXrayFromJSON("", "", string(cfgData))
}

func stopXrayInternal() error {
	if !xray.GetXrayState() {
		return errors.New("not running")
	}
	return xray.StopXray()
}

func clearNodeRegistry() {
	procMap.Range(func(key, value any) bool {
		procMap.Delete(key)
		return true
	})
}

type processMemoryCounters struct {
	CB                         uint32
	PageFaultCount             uint32
	PeakWorkingSetSize         uintptr
	WorkingSetSize             uintptr
	QuotaPeakPagedPoolUsage    uintptr
	QuotaPagedPoolUsage        uintptr
	QuotaPeakNonPagedPoolUsage uintptr
	QuotaNonPagedPoolUsage     uintptr
	PagefileUsage              uintptr
	PeakPagefileUsage          uintptr
}

type desktopRuntimeSnapshot struct {
	Running                bool     `json:"running"`
	DownloadBytesPerSecond *int     `json:"downloadBytesPerSecond,omitempty"`
	UploadBytesPerSecond   *int     `json:"uploadBytesPerSecond,omitempty"`
	MemoryBytes            *int64   `json:"memoryBytes,omitempty"`
	CPUPercent             *float64 `json:"cpuPercent,omitempty"`
	UpdatedAt              int64    `json:"updatedAt"`
}

func filetimeToUint64(value windows.Filetime) uint64 {
	return uint64(value.HighDateTime)<<32 | uint64(value.LowDateTime)
}

func currentWorkingSetBytes() *int64 {
	psapi := windows.NewLazySystemDLL("psapi.dll")
	proc := psapi.NewProc("GetProcessMemoryInfo")
	counters := processMemoryCounters{CB: uint32(unsafe.Sizeof(processMemoryCounters{}))}
	r1, _, _ := proc.Call(
		uintptr(windows.CurrentProcess()),
		uintptr(unsafe.Pointer(&counters)),
		uintptr(counters.CB),
	)
	if r1 == 0 {
		return nil
	}
	value := int64(counters.WorkingSetSize)
	return &value
}

func currentCPUPercent() *float64 {
	var creation windows.Filetime
	var exit windows.Filetime
	var kernel windows.Filetime
	var user windows.Filetime
	if err := windows.GetProcessTimes(
		windows.CurrentProcess(),
		&creation,
		&exit,
		&kernel,
		&user,
	); err != nil {
		return nil
	}

	processTime := filetimeToUint64(kernel) + filetimeToUint64(user)
	now := time.Now()

	runtimeStatsMu.Lock()
	defer runtimeStatsMu.Unlock()

	if lastCPUWallTime.IsZero() {
		lastCPUWallTime = now
		lastCPUProcessTime = processTime
		return nil
	}

	wallDelta := now.Sub(lastCPUWallTime)
	processDelta := processTime - lastCPUProcessTime
	lastCPUWallTime = now
	lastCPUProcessTime = processTime
	if wallDelta <= 0 {
		return nil
	}

	wallTicks := float64(wallDelta.Nanoseconds()) / 100
	if wallTicks <= 0 {
		return nil
	}
	percent := (float64(processDelta) / wallTicks) * 100
	if runtime.NumCPU() > 0 {
		percent /= float64(runtime.NumCPU())
	}
	if percent < 0 {
		percent = 0
	}
	return &percent
}

//export WriteConfigFiles
func WriteConfigFiles(xrayPath, xrayContent, servicePath, serviceContent, vpnPath, vpnContent, password *C.char) *C.char {
	if res := writeConfigFile(xrayPath, xrayContent); res != nil {
		return res
	}
	if res := writeConfigFile(servicePath, serviceContent); res != nil {
		return res
	}
	return updateVpnNodesConfig(vpnPath, vpnContent)
}

func writeConfigFile(pathC, contentC *C.char) *C.char {
	p := C.GoString(pathC)
	c := C.GoString(contentC)
	if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(p, []byte(c), 0644); err != nil {
		return C.CString("error:" + err.Error())
	}
	return nil
}

func updateVpnNodesConfig(pathC, contentC *C.char) *C.char {
	p := C.GoString(pathC)
	c := C.GoString(contentC)
	if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
		return C.CString("error:" + err.Error())
	}
	var nodes []map[string]interface{}
	if data, err := os.ReadFile(p); err == nil {
		json.Unmarshal(data, &nodes)
	}
	var newNodes []map[string]interface{}
	if err := json.Unmarshal([]byte(c), &newNodes); err != nil {
		return C.CString("error:" + err.Error())
	}
	nodes = append(nodes, newNodes...)
	out, err := json.MarshalIndent(nodes, "", "  ")
	if err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(p, out, 0644); err != nil {
		return C.CString("error:" + err.Error())
	}
	return C.CString("success")
}

//export CreateWindowsService
func CreateWindowsService(name, execPath, configPath *C.char) *C.char {
	return C.CString("error:not supported")
}

//export StartNodeService
func StartNodeService(name *C.char) *C.char {
	instMu.Lock()
	defer instMu.Unlock()

	node := C.GoString(name)
	if _, ok := procMap.Load(node); ok && xray.GetXrayState() {
		return C.CString("success")
	}
	if xray.GetXrayState() {
		return C.CString("error:already running")
	}

	configPath := filepath.Join(os.TempDir(), node+".json")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := startXrayInternal(data); err != nil {
		return C.CString("error:" + err.Error())
	}
	procMap.Store(node, true)
	return C.CString("success")
}

//export StopNodeService
func StopNodeService(name *C.char) *C.char {
	instMu.Lock()
	defer instMu.Unlock()

	node := C.GoString(name)
	if _, ok := procMap.Load(node); ok {
		if xray.GetXrayState() {
			if err := stopXrayInternal(); err != nil {
				return C.CString("error:" + err.Error())
			}
		}
		procMap.Delete(node)
		return C.CString("success")
	}
	if xray.GetXrayState() {
		if err := stopXrayInternal(); err != nil {
			return C.CString("error:" + err.Error())
		}
	}
	clearNodeRegistry()
	return C.CString("success")
}

//export CheckNodeStatus
func CheckNodeStatus(name *C.char) C.int {
	node := C.GoString(name)
	if _, ok := procMap.Load(node); ok && xray.GetXrayState() {
		return 1
	}
	return 0
}

//export PerformAction
func PerformAction(action, password *C.char) *C.char {
	act := C.GoString(action)
	if act == "isXrayDownloading" {
		return C.CString("0")
	}
	return C.CString("error:unsupported")
}

//export IsXrayDownloading
func IsXrayDownloading() C.int { return 0 }

//export FreeCString
func FreeCString(str *C.char) { C.free(unsafe.Pointer(str)) }

//export StartXray
func StartXray(configC *C.char) *C.char {
	instMu.Lock()
	defer instMu.Unlock()

	if xray.GetXrayState() {
		return C.CString("error:already running")
	}
	cfgData := []byte(C.GoString(configC))
	if err := startXrayInternal(cfgData); err != nil {
		return C.CString("error:" + err.Error())
	}
	return C.CString("success")
}

//export StopXray
func StopXray() *C.char {
	instMu.Lock()
	defer instMu.Unlock()

	if !xray.GetXrayState() {
		return C.CString("error:not running")
	}
	if err := stopXrayInternal(); err != nil {
		return C.CString("error:" + err.Error())
	}
	clearNodeRegistry()
	return C.CString("success")
}

//export GetDesktopRuntimeSnapshot
func GetDesktopRuntimeSnapshot() *C.char {
	snapshot := desktopRuntimeSnapshot{
		Running:     xray.GetXrayState(),
		MemoryBytes: currentWorkingSetBytes(),
		CPUPercent:  currentCPUPercent(),
		UpdatedAt:   time.Now().UnixMilli(),
	}
	payload, err := json.Marshal(snapshot)
	if err != nil {
		return C.CString("{}")
	}
	return C.CString(string(payload))
}

// ---- System tray integration ----

var trayOnce sync.Once
var windowHandle windows.Handle

var (
	user32                  = windows.NewLazySystemDLL("user32.dll")
	procFindWindowW         = user32.NewProc("FindWindowW")
	procShowWindow          = user32.NewProc("ShowWindow")
	procGetWindowPlacement  = user32.NewProc("GetWindowPlacement")
	procSetForegroundWindow = user32.NewProc("SetForegroundWindow")
)

type point struct {
	X int32
	Y int32
}

type rect struct {
	Left   int32
	Top    int32
	Right  int32
	Bottom int32
}

type windowPlacement struct {
	Length         uint32
	Flags          uint32
	ShowCmd        uint32
	MinPosition    point
	MaxPosition    point
	NormalPosition rect
}

func findMainWindow() windows.Handle {
	title, _ := windows.UTF16PtrFromString("xstream")
	h, _, _ := procFindWindowW.Call(0, uintptr(unsafe.Pointer(title)))
	return windows.Handle(h)
}

func showWindow(h windows.Handle, cmd int32) {
	procShowWindow.Call(uintptr(h), uintptr(cmd))
}

func getPlacement(h windows.Handle, wp *windowPlacement) bool {
	r, _, _ := procGetWindowPlacement.Call(uintptr(h), uintptr(unsafe.Pointer(wp)))
	return r != 0
}

func monitorMinimize() {
	for {
		if windowHandle == 0 {
			windowHandle = findMainWindow()
		}
		if windowHandle != 0 {
			var wp windowPlacement
			wp.Length = uint32(unsafe.Sizeof(wp))
			if getPlacement(windowHandle, &wp) {
				if wp.ShowCmd == windows.SW_SHOWMINIMIZED {
					showWindow(windowHandle, windows.SW_HIDE)
				}
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func onTrayReady() {
	icon, err := os.ReadFile("data/flutter_assets/assets/logo.png")
	if err == nil {
		systray.SetIcon(icon)
	}
	mShow := systray.AddMenuItem("Show", "Show window")
	mQuit := systray.AddMenuItem("Quit", "Quit")
	go func() {
		for {
			select {
			case <-mShow.ClickedCh:
				if windowHandle == 0 {
					windowHandle = findMainWindow()
				}
				if windowHandle != 0 {
					showWindow(windowHandle, windows.SW_RESTORE)
					procSetForegroundWindow.Call(uintptr(windowHandle))
				}
			case <-mQuit.ClickedCh:
				systray.Quit()
				return
			}
		}
	}()
	go monitorMinimize()
}

//export InitTray
func InitTray() {
	trayOnce.Do(func() {
		go func() {
			runtime.LockOSThread()
			systray.Run(onTrayReady, func() {})
		}()
	})
}

func main() {}
