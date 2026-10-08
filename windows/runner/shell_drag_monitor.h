#ifndef RUNNER_SHELL_DRAG_MONITOR_H_
#define RUNNER_SHELL_DRAG_MONITOR_H_

#include <windows.h>

#include <memory>

// Observes a drag gesture starting on an Explorer/desktop file item. This is
// only a hint for showing a drop target: the target must still validate the
// IDataObject it receives. No mouse input is intercepted or synthesized.
class ShellDragMonitor {
 public:
  ShellDragMonitor();
  ~ShellDragMonitor();

  ShellDragMonitor(const ShellDragMonitor&) = delete;
  ShellDragMonitor& operator=(const ShellDragMonitor&) = delete;

  // Start/Stop must be called on the owning UI thread. Notifications are posted
  // to that thread, with wParam 1 for a gesture and 0 when it ends. Read
  // IsDragging() when handling a notification to discard stale queued events.
  bool Start(HWND notification_window, UINT notification_message);
  void Stop();
  bool IsDragging() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_SHELL_DRAG_MONITOR_H_
