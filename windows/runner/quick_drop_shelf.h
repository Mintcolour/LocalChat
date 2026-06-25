#ifndef RUNNER_QUICK_DROP_SHELF_H_
#define RUNNER_QUICK_DROP_SHELF_H_

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

struct QuickDropDevice {
  std::string id;
  std::string display_name;
  std::string platform;
  std::string avatar_initial;
  std::string avatar_color;
  bool selected = false;
};

class QuickDropShelf {
 public:
  using DropCallback =
      std::function<void(const std::string& device_id,
                         const std::vector<std::string>& paths)>;
  using HideCallback = std::function<void()>;

  QuickDropShelf();
  ~QuickDropShelf();

  void SetDropCallback(DropCallback callback);
  void SetHideCallback(HideCallback callback);
  void SetEnabled(bool enabled, HWND owner);
  void SetAutoHide(bool auto_hide);
  void UpdateDevices(std::vector<QuickDropDevice> devices);
  void Destroy();
  static LRESULT CALLBACK WndProc(HWND hwnd,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam);

 private:
  class DropTarget;

  enum State {
    STATE_COLLAPSED,
    STATE_PROMPT,
    STATE_DEVICES,
    STATE_HIDDEN_BAR
  };

  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  bool Create(HWND owner);
  void RegisterDropTarget();
  void RevokeDropTarget();
  void LayoutCollapsed();
  void LayoutExpanded();
  void SetExpanded(bool expanded);
  void Paint();
  int HitTest(POINT screen_point) const;
  void ScrollToward(POINT screen_point);
  void NotifyDrop(int device_index, const std::vector<std::string>& paths);
  void StartAnimation(bool expanding);
  void AnimateStep();
  void WakeUp();
  void TransitionToHiddenBar();

  void ShowContextMenu(int x, int y);

  HWND hwnd_ = nullptr;
  HWND owner_ = nullptr;
  bool enabled_ = false;
  bool expanded_ = false;
  State state_ = STATE_COLLAPSED;
  int scroll_x_ = 0;
  int hover_index_ = -1;
  std::vector<QuickDropDevice> devices_;
  DropCallback drop_callback_;
  HideCallback hide_callback_;
  DropTarget* drop_target_ = nullptr;
  bool ole_initialized_ = false;
  bool drag_leave_pending_ = false;

  // Floating window position (collapsed state)
  int x_ = -1;
  int y_ = -1;

  // Animation parameters
  bool anim_active_ = false;
  bool anim_expanding_ = false;
  ULONGLONG anim_start_time_ = 0;
  int anim_start_x_ = 0;
  int anim_start_y_ = 0;
  int anim_start_w_ = 0;
  int anim_start_h_ = 0;
  int anim_start_alpha_ = 0;
  int anim_target_x_ = 0;
  int anim_target_y_ = 0;
  int anim_target_w_ = 0;
  int anim_target_h_ = 0;
  int anim_target_alpha_ = 0;

  // Application Icon
  HICON app_icon_ = nullptr;

  // Docking & Breathing light states
  ULONGLONG last_active_time_ = 0;
  double pulse_angle_ = 0.0;
  bool auto_hide_ = true;
};

#endif  // RUNNER_QUICK_DROP_SHELF_H_
