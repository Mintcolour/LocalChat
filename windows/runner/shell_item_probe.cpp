#include "shell_item_probe.h"

#include <wrl/client.h>
#include <commctrl.h>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace shell_item_probe {
using Microsoft::WRL::ComPtr;

namespace {
constexpr UINT kNativeQueryTimeoutMs = 80;

class PhysicalCoordinates {
 public:
  PhysicalCoordinates() : previous_(SetThreadDpiAwarenessContext(
      DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {}
  ~PhysicalCoordinates() {
    if (previous_) SetThreadDpiAwarenessContext(previous_);
  }
 private:
  DPI_AWARENESS_CONTEXT previous_;
};

// Windows does not marshal LVM_HITTEST pointers across processes. Allocate
// only the pointer-free LVHITTESTINFO in the receiving process, never pass a
// local address. On a timeout the receiver may still be using that allocation:
// leave it alive until process exit and disable further allocations for that
// process. This bounds the retained memory to one page per unresponsive owner.
struct TimedOutOwner { DWORD id; HANDLE process; };
std::mutex timed_out_mutex;
std::mutex native_query_mutex;
std::vector<TimedOutOwner> timed_out_owners;

bool OwnerTimedOut(DWORD id) {
  std::lock_guard<std::mutex> lock(timed_out_mutex);
  for (auto it = timed_out_owners.begin(); it != timed_out_owners.end();) {
    if (WaitForSingleObject(it->process, 0) == WAIT_OBJECT_0) {
      CloseHandle(it->process);
      it = timed_out_owners.erase(it);
    } else {
      if (it->id == id) return true;
      ++it;
    }
  }
  return false;
}

bool NativeHitTest(HWND window, POINT screen_point, NativeListViewResult& result) {
  std::lock_guard<std::mutex> query_lock(native_query_mutex);
  PhysicalCoordinates physical;
  POINT client = screen_point;
  RECT bounds = {};
  result.screen_point = screen_point;
  if (!ScreenToClient(window, &client) || !GetClientRect(window, &bounds)) {
    result.native_query = "coordinate_conversion_failed";
    result.result = HRESULT_FROM_WIN32(GetLastError());
    return false;
  }
  result.client_point = client;
  result.client_size = {bounds.right - bounds.left, bounds.bottom - bounds.top};
  if (!PtInRect(&bounds, client)) {
    result.native_query = "outside_client";
    result.definitive = true;
    return true;
  }
  DWORD owner = 0;
  GetWindowThreadProcessId(window, &owner);
  if (!owner || OwnerTimedOut(owner)) {
    result.native_query = "owner_unavailable_or_timed_out";
    return false;
  }
  LVHITTESTINFO hit = {};
  hit.pt = client;
  hit.iItem = -1;
  HANDLE process = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_READ |
                               PROCESS_VM_WRITE | SYNCHRONIZE, FALSE, owner);
  if (!process) {
    result.native_query = "owner_access_denied";
    result.result = HRESULT_FROM_WIN32(GetLastError());
    return false;
  }
  void* buffer = VirtualAllocEx(process, nullptr, sizeof(hit), MEM_COMMIT | MEM_RESERVE,
                               PAGE_READWRITE);
  if (!buffer || !WriteProcessMemory(process, buffer, &hit, sizeof(hit), nullptr)) {
    result.native_query = "query_buffer_failed";
    result.result = HRESULT_FROM_WIN32(GetLastError());
    if (buffer) VirtualFreeEx(process, buffer, 0, MEM_RELEASE);
    CloseHandle(process);
    return false;
  }
  DWORD current_owner = 0;
  GetWindowThreadProcessId(window, &current_owner);
  if (current_owner != owner) {
    VirtualFreeEx(process, buffer, 0, MEM_RELEASE);
    CloseHandle(process);
    result.native_query = "source_window_changed";
    return false;
  }
  DWORD_PTR value = 0;
  SetLastError(ERROR_SUCCESS);
  const bool sent = SendMessageTimeoutW(window, LVM_HITTEST, 0,
      reinterpret_cast<LPARAM>(buffer),
      SMTO_ABORTIFHUNG | SMTO_BLOCK | SMTO_ERRORONEXIT,
      kNativeQueryTimeoutMs, &value) != 0;
  if (!sent) {
    const DWORD error = GetLastError();
    result.result = HRESULT_FROM_WIN32(error ? error : ERROR_TIMEOUT);
    result.native_query = "native_query_failed_or_timed_out";
    std::lock_guard<std::mutex> lock(timed_out_mutex);
    timed_out_owners.push_back({owner, process});
    return false;
  }
  const bool read = ReadProcessMemory(process, buffer, &hit, sizeof(hit), nullptr) != 0;
  if (!read) result.result = HRESULT_FROM_WIN32(GetLastError());
  VirtualFreeEx(process, buffer, 0, MEM_RELEASE);
  CloseHandle(process);
  result.native_query = read ? "native_hit_test" : "query_result_failed";
  if (!read) return false;
  result.definitive = true;
  result.item_index = hit.iItem;
  result.hit_flags = hit.flags;
  result.is_item = hit.iItem >= 0 && (hit.flags & LVHT_ONITEM) != 0;
  return true;
}
}  // namespace

NativeListViewResult ProbeNativeListView(HWND original_window, POINT point) {
  NativeListViewResult result;
  wchar_t class_name[128] = {};
  if (!GetClassNameW(original_window, class_name, ARRAYSIZE(class_name)) ||
      _wcsicmp(class_name, L"SysListView32") != 0) return result;
  if (NativeHitTest(original_window, point, result)) {
    result.reason = result.is_item ? "native_list_view_item" : "native_list_view_no_item";
    return result;
  }
  // Do not enter another provider call when the control just timed out.
  if (result.native_query == std::string("native_query_failed_or_timed_out") ||
      result.native_query == std::string("owner_unavailable_or_timed_out")) {
    result.reason = "native_query_unavailable";
    return result;
  }
  PhysicalCoordinates physical;
  ComPtr<IAccessible> standard;
  const HRESULT created = CreateStdAccessibleObject(original_window, OBJID_CLIENT,
                                                    IID_PPV_ARGS(&standard));
  if (FAILED(created) || !standard) {
    result.result = created;
    result.reason = "standard_proxy_unavailable";
    return result;
  }
  result.is_item = IsFileItem(standard.Get(), point);
  result.reason = result.is_item ? "native_list_view_item" : "native_list_view_no_item";
  return result;
}

bool IsFileItem(IAccessible* accessible, POINT point) {
  if (!accessible) return false;
  ComPtr<IAccessible> current = accessible;
  // accHitTest may return either a child ID or another accessible object.
  for (int depth = 0; depth < 8; ++depth) {
    VARIANT hit;
    VariantInit(&hit);
    const HRESULT tested = current->accHitTest(point.x, point.y, &hit);
    if (tested != S_OK) { VariantClear(&hit); return false; }
    if (hit.vt == VT_DISPATCH && hit.pdispVal) {
      ComPtr<IAccessible> child;
      const HRESULT queried = hit.pdispVal->QueryInterface(IID_PPV_ARGS(&child));
      VariantClear(&hit);
      if (FAILED(queried) || !child) return false;
      VARIANT self;
      VariantInit(&self);
      self.vt = VT_I4;
      self.lVal = CHILDID_SELF;
      VARIANT role;
      VariantInit(&role);
      const HRESULT got = child->get_accRole(self, &role);
      const bool item = got == S_OK && role.vt == VT_I4 &&
                        role.lVal == ROLE_SYSTEM_LISTITEM;
      const bool edit = got == S_OK && role.vt == VT_I4 &&
                        role.lVal == ROLE_SYSTEM_TEXT;
      VariantClear(&role);
      if (item || edit) return item;
      if (child.Get() == current.Get()) return false;
      current = std::move(child);
      continue;
    }
    if (hit.vt != VT_I4) { VariantClear(&hit); return false; }
    VARIANT role;
    VariantInit(&role);
    const HRESULT got = current->get_accRole(hit, &role);
    const bool item = got == S_OK && role.vt == VT_I4 &&
                      role.lVal == ROLE_SYSTEM_LISTITEM;
    VariantClear(&role);
    VariantClear(&hit);
    return item;
  }
  return false;
}

bool IsFileItem(HWND original_window, POINT point) {
  if (!IsWindow(original_window)) return false;
  ComPtr<IAccessible> accessible;
  if (FAILED(AccessibleObjectFromWindow(original_window, static_cast<DWORD>(OBJID_CLIENT),
                                        IID_PPV_ARGS(&accessible)))) return false;
  return IsFileItem(accessible.Get(), point);
}
}  // namespace shell_item_probe
