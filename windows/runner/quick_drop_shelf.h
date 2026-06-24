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

  QuickDropShelf();
  ~QuickDropShelf();

  void SetDropCallback(DropCallback callback);
  void SetEnabled(bool enabled, HWND owner);
  void UpdateDevices(std::vector<QuickDropDevice> devices);
  void Destroy();
  static LRESULT CALLBACK WndProc(HWND hwnd,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam);

 private:
  class DropTarget;

  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  bool Create(HWND owner);
  void RegisterDropTarget();
  void RevokeDropTarget();
  void LayoutCollapsed();
  void LayoutExpanded();
  void SetExpanded(bool expanded);
  void Paint();
  int HitTest(POINT screen_point) const;
  RECT CardRect(int index) const;
  void ScrollToward(POINT screen_point);
  void NotifyDrop(int device_index, const std::vector<std::string>& paths);

  HWND hwnd_ = nullptr;
  HWND owner_ = nullptr;
  bool enabled_ = false;
  bool expanded_ = false;
  int scroll_x_ = 0;
  int hover_index_ = -1;
  std::vector<QuickDropDevice> devices_;
  DropCallback drop_callback_;
  DropTarget* drop_target_ = nullptr;
  bool ole_initialized_ = false;
};

#endif  // RUNNER_QUICK_DROP_SHELF_H_
