#ifndef RUNNER_QUICK_DROP_SHELF_H_
#define RUNNER_QUICK_DROP_SHELF_H_

#include <windows.h>
#include <oleidl.h>
#include <functional>
#include <string>
#include <vector>
#include "shell_drag_monitor.h"

struct QuickDropDevice {
  std::string id;
  std::string display_name;
  std::string platform;
  std::string avatar_initial;
  std::string avatar_color;
  bool selected = false;
};

// Visibility follows Shell gestures. Only OLE's IDataObject supplies sent files.
class QuickDropShelf {
 public:
  using DropCallback = std::function<void(
      const std::string&, const std::vector<std::string>&)>;
  QuickDropShelf();
  ~QuickDropShelf();
  void SetDropCallback(DropCallback callback);
  void SetEnabled(bool enabled, HWND owner);
  void UpdateDevices(std::vector<QuickDropDevice> devices);
  void Destroy();
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);

 private:
  friend struct QuickDropShelfTestAccess;
  class DropTarget;
  enum class State { hidden, prompt, devices };
  bool Create(HWND owner);
  void ShowForDrag(POINT point);
  void Hide();
  void SetExpanded(bool expanded);
  void Layout(POINT point);
  void Paint();
  int Scale(int value) const;
  int HitTest(POINT point) const;
  bool IsAvailable(const std::string& id) const;
  int DropIndex(POINT point) const;
  RECT CardRect(int index) const;
  RECT CardsClip() const;
  int MaxScroll() const;
  void ScrollToward(POINT point);
  void NotifyDrop(int index, const std::vector<std::string>& paths);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  HWND hwnd_ = nullptr;
  HWND owner_ = nullptr;
  bool enabled_ = false;
  bool ole_initialized_ = false;
  bool ole_drag_active_ = false;
  bool laying_out_ = false;
  State state_ = State::hidden;
  UINT dpi_ = 96;
  HMONITOR monitor_ = nullptr;
  int scroll_x_ = 0;
  int hover_index_ = -1;
  ULONGLONG shown_at_ = 0;
  HICON app_icon_ = nullptr;
  IDropTarget* drop_target_ = nullptr;
  ShellDragMonitor drag_monitor_;
  std::vector<QuickDropDevice> devices_;
  // Freeze ordering during a gesture to avoid moving another recipient under
  // the pointer. Removed devices become undroppable until the next gesture.
  std::vector<QuickDropDevice> drag_devices_;
  DropCallback drop_callback_;
};

#endif  // RUNNER_QUICK_DROP_SHELF_H_
