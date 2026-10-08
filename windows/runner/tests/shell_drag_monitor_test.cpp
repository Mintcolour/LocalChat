#include "../shell_drag_monitor.h"

#include <chrono>
#include <iostream>

int wmain() {
  ShellDragMonitor monitor;
  if (monitor.IsDragging() || monitor.Start(nullptr, WM_APP + 1)) return 1;
  monitor.Stop();
  monitor.Stop();

  // A message-only window receives notifications without changing the user's
  // desktop. This test installs/removes real hooks, but synthesizes no input.
  HWND receiver = CreateWindowExW(0, L"STATIC", L"Drag monitor lifecycle test",
                                  0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                  GetModuleHandleW(nullptr), nullptr);
  if (receiver == nullptr) return 1;
  if (monitor.Start(receiver, WM_USER) || monitor.IsDragging()) {
    DestroyWindow(receiver);
    return 1;
  }

  const auto started = std::chrono::steady_clock::now();
  bool passed = true;
  for (int index = 0; index < 5 && passed; ++index) {
    passed = monitor.Start(receiver, WM_APP + 1);
    // Restart while enabled exercises hook/worker cleanup before replacement.
    if (passed) passed = monitor.Start(receiver, WM_APP + 1);
    monitor.Stop();
    monitor.Stop();
    passed = passed && !monitor.IsDragging();
  }
  DestroyWindow(receiver);
  const auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::steady_clock::now() - started);
  passed = passed && elapsed.count() < 20;
  std::cout << (passed ? "Drag monitor validation, restart and shutdown passed.\n"
                      : "Drag monitor lifecycle test failed.\n");
  return passed ? 0 : 1;
}
