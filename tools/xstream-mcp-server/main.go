package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

type cmdResult struct {
	OK         bool   `json:"ok"`
	Command    string `json:"command"`
	Cwd        string `json:"cwd"`
	DurationMs int64  `json:"durationMs"`
	Code       int    `json:"code,omitempty"`
	Stdout     string `json:"stdout"`
	Stderr     string `json:"stderr"`
}

type authState struct {
	mu        sync.Mutex
	baseURL   string
	token     string
	cookie    string
	mfaTicket string
}

var debugMode bool

func debugf(format string, args ...any) {
	if !debugMode {
		return
	}
	log.Printf("[xstream-mcp-debug] "+format, args...)
}

func (s *authState) snapshot() map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return map[string]any{
		"base_url":     s.baseURL,
		"has_token":    s.token != "",
		"has_cookie":   s.cookie != "",
		"mfa_required": s.mfaTicket != "",
	}
}

func (s *authState) update(baseURL, token, cookie, mfaTicket string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if baseURL != "" {
		s.baseURL = normalizeBaseURL(baseURL)
	}
	if token != "" {
		s.token = token
	}
	if cookie != "" {
		s.cookie = cookie
	}
	s.mfaTicket = mfaTicket
}

func (s *authState) values() (baseURL, token, cookie, mfaTicket string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.baseURL, s.token, s.cookie, s.mfaTicket
}

func main() {
	rootDir := os.Getenv("XSTREAM_ROOT")
	if rootDir == "" {
		wd, err := os.Getwd()
		if err != nil {
			panic(err)
		}
		rootDir = wd
	}

	absRoot, err := filepath.Abs(rootDir)
	if err != nil {
		panic(err)
	}

	auth := &authState{baseURL: "https://accounts.svc.plus"}
	client := &http.Client{Timeout: 30 * time.Second}
	debugMode = strings.EqualFold(strings.TrimSpace(os.Getenv("XSTREAM_MCP_DEBUG")), "true") ||
		strings.TrimSpace(os.Getenv("XSTREAM_MCP_DEBUG")) == "1"
	debugf("server start root=%s", absRoot)

	s := server.NewMCPServer("xstream-local-mcp", "0.3.0")

	s.AddTool(
		mcp.NewTool("workspace_info", mcp.WithDescription("Return XStream workspace metadata for MCP diagnostics.")),
		func(_ context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := map[string]any{
				"ok":                  true,
				"rootDir":             absRoot,
				"xcodeWorkspaceMacOS": filepath.Join(absRoot, "macos/Runner.xcworkspace"),
				"xcodeWorkspaceIOS":   filepath.Join(absRoot, "ios/Runner.xcworkspace"),
				"xcodeProjectMacOS":   filepath.Join(absRoot, "macos/Runner.xcodeproj"),
				"xcodeProjectIOS":     filepath.Join(absRoot, "ios/Runner.xcodeproj"),
				"auth_state":          auth.snapshot(),
				"note":                "Use xcworkspace for CocoaPods-based builds.",
			}
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("macos_app_paths", mcp.WithDescription("Discover local macOS app support/config/log paths used by XStream.")),
		func(_ context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := discoverMacOSPaths(absRoot)
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("macos_tail_logs",
			mcp.WithDescription("Tail log files under XStream macOS logs directory."),
			mcp.WithString("pattern", mcp.Description("Glob pattern, default *.log")),
			mcp.WithNumber("lines", mcp.Description("Tail line count, default 200")),
		),
		func(_ context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			pattern := req.GetString("pattern", "*.log")
			lines := req.GetInt("lines", 200)
			if lines <= 0 {
				lines = 200
			}
			res, err := tailMacOSLogs(absRoot, pattern, lines)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("macos_read_sync_artifacts", mcp.WithDescription("Read vpn_nodes.json and desktop_sync.json from local macOS app support path.")),
		func(_ context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res, err := readSyncArtifacts(absRoot)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("runtime_config_check",
			mcp.WithDescription("Check Xray runtime config.json structure and key fields."),
			mcp.WithString("config_path", mcp.Description("Override config path. Defaults to runtime config path.")),
		),
		func(_ context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			configPath := strings.TrimSpace(req.GetString("config_path", ""))
			res, err := checkRuntimeConfig(absRoot, configPath)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("runtime_log_check",
			mcp.WithDescription("Check Xray runtime log tail and summarize warning/error signals."),
			mcp.WithString("log_path", mcp.Description("Override runtime log path. Defaults to runtime log path.")),
			mcp.WithNumber("lines", mcp.Description("Tail line count, default 200")),
			mcp.WithString("grep", mcp.Description("Case-insensitive substring filter for returned lines.")),
		),
		func(_ context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			logPath := strings.TrimSpace(req.GetString("log_path", ""))
			lines := req.GetInt("lines", 200)
			if lines <= 0 {
				lines = 200
			}
			grep := strings.TrimSpace(req.GetString("grep", ""))
			res, err := checkRuntimeLog(absRoot, logPath, lines, grep)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("runtime_process_check",
			mcp.WithDescription("Check whether Xray runtime process is running and return process list matches."),
			mcp.WithString("executable", mcp.Description("Override executable path. Defaults to runtime executable path.")),
			mcp.WithString("config_path", mcp.Description("Optional config path filter. Defaults to runtime config path.")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			executable := strings.TrimSpace(req.GetString("executable", ""))
			configPath := strings.TrimSpace(req.GetString("config_path", ""))
			res, err := checkRuntimeProcess(ctx, absRoot, executable, configPath)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("runtime_diagnose",
			mcp.WithDescription("Run config/log/process checks for Xray runtime in one call."),
			mcp.WithNumber("lines", mcp.Description("Log tail line count, default 200")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			lines := req.GetInt("lines", 200)
			if lines <= 0 {
				lines = 200
			}
			paths, err := discoverRuntimePaths(absRoot)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			configRes, configErr := checkRuntimeConfig(absRoot, paths["runtime_config"])
			logRes, logErr := checkRuntimeLog(absRoot, paths["runtime_log"], lines, "")
			processRes, processErr := checkRuntimeProcess(ctx, absRoot, paths["executable"], paths["runtime_config"])
			res := map[string]any{
				"ok":            configErr == nil && logErr == nil && processErr == nil,
				"paths":         paths,
				"config_check":  configRes,
				"log_check":     logRes,
				"process_check": processRes,
			}
			if configErr != nil {
				res["config_error"] = configErr.Error()
			}
			if logErr != nil {
				res["log_error"] = logErr.Error()
			}
			if processErr != nil {
				res["process_error"] = processErr.Error()
			}
			return jsonResult(res, configErr != nil || logErr != nil || processErr != nil)
		},
	)

	s.AddTool(
		mcp.NewTool("runtime_post_start_inspect",
			mcp.WithDescription("Fixed post-start inspection pipeline: wait, paths, process, config, log, grep failed, diagnose. Continues checks even if process is not running."),
			mcp.WithNumber("wait_seconds", mcp.Description("Delay before inspection, default 30")),
			mcp.WithNumber("log_lines", mcp.Description("Log tail lines for checks, default 300")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			waitSeconds := req.GetInt("wait_seconds", 30)
			if waitSeconds < 0 {
				waitSeconds = 0
			}
			logLines := req.GetInt("log_lines", 300)
			if logLines <= 0 {
				logLines = 300
			}

			res, err := runPostStartInspectFlow(ctx, absRoot, waitSeconds, logLines)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			return jsonResult(res, false)
		},
	)

	s.AddTool(
		mcp.NewTool("auth_login",
			mcp.WithDescription("Call accounts login endpoint and cache token/cookie for sync debugging."),
			mcp.WithString("username", mcp.Description("Account username")),
			mcp.WithString("password", mcp.Description("Account password")),
			mcp.WithString("base_url", mcp.Description("Accounts base URL, default https://accounts.svc.plus")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			username := strings.TrimSpace(req.GetString("username", ""))
			password := strings.TrimSpace(req.GetString("password", ""))
			if username == "" {
				username = strings.TrimSpace(os.Getenv("XSTREAM_ACCOUNTS_USERNAME"))
			}
			if password == "" {
				password = strings.TrimSpace(os.Getenv("XSTREAM_ACCOUNTS_PASSWORD"))
			}
			if username == "" || password == "" {
				return mcp.NewToolResultError("missing username/password; pass arguments or set XSTREAM_ACCOUNTS_USERNAME/XSTREAM_ACCOUNTS_PASSWORD"), nil
			}
			baseURL := req.GetString("base_url", "")
			if baseURL == "" {
				baseURL, _, _, _ = auth.values()
			}
			if baseURL == "" {
				baseURL = strings.TrimSpace(os.Getenv("XSTREAM_ACCOUNTS_BASE_URL"))
			}
			if baseURL == "" {
				baseURL = "https://accounts.svc.plus"
			}
			baseURL = normalizeBaseURL(baseURL)

			payload := map[string]any{"username": username, "password": password}
			resp, body, parsed, err := doJSON(ctx, client, http.MethodPost, baseURL+"/api/auth/login", map[string]string{"Content-Type": "application/json", "Accept": "application/json"}, payload)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}

			mfaRequired := readBool(parsed, "mfa_required") || readBool(parsed, "mfaRequired")
			mfaTicket := firstNonEmpty(parsed, "mfa_ticket", "mfaTicket", "mfaToken")
			token := firstNonEmpty(parsed, "token", "access_token")
			cookie := extractSessionCookie(resp.Header.Get("Set-Cookie"))
			auth.update(baseURL, token, cookie, mfaTicket)

			res := map[string]any{
				"ok":           resp.StatusCode == 200 || mfaRequired,
				"status_code":  resp.StatusCode,
				"mfa_required": mfaRequired,
				"has_token":    token != "",
				"has_cookie":   cookie != "",
				"message":      firstNonEmpty(parsed, "message"),
				"body":         parsed,
				"raw_body":     body,
			}
			return jsonResult(res, resp.StatusCode >= 400 && !mfaRequired)
		},
	)

	s.AddTool(
		mcp.NewTool("auth_mfa_verify",
			mcp.WithDescription("Call MFA verify endpoint using cached mfa_ticket from auth_login."),
			mcp.WithString("code", mcp.Required(), mcp.Description("MFA code")),
			mcp.WithString("method", mcp.Description("MFA method, default totp")),
			mcp.WithString("base_url", mcp.Description("Accounts base URL override")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			code, err := req.RequireString("code")
			if err != nil {
				return mcp.NewToolResultError(err.Error()), nil
			}
			method := req.GetString("method", "totp")
			baseURL := req.GetString("base_url", "")
			stateBase, _, _, mfaTicket := auth.values()
			if baseURL == "" {
				baseURL = stateBase
			}
			if baseURL == "" {
				baseURL = "https://accounts.svc.plus"
			}
			if strings.TrimSpace(mfaTicket) == "" {
				return mcp.NewToolResultError("missing mfa_ticket; run auth_login first"), nil
			}

			payload := map[string]any{"mfa_ticket": mfaTicket, "code": strings.TrimSpace(code), "method": method}
			resp, body, parsed, err := doJSON(ctx, client, http.MethodPost, normalizeBaseURL(baseURL)+"/api/auth/mfa/verify", map[string]string{"Content-Type": "application/json", "Accept": "application/json"}, payload)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			token := firstNonEmpty(parsed, "token", "access_token")
			cookie := extractSessionCookie(resp.Header.Get("Set-Cookie"))
			auth.update(baseURL, token, cookie, "")
			res := map[string]any{
				"ok":          resp.StatusCode == 200,
				"status_code": resp.StatusCode,
				"has_token":   token != "",
				"has_cookie":  cookie != "",
				"message":     firstNonEmpty(parsed, "message"),
				"body":        parsed,
				"raw_body":    body,
			}
			return jsonResult(res, resp.StatusCode >= 400)
		},
	)

	s.AddTool(
		mcp.NewTool("auth_sync_pull",
			mcp.WithDescription("Call /api/auth/sync/config using cached token/cookie."),
			mcp.WithNumber("since_version", mcp.Description("Sync baseline version")),
			mcp.WithString("base_url", mcp.Description("Accounts base URL override")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			since := req.GetInt("since_version", 0)
			baseURL := req.GetString("base_url", "")
			stateBase, token, cookie, _ := auth.values()
			if baseURL == "" {
				baseURL = stateBase
			}
			if baseURL == "" {
				baseURL = "https://accounts.svc.plus"
			}
			if token == "" && cookie == "" {
				return mcp.NewToolResultError("missing auth state; run auth_login/auth_mfa_verify first"), nil
			}

			headers := map[string]string{"Accept": "application/json"}
			if token != "" {
				headers["Authorization"] = "Bearer " + token
			}
			if cookie != "" {
				headers["Cookie"] = cookie
			}
			url := fmt.Sprintf("%s/api/auth/sync/config?since_version=%d", normalizeBaseURL(baseURL), since)
			resp, body, parsed, err := doJSON(ctx, client, http.MethodGet, url, headers, nil)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			res := map[string]any{
				"ok":           resp.StatusCode == 200,
				"status_code":  resp.StatusCode,
				"changed":      readBool(parsed, "changed"),
				"version":      readInt(parsed, "version"),
				"has_rendered": firstNonEmpty(parsed, "rendered_json") != "",
				"digest":       firstNonEmpty(parsed, "digest"),
				"body":         parsed,
				"raw_body":     body,
			}
			return jsonResult(res, resp.StatusCode >= 400)
		},
	)

	s.AddTool(
		mcp.NewTool("auth_sync_ack",
			mcp.WithDescription("Call /api/auth/sync/ack with version/device_id/applied_at."),
			mcp.WithNumber("version", mcp.Required(), mcp.Description("Applied version")),
			mcp.WithString("device_id", mcp.Description("Device id; default mcp-local")),
			mcp.WithString("base_url", mcp.Description("Accounts base URL override")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			version, err := req.RequireInt("version")
			if err != nil {
				return mcp.NewToolResultError(err.Error()), nil
			}
			deviceID := req.GetString("device_id", "mcp-local")
			baseURL := req.GetString("base_url", "")
			stateBase, token, cookie, _ := auth.values()
			if baseURL == "" {
				baseURL = stateBase
			}
			if baseURL == "" {
				baseURL = "https://accounts.svc.plus"
			}
			if token == "" && cookie == "" {
				return mcp.NewToolResultError("missing auth state; run auth_login/auth_mfa_verify first"), nil
			}

			headers := map[string]string{"Content-Type": "application/json", "Accept": "application/json"}
			if token != "" {
				headers["Authorization"] = "Bearer " + token
			}
			if cookie != "" {
				headers["Cookie"] = cookie
			}
			payload := map[string]any{
				"version":    version,
				"device_id":  deviceID,
				"applied_at": time.Now().UTC().Format(time.RFC3339),
			}
			resp, body, parsed, err := doJSON(ctx, client, http.MethodPost, normalizeBaseURL(baseURL)+"/api/auth/sync/ack", headers, payload)
			if err != nil {
				return jsonResult(map[string]any{"ok": false, "error": err.Error()}, true)
			}
			res := map[string]any{"ok": resp.StatusCode < 400, "status_code": resp.StatusCode, "body": parsed, "raw_body": body}
			return jsonResult(res, resp.StatusCode >= 400)
		},
	)

	// Build/debug helpers
	s.AddTool(mcp.NewTool("flutter_pub_get", mcp.WithDescription("Run flutter pub get in XStream workspace.")),
		func(ctx context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := runCommand(ctx, absRoot, "flutter", "pub", "get")
			return jsonResult(res, !res.OK)
		},
	)
	s.AddTool(mcp.NewTool("flutter_analyze", mcp.WithDescription("Run flutter analyze in XStream workspace.")),
		func(ctx context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := runCommand(ctx, absRoot, "flutter", "analyze")
			return jsonResult(res, !res.OK)
		},
	)
	s.AddTool(mcp.NewTool("flutter_build_macos_debug", mcp.WithDescription("Build macOS debug app via flutter build macos --debug.")),
		func(ctx context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := runCommand(ctx, absRoot, "flutter", "build", "macos", "--debug")
			return jsonResult(res, !res.OK)
		},
	)
	s.AddTool(mcp.NewTool("flutter_build_ios_sim_debug", mcp.WithDescription("Build iOS simulator debug app via flutter build ios --debug --simulator.")),
		func(ctx context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := runCommand(ctx, absRoot, "flutter", "build", "ios", "--debug", "--simulator")
			return jsonResult(res, !res.OK)
		},
	)
	s.AddTool(mcp.NewTool("xcode_build_macos_workspace", mcp.WithDescription("Build macOS Runner via xcworkspace to ensure CocoaPods modules are linked.")),
		func(ctx context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := runCommand(ctx, absRoot, "xcodebuild", "-workspace", "macos/Runner.xcworkspace", "-scheme", "Runner", "-configuration", "Debug", "-sdk", "macosx", "build")
			return jsonResult(res, !res.OK)
		},
	)
	s.AddTool(mcp.NewTool("xcode_mcp_doctor", mcp.WithDescription("Run make xcode-mcp-doctor to prepare iOS/macOS workspaces for MCP debugging.")),
		func(ctx context.Context, _ mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			res := runCommand(ctx, absRoot, "make", "xcode-mcp-doctor")
			return jsonResult(res, !res.OK)
		},
	)

	if err := server.ServeStdio(s); err != nil {
		panic(err)
	}
}

func normalizeBaseURL(v string) string {
	value := strings.TrimSpace(v)
	if value == "" {
		return "https://accounts.svc.plus"
	}
	if !strings.HasPrefix(value, "http://") && !strings.HasPrefix(value, "https://") {
		value = "https://" + value
	}
	return strings.TrimRight(value, "/")
}

func doJSON(ctx context.Context, client *http.Client, method, url string, headers map[string]string, body any) (*http.Response, string, map[string]any, error) {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, "", nil, err
		}
		reader = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, url, reader)
	if err != nil {
		return nil, "", nil, err
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	debugf("http request method=%s url=%s headers=%v", method, url, sanitizeHeaders(headers))
	resp, err := client.Do(req)
	if err != nil {
		return nil, "", nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return resp, "", nil, err
	}
	raw := string(data)
	parsed := map[string]any{}
	if err := json.Unmarshal(data, &parsed); err != nil {
		parsed = map[string]any{}
	}
	debugf("http response status=%d url=%s body_bytes=%d", resp.StatusCode, url, len(data))
	return resp, raw, parsed, nil
}

func readBool(m map[string]any, key string) bool {
	v, ok := m[key]
	if !ok {
		return false
	}
	b, ok := v.(bool)
	return ok && b
}

func readInt(m map[string]any, key string) int {
	v, ok := m[key]
	if !ok {
		return 0
	}
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	default:
		return 0
	}
}

func firstNonEmpty(m map[string]any, keys ...string) string {
	for _, k := range keys {
		v, ok := m[k]
		if !ok {
			continue
		}
		s, ok := v.(string)
		if ok && strings.TrimSpace(s) != "" {
			return strings.TrimSpace(s)
		}
	}
	return ""
}

func extractSessionCookie(setCookie string) string {
	if strings.TrimSpace(setCookie) == "" {
		return ""
	}
	re := regexp.MustCompile(`xc_session=([^;]+)`)
	m := re.FindStringSubmatch(setCookie)
	if len(m) < 2 {
		return ""
	}
	return "xc_session=" + strings.TrimSpace(m[1])
}

func discoverMacOSPaths(root string) map[string]any {
	bundleID := readBundleID(root)
	candidates := buildAppSupportCandidates(bundleID)
	existing := make([]string, 0)
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && st.IsDir() {
			existing = append(existing, c)
		}
	}
	active := ""
	if len(existing) > 0 {
		active = existing[0]
	} else if len(candidates) > 0 {
		active = candidates[0]
	}
	return map[string]any{
		"ok":          true,
		"bundle_id":   bundleID,
		"candidates":  candidates,
		"existing":    existing,
		"active_base": active,
		"active_paths": map[string]string{
			"vpn_nodes":       filepath.Join(active, "vpn_nodes.json"),
			"sync_config":     filepath.Join(active, "configs", "desktop_sync.json"),
			"logs_dir":        filepath.Join(active, "logs"),
			"configs_dir":     filepath.Join(active, "configs"),
			"runtime_config":  filepath.Join(active, "configs", "config.json"),
			"runtime_log":     filepath.Join(active, "logs", "xray-runtime.log"),
			"runtime_bin_dir": filepath.Join(active, "bin"),
			"runtime_xray":    filepath.Join(active, "bin", "xray"),
		},
	}
}

func discoverRuntimePaths(root string) (map[string]string, error) {
	paths := discoverMacOSPaths(root)
	active, _ := paths["active_base"].(string)
	if strings.TrimSpace(active) == "" {
		return nil, fmt.Errorf("no active macOS app path detected")
	}
	return map[string]string{
		"base_dir":       active,
		"executable":     filepath.Join(active, "bin", "xray"),
		"runtime_config": filepath.Join(active, "configs", "config.json"),
		"runtime_log":    filepath.Join(active, "logs", "xray-runtime.log"),
	}, nil
}

func checkRuntimeConfig(root, overridePath string) (map[string]any, error) {
	paths, err := discoverRuntimePaths(root)
	if err != nil {
		return nil, err
	}
	configPath := strings.TrimSpace(overridePath)
	if configPath == "" {
		configPath = paths["runtime_config"]
	}
	st, err := os.Stat(configPath)
	if err != nil {
		return nil, fmt.Errorf("runtime config not found: %s", configPath)
	}
	raw, err := os.ReadFile(configPath)
	if err != nil {
		return nil, err
	}
	var parsed any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return map[string]any{
			"ok":          false,
			"config_path": configPath,
			"size":        st.Size(),
			"modified":    st.ModTime().Format(time.RFC3339),
			"json_valid":  false,
			"error":       err.Error(),
		}, nil
	}

	summary, warnings := summarizeRuntimeConfig(parsed)
	return map[string]any{
		"ok":          true,
		"config_path": configPath,
		"size":        st.Size(),
		"modified":    st.ModTime().Format(time.RFC3339),
		"json_valid":  true,
		"summary":     summary,
		"warnings":    warnings,
	}, nil
}

func summarizeRuntimeConfig(parsed any) (map[string]any, []string) {
	doc, ok := parsed.(map[string]any)
	if !ok {
		return map[string]any{
			"root_type": fmt.Sprintf("%T", parsed),
		}, []string{"config root is not a JSON object"}
	}

	warnings := make([]string, 0)
	summary := map[string]any{}

	if logCfg, ok := doc["log"].(map[string]any); ok {
		summary["loglevel"] = firstStringValue(logCfg, "loglevel", "level")
	}

	if dnsCfg, ok := doc["dns"].(map[string]any); ok {
		if servers, ok := dnsCfg["servers"].([]any); ok {
			summary["dns_server_count"] = len(servers)
		}
	}

	inboundCount := 0
	tunCount := 0
	if inbounds, ok := doc["inbounds"].([]any); ok {
		inboundCount = len(inbounds)
		for i, inboundRaw := range inbounds {
			inbound, ok := inboundRaw.(map[string]any)
			if !ok {
				continue
			}
			protocol, _ := inbound["protocol"].(string)
			if protocol != "tun" {
				continue
			}
			tunCount++
			settings, _ := inbound["settings"].(map[string]any)
			if settings == nil {
				continue
			}
			for _, key := range []string{"interfaceName", "name", "interface"} {
				value, exists := settings[key]
				if !exists {
					continue
				}
				name, ok := value.(string)
				if !ok || !regexp.MustCompile(`^utun\d+$`).MatchString(name) {
					warnings = append(warnings, fmt.Sprintf("inbounds[%d].settings.%s is not utunN (%v)", i, key, value))
				}
			}
		}
	}
	summary["inbound_count"] = inboundCount
	summary["tun_inbound_count"] = tunCount

	if outbounds, ok := doc["outbounds"].([]any); ok {
		summary["outbound_count"] = len(outbounds)
	}

	return summary, warnings
}

func firstStringValue(m map[string]any, keys ...string) string {
	for _, key := range keys {
		v, ok := m[key]
		if !ok {
			continue
		}
		s, ok := v.(string)
		if ok && strings.TrimSpace(s) != "" {
			return strings.TrimSpace(s)
		}
	}
	return ""
}

func checkRuntimeLog(root, overridePath string, lines int, grep string) (map[string]any, error) {
	paths, err := discoverRuntimePaths(root)
	if err != nil {
		return nil, err
	}
	logPath := strings.TrimSpace(overridePath)
	if logPath == "" {
		logPath = paths["runtime_log"]
	}
	st, err := os.Stat(logPath)
	if err != nil {
		return nil, fmt.Errorf("runtime log not found: %s", logPath)
	}
	raw, err := os.ReadFile(logPath)
	if err != nil {
		return nil, err
	}
	allLines := strings.Split(strings.ReplaceAll(string(raw), "\r\n", "\n"), "\n")
	tail := allLines
	if lines < len(allLines) {
		tail = allLines[len(allLines)-lines:]
	}
	filtered := tail
	if strings.TrimSpace(grep) != "" {
		g := strings.ToLower(strings.TrimSpace(grep))
		filtered = make([]string, 0, len(tail))
		for _, line := range tail {
			if strings.Contains(strings.ToLower(line), g) {
				filtered = append(filtered, line)
			}
		}
	}

	errorCount := 0
	warnCount := 0
	infoCount := 0
	samples := make([]string, 0, 20)
	for _, line := range tail {
		lower := strings.ToLower(line)
		switch {
		case strings.Contains(lower, "[error]") || strings.Contains(lower, " error "):
			errorCount++
		case strings.Contains(lower, "[warning]") || strings.Contains(lower, " warning "):
			warnCount++
		case strings.Contains(lower, "[info]") || strings.Contains(lower, " info "):
			infoCount++
		}
		if strings.Contains(lower, "failed") || strings.Contains(lower, "panic") {
			if len(samples) < 20 {
				samples = append(samples, line)
			}
		}
	}

	return map[string]any{
		"ok":         true,
		"log_path":   logPath,
		"size":       st.Size(),
		"modified":   st.ModTime().Format(time.RFC3339),
		"line_count": len(allLines),
		"tail_lines": len(tail),
		"grep":       grep,
		"matched":    len(filtered),
		"level_count": map[string]int{
			"error": errorCount,
			"warn":  warnCount,
			"info":  infoCount,
		},
		"failure_samples": samples,
		"tail":            strings.Join(filtered, "\n"),
	}, nil
}

func checkRuntimeProcess(ctx context.Context, root, overrideExe, overrideConfig string) (map[string]any, error) {
	paths, err := discoverRuntimePaths(root)
	if err != nil {
		return nil, err
	}
	executable := strings.TrimSpace(overrideExe)
	if executable == "" {
		executable = paths["executable"]
	}
	configPath := strings.TrimSpace(overrideConfig)
	if configPath == "" {
		configPath = paths["runtime_config"]
	}

	psRes := runCommand(ctx, "/", "ps", "-axo", "pid,ppid,etime,command")
	if !psRes.OK {
		return map[string]any{
			"ok":      false,
			"command": psRes.Command,
			"stderr":  psRes.Stderr,
		}, nil
	}

	lines := strings.Split(strings.ReplaceAll(psRes.Stdout, "\r\n", "\n"), "\n")
	matches := make([]map[string]any, 0)
	exeBase := filepath.Base(executable)
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(strings.ToLower(trimmed), "pid ") {
			continue
		}
		fields := strings.Fields(trimmed)
		if len(fields) < 4 {
			continue
		}
		pid := fields[0]
		ppid := fields[1]
		etime := fields[2]
		command := strings.Join(fields[3:], " ")
		lowerCmd := strings.ToLower(command)

		matchedByExe := strings.Contains(command, executable) ||
			strings.Contains(lowerCmd, "/"+strings.ToLower(exeBase)+" ") ||
			strings.Contains(lowerCmd, " "+strings.ToLower(exeBase)+" ")
		if !matchedByExe {
			continue
		}
		matchedByConfig := configPath == "" || strings.Contains(command, configPath)
		matches = append(matches, map[string]any{
			"pid":          pid,
			"ppid":         ppid,
			"etime":        etime,
			"command":      command,
			"match_config": matchedByConfig,
		})
	}

	configMatches := 0
	for _, item := range matches {
		if v, ok := item["match_config"].(bool); ok && v {
			configMatches++
		}
	}

	return map[string]any{
		"ok":                    true,
		"executable":            executable,
		"config_path":           configPath,
		"running":               len(matches) > 0,
		"process_count":         len(matches),
		"config_match_count":    configMatches,
		"processes":             matches,
		"process_query_command": psRes.Command,
	}, nil
}

func runPostStartInspectFlow(ctx context.Context, root string, waitSeconds, logLines int) (map[string]any, error) {
	steps := make([]map[string]any, 0, 7)
	start := time.Now()

	if waitSeconds > 0 {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Duration(waitSeconds) * time.Second):
		}
	}
	steps = append(steps, map[string]any{
		"step":         "1_wait",
		"ok":           true,
		"wait_seconds": waitSeconds,
	})

	pathsView := discoverMacOSPaths(root)
	steps = append(steps, map[string]any{
		"step": "2_macos_app_paths",
		"ok":   true,
		"data": pathsView,
	})

	paths, pathsErr := discoverRuntimePaths(root)
	if pathsErr != nil {
		steps = append(steps, map[string]any{
			"step":  "path_resolution",
			"ok":    false,
			"error": pathsErr.Error(),
		})
		return map[string]any{
			"ok":          false,
			"duration_ms": time.Since(start).Milliseconds(),
			"steps":       steps,
		}, nil
	}

	processRes, processErr := checkRuntimeProcess(ctx, root, "", paths["runtime_config"])
	steps = append(steps, map[string]any{
		"step":  "3_runtime_process_check",
		"ok":    processErr == nil,
		"data":  processRes,
		"error": errString(processErr),
	})

	configRes, configErr := checkRuntimeConfig(root, paths["runtime_config"])
	steps = append(steps, map[string]any{
		"step":  "4_runtime_config_check",
		"ok":    configErr == nil,
		"data":  configRes,
		"error": errString(configErr),
	})

	logRes, logErr := checkRuntimeLog(root, paths["runtime_log"], logLines, "")
	steps = append(steps, map[string]any{
		"step":  "5_runtime_log_check",
		"ok":    logErr == nil,
		"data":  logRes,
		"error": errString(logErr),
	})

	grepRes, grepErr := checkRuntimeLog(root, paths["runtime_log"], 500, "failed")
	steps = append(steps, map[string]any{
		"step":  "6_runtime_log_check_failed",
		"ok":    grepErr == nil,
		"data":  grepRes,
		"error": errString(grepErr),
	})

	diagRes := map[string]any{
		"ok":            configErr == nil && logErr == nil && processErr == nil,
		"paths":         paths,
		"config_check":  configRes,
		"log_check":     logRes,
		"process_check": processRes,
	}
	if configErr != nil {
		diagRes["config_error"] = configErr.Error()
	}
	if logErr != nil {
		diagRes["log_error"] = logErr.Error()
	}
	if processErr != nil {
		diagRes["process_error"] = processErr.Error()
	}

	steps = append(steps, map[string]any{
		"step": "7_runtime_diagnose",
		"ok":   configErr == nil && logErr == nil && processErr == nil,
		"data": diagRes,
	})

	return map[string]any{
		"ok":          true,
		"duration_ms": time.Since(start).Milliseconds(),
		"steps":       steps,
		"summary": map[string]any{
			"process_check_ok": processErr == nil,
			"config_check_ok":  configErr == nil,
			"log_check_ok":     logErr == nil,
			"running":          readBoolFromMap(processRes, "running"),
		},
	}, nil
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func readBoolFromMap(m map[string]any, key string) bool {
	if m == nil {
		return false
	}
	v, ok := m[key]
	if !ok {
		return false
	}
	b, ok := v.(bool)
	return ok && b
}

func readSyncArtifacts(root string) (map[string]any, error) {
	paths := discoverMacOSPaths(root)
	active, _ := paths["active_base"].(string)
	if strings.TrimSpace(active) == "" {
		return nil, fmt.Errorf("no active macOS app path detected")
	}
	vpnPath := filepath.Join(active, "vpn_nodes.json")
	syncPath := filepath.Join(active, "configs", "desktop_sync.json")
	vpnRaw, _ := os.ReadFile(vpnPath)
	syncRaw, _ := os.ReadFile(syncPath)
	return map[string]any{
		"ok":          true,
		"base_path":   active,
		"vpn_nodes":   decodeJSON(string(vpnRaw)),
		"sync_config": decodeJSON(string(syncRaw)),
		"vpn_path":    vpnPath,
		"sync_path":   syncPath,
	}, nil
}

func tailMacOSLogs(root, pattern string, lines int) (map[string]any, error) {
	paths := discoverMacOSPaths(root)
	active, _ := paths["active_base"].(string)
	if strings.TrimSpace(active) == "" {
		return nil, fmt.Errorf("no active macOS app path detected")
	}
	logDir := filepath.Join(active, "logs")
	entries, err := filepath.Glob(filepath.Join(logDir, pattern))
	if err != nil {
		return nil, err
	}
	sort.Strings(entries)
	files := make([]map[string]any, 0, len(entries))
	for _, p := range entries {
		st, err := os.Stat(p)
		if err != nil || st.IsDir() {
			continue
		}
		content, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		files = append(files, map[string]any{
			"path":     p,
			"size":     st.Size(),
			"modified": st.ModTime().Format(time.RFC3339),
			"tail":     lastLines(string(content), lines),
		})
	}
	return map[string]any{"ok": true, "log_dir": logDir, "files": files}, nil
}

func decodeJSON(raw string) any {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return map[string]any{}
	}
	var out any
	if err := json.Unmarshal([]byte(trimmed), &out); err != nil {
		return map[string]any{"raw": raw, "parse_error": err.Error()}
	}
	return out
}

func lastLines(content string, n int) string {
	lines := strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n")
	if n >= len(lines) {
		return strings.Join(lines, "\n")
	}
	return strings.Join(lines[len(lines)-n:], "\n")
}

func readBundleID(root string) string {
	content, err := os.ReadFile(filepath.Join(root, "macos", "Runner", "Configs", "AppInfo.xcconfig"))
	if err != nil {
		return "xstream.svc.plus"
	}
	for _, line := range strings.Split(string(content), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "PRODUCT_BUNDLE_IDENTIFIER") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				v := strings.TrimSpace(parts[1])
				if v != "" {
					return v
				}
			}
		}
	}
	return "xstream.svc.plus"
}

func buildAppSupportCandidates(bundleID string) []string {
	home, _ := os.UserHomeDir()
	unique := map[string]bool{}
	out := make([]string, 0)
	add := func(p string) {
		if p == "" || unique[p] {
			return
		}
		unique[p] = true
		out = append(out, p)
	}
	ids := []string{bundleID, "xstream.svc.plus", "com.xstream"}
	for _, id := range ids {
		add(filepath.Join(home, "Library", "Application Support", id))
		add(filepath.Join(home, "Library", "Containers", id, "Data", "Library", "Application Support", id))
	}
	return out
}

func runCommand(parent context.Context, cwd string, command string, args ...string) cmdResult {
	start := time.Now()
	ctx, cancel := context.WithTimeout(parent, 10*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(ctx, command, args...)
	cmd.Dir = cwd
	cmd.Env = os.Environ()

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	res := cmdResult{
		OK:      true,
		Command: strings.TrimSpace(command + " " + strings.Join(args, " ")),
		Cwd:     cwd,
	}
	debugf("run command: %s", res.Command)

	err := cmd.Run()
	res.DurationMs = time.Since(start).Milliseconds()
	res.Stdout = stdout.String()
	res.Stderr = stderr.String()
	if err == nil {
		return res
	}

	res.OK = false
	if exitErr, ok := err.(*exec.ExitError); ok {
		res.Code = exitErr.ExitCode()
	} else {
		res.Stderr = res.Stderr + "\n" + err.Error()
	}
	return res
}

func sanitizeHeaders(h map[string]string) map[string]string {
	out := make(map[string]string, len(h))
	for k, v := range h {
		lk := strings.ToLower(k)
		if lk == "authorization" || lk == "cookie" {
			out[k] = "***"
			continue
		}
		out[k] = v
	}
	return out
}

func jsonResult(v any, isErr bool) (*mcp.CallToolResult, error) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return nil, err
	}
	if isErr {
		return mcp.NewToolResultError(string(data)), nil
	}
	return mcp.NewToolResultText(string(data)), nil
}
