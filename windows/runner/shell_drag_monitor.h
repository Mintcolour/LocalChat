#ifndef RUNNER_SHELL_DRAG_MONITOR_H_
#define RUNNER_SHELL_DRAG_MONITOR_H_

#include <windows.h>

#include <memory>
#include <string>
#include <vector>

struct ShellDragProbeDiagnostic {
  std::string source_class;
  std::string ancestor_classes;
  std::string decision;
  std::string native_list_view;
  std::string native_query;
  int native_item_index = -1;
  UINT native_hit_flags = 0;
  POINT native_screen_point = {};
  POINT native_client_point = {};
  SIZE native_client_size = {};
  HRESULT native_list_view_result = S_OK;
  unsigned long long probe_ms = 0;
  DWORD source_process = 0;
  int uia_process = 0;
  int uia_candidates = 0;
  std::string uia_source_decision;
  HRESULT uia_property_result = S_OK;
};

struct ShellDragDiagnostics {
  bool running = false;
  bool uia_available = false;
  unsigned long long mouse_events = 0;
  unsigned long long mouse_presses = 0;
  unsigned long long drag_thresholds = 0;
  unsigned long long probes_started = 0;
  unsigned long long probes_completed = 0;
  unsigned long long results_applied = 0;
  unsigned long long drags_accepted = 0;
  unsigned long long timer_ticks = 0;
  bool probe_pending = false;
  std::vector<ShellDragProbeDiagnostic> recent_probes;
};

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
  ShellDragDiagnostics GetDiagnostics() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_SHELL_DRAG_MONITOR_H_
