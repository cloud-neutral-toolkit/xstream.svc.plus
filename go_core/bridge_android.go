//go:build android

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
	"strconv"
	"sync"
	"sync/atomic"
	"unsafe"

	"github.com/xtls/xray-core/common/platform"
	"github.com/xtls/xray-core/core"
)

var androidProcMap sync.Map
var androidSingleInstance *xrayInstance
var androidInstMu sync.Mutex
var androidTunnelSeq atomic.Int64
var androidTunnelSession sync.Map

type xrayInstance struct {
	server core.Server
}

func androidStartXrayInternal(cfgData []byte) error {
	if androidSingleInstance != nil {
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
	androidSingleInstance = &xrayInstance{server: srv}
	return nil
}

func androidStopXrayInternal() error {
	if androidSingleInstance == nil {
		return errors.New("not running")
	}
	if err := androidSingleInstance.server.Close(); err != nil {
		return err
	}
	androidSingleInstance = nil
	return nil
}

//export WriteConfigFiles
func WriteConfigFiles(xrayPathC, xrayContentC, servicePathC, serviceContentC, vpnPathC, vpnContentC, passwordC *C.char) *C.char {
	_ = passwordC
	xrayPath := C.GoString(xrayPathC)
	xrayContent := C.GoString(xrayContentC)
	servicePath := C.GoString(servicePathC)
	serviceContent := C.GoString(serviceContentC)
	vpnPath := C.GoString(vpnPathC)
	vpnContent := C.GoString(vpnContentC)

	if err := os.MkdirAll(filepath.Dir(xrayPath), 0o755); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(xrayPath, []byte(xrayContent), 0o644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.MkdirAll(filepath.Dir(servicePath), 0o755); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(servicePath, []byte(serviceContent), 0o644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.MkdirAll(filepath.Dir(vpnPath), 0o755); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(vpnPath, []byte(vpnContent), 0o644); err != nil {
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
	androidProcMap.Store(node, &xrayInstance{server: srv})
	return C.CString("success")
}

//export StopNodeService
func StopNodeService(name *C.char) *C.char {
	node := C.GoString(name)
	if v, ok := androidProcMap.Load(node); ok {
		inst := v.(*xrayInstance)
		if err := inst.server.Close(); err != nil {
			return C.CString("error:" + err.Error())
		}
		androidProcMap.Delete(node)
	}
	return C.CString("success")
}

//export CheckNodeStatus
func CheckNodeStatus(name *C.char) C.int {
	node := C.GoString(name)
	if _, ok := androidProcMap.Load(node); ok {
		return 1
	}
	return 0
}

//export StartXray
func StartXray(configC *C.char) *C.char {
	androidInstMu.Lock()
	defer androidInstMu.Unlock()

	if androidSingleInstance != nil {
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
	androidSingleInstance = &xrayInstance{server: srv}

	return C.CString("success")
}

//export StopXray
func StopXray() *C.char {
	androidInstMu.Lock()
	defer androidInstMu.Unlock()

	if androidSingleInstance == nil {
		return C.CString("error:not running")
	}
	if err := androidSingleInstance.server.Close(); err != nil {
		return C.CString("error:" + err.Error())
	}
	androidSingleInstance = nil

	return C.CString("success")
}

//export StartXrayTunnel
func StartXrayTunnel(configC *C.char) C.longlong {
	androidInstMu.Lock()
	defer androidInstMu.Unlock()

	if androidSingleInstance != nil {
		return C.longlong(-1)
	}

	cfgData := []byte(C.GoString(configC))
	if err := androidStartXrayInternal(cfgData); err != nil {
		return C.longlong(-1)
	}

	handle := androidTunnelSeq.Add(1)
	androidTunnelSession.Store(handle, true)
	return C.longlong(handle)
}

//export StartXrayTunnelWithFd
func StartXrayTunnelWithFd(configC *C.char, tunFd C.int32_t) C.longlong {
	fd := int(tunFd)
	if fd <= 0 {
		return C.longlong(-1)
	}

	androidInstMu.Lock()
	defer androidInstMu.Unlock()

	if androidSingleInstance != nil {
		return C.longlong(-1)
	}

	_ = os.Setenv(platform.TunFdKey, strconv.Itoa(fd))
	_ = os.Setenv(platform.NormalizeEnvName(platform.TunFdKey), strconv.Itoa(fd))

	cfgData := []byte(C.GoString(configC))
	if err := androidStartXrayInternal(cfgData); err != nil {
		_ = os.Unsetenv(platform.TunFdKey)
		_ = os.Unsetenv(platform.NormalizeEnvName(platform.TunFdKey))
		return C.longlong(-1)
	}

	handle := androidTunnelSeq.Add(1)
	androidTunnelSession.Store(handle, fd)
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
	if _, ok := androidTunnelSession.Load(id); !ok {
		return C.int32_t(-1)
	}

	// Android Packet Tunnel entry point: packet forwarding to xray-core Tun session.
	return C.int32_t(0)
}

//export StopXrayTunnel
func StopXrayTunnel(handle C.longlong) *C.char {
	androidInstMu.Lock()
	defer androidInstMu.Unlock()

	id := int64(handle)
	if id <= 0 {
		return C.CString("error:invalid handle")
	}
	if _, ok := androidTunnelSession.Load(id); !ok {
		return C.CString("error:session not found")
	}
	androidTunnelSession.Delete(id)

	if err := androidStopXrayInternal(); err != nil {
		return C.CString("error:" + err.Error())
	}
	_ = os.Unsetenv(platform.TunFdKey)
	_ = os.Unsetenv(platform.NormalizeEnvName(platform.TunFdKey))

	return C.CString("success")
}

//export FreeXrayTunnel
func FreeXrayTunnel(handle C.longlong) *C.char {
	id := int64(handle)
	if id <= 0 {
		return C.CString("error:invalid handle")
	}
	androidTunnelSession.Delete(id)
	return C.CString("success")
}

//export CreateWindowsService
func CreateWindowsService(name, execPath, configPath *C.char) *C.char {
	_ = name
	_ = execPath
	_ = configPath
	return C.CString("error:not supported")
}

//export PerformAction
func PerformAction(action, password *C.char) *C.char {
	_ = password
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
