#include "flutter_window.h"

#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kMenuIdStartStop = 1001;
constexpr UINT kMenuIdReconnect = 1002;
constexpr UINT kMenuIdTunnelMode = 1003;
constexpr UINT kMenuIdProxyMode = 1004;
constexpr UINT kMenuIdShowWindow = 1005;
constexpr UINT kMenuIdQuit = 1006;

std::optional<bool> FindBoolValue(const flutter::EncodableMap& map,
                                  const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return std::nullopt;
}

std::optional<std::string> FindStringValue(const flutter::EncodableMap& map,
                                           const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return std::nullopt;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Initialize system tray icon
  nid_ = {};
  nid_.cbSize = sizeof(NOTIFYICONDATA);
  nid_.hWnd = GetHandle();
  nid_.uID = 1;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = kTrayMessage;
  nid_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  lstrcpyW(nid_.szTip, L"xstream");
  Shell_NotifyIcon(NIM_ADD, &nid_);

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterNativeChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  native_channel_.reset();

  Shell_NotifyIcon(NIM_DELETE, &nid_);

  Win32Window::OnDestroy();
}

void FlutterWindow::RegisterNativeChannel() {
  native_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.xstream/native",
          &flutter::StandardMethodCodec::GetInstance());
  native_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleNativeMethodCall(call, std::move(result));
      });
}

void FlutterWindow::HandleNativeMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "updateMenuState") {
    result->NotImplemented();
    return;
  }

  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    result->Error("INVALID_ARGS", "Missing tray menu state");
    return;
  }

  if (const auto connected = FindBoolValue(*arguments, "connected")) {
    tray_menu_state_.connected = *connected;
  }
  if (const auto node_name = FindStringValue(*arguments, "nodeName")) {
    tray_menu_state_.node_name =
        node_name->empty() ? "-" : *node_name;
  }
  if (const auto proxy_mode = FindStringValue(*arguments, "proxyMode")) {
    tray_menu_state_.proxy_mode = *proxy_mode;
  }
  if (const auto language_code = FindStringValue(*arguments, "languageCode")) {
    tray_menu_state_.language_code = *language_code;
  }

  result->Success(flutter::EncodableValue("success"));
}

void FlutterWindow::ShowMainWindow() {
  Show();
  SetForegroundWindow(GetHandle());
}

std::wstring FlutterWindow::WideFromUtf8(const std::string& utf8_text) const {
  if (utf8_text.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8_text.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring wide_text(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8_text.c_str(), -1, wide_text.data(),
                      size);
  if (!wide_text.empty() && wide_text.back() == L'\0') {
    wide_text.pop_back();
  }
  return wide_text;
}

std::string FlutterWindow::MenuText(MenuTextKey key) const {
  const bool use_zh =
      tray_menu_state_.language_code.rfind("zh", 0) == 0;
  if (use_zh) {
    switch (key) {
      case MenuTextKey::kStatus:
        return "状态";
      case MenuTextKey::kConnected:
        return "已连接";
      case MenuTextKey::kDisconnected:
        return "未连接";
      case MenuTextKey::kNode:
        return "节点";
      case MenuTextKey::kStartAcceleration:
        return "启动加速";
      case MenuTextKey::kStopAcceleration:
        return "停止加速";
      case MenuTextKey::kReconnect:
        return "重新连接";
      case MenuTextKey::kTunnelMode:
        return "隧道模式";
      case MenuTextKey::kProxyMode:
        return "代理模式";
      case MenuTextKey::kShowMainWindow:
        return "显示主窗口";
      case MenuTextKey::kQuitAndStopAcceleration:
        return "退出并停止加速";
    }
  }

  switch (key) {
    case MenuTextKey::kStatus:
      return "Status";
    case MenuTextKey::kConnected:
      return "Connected";
    case MenuTextKey::kDisconnected:
      return "Disconnected";
    case MenuTextKey::kNode:
      return "Node";
    case MenuTextKey::kStartAcceleration:
      return "Start Acceleration";
    case MenuTextKey::kStopAcceleration:
      return "Stop Acceleration";
    case MenuTextKey::kReconnect:
      return "Reconnect";
    case MenuTextKey::kTunnelMode:
      return "Tunnel Mode";
    case MenuTextKey::kProxyMode:
      return "Proxy Mode";
    case MenuTextKey::kShowMainWindow:
      return "Show Main Window";
    case MenuTextKey::kQuitAndStopAcceleration:
      return "Quit & Stop Acceleration";
  }

  return "";
}

void FlutterWindow::InvokeFlutterMenuAction(
    const std::string& action, flutter::EncodableMap payload) const {
  if (!native_channel_) {
    return;
  }

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  arguments[flutter::EncodableValue("payload")] = flutter::EncodableValue(payload);
  native_channel_->InvokeMethod("nativeMenuAction",
                                std::make_unique<flutter::EncodableValue>(
                                    flutter::EncodableValue(arguments)));
}

void FlutterWindow::ShowTrayContextMenu() {
  HMENU menu = CreatePopupMenu();
  HMENU mode_menu = CreatePopupMenu();
  if (menu == nullptr || mode_menu == nullptr) {
    if (mode_menu != nullptr) {
      DestroyMenu(mode_menu);
    }
    if (menu != nullptr) {
      DestroyMenu(menu);
    }
    return;
  }

  const auto status_text = WideFromUtf8(
      MenuText(MenuTextKey::kStatus) + ": " +
      (tray_menu_state_.connected ? MenuText(MenuTextKey::kConnected)
                                  : MenuText(MenuTextKey::kDisconnected)));
  const auto node_text = WideFromUtf8(
      MenuText(MenuTextKey::kNode) + ": " + tray_menu_state_.node_name);
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, status_text.c_str());
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, node_text.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  const auto start_stop_label = WideFromUtf8(
      tray_menu_state_.connected ? MenuText(MenuTextKey::kStopAcceleration)
                                 : MenuText(MenuTextKey::kStartAcceleration));
  AppendMenuW(menu, MF_STRING, kMenuIdStartStop, start_stop_label.c_str());

  UINT reconnect_flags = MF_STRING;
  if (tray_menu_state_.node_name.empty() || tray_menu_state_.node_name == "-") {
    reconnect_flags |= MF_GRAYED;
  }
  AppendMenuW(menu, reconnect_flags, kMenuIdReconnect,
              WideFromUtf8(MenuText(MenuTextKey::kReconnect)).c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  const bool tunnel_mode = tray_menu_state_.proxy_mode != "proxyOnly";
  AppendMenuW(mode_menu, MF_STRING | (tunnel_mode ? MF_CHECKED : MF_UNCHECKED),
              kMenuIdTunnelMode,
              WideFromUtf8(MenuText(MenuTextKey::kTunnelMode)).c_str());
  AppendMenuW(mode_menu,
              MF_STRING | (!tunnel_mode ? MF_CHECKED : MF_UNCHECKED),
              kMenuIdProxyMode,
              WideFromUtf8(MenuText(MenuTextKey::kProxyMode)).c_str());
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(mode_menu),
              WideFromUtf8(MenuText(MenuTextKey::kProxyMode)).c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  AppendMenuW(menu, MF_STRING, kMenuIdShowWindow,
              WideFromUtf8(MenuText(MenuTextKey::kShowMainWindow)).c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuIdQuit,
              WideFromUtf8(MenuText(MenuTextKey::kQuitAndStopAcceleration))
                  .c_str());

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(GetHandle());
  const UINT command = TrackPopupMenu(
      menu, TPM_BOTTOMALIGN | TPM_LEFTALIGN | TPM_RETURNCMD | TPM_NONOTIFY,
      cursor.x, cursor.y, 0, GetHandle(), nullptr);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
  DestroyMenu(menu);

  flutter::EncodableMap payload;
  if (!tray_menu_state_.node_name.empty() && tray_menu_state_.node_name != "-") {
    payload[flutter::EncodableValue("nodeName")] =
        flutter::EncodableValue(tray_menu_state_.node_name);
  }
  payload[flutter::EncodableValue("proxyMode")] =
      flutter::EncodableValue(tray_menu_state_.proxy_mode);

  switch (command) {
    case kMenuIdStartStop:
      InvokeFlutterMenuAction(
          tray_menu_state_.connected ? "stopAcceleration"
                                     : "startAcceleration",
          payload);
      break;
    case kMenuIdReconnect:
      InvokeFlutterMenuAction("reconnectAcceleration", payload);
      break;
    case kMenuIdTunnelMode:
      tray_menu_state_.proxy_mode = "tun";
      InvokeFlutterMenuAction("setProxyMode",
                              {{flutter::EncodableValue("mode"),
                                flutter::EncodableValue("VPN")}});
      break;
    case kMenuIdProxyMode:
      tray_menu_state_.proxy_mode = "proxyOnly";
      InvokeFlutterMenuAction("setProxyMode",
                              {{flutter::EncodableValue("mode"),
                                flutter::EncodableValue("仅代理")}});
      break;
    case kMenuIdShowWindow:
      ShowMainWindow();
      InvokeFlutterMenuAction("showMainWindow");
      break;
    case kMenuIdQuit:
      if (tray_menu_state_.connected) {
        quit_after_stop_ = true;
        InvokeFlutterMenuAction("stopAcceleration", payload);
        SetTimer(GetHandle(), kQuitTimerId, 1000, nullptr);
      } else {
        PostMessage(GetHandle(), WM_CLOSE, 0, 0);
      }
      break;
    default:
      break;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kTrayMessage:
      if (LOWORD(lparam) == WM_LBUTTONUP) {
        ShowMainWindow();
      } else if (LOWORD(lparam) == WM_RBUTTONUP ||
                 LOWORD(lparam) == WM_CONTEXTMENU) {
        ShowTrayContextMenu();
      }
      return 0;
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kQuitTimerId && quit_after_stop_) {
        KillTimer(hwnd, kQuitTimerId);
        quit_after_stop_ = false;
        PostMessage(hwnd, WM_CLOSE, 0, 0);
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
