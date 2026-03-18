#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <shellapi.h>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

 // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      native_channel_;

  struct TrayMenuState {
    bool connected = false;
    std::string node_name = "-";
    std::string proxy_mode = "tun";
    std::string language_code = "zh";
  };

  enum class MenuTextKey {
    kStatus,
    kConnected,
    kDisconnected,
    kNode,
    kStartAcceleration,
    kStopAcceleration,
    kReconnect,
    kTunnelMode,
    kProxyMode,
    kShowMainWindow,
    kQuitAndStopAcceleration,
  };

  void RegisterNativeChannel();
  void HandleNativeMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ShowMainWindow();
  void ShowTrayContextMenu();
  void InvokeFlutterMenuAction(
      const std::string& action,
      flutter::EncodableMap payload = flutter::EncodableMap()) const;
  std::string MenuText(MenuTextKey key) const;
  std::wstring WideFromUtf8(const std::string& utf8_text) const;

  NOTIFYICONDATA nid_{};
  TrayMenuState tray_menu_state_{};
  bool quit_after_stop_ = false;

  static constexpr UINT kTrayMessage = WM_APP + 1;
  static constexpr UINT_PTR kQuitTimerId = 1;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
