//go:build ios

package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"unsafe"

	"github.com/xtls/libxray/xray"
)

var procMap sync.Map
var instMu sync.Mutex
var tunnelSeq atomic.Int64
var tunnelSession sync.Map

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

//export WriteConfigFiles
func WriteConfigFiles(xrayPathC, xrayContentC, servicePathC, serviceContentC, vpnPathC, vpnContentC, passwordC *C.char) *C.char {
	xrayPath := C.GoString(xrayPathC)
	xrayContent := C.GoString(xrayContentC)
	servicePath := C.GoString(servicePathC)
	serviceContent := C.GoString(serviceContentC)
	vpnPath := C.GoString(vpnPathC)
	vpnContent := C.GoString(vpnContentC)
	if err := os.WriteFile(xrayPath, []byte(xrayContent), 0o644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(servicePath, []byte(serviceContent), 0o644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(vpnPath, []byte(vpnContent), 0o644); err != nil {
		return C.CString("error:" + err.Error())
	}
	return C.CString("success")
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

//export StartXrayTunnel
func StartXrayTunnel(configC *C.char) C.longlong {
	instMu.Lock()
	defer instMu.Unlock()

	if xray.GetXrayState() {
		return C.longlong(-1)
	}

	cfgData := []byte(C.GoString(configC))
	if err := startXrayInternal(cfgData); err != nil {
		return C.longlong(-1)
	}

	handle := tunnelSeq.Add(1)
	tunnelSession.Store(handle, true)
	return C.longlong(handle)
}

//export SubmitInboundPacket
func SubmitInboundPacket(handle C.longlong, data *C.uint8_t, length C.int32_t, protocol C.int32_t) C.int32_t {
	_ = data
	_ = length
	_ = protocol

	id := int64(handle)
	if id <= 0 {
		return C.int32_t(-1)
	}
	if _, ok := tunnelSession.Load(id); !ok {
		return C.int32_t(-1)
	}
	if !xray.GetXrayState() {
		return C.int32_t(-1)
	}

	// Packet forwarding happens in Packet Tunnel provider.
	return C.int32_t(0)
}

//export StopXrayTunnel
func StopXrayTunnel(handle C.longlong) *C.char {
	instMu.Lock()
	defer instMu.Unlock()

	id := int64(handle)
	if id <= 0 {
		return C.CString("error:invalid handle")
	}
	if _, ok := tunnelSession.Load(id); !ok {
		return C.CString("error:session not found")
	}
	tunnelSession.Delete(id)

	if xray.GetXrayState() {
		if err := stopXrayInternal(); err != nil {
			return C.CString("error:" + err.Error())
		}
	}
	clearNodeRegistry()
	return C.CString("success")
}

//export FreeXrayTunnel
func FreeXrayTunnel(handle C.longlong) *C.char {
	id := int64(handle)
	if id <= 0 {
		return C.CString("error:invalid handle")
	}
	tunnelSession.Delete(id)
	return C.CString("success")
}

//export CreateWindowsService
func CreateWindowsService(name, execPath, configPath *C.char) *C.char {
	return C.CString("error:not supported")
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

func main() {}
