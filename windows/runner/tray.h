#ifndef RUNNER_TRAY_H_
#define RUNNER_TRAY_H_

#include <windows.h>

#include <functional>

// 管理系统托盘图标与右键菜单。
// 关窗时由 FlutterWindow 决定隐藏到托盘还是退出；本类只负责图标/菜单/回调。
class TrayController {
 public:
  TrayController();
  ~TrayController();

  TrayController(const TrayController&) = delete;
  TrayController& operator=(const TrayController&) = delete;

  // 注册托盘图标，关联到 |owner| 窗口。返回是否成功。
  bool AddTrayIcon(HWND owner);

  // 移除托盘图标。
  void RemoveTrayIcon();

  // 是否已注册托盘图标。
  bool HasIcon() const { return has_icon_; }

  // 处理托盘回调消息（WM_APP+kCallbackMessage）。
  // 返回 true 表示已消费该消息。
  bool HandleCallback(WPARAM wparam, LPARAM lparam);

  // 设置"显示窗口"与"退出"回调。
  void SetShowCallback(std::function<void()> callback) {
    show_callback_ = std::move(callback);
  }
  void SetQuitCallback(std::function<void()> callback) {
    quit_callback_ = std::move(callback);
  }

 private:
  static UINT_PTR callback_message_id();

  HWND owner_ = nullptr;
  bool has_icon_ = false;
  std::function<void()> show_callback_;
  std::function<void()> quit_callback_;

  void ShowContextMenu();
};

#endif  // RUNNER_TRAY_H_
