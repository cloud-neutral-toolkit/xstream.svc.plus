//go:build windows

package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const payloadExeName = "xstream_runtime.exe"

//go:embed payload.zip
var payloadZip []byte

func payloadHash() string {
	sum := sha256.Sum256(payloadZip)
	return hex.EncodeToString(sum[:8])
}

func extractionDir() string {
	base, err := os.UserCacheDir()
	if err != nil || base == "" {
		base = os.TempDir()
	}
	return filepath.Join(base, "Xstream", "portable", payloadHash())
}

func showError(message string) {
	title, _ := syscall.UTF16PtrFromString("Xstream")
	body, _ := syscall.UTF16PtrFromString(message)
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBoxW := user32.NewProc("MessageBoxW")
	const mbIconError = 0x00000010
	messageBoxW.Call(
		0,
		uintptr(unsafe.Pointer(body)),
		uintptr(unsafe.Pointer(title)),
		uintptr(mbIconError),
	)
}

func logError(message string) {
	exePath, err := os.Executable()
	if err != nil {
		return
	}
	logPath := filepath.Join(filepath.Dir(exePath), "xstream-launcher-error.log")
	entry := fmt.Sprintf("[%s] %s\r\n", time.Now().Format(time.RFC3339), message)
	_ = os.WriteFile(logPath, []byte(entry), 0o644)
}

func writeMarker(dir string) error {
	return os.WriteFile(filepath.Join(dir, ".payload-hash"), []byte(payloadHash()), 0o644)
}

func payloadReady(dir string) bool {
	hashPath := filepath.Join(dir, ".payload-hash")
	hashBytes, err := os.ReadFile(hashPath)
	if err != nil {
		return false
	}
	if strings.TrimSpace(string(hashBytes)) != payloadHash() {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, payloadExeName))
	return err == nil
}

func extractPayload(dir string) error {
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	reader, err := zip.NewReader(bytes.NewReader(payloadZip), int64(len(payloadZip)))
	if err != nil {
		return err
	}

	prefix := dir + string(os.PathSeparator)
	for _, file := range reader.File {
		cleanName := filepath.Clean(file.Name)
		targetPath := filepath.Join(dir, cleanName)
		if targetPath != dir && !strings.HasPrefix(targetPath, prefix) {
			return fmt.Errorf("invalid archive path: %s", file.Name)
		}

		if file.FileInfo().IsDir() || strings.HasSuffix(file.Name, "/") || strings.HasSuffix(file.Name, "\\") {
			continue
		}

		if err := os.MkdirAll(filepath.Dir(targetPath), 0o755); err != nil {
			return fmt.Errorf("%s: create parent directory: %w", file.Name, err)
		}

		src, err := file.Open()
		if err != nil {
			return fmt.Errorf("%s: open zip entry: %w", file.Name, err)
		}

		dst, err := os.OpenFile(targetPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
		if err != nil {
			src.Close()
			return fmt.Errorf("%s: open destination: %w", file.Name, err)
		}

		_, copyErr := io.Copy(dst, src)
		closeErr := dst.Close()
		srcErr := src.Close()
		if copyErr != nil {
			return fmt.Errorf("%s: copy: %w", file.Name, copyErr)
		}
		if closeErr != nil {
			return fmt.Errorf("%s: close destination: %w", file.Name, closeErr)
		}
		if srcErr != nil {
			return fmt.Errorf("%s: close source: %w", file.Name, srcErr)
		}
	}

	return writeMarker(dir)
}

func ensurePayload(dir string) error {
	if payloadReady(dir) {
		return nil
	}
	return extractPayload(dir)
}

func launchRuntime(dir string) error {
	runtimeExe := filepath.Join(dir, payloadExeName)
	cmd := exec.Command(runtimeExe, os.Args[1:]...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "XSTREAM_SINGLE_FILE=1")
	cmd.SysProcAttr = &syscall.SysProcAttr{}
	return cmd.Start()
}

func main() {
	dir := extractionDir()
	if err := ensurePayload(dir); err != nil {
		message := "Failed to prepare the embedded runtime.\r\n\r\n" + err.Error()
		logError(message)
		showError(message)
		return
	}
	if err := launchRuntime(dir); err != nil {
		message := "Failed to launch the embedded runtime.\r\n\r\n" + err.Error()
		logError(message)
		showError(message)
	}
}
