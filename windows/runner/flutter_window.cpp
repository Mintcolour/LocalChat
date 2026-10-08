#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>

#include <chrono>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "firewall_manager.h"
#include "autostart.h"
#include "automation_bridge.h"
#include "single_instance.h"

namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return "";
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.length()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.length()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

std::wstring ClipboardTempDirectory() {
  wchar_t temp_path[MAX_PATH];
  DWORD length = GetTempPathW(MAX_PATH, temp_path);
  std::wstring directory(temp_path, length);
  directory += L"LocalChatClipboard";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory;
}

std::wstring UniqueClipboardImagePath() {
  auto now = std::chrono::system_clock::now().time_since_epoch().count();
  std::wstringstream stream;
  stream << ClipboardTempDirectory() << L"\\clipboard-" << now << L".bmp";
  return stream.str();
}

std::vector<std::string> ReadClipboardFilePaths() {
  std::vector<std::string> paths;
  HANDLE handle = GetClipboardData(CF_HDROP);
  if (handle == nullptr) {
    return paths;
  }
  HDROP drop = static_cast<HDROP>(handle);
  UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT index = 0; index < count; ++index) {
    UINT length = DragQueryFileW(drop, index, nullptr, 0);
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, index, path.data(), length + 1);
    path.resize(length);
    paths.push_back(WideToUtf8(path));
  }
  return paths;
}

DWORD DibColorTableSize(const BITMAPINFOHEADER* header) {
  if (header->biClrUsed > 0) {
    return header->biClrUsed * sizeof(RGBQUAD);
  }
  if (header->biBitCount <= 8) {
    return (1ull << header->biBitCount) * sizeof(RGBQUAD);
  }
  return 0;
}

DWORD DibMaskSize(const BITMAPINFOHEADER* header) {
  if (header->biSize == sizeof(BITMAPINFOHEADER) &&
      header->biCompression == BI_BITFIELDS) {
    return 3 * sizeof(DWORD);
  }
  return 0;
}

std::optional<std::string> SaveClipboardDibImage() {
  HANDLE handle = GetClipboardData(CF_DIB);
  if (handle == nullptr) {
    return std::nullopt;
  }
  void* dib = GlobalLock(handle);
  if (dib == nullptr) {
    return std::nullopt;
  }
  SIZE_T dib_size = GlobalSize(handle);
  if (dib_size < sizeof(BITMAPINFOHEADER)) {
    GlobalUnlock(handle);
    return std::nullopt;
  }

  auto* header = static_cast<BITMAPINFOHEADER*>(dib);
  DWORD pixel_offset = sizeof(BITMAPFILEHEADER) + header->biSize +
                       DibMaskSize(header) + DibColorTableSize(header);
  BITMAPFILEHEADER file_header = {};
  file_header.bfType = 0x4D42;
  file_header.bfSize =
      static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + dib_size);
  file_header.bfOffBits = pixel_offset;

  std::wstring path = UniqueClipboardImagePath();
  std::ofstream output(path, std::ios::binary);
  if (!output) {
    GlobalUnlock(handle);
    return std::nullopt;
  }
  output.write(reinterpret_cast<const char*>(&file_header),
               sizeof(file_header));
  output.write(static_cast<const char*>(dib), dib_size);
  output.close();
  GlobalUnlock(handle);
  return WideToUtf8(path);
}

flutter::EncodableValue GetClipboardFiles(HWND hwnd) {
  flutter::EncodableList list;
  if (!OpenClipboard(hwnd)) {
    return flutter::EncodableValue(list);
  }
  std::vector<std::string> paths = ReadClipboardFilePaths();
  if (paths.empty()) {
    std::optional<std::string> image_path = SaveClipboardDibImage();
    if (image_path.has_value()) {
      paths.push_back(image_path.value());
    }
  }
  CloseClipboard();
  for (const auto& path : paths) {
    list.emplace_back(path);
  }
  return flutter::EncodableValue(list);
}

bool BoolFromMap(const flutter::EncodableMap& map,
                 const char* key,
                 bool fallback = false) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end() && std::holds_alternative<bool>(it->second)) {
    return std::get<bool>(it->second);
  }
  return fallback;
}

std::string StringFromMap(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end() && std::holds_alternative<std::string>(it->second)) {
    return std::get<std::string>(it->second);
  }
  return "";
}

std::vector<QuickDropDevice> ParseQuickDropDevices(
    const flutter::EncodableValue* args) {
  std::vector<QuickDropDevice> devices;
  if (args == nullptr) {
    return devices;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (map == nullptr) {
    return devices;
  }
  auto devices_it = map->find(flutter::EncodableValue("devices"));
  if (devices_it == map->end() ||
      !std::holds_alternative<flutter::EncodableList>(devices_it->second)) {
    return devices;
  }
  const auto& list = std::get<flutter::EncodableList>(devices_it->second);
  for (const auto& item : list) {
    const auto* device_map = std::get_if<flutter::EncodableMap>(&item);
    if (device_map == nullptr) {
      continue;
    }
    QuickDropDevice device;
    device.id = StringFromMap(*device_map, "id");
    device.display_name = StringFromMap(*device_map, "displayName");
    device.platform = StringFromMap(*device_map, "platform");
    device.avatar_initial = StringFromMap(*device_map, "avatarInitial");
    device.avatar_color = StringFromMap(*device_map, "avatarColor");
    device.selected = BoolFromMap(*device_map, "selected");
    if (!device.id.empty()) {
      devices.push_back(device);
    }
  }
  return devices;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool automation_start)
    : project_(project), automation_start_(automation_start) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

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
  auto clipboard_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "localchat/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getFiles") {
          result->Success(GetClipboardFiles(GetHandle()));
          return;
        }
        result->NotImplemented();
      });
  clipboard_channel_ = std::move(clipboard_channel);

  // 托盘与窗口控制通道：最小化到托盘、显示、退出、开机自启开关。
  tray_.AddTrayIcon(GetHandle());
  tray_.SetShowCallback([this]() {
    ShowWindow(GetHandle(), SW_SHOWNORMAL);
    SetForegroundWindow(GetHandle());
  });
  tray_.SetQuitCallback([this]() {
    tray_.RemoveTrayIcon();
    SetHideOnClose(false);
    SetQuitOnClose(true);
    Destroy();
  });
  // 默认开启"关窗隐藏到托盘"以实现后台常驻。
  SetHideOnClose(true);
  auto window_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "localchat/window",
          &flutter::StandardMethodCodec::GetInstance());
  quick_drop_shelf_.SetDropCallback(
      [this](const std::string& device_id,
             const std::vector<std::string>& paths) {
        if (!window_channel_) {
          return;
        }
        flutter::EncodableList path_list;
        for (const auto& path : paths) {
          path_list.emplace_back(path);
        }
        flutter::EncodableMap args;
        args[flutter::EncodableValue("deviceId")] =
            flutter::EncodableValue(device_id);
        args[flutter::EncodableValue("paths")] =
            flutter::EncodableValue(path_list);
        window_channel_->InvokeMethod(
            "quickDropFiles",
            std::make_unique<flutter::EncodableValue>(args));
      });
  window_channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "publishAutomationDescriptor") {
          const auto* args = call.arguments();
          const auto* map = args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
          if (map == nullptr) {
            result->Error("invalid_arguments", "Descriptor contents required.");
            return;
          }
          const auto it = map->find(flutter::EncodableValue("contents"));
          const auto* contents = it == map->end()
                                     ? nullptr
                                     : std::get_if<std::string>(&it->second);
          if (contents == nullptr) {
            result->Error("invalid_arguments", "Descriptor contents required.");
            return;
          }
          std::wstring path;
          DWORD error = ERROR_SUCCESS;
          if (!automation::PublishDescriptor(*contents, &path, &error)) {
            result->Error("automation_publish_failed",
                          "Could not secure or publish automation descriptor.",
                          flutter::EncodableValue(static_cast<int64_t>(error)));
            return;
          }
          result->Success(flutter::EncodableValue(WideToUtf8(path)));
          return;
        }
        if (method == "removeAutomationDescriptor") {
          automation::RemoveDescriptor();
          result->Success();
          return;
        }
        if (method == "minimizeToTray") {
          ShowWindow(GetHandle(), SW_HIDE);
          result->Success();
          return;
        }
        if (method == "show") {
          ShowWindow(GetHandle(), SW_SHOWNORMAL);
          SetForegroundWindow(GetHandle());
          result->Success();
          return;
        }
        if (method == "isForeground") {
          const HWND handle = GetHandle();
          const bool foreground =
              handle != nullptr && IsWindowVisible(handle) &&
              GetForegroundWindow() == handle;
          result->Success(flutter::EncodableValue(foreground));
          return;
        }
        if (method == "quit") {
          tray_.RemoveTrayIcon();
          SetHideOnClose(false);
          SetQuitOnClose(true);
          Destroy();
          result->Success();
          return;
        }
        if (method == "isAutostartEnabled") {
          result->Success(flutter::EncodableValue(autostart::IsEnabled()));
          return;
        }
        if (method == "setAutostartEnabled") {
          const auto* args = call.arguments();
          bool enabled = false;
          if (args != nullptr) {
            const auto* map = std::get_if<flutter::EncodableMap>(args);
            if (map != nullptr) {
              auto it = map->find(flutter::EncodableValue("enabled"));
              if (it != map->end() && std::holds_alternative<bool>(it->second)) {
                enabled = std::get<bool>(it->second);
              }
            }
          }
          result->Success(flutter::EncodableValue(autostart::SetEnabled(enabled)));
          return;
        }
        if (method == "setTrayEnabled") {
          const auto* args = call.arguments();
          bool enabled = true;
          if (args != nullptr) {
            const auto* map = std::get_if<flutter::EncodableMap>(args);
            if (map != nullptr) {
              auto it = map->find(flutter::EncodableValue("enabled"));
              if (it != map->end() && std::holds_alternative<bool>(it->second)) {
                enabled = std::get<bool>(it->second);
              }
            }
          }
          if (enabled || (automation_start_ && !IsWindowVisible(GetHandle()))) {
            tray_.AddTrayIcon(GetHandle());
            SetHideOnClose(true);
          } else {
            tray_.RemoveTrayIcon();
            SetHideOnClose(false);
          }
          result->Success();
          return;
        }
        if (method == "setQuickSendEnabled") {
          const auto* args = call.arguments();
          bool enabled = false;
          if (args != nullptr) {
            const auto* map = std::get_if<flutter::EncodableMap>(args);
            if (map != nullptr) {
              enabled = BoolFromMap(*map, "enabled");
            }
          }
          if (!quick_drop_shelf_.SetEnabled(enabled, GetHandle())) {
            result->Error("quick_send_start_failed",
                          "Could not start Windows file drag detection.");
            return;
          }
          result->Success();
          return;
        }
        if (method == "updateQuickSendDevices") {
          quick_drop_shelf_.UpdateDevices(ParseQuickDropDevices(call.arguments()));
          result->Success();
          return;
        }
        if (method == "getQuickSendDiagnostics") {
          const auto diagnostic = quick_drop_shelf_.GetDiagnostics();
          flutter::EncodableMap map;
          const auto put = [&](const char* key, flutter::EncodableValue value) {
            map[flutter::EncodableValue(key)] = std::move(value);
          };
          put("build", flutter::EncodableValue("drag-explorer-compact-v4"));
          put("enabled", flutter::EncodableValue(quick_drop_shelf_.IsEnabled()));
          put("monitorRunning", flutter::EncodableValue(diagnostic.running));
          put("uiaAvailable", flutter::EncodableValue(diagnostic.uia_available));
          put("panelVisible", flutter::EncodableValue(quick_drop_shelf_.IsVisible()));
          put("buttonsSwapped", flutter::EncodableValue(GetSystemMetrics(SM_SWAPBUTTON) != 0));
          put("mouseEvents", flutter::EncodableValue(static_cast<int64_t>(diagnostic.mouse_events)));
          put("mousePresses", flutter::EncodableValue(static_cast<int64_t>(diagnostic.mouse_presses)));
          put("dragThresholds", flutter::EncodableValue(static_cast<int64_t>(diagnostic.drag_thresholds)));
          put("probesStarted", flutter::EncodableValue(static_cast<int64_t>(diagnostic.probes_started)));
          put("probesCompleted", flutter::EncodableValue(static_cast<int64_t>(diagnostic.probes_completed)));
          put("resultsApplied", flutter::EncodableValue(static_cast<int64_t>(diagnostic.results_applied)));
          put("dragsAccepted", flutter::EncodableValue(static_cast<int64_t>(diagnostic.drags_accepted)));
          put("timerTicks", flutter::EncodableValue(static_cast<int64_t>(diagnostic.timer_ticks)));
          put("probePending", flutter::EncodableValue(diagnostic.probe_pending));
          put("shownCount", flutter::EncodableValue(static_cast<int64_t>(quick_drop_shelf_.ShownCount())));
          flutter::EncodableList probes;
          for (const auto& probe : diagnostic.recent_probes) {
            flutter::EncodableMap item;
            item[flutter::EncodableValue("sourceClass")] = flutter::EncodableValue(probe.source_class);
            item[flutter::EncodableValue("ancestors")] = flutter::EncodableValue(probe.ancestor_classes);
            item[flutter::EncodableValue("decision")] = flutter::EncodableValue(probe.decision);
            item[flutter::EncodableValue("nativeListView")] = flutter::EncodableValue(probe.native_list_view);
            item[flutter::EncodableValue("nativeQuery")] = flutter::EncodableValue(probe.native_query);
            item[flutter::EncodableValue("nativeItemIndex")] = flutter::EncodableValue(probe.native_item_index);
            item[flutter::EncodableValue("nativeHitFlags")] = flutter::EncodableValue(static_cast<int64_t>(probe.native_hit_flags));
            item[flutter::EncodableValue("nativeScreenPoint")] = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue(probe.native_screen_point.x), flutter::EncodableValue(probe.native_screen_point.y)});
            item[flutter::EncodableValue("nativeClientPoint")] = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue(probe.native_client_point.x), flutter::EncodableValue(probe.native_client_point.y)});
            item[flutter::EncodableValue("nativeClientSize")] = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue(probe.native_client_size.cx), flutter::EncodableValue(probe.native_client_size.cy)});
            item[flutter::EncodableValue("nativeListViewResult")] = flutter::EncodableValue(static_cast<int64_t>(probe.native_list_view_result));
            item[flutter::EncodableValue("probeMs")] = flutter::EncodableValue(static_cast<int64_t>(probe.probe_ms));
            item[flutter::EncodableValue("sourceProcess")] = flutter::EncodableValue(static_cast<int64_t>(probe.source_process));
            item[flutter::EncodableValue("uiaProcess")] = flutter::EncodableValue(probe.uia_process);
            item[flutter::EncodableValue("uiaSourceDecision")] = flutter::EncodableValue(probe.uia_source_decision);
            item[flutter::EncodableValue("uiaCandidates")] = flutter::EncodableValue(probe.uia_candidates);
            item[flutter::EncodableValue("uiaPropertyResult")] = flutter::EncodableValue(static_cast<int64_t>(probe.uia_property_result));
            probes.emplace_back(std::move(item));
          }
          put("recentProbes", flutter::EncodableValue(probes));
          result->Success(flutter::EncodableValue(map));
          return;
        }
        result->NotImplemented();
      });
  window_channel_ = std::move(window_channel);

  auto windows_network_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "localchat/windows_network",
          &flutter::StandardMethodCodec::GetInstance());
  windows_network_channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto status_map = []() {
          const auto status = firewall::GetStatus();
          flutter::EncodableMap value;
          value[flutter::EncodableValue("udpConfigured")] =
              flutter::EncodableValue(status.udp_configured);
          value[flutter::EncodableValue("tcpConfigured")] =
              flutter::EncodableValue(status.tcp_configured);
          value[flutter::EncodableValue("errorCode")] =
              flutter::EncodableValue(static_cast<int64_t>(status.error_code));
          return value;
        };
        if (call.method_name() == "getFirewallStatus") {
          result->Success(flutter::EncodableValue(status_map()));
          return;
        }
        if (call.method_name() == "repairFirewall") {
          const DWORD repair_result = firewall::RunElevatedRepair(GetHandle());
          if (repair_result != 0) {
            result->Error(std::to_string(repair_result),
                          repair_result == ERROR_CANCELLED
                              ? "The administrator prompt was canceled."
                              : "Unable to configure Windows Firewall.");
            return;
          }
          result->Success(flutter::EncodableValue(status_map()));
          return;
        }
        result->NotImplemented();
      });
  windows_network_channel_ = std::move(windows_network_channel);

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!automation_start_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  automation::RemoveDescriptor();
  quick_drop_shelf_.Destroy();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == single_instance::ActivationMessage()) {
    ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOWNORMAL);
    SetForegroundWindow(hwnd);
    FLASHWINFO flash = {};
    flash.cbSize = sizeof(flash);
    flash.hwnd = hwnd;
    flash.dwFlags = FLASHW_TRAY;
    flash.uCount = 2;
    flash.dwTimeout = 0;
    FlashWindowEx(&flash);
    return 0;
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  // 托盘图标回调（左键双击显示、右键菜单）。
  if (tray_.HandleCallback(wparam, lparam)) {
    return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
