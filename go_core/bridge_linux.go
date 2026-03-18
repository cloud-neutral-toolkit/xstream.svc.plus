//go:build linux

package main

/*
#cgo LDFLAGS: -lX11
#include <stdlib.h>
#include <string.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

static Display* disp = NULL;
static Window mainWin = 0;

static Window getMainWin() {
    return mainWin;
}

static Window findWindow(const char* name) {
    if (disp == NULL) {
        disp = XOpenDisplay(NULL);
        if (disp == NULL) return 0;
    }
    Atom clientList = XInternAtom(disp, "_NET_CLIENT_LIST", True);
    Atom type;
    int format;
    unsigned long nitems, bytes;
    unsigned char* data = NULL;
    if (XGetWindowProperty(disp, DefaultRootWindow(disp), clientList, 0, 1024, False, XA_WINDOW, &type, &format, &nitems, &bytes, &data) == Success && data) {
        Window* list = (Window*)data;
        for (unsigned long i=0; i<nitems; i++) {
            char* wname = NULL;
            if (XFetchName(disp, list[i], &wname) > 0) {
                if (wname && strcmp(wname, name)==0) {
                    mainWin = list[i];
                    if (wname) XFree(wname);
                    XFree(data);
                    return mainWin;
                }
                if (wname) XFree(wname);
            }
        }
        XFree(data);
    }
    return 0;
}

static int isIconic() {
    if (!disp || mainWin==0) return 0;
    Atom WM_STATE = XInternAtom(disp, "WM_STATE", True);
    Atom type; int format; unsigned long items, bytes; unsigned char* prop=NULL;
    if (XGetWindowProperty(disp, mainWin, WM_STATE, 0, 2, False, WM_STATE, &type, &format, &items, &bytes, &prop) == Success && prop) {
        long state = *(long*)prop;
        XFree(prop);
        return state == IconicState;
    }
    return 0;
}

static void hideWindow() {
    if (disp && mainWin) { XUnmapWindow(disp, mainWin); XFlush(disp); }
}

static void showWindow() {
    if (disp && mainWin) { XMapRaised(disp, mainWin); XFlush(disp); }
}
*/
import "C"
import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/getlantern/systray"
	"github.com/xtls/libxray/xray"
)

var procMap sync.Map
var instMu sync.Mutex

type desktopIntegrationRequest struct {
	Action   string `json:"action"`
	Enable   bool   `json:"enable,omitempty"`
	ExecPath string `json:"execPath,omitempty"`
	Title    string `json:"title,omitempty"`
	Body     string `json:"body,omitempty"`
	Mode     string `json:"mode,omitempty"`
}

type desktopIntegrationResponse struct {
	OK                 bool   `json:"ok"`
	Message            string `json:"message,omitempty"`
	DesktopEnvironment string `json:"desktopEnvironment,omitempty"`
	AutostartEnabled   bool   `json:"autostartEnabled,omitempty"`
	PrivilegeReady     bool   `json:"privilegeReady,omitempty"`
	HelperPath         string `json:"helperPath,omitempty"`
}

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

func desktopIntegrationResult(resp desktopIntegrationResponse) *C.char {
	data, err := json.Marshal(resp)
	if err != nil {
		return C.CString(`{"ok":false,"message":"failed to encode response"}`)
	}
	return C.CString(string(data))
}

func detectDesktopEnvironment() string {
	candidates := []string{
		strings.ToLower(os.Getenv("XDG_CURRENT_DESKTOP")),
		strings.ToLower(os.Getenv("DESKTOP_SESSION")),
		strings.ToLower(os.Getenv("XDG_SESSION_DESKTOP")),
	}
	for _, candidate := range candidates {
		switch {
		case strings.Contains(candidate, "gnome"), strings.Contains(candidate, "ubuntu"), strings.Contains(candidate, "unity"):
			return "gnome"
		case strings.Contains(candidate, "kde"), strings.Contains(candidate, "plasma"):
			return "kde"
		}
	}
	return "unknown"
}

func runOutput(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(output)), err
}

func linuxConfigDir() string {
	dir, err := os.UserConfigDir()
	if err != nil || dir == "" {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, ".config", "xstream")
	}
	return filepath.Join(dir, "xstream")
}

func linuxAutostartDesktopFile() string {
	dir, err := os.UserConfigDir()
	if err != nil || dir == "" {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, ".config", "autostart", "xstream.desktop")
	}
	return filepath.Join(dir, "autostart", "xstream.desktop")
}

func linuxProxySnapshotPath() string {
	return filepath.Join(linuxConfigDir(), "linux_proxy_snapshot.json")
}

func linuxTunnelHelperPath() string {
	candidates := []string{
		"/usr/libexec/xstream/xstream-net-helper",
		filepath.Join(filepath.Dir(os.Args[0]), "xstream-net-helper"),
		filepath.Join(filepath.Dir(os.Args[0]), "..", "libexec", "xstream", "xstream-net-helper"),
		"scripts/linux/xstream-net-helper",
	}
	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			return candidate
		}
	}
	return ""
}

func notifyDesktop(title, body string) error {
	if _, err := exec.LookPath("notify-send"); err != nil {
		return err
	}
	_, err := runOutput("notify-send", title, body)
	return err
}

func setAutostartEnabled(enable bool, execPath string) error {
	desktopFile := linuxAutostartDesktopFile()
	if enable {
		if execPath == "" {
			execPath = "/opt/xstream/xstream"
		}
		if err := os.MkdirAll(filepath.Dir(desktopFile), 0755); err != nil {
			return err
		}
		content := strings.Join([]string{
			"[Desktop Entry]",
			"Type=Application",
			"Version=1.0",
			"Name=Xstream",
			"Comment=Xstream desktop launcher",
			"Exec=" + execPath,
			"Icon=xstream",
			"Terminal=false",
			"Categories=Network;Utility;",
			"X-GNOME-Autostart-enabled=true",
			"",
		}, "\n")
		return os.WriteFile(desktopFile, []byte(content), 0644)
	}
	if err := os.Remove(desktopFile); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func isAutostartEnabled() bool {
	_, err := os.Stat(linuxAutostartDesktopFile())
	return err == nil
}

func writeProxySnapshot(data map[string]string) error {
	if err := os.MkdirAll(filepath.Dir(linuxProxySnapshotPath()), 0755); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(linuxProxySnapshotPath(), raw, 0644)
}

func readProxySnapshot() map[string]string {
	raw, err := os.ReadFile(linuxProxySnapshotPath())
	if err != nil {
		return map[string]string{}
	}
	var data map[string]string
	if err := json.Unmarshal(raw, &data); err != nil {
		return map[string]string{}
	}
	return data
}

func gsettingsGet(schema string, key string) string {
	output, err := runOutput("gsettings", "get", schema, key)
	if err != nil {
		return ""
	}
	return output
}

func gsettingsSet(schema string, key string, value string) error {
	_, err := runOutput("gsettings", "set", schema, key, value)
	return err
}

func kdeConfigTool() string {
	for _, candidate := range []string{"kwriteconfig6", "kwriteconfig5", "kwriteconfig"} {
		if _, err := exec.LookPath(candidate); err == nil {
			return candidate
		}
	}
	return ""
}

func kreadConfigTool() string {
	for _, candidate := range []string{"kreadconfig6", "kreadconfig5", "kreadconfig"} {
		if _, err := exec.LookPath(candidate); err == nil {
			return candidate
		}
	}
	return ""
}

func reloadKDEProxy() {
	if _, err := exec.LookPath("qdbus"); err == nil {
		_, _ = runOutput("qdbus", "org.kde.KIO.Scheduler", "/KIO/Scheduler", "org.kde.KIO.Scheduler.reparseSlaveConfiguration", "")
		return
	}
	if _, err := exec.LookPath("dbus-send"); err == nil {
		_, _ = runOutput("dbus-send", "--session", "--dest=org.kde.KIO.Scheduler", "--type=method_call", "/KIO/Scheduler", "org.kde.KIO.Scheduler.reparseSlaveConfiguration")
	}
}

func setLinuxProxy(enable bool) error {
	desktop := detectDesktopEnvironment()
	switch desktop {
	case "gnome":
		if enable {
			snapshot := map[string]string{
				"desktop":   "gnome",
				"mode":      gsettingsGet("org.gnome.system.proxy", "mode"),
				"socksHost": gsettingsGet("org.gnome.system.proxy.socks", "host"),
				"socksPort": gsettingsGet("org.gnome.system.proxy.socks", "port"),
				"httpHost":  gsettingsGet("org.gnome.system.proxy.http", "host"),
				"httpPort":  gsettingsGet("org.gnome.system.proxy.http", "port"),
			}
			if err := writeProxySnapshot(snapshot); err != nil {
				return err
			}
			for _, op := range []struct {
				schema string
				key    string
				value  string
			}{
				{"org.gnome.system.proxy", "mode", "'manual'"},
				{"org.gnome.system.proxy.socks", "host", "'127.0.0.1'"},
				{"org.gnome.system.proxy.socks", "port", "1080"},
				{"org.gnome.system.proxy.http", "host", "'127.0.0.1'"},
				{"org.gnome.system.proxy.http", "port", "1081"},
			} {
				if err := gsettingsSet(op.schema, op.key, op.value); err != nil {
					return err
				}
			}
			return nil
		}
		snapshot := readProxySnapshot()
		mode := snapshot["mode"]
		if mode == "" {
			mode = "'none'"
		}
		for _, op := range []struct {
			schema string
			key    string
			value  string
		}{
			{"org.gnome.system.proxy", "mode", mode},
			{"org.gnome.system.proxy.socks", "host", "'" + strings.Trim(snapshot["socksHost"], "'") + "'"},
			{"org.gnome.system.proxy.socks", "port", defaultIfEmpty(snapshot["socksPort"], "0")},
			{"org.gnome.system.proxy.http", "host", "'" + strings.Trim(snapshot["httpHost"], "'") + "'"},
			{"org.gnome.system.proxy.http", "port", defaultIfEmpty(snapshot["httpPort"], "0")},
		} {
			if op.value == "" {
				continue
			}
			if err := gsettingsSet(op.schema, op.key, op.value); err != nil {
				return err
			}
		}
		return nil
	case "kde":
		writer := kdeConfigTool()
		reader := kreadConfigTool()
		if writer == "" {
			return errors.New("kwriteconfig is required for KDE proxy integration")
		}
		if enable {
			snapshot := map[string]string{"desktop": "kde"}
			if reader != "" {
				for _, item := range []struct {
					key   string
					group string
					name  string
				}{
					{"ProxyType", "Proxy Settings", "ProxyType"},
					{"httpProxy", "Proxy Settings", "httpProxy"},
					{"socksProxy", "Proxy Settings", "socksProxy"},
				} {
					value, _ := runOutput(reader, "--file", "kioslaverc", "--group", item.group, "--key", item.name)
					snapshot[item.key] = value
				}
			}
			if err := writeProxySnapshot(snapshot); err != nil {
				return err
			}
			for _, args := range [][]string{
				{"--file", "kioslaverc", "--group", "Proxy Settings", "--key", "ProxyType", "1"},
				{"--file", "kioslaverc", "--group", "Proxy Settings", "--key", "httpProxy", "http://127.0.0.1 1081"},
				{"--file", "kioslaverc", "--group", "Proxy Settings", "--key", "socksProxy", "socks://127.0.0.1 1080"},
			} {
				if _, err := runOutput(writer, args...); err != nil {
					return err
				}
			}
			reloadKDEProxy()
			return nil
		}
		snapshot := readProxySnapshot()
		proxyType := defaultIfEmpty(snapshot["ProxyType"], "0")
		httpProxy := snapshot["httpProxy"]
		socksProxy := snapshot["socksProxy"]
		for _, args := range [][]string{
			{"--file", "kioslaverc", "--group", "Proxy Settings", "--key", "ProxyType", proxyType},
			{"--file", "kioslaverc", "--group", "Proxy Settings", "--key", "httpProxy", httpProxy},
			{"--file", "kioslaverc", "--group", "Proxy Settings", "--key", "socksProxy", socksProxy},
		} {
			if _, err := runOutput(writer, args...); err != nil {
				return err
			}
		}
		reloadKDEProxy()
		return nil
	default:
		return errors.New("unsupported desktop environment")
	}
}

func defaultIfEmpty(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func handleTunnelHelper(action string, mode string) (string, error) {
	helper := linuxTunnelHelperPath()
	if helper == "" {
		return "", errors.New("xstream-net-helper not found")
	}
	if _, err := exec.LookPath("pkexec"); err != nil {
		return helper, errors.New("pkexec not found")
	}
	args := []string{helper, action}
	if mode != "" {
		args = append(args, "--mode", mode)
	}
	output, err := runOutput("pkexec", args...)
	if err != nil {
		return helper, errors.New(strings.TrimSpace(output))
	}
	return helper, nil
}

//export DesktopIntegrationCommand
func DesktopIntegrationCommand(requestC *C.char) *C.char {
	var req desktopIntegrationRequest
	if err := json.Unmarshal([]byte(C.GoString(requestC)), &req); err != nil {
		return desktopIntegrationResult(desktopIntegrationResponse{
			OK:      false,
			Message: "invalid request: " + err.Error(),
		})
	}

	resp := desktopIntegrationResponse{
		OK:                 true,
		DesktopEnvironment: detectDesktopEnvironment(),
		AutostartEnabled:   isAutostartEnabled(),
	}

	switch req.Action {
	case "getDesktopEnvironment":
		resp.PrivilegeReady = linuxTunnelHelperPath() != ""
	case "setSystemProxy":
		if err := setLinuxProxy(true); err != nil {
			resp.OK = false
			resp.Message = err.Error()
		} else {
			resp.Message = "system proxy enabled"
		}
	case "clearSystemProxy":
		if err := setLinuxProxy(false); err != nil {
			resp.OK = false
			resp.Message = err.Error()
		} else {
			resp.Message = "system proxy restored"
		}
	case "setAutostartEnabled":
		if err := setAutostartEnabled(req.Enable, req.ExecPath); err != nil {
			resp.OK = false
			resp.Message = err.Error()
		} else {
			resp.AutostartEnabled = req.Enable
			resp.Message = "autostart updated"
		}
	case "isAutostartEnabled":
		resp.Message = "autostart status loaded"
	case "ensureTunnelPrivileges":
		helper := linuxTunnelHelperPath()
		resp.HelperPath = helper
		if helper == "" {
			resp.OK = false
			resp.Message = "xstream-net-helper not found"
			break
		}
		if _, err := exec.LookPath("pkexec"); err != nil {
			resp.OK = false
			resp.Message = "pkexec not found"
			break
		}
		resp.PrivilegeReady = true
		resp.Message = "tunnel privileges ready"
	case "startTunnelHelper":
		helper, err := handleTunnelHelper("start", req.Mode)
		resp.HelperPath = helper
		if err != nil {
			resp.OK = false
			resp.Message = err.Error()
		} else {
			resp.PrivilegeReady = true
			resp.Message = "tunnel helper started"
		}
	case "stopTunnelHelper":
		helper, err := handleTunnelHelper("stop", req.Mode)
		resp.HelperPath = helper
		if err != nil {
			resp.OK = false
			resp.Message = err.Error()
		} else {
			resp.Message = "tunnel helper stopped"
		}
	case "notify":
		if err := notifyDesktop(defaultIfEmpty(req.Title, "Xstream"), req.Body); err != nil {
			resp.OK = false
			resp.Message = err.Error()
		} else {
			resp.Message = "notification sent"
		}
	default:
		resp.OK = false
		resp.Message = "unsupported action"
	}

	resp.AutostartEnabled = isAutostartEnabled()
	return desktopIntegrationResult(resp)
}

//export WriteConfigFiles
func WriteConfigFiles(xrayPathC, xrayContentC, servicePathC, serviceContentC, vpnPathC, vpnContentC, passwordC *C.char) *C.char {
	xrayPath := C.GoString(xrayPathC)
	xrayContent := C.GoString(xrayContentC)
	servicePath := C.GoString(servicePathC)
	serviceContent := C.GoString(serviceContentC)
	vpnPath := C.GoString(vpnPathC)
	vpnContent := C.GoString(vpnContentC)
	_ = passwordC

	if err := os.MkdirAll(filepath.Dir(xrayPath), 0755); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(xrayPath, []byte(xrayContent), 0644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.MkdirAll(filepath.Dir(servicePath), 0755); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.WriteFile(servicePath, []byte(serviceContent), 0644); err != nil {
		return C.CString("error:" + err.Error())
	}
	if err := os.MkdirAll(filepath.Dir(vpnPath), 0755); err != nil {
		return C.CString("error:" + err.Error())
	}
	var existing []map[string]interface{}
	if data, err := os.ReadFile(vpnPath); err == nil {
		json.Unmarshal(data, &existing)
	}
	var newNodes []map[string]interface{}
	if err := json.Unmarshal([]byte(vpnContent), &newNodes); err == nil {
		existing = append(existing, newNodes...)
	} else {
		return C.CString("error:invalid vpn node content")
	}
	updated, _ := json.MarshalIndent(existing, "", "  ")
	if err := os.WriteFile(vpnPath, updated, 0644); err != nil {
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

// ---- System tray integration ----

var trayOnce sync.Once

func monitorMinimize() {
	for {
		if C.getMainWin() == 0 {
			cname := C.CString("xstream")
			C.findWindow(cname)
			C.free(unsafe.Pointer(cname))
		}
		if C.getMainWin() != 0 {
			if C.isIconic() != 0 {
				C.hideWindow()
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
}

//export InitTray
func InitTray() {
	trayOnce.Do(func() {
		go func() {
			runtime.LockOSThread()
			systray.Run(func() {
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
							if C.getMainWin() == 0 {
								cname := C.CString("xstream")
								C.findWindow(cname)
								C.free(unsafe.Pointer(cname))
							}
							if C.getMainWin() != 0 {
								C.showWindow()
							}
						case <-mQuit.ClickedCh:
							systray.Quit()
							return
						}
					}
				}()
				go monitorMinimize()
			}, func() {})
		}()
	})
}
