#ifndef RUNNER_SHELL_UIA_PROBE_H_
#define RUNNER_SHELL_UIA_PROBE_H_

#include <windows.h>
#include <UIAutomation.h>
#include <atomic>

namespace shell_uia_probe {
struct Result {
  bool is_item = false;
  bool definitive = false;
  const char* reason = "uia_unavailable";
  HRESULT error = S_OK;
  int process = 0;
  int candidates = 0;
};

// Source HWND and process must already belong to an Explorer file view.
// Query that view's cached geometry, without global point lookup or names.
Result Probe(IUIAutomation* automation, HWND source, DWORD process, POINT point,
             const std::atomic<bool>& stopping);
// DirectUI can expose read-only filename labels as Edit controls.
bool IsWritableEdit(bool focusable, bool focused, bool read_only);
}  // namespace shell_uia_probe
#endif
