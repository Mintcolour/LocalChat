#include "shell_drag_monitor.h"
#include "shell_item_probe.h"
#include "shell_uia_probe.h"

#include <UIAutomation.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdlib>
#include <string>

namespace {

constexpr UINT kQueryResultMessage = WM_APP + 81;
constexpr UINT kMonitorTimerMilliseconds = 40;
constexpr DWORD kAutomationTimeoutMilliseconds = 250;

using Microsoft::WRL::ComPtr;

std::string WindowClass(HWND window) {
  wchar_t wide[128] = {};
  if (!GetClassNameW(window, wide, ARRAYSIZE(wide))) return "<unavailable>";
  char utf8[512] = {};
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8, ARRAYSIZE(utf8), nullptr, nullptr);
  return utf8;
}

// Restrict the heuristic to the actual Shell file view, excluding Explorer's
// title bar, address bar, navigation tree and unrelated applications.
DWORD ShellViewProcessAt(HWND window, ShellDragProbeDiagnostic& diagnostic) {
  diagnostic.source_class = WindowClass(window);
  bool in_shell_view = false;
  int depth = 0;
  for (HWND ancestor = window; ancestor != nullptr && depth < 16;
       ancestor = GetParent(ancestor), ++depth) {
    wchar_t class_name[128] = {};
    GetClassNameW(ancestor, class_name, ARRAYSIZE(class_name));
    if (!diagnostic.ancestor_classes.empty()) diagnostic.ancestor_classes += " > ";
    diagnostic.ancestor_classes += WindowClass(ancestor);
    // WindowFromPoint may expose a Shell host rather than its DefView child.
    // Still require Explorer ownership and a file-item accessibility role.
    if (wcscmp(class_name, L"SHELLDLL_DefView") == 0 ||
        wcscmp(class_name, L"CabinetWClass") == 0 ||
        wcscmp(class_name, L"ExploreWClass") == 0 ||
        wcscmp(class_name, L"Progman") == 0 ||
        wcscmp(class_name, L"WorkerW") == 0) {
      in_shell_view = true;
    }
  }
  if (!in_shell_view) { diagnostic.decision = "not_shell_window"; return 0; }

  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  diagnostic.source_process = process_id;
  DWORD shell_process = 0;
  GetWindowThreadProcessId(GetShellWindow(), &shell_process);
  if (process_id != 0 && process_id == shell_process) return process_id;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (process == nullptr) {
    diagnostic.decision = "process_query_failed:" + std::to_string(GetLastError());
    return 0;
  }
  wchar_t executable[MAX_PATH] = {};
  DWORD length = ARRAYSIZE(executable);
  const bool queried = QueryFullProcessImageNameW(process, 0, executable,
                                                &length) != FALSE;
  CloseHandle(process);
  if (!queried) { diagnostic.decision = "process_identity_unavailable"; return 0; }
  const wchar_t* name = wcsrchr(executable, L'\\');
  name = name == nullptr ? executable : name + 1;
  if (_wcsicmp(name, L"explorer.exe") == 0) return process_id;
  diagnostic.decision = "not_explorer_process";
  return 0;
}

bool IsShellFileItem(IUIAutomation* automation, HWND original_window, POINT point,
                     const std::atomic<bool>& stopping,
                     ShellDragProbeDiagnostic& diagnostic) {
  const DWORD shell_process = ShellViewProcessAt(original_window, diagnostic);
  if (shell_process == 0 || stopping.load()) return false;

  const auto native = shell_item_probe::ProbeNativeListView(original_window, point);
  diagnostic.native_list_view = native.reason;
  diagnostic.native_query = native.native_query;
  diagnostic.native_item_index = native.item_index;
  diagnostic.native_hit_flags = native.hit_flags;
  diagnostic.native_screen_point = native.screen_point;
  diagnostic.native_client_point = native.client_point;
  diagnostic.native_client_size = native.client_size;
  diagnostic.native_list_view_result = native.result;
  if (native.is_item) {
    diagnostic.decision = "file_item_native_list_view";
    return true;
  }
  if (native.definitive) {
    diagnostic.decision = "native_list_view_not_file_item";
    return false;
  }
  if (std::string(native.reason) == "native_query_unavailable") {
    diagnostic.decision = native.native_query;
    return false;
  }

  if (automation && (diagnostic.source_class == "DirectUIHWND" ||
      diagnostic.source_class == "SHELLDLL_DefView" ||
      diagnostic.source_class == "DUIViewWndClassName")) {
    const auto view = shell_uia_probe::Probe(
        automation, original_window, shell_process, point, stopping);
    diagnostic.uia_process = view.process;
    diagnostic.uia_property_result = view.error;
    diagnostic.uia_source_decision = view.reason;
    diagnostic.uia_candidates = view.candidates;
    if (view.definitive) {
      diagnostic.decision = view.reason;
      return view.is_item;
    }
  }

  // Query the captured source window, not a drag image or popup that may now
  // cover the original point. Classic desktop lists support this MSAA path.
  if (shell_item_probe::IsFileItem(original_window, point)) {
    diagnostic.decision = "file_item_msaa";
    return true;
  }
  if (!automation || stopping.load()) {
    diagnostic.decision = "msaa_not_item_uia_unavailable";
    return false;
  }

  ComPtr<IUIAutomationElement> element;
  if (FAILED(automation->ElementFromPoint(point, &element)) || !element) {
    diagnostic.decision = "uia_element_unavailable";
    return false;
  }
  ComPtr<IUIAutomationTreeWalker> walker;
  if (FAILED(automation->get_ControlViewWalker(&walker)) || !walker) {
    diagnostic.decision = "uia_walker_unavailable";
    return false;
  }

  // ElementFromPoint can return an item's icon or text child. A bounded walk
  // finds its list item, while an Edit control rejects filename text dragging.
  for (int depth = 0; depth < 8 && element && !stopping.load(); ++depth) {
    int process_id = 0;
    CONTROLTYPEID type = 0;
    const HRESULT process_result = element->get_CurrentProcessId(&process_id);
    diagnostic.uia_process = process_id;
    diagnostic.uia_property_result = process_result;
    if (FAILED(process_result)) {
      diagnostic.decision = "uia_process_property_failed";
      return false;
    }
    if (static_cast<DWORD>(process_id) != shell_process) {
      diagnostic.decision = "uia_process_mismatch";
      return false;
    }
    const HRESULT type_result = element->get_CurrentControlType(&type);
    diagnostic.uia_property_result = type_result;
    if (FAILED(type_result)) {
      diagnostic.decision = "uia_control_type_failed";
      return false;
    }
    if (type == UIA_EditControlTypeId) {
      BOOL focusable = TRUE, focused = TRUE;
      VARIANT read_only;
      VariantInit(&read_only);
      element->get_CurrentIsKeyboardFocusable(&focusable);
      element->get_CurrentHasKeyboardFocus(&focused);
      const HRESULT got = element->GetCurrentPropertyValue(UIA_ValueIsReadOnlyPropertyId,
                                                           &read_only);
      const bool immutable = SUCCEEDED(got) && read_only.vt == VT_BOOL &&
                             read_only.boolVal == VARIANT_TRUE;
      VariantClear(&read_only);
      if (shell_uia_probe::IsWritableEdit(focusable != FALSE, focused != FALSE, immutable)) {
        diagnostic.decision = "edit_control";
        return false;
      }
    }
    if (type == UIA_ListItemControlTypeId ||
        type == UIA_DataItemControlTypeId) {
      diagnostic.decision = "file_item_uia";
      return true;
    }
    if (type == UIA_ListControlTypeId || type == UIA_TableControlTypeId ||
        type == UIA_DataGridControlTypeId || type == UIA_WindowControlTypeId) {
      diagnostic.decision = "uia_container_without_file_item";
      return false;
    }
    ComPtr<IUIAutomationElement> parent;
    if (FAILED(walker->GetParentElement(element.Get(), &parent))) {
      diagnostic.decision = "uia_parent_unavailable";
      return false;
    }
    element = std::move(parent);
  }
  diagnostic.decision = "no_file_item_ancestor";
  return false;
}

}  // namespace

struct ShellDragMonitor::Impl {
  HWND notification_window = nullptr;
  UINT notification_message = 0;
  HANDLE stop_event = nullptr;
  HANDLE query_event = nullptr;
  HANDLE ready_event = nullptr;
  HANDLE hook_thread = nullptr;
  HANDLE query_thread = nullptr;
  std::atomic<DWORD> hook_thread_id{0};
  DWORD query_thread_id = 0;
  std::atomic<bool> stopping{false};
  std::atomic<bool> dragging{false};
  std::atomic<bool> thread_ready{false};
  std::atomic<ULONG_PTR> generation{0};
  SRWLOCK query_lock = SRWLOCK_INIT;
  POINT query_point = {};
  HWND query_window = nullptr;
  ULONG_PTR query_generation = 0;
  std::atomic<bool> uia_available{false};
  std::atomic<unsigned long long> mouse_events{0};
  std::atomic<unsigned long long> mouse_presses{0};
  std::atomic<unsigned long long> drag_thresholds{0};
  std::atomic<unsigned long long> probes_started{0};
  std::atomic<unsigned long long> probes_completed{0};
  std::atomic<unsigned long long> results_applied{0};
  std::atomic<unsigned long long> drags_accepted{0};
  std::atomic<unsigned long long> timer_ticks{0};
  SRWLOCK diagnostic_lock = SRWLOCK_INIT;
  std::vector<ShellDragProbeDiagnostic> recent_probes;

  // The following state is used only by the hook thread.
  HHOOK mouse_hook = nullptr;
  bool tracking_press = false;
  bool threshold_crossed = false;
  bool candidate_known = false;
  bool candidate = false;
  POINT press_point = {};
  int horizontal_threshold = 0;
  int vertical_threshold = 0;
  static thread_local Impl* current;

  ~Impl() { Stop(); }

  bool Start(HWND window, UINT message) {
    notification_window = window;
    notification_message = message;
    stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    query_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    ready_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!stop_event || !query_event || !ready_event) return false;

    query_thread = CreateThread(nullptr, 0, QueryThread, this, 0,
                                &query_thread_id);
    if (!query_thread ||
        WaitForSingleObject(ready_event, 2000) != WAIT_OBJECT_0 ||
        !thread_ready.load()) {
      return false;
    }

    ResetEvent(ready_event);
    thread_ready.store(false);
    hook_thread = CreateThread(nullptr, 0, HookThread, this, 0, nullptr);
    return hook_thread &&
           WaitForSingleObject(ready_event, 2000) == WAIT_OBJECT_0 &&
           thread_ready.load();
  }

  void Stop() {
    stopping.store(true);
    dragging.store(false);
    generation.fetch_add(1);
    if (stop_event) SetEvent(stop_event);
    const DWORD input_thread = hook_thread_id.load();
    if (input_thread != 0) PostThreadMessageW(input_thread, WM_QUIT, 0, 0);
    if (hook_thread) {
      WaitForSingleObject(hook_thread, INFINITE);
      CloseHandle(hook_thread);
      hook_thread = nullptr;
    }
    if (query_thread) {
      // UIA connection/transaction timeouts bound provider calls; cancellation
      // also lets an outstanding COM call return promptly during shutdown.
      CoCancelCall(query_thread_id, 0);
      WaitForSingleObject(query_thread, INFINITE);
      CloseHandle(query_thread);
      query_thread = nullptr;
    }
    for (HANDLE* event : {&stop_event, &query_event, &ready_event}) {
      if (*event) {
        CloseHandle(*event);
        *event = nullptr;
      }
    }
  }

  void SetDragging(bool active) {
    if (dragging.exchange(active) != active && !stopping.load()) {
      if (active) drags_accepted.fetch_add(1);
      PostMessageW(notification_window, notification_message,
                   active ? 1 : 0, 0);
    }
  }

  void EndGesture() {
    tracking_press = false;
    threshold_crossed = false;
    candidate_known = false;
    candidate = false;
    generation.fetch_add(1);
    SetDragging(false);
  }

  void OnMouse(WPARAM message, const MSLLHOOKSTRUCT& event) {
    if (stopping.load()) return;
    mouse_events.fetch_add(1);
    if (message == WM_LBUTTONDOWN) {
      mouse_presses.fetch_add(1);
      EndGesture();
      tracking_press = true;
      press_point = event.pt;
      // Probe at mouse-down, before DoDragDrop creates drag images/overlays.
      // The hook only snapshots Win32 state; accessibility work stays off-thread.
      AcquireSRWLockExclusive(&query_lock);
      query_point = press_point;
      query_window = WindowFromPhysicalPoint(press_point);
      query_generation = generation.load();
      ReleaseSRWLockExclusive(&query_lock);
      SetEvent(query_event);
    } else if (message == WM_LBUTTONUP || message == WM_RBUTTONDOWN) {
      EndGesture();
    } else if (message == WM_MOUSEMOVE && tracking_press && !threshold_crossed &&
               (std::abs(event.pt.x - press_point.x) > horizontal_threshold ||
                std::abs(event.pt.y - press_point.y) > vertical_threshold)) {
      threshold_crossed = true;
      drag_thresholds.fetch_add(1);
      if (candidate_known && candidate) SetDragging(true);
    }
  }

  static LRESULT CALLBACK MouseHook(int code, WPARAM message, LPARAM value) {
    if (code == HC_ACTION && current != nullptr) {
      current->OnMouse(message, *reinterpret_cast<MSLLHOOKSTRUCT*>(value));
    }
    // Always pass the event on. Neither clicks nor drag input are consumed.
    return CallNextHookEx(nullptr, code, message, value);
  }

  static DWORD WINAPI HookThread(void* context) {
    auto* self = static_cast<Impl*>(context);
    // Low-level hook points and accessibility rectangles are physical pixels.
    SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    current = self;
    MSG message = {};
    PeekMessageW(&message, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
    self->hook_thread_id.store(GetCurrentThreadId());
    self->horizontal_threshold = GetSystemMetrics(SM_CXDRAG);
    self->vertical_threshold = GetSystemMetrics(SM_CYDRAG);
    self->mouse_hook = SetWindowsHookExW(WH_MOUSE_LL, MouseHook,
                                        GetModuleHandleW(nullptr), 0);
    const UINT_PTR timer = SetTimer(nullptr, 0, kMonitorTimerMilliseconds,
                                    nullptr);
    self->thread_ready.store(self->mouse_hook != nullptr && timer != 0);
    SetEvent(self->ready_event);

    while (self->thread_ready.load() && !self->stopping.load() &&
           GetMessageW(&message, nullptr, 0, 0) > 0) {
      if (message.message == kQueryResultMessage) {
        if (message.wParam == self->generation.load() &&
            self->tracking_press &&
            (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0 &&
            (GetAsyncKeyState(VK_ESCAPE) & 0x8000) == 0) {
          self->candidate_known = true;
          self->results_applied.fetch_add(1);
          self->candidate = message.lParam != 0;
          if (self->threshold_crossed && self->candidate) self->SetDragging(true);
        }
      } else if (message.message == WM_TIMER) {
        self->timer_ticks.fetch_add(1);
        // Recover if a button-up was lost (e.g. session switch), and handle
        // Escape without installing a global keyboard hook.
        if (self->tracking_press && ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0 ||
            (GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0)) {
          self->EndGesture();
        }
      } else {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    }
    if (self->mouse_hook) UnhookWindowsHookEx(self->mouse_hook);
    if (timer) KillTimer(nullptr, timer);
    self->mouse_hook = nullptr;
    self->hook_thread_id.store(0);
    current = nullptr;
    return 0;
  }

  static DWORD WINAPI QueryThread(void* context) {
    auto* self = static_cast<Impl*>(context);
    SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized)) {
      SetEvent(self->ready_event);
      return 0;
    }
    CoEnableCallCancellation(nullptr);
    {
      ComPtr<IUIAutomation> automation;
      ComPtr<IUIAutomation2> options;
      if (SUCCEEDED(CoCreateInstance(__uuidof(CUIAutomation8), nullptr,
                                     CLSCTX_INPROC_SERVER,
                                     IID_PPV_ARGS(&automation))) &&
          SUCCEEDED(automation.As(&options))) {
        if (FAILED(options->put_ConnectionTimeout(kAutomationTimeoutMilliseconds)) ||
            FAILED(options->put_TransactionTimeout(kAutomationTimeoutMilliseconds))) {
          automation.Reset();
        }
      } else {
        automation.Reset();
      }
      // UIA is optional. MSAA remains usable when UIA cannot initialize.
      self->uia_available.store(automation != nullptr);
      self->thread_ready.store(true);
      SetEvent(self->ready_event);
      const HANDLE events[] = {self->stop_event, self->query_event};
      while (!self->stopping.load() &&
             WaitForMultipleObjects(ARRAYSIZE(events), events, FALSE,
                                     INFINITE) == WAIT_OBJECT_0 + 1) {
        AcquireSRWLockExclusive(&self->query_lock);
        const POINT point = self->query_point;
        const HWND source = self->query_window;
        const ULONG_PTR generation = self->query_generation;
        ReleaseSRWLockExclusive(&self->query_lock);
        self->probes_started.fetch_add(1);
        ShellDragProbeDiagnostic diagnostic;
        const ULONGLONG started = GetTickCount64();
        const bool candidate = IsShellFileItem(
            automation.Get(), source, point, self->stopping, diagnostic);
        diagnostic.probe_ms = GetTickCount64() - started;
        AcquireSRWLockExclusive(&self->diagnostic_lock);
        if (self->recent_probes.size() >= 16) self->recent_probes.erase(self->recent_probes.begin());
        self->recent_probes.push_back(std::move(diagnostic));
        ReleaseSRWLockExclusive(&self->diagnostic_lock);
        self->probes_completed.fetch_add(1);
        const DWORD target = self->hook_thread_id.load();
        if (!self->stopping.load() && target != 0 &&
            generation == self->generation.load()) {
          PostThreadMessageW(target, kQueryResultMessage, generation,
                              candidate ? 1 : 0);
        }
      }
    }
    CoDisableCallCancellation(nullptr);
    CoUninitialize();
    return 0;
  }
};

thread_local ShellDragMonitor::Impl* ShellDragMonitor::Impl::current = nullptr;

ShellDragMonitor::ShellDragMonitor() = default;

ShellDragMonitor::~ShellDragMonitor() { Stop(); }

bool ShellDragMonitor::Start(HWND window, UINT message) {
  Stop();
  if (!IsWindow(window) || message < WM_APP) return false;
  auto implementation = std::make_unique<Impl>();
  if (!implementation->Start(window, message)) return false;
  impl_ = std::move(implementation);
  return true;
}

void ShellDragMonitor::Stop() { impl_.reset(); }

bool ShellDragMonitor::IsDragging() const {
  return impl_ != nullptr && impl_->dragging.load();
}

ShellDragDiagnostics ShellDragMonitor::GetDiagnostics() const {
  ShellDragDiagnostics diagnostic;
  if (!impl_) return diagnostic;
  diagnostic.running = impl_->hook_thread_id.load() != 0 && !impl_->stopping.load();
  diagnostic.uia_available = impl_->uia_available.load();
  diagnostic.mouse_events = impl_->mouse_events.load();
  diagnostic.mouse_presses = impl_->mouse_presses.load();
  diagnostic.drag_thresholds = impl_->drag_thresholds.load();
  diagnostic.probes_started = impl_->probes_started.load();
  diagnostic.probes_completed = impl_->probes_completed.load();
  diagnostic.results_applied = impl_->results_applied.load();
  diagnostic.drags_accepted = impl_->drags_accepted.load();
  diagnostic.timer_ticks = impl_->timer_ticks.load();
  diagnostic.probe_pending = diagnostic.probes_started > diagnostic.probes_completed;
  AcquireSRWLockShared(&impl_->diagnostic_lock);
  diagnostic.recent_probes = impl_->recent_probes;
  ReleaseSRWLockShared(&impl_->diagnostic_lock);
  return diagnostic;
}
