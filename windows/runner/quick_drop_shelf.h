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
  bool SetEnabled(bool enabled, HWND owner);
  void UpdateDevices(std::vector<QuickDropDevice> devices);
  void Destroy();
  ShellDragDiagnostics GetDiagnostics() const;
  bool IsEnabled() const { return enabled_; }
  bool IsVisible() const { return hwnd_ && IsWindowVisible(hwnd_) != FALSE; }
  unsigned long long ShownCount() const { return shown_count_; }
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);

 private:
  friend struct QuickDropShelfTestAccess;
  class DropTarget;
  enum class State { hidden, prompt, devices };
  // Eased transition between two values; retargeting starts from the current
  // value so reversing mid-flight never jumps.
  struct Tween {
    double from = 0;
    double to = 0;
    ULONGLONG start = 0;
    double duration = 0;
    double Value(ULONGLONG now) const;
    bool Done(ULONGLONG now) const;
    void Retarget(double target, double duration_ms, ULONGLONG now);
    void Finish();
  };
  bool Create(HWND owner);
  void ShowForDrag(POINT point);
  // Hide() is immediate; BeginHide() logically hides at once, then fades out.
  void Hide();
  void BeginHide();
  void SetExpanded(bool expanded);
  void SetHover(int index);
  void Layout(POINT point);
  void ApplyFrame();
  // Applies the current tween values and keeps the frame timer running until
  // every tween settles. Safe to call from any state change.
  void AnimationFrame();
  void FinishAnimations();
  // Honors the system "show animations" accessibility setting.
  double Duration(double milliseconds) const;
  // Client-space origin of the fully expanded layout inside the current,
  // possibly mid-animation, window.
  POINT ContentOffset() const;
  int ExpandedWidth() const;
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
  unsigned long long shown_count_ = 0;
  bool ole_initialized_ = false;
  bool ole_drag_active_ = false;
  bool laying_out_ = false;
  State state_ = State::hidden;
  UINT dpi_ = 96;
  HMONITOR monitor_ = nullptr;
  RECT work_ = {};
  RECT region_ = {};
  int scroll_x_ = 0;
  int hover_index_ = -1;
  bool animate_ = true;
  bool animating_ = false;
  Tween visibility_;
  Tween expand_;
  std::vector<Tween> hover_;
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
