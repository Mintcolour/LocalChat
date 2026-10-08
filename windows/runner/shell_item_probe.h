#ifndef RUNNER_SHELL_ITEM_PROBE_H_
#define RUNNER_SHELL_ITEM_PROBE_H_

#include <windows.h>
#include <oleacc.h>

namespace shell_item_probe {
struct NativeListViewResult {
  bool is_item = false;
  bool definitive = false;
  const char* reason = "not_native_list_view";
  const char* native_query = "not_attempted";
  int item_index = -1;
  UINT hit_flags = 0;
  POINT screen_point = {};
  POINT client_point = {};
  SIZE client_size = {};
  HRESULT result = S_OK;
};
// Hit-test a verified SysListView32 in its own client coordinates. The HWND
// owner must be checked by the caller before querying another process.
NativeListViewResult ProbeNativeListView(HWND original_window, POINT point);
// Legacy Shell list views can expose MSAA items when UIA only exposes a pane.
// Callers must validate the original HWND belongs to Explorer's file view.
bool IsFileItem(IAccessible* accessible, POINT point);
bool IsFileItem(HWND original_window, POINT point);
}  // namespace shell_item_probe

#endif  // RUNNER_SHELL_ITEM_PROBE_H_
