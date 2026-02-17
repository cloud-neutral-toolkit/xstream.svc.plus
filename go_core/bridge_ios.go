//go:build ios

package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"unsafe"

	"github.com/xtls/xray-core/core"
)

var procMap sync.Map
var singleInstance *xrayInstance
var instMu sync.Mutex
var tunnelSeq atomic.Int64
var tunnelSession sync.Map

type xrayInstance struct {
	server core.Server
}

func startXrayInternal(cfgData []byte) error {
	if singleInstance != nil {
		return errors.New("already running")
	}
	cfg, err := core.LoadConfig("json", bytes.NewReader(cfgData))
	if err != nil {
		return err
	}
	srv, err := core.New(cfg)
	if err != nil {
		return err
	}
	if err := srv.Start(); err != nil {
		return err
	}
	singleInstance = &xrayInstance{server: srv}
	return nil
}

func stopXrayInternal() error {
	if singleInstance == nil {
		return errors.New("not running")
	}
	if err := singleInstance.server.Close(); err != nil {
		return err
	}
	singleInstance = nil
	return nil
}

//export WriteConfigFiles
func WriteConfigFiles(xrayPathC, xrayContentC, servicePathC, serviceContentC, vpnPathC, vpnContentC, passwordC *C.char) *C.char {
	xrayPath := C.GoString(xrayPathC)
	xrayContent := C.GoString(xrayContentC)
	servicePath := C.GoString(servicePathC)
	serviceContent := C.GoString(serviceContentC)
	vpnPath := C.GoString(vpnPathC)
	vpnContent := C.GoString(vpnContentC)
	if err := os.WriteFile(xrayPath, []byte(xrayContent), 0644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(servicePath, []byte(serviceContent), 0644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(vpnPath, []byte(vpnContent), 0644); err != nil {
		return C.CString("error:" + err.Error())
	}
	return C.CString("success")
}

//export StartNodeService
func StartNodeService(name *C.char) *C.char {
	node := C.GoString(name)
	configPath := filepath.Join(os.TempDir(), node+".json")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return C.CString("error:" + err.Error())
	}
	cfg, err := core.LoadConfig("json", bytes.NewReader(data))
	if err != nil {
		return C.CString("error:" + err.Error())
	}
	srv, err := core.New(cfg)
	if err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := srv.Start(); err != nil {
		return C.CString("error:" + err.Error())
	}
	procMap.Store(node, &xrayInstance{server: srv})
	return C.CString("success")
}

//export StopNodeService
func StopNodeService(name *C.char) *C.char {
	node := C.GoString(name)
	if v, ok := procMap.Load(node); ok {
		inst := v.(*xrayInstance)
		if err := inst.server.Close(); err != nil {
			return C.CString("error:" + err.Error())
		}
		procMap.Delete(node)
	}
	return C.CString("success")
}

//export CheckNodeStatus
func CheckNodeStatus(name *C.char) C.int {
	node := C.GoString(name)
	if _, ok := procMap.Load(node); ok {
		return 1
	}
	return 0
}

//export StartXray
func StartXray(configC *C.char) *C.char {
	instMu.Lock()
	defer instMu.Unlock()

	if singleInstance != nil {
		return C.CString("error:already running")
	}
	cfgData := []byte(C.GoString(configC))
	cfg, err := core.LoadConfig("json", bytes.NewReader(cfgData))
	if err != nil {
		return C.CString("error:" + err.Error())
	}
	srv, err := core.New(cfg)
	if err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := srv.Start(); err != nil {
		return C.CString("error:" + err.Error())
	}
	singleInstance = &xrayInstance{server: srv}

	return C.CString("success")
}

//export StopXray
func StopXray() *C.char {
	instMu.Lock()
	defer instMu.Unlock()

	if singleInstance == nil {
		return C.CString("error:not running")
	}
	if err := singleInstance.server.Close(); err != nil {
		return C.CString("error:" + err.Error())
	}
	singleInstance = nil

	return C.CString("success")
}

//export StartXrayTunnel
func StartXrayTunnel(configC *C.char) C.longlong {
	instMu.Lock()
	defer instMu.Unlock()

	if singleInstance != nil {
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

	// Integration point: forward packet bytes into xray-core Tun session.
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

	if err := stopXrayInternal(); err != nil {
		return C.CString("error:" + err.Error())
	}

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
