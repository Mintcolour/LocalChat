#include "shell_drag_monitor.h"

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

// Restrict the heuristic to the actual Shell file view, excluding Explorer's
// title bar, address bar, navigation tree and unrelated applications.
DWORD ShellViewProcessAt(POINT point) {
  HWND window = WindowFromPoint(point);
  bool in_shell_view = false;
  for (HWND ancestor = window; ancestor != nullptr;
       ancestor = GetParent(ancestor)) {
    wchar_t class_name[128] = {};
    GetClassNameW(ancestor, class_name, ARRAYSIZE(class_name));
    if (wcscmp(class_name, L"SHELLDLL_DefView") == 0) {
      in_shell_view = true;
      break;
    }
  }
  if (!in_shell_view) return 0;

  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (process == nullptr) return 0;
  wchar_t executable[MAX_PATH] = {};
  DWORD length = ARRAYSIZE(executable);
  const bool queried = QueryFullProcessImageNameW(process, 0, executable,
                                                &length) != FALSE;
  CloseHandle(process);
  if (!queried) return 0;
  const wchar_t* name = wcsrchr(executable, L'\\');
  name = name == nullptr ? executable : name + 1;
  return _wcsicmp(name, L"explorer.exe") == 0 ? process_id : 0;
}

bool IsShellFileItem(IUIAutomation* automation, POINT point,
                     const std::atomic<bool>& stopping) {
  const DWORD shell_process = ShellViewProcessAt(point);
  if (shell_process == 0 || stopping.load()) return false;

  ComPtr<IUIAutomationElement> element;
  if (FAILED(automation->ElementFromPoint(point, &element)) || !element) {
    return false;
  }
  ComPtr<IUIAutomationTreeWalker> walker;
  if (FAILED(automation->get_ControlViewWalker(&walker)) || !walker) {
    return false;
  }

  // ElementFromPoint can return an item's icon or text child. A bounded walk
  // finds its list item, while an Edit control rejects filename text dragging.
  for (int depth = 0; depth < 8 && element && !stopping.load(); ++depth) {
    int process_id = 0;
    CONTROLTYPEID type = 0;
    if (FAILED(element->get_CurrentProcessId(&process_id)) ||
        static_cast<DWORD>(process_id) != shell_process ||
        FAILED(element->get_CurrentControlType(&type))) {
      return false;
    }
    if (type == UIA_EditControlTypeId) return false;
    if (type == UIA_ListItemControlTypeId ||
        type == UIA_DataItemControlTypeId) {
      return true;
    }
    if (type == UIA_ListControlTypeId || type == UIA_TableControlTypeId ||
        type == UIA_DataGridControlTypeId || type == UIA_WindowControlTypeId) {
      return false;
    }
    ComPtr<IUIAutomationElement> parent;
    if (FAILED(walker->GetParentElement(element.Get(), &parent))) return false;
    element = std::move(parent);
  }
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
  ULONG_PTR query_generation = 0;

  // The following state is used only by the hook thread.
  HHOOK mouse_hook = nullptr;
  bool tracking_press = false;
  bool query_requested = false;
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
      PostMessageW(notification_window, notification_message,
                   active ? 1 : 0, 0);
    }
  }

  void EndGesture() {
    tracking_press = false;
    query_requested = false;
    generation.fetch_add(1);
    SetDragging(false);
  }

  void OnMouse(WPARAM message, const MSLLHOOKSTRUCT& event) {
    if (stopping.load()) return;
    if (message == WM_LBUTTONDOWN) {
      EndGesture();
      tracking_press = true;
      press_point = event.pt;
    } else if (message == WM_LBUTTONUP || message == WM_RBUTTONDOWN) {
      EndGesture();
    } else if (message == WM_MOUSEMOVE && tracking_press && !query_requested &&
               (std::abs(event.pt.x - press_point.x) > horizontal_threshold ||
                std::abs(event.pt.y - press_point.y) > vertical_threshold)) {
      query_requested = true;
      AcquireSRWLockExclusive(&query_lock);
      query_point = press_point;
      query_generation = generation.load();
      ReleaseSRWLockExclusive(&query_lock);
      SetEvent(query_event);
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
            self->tracking_press && message.lParam != 0 &&
            (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0 &&
            (GetAsyncKeyState(VK_ESCAPE) & 0x8000) == 0) {
          self->SetDragging(true);
        }
      } else if (message.message == WM_TIMER && self->tracking_press) {
        // Recover if a button-up was lost (e.g. session switch), and handle
        // Escape without installing a global keyboard hook.
        if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0 ||
            (GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0) {
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
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized)) {
      SetEvent(self->ready_event);
      return 0;
    }
    CoEnableCallCancellation(nullptr);
    {
      ComPtr<IUIAutomation> automation;
      ComPtr<IUIAutomation2> options;
      const bool ready =
          SUCCEEDED(CoCreateInstance(__uuidof(CUIAutomation8), nullptr,
                                     CLSCTX_INPROC_SERVER,
                                     IID_PPV_ARGS(&automation))) &&
          SUCCEEDED(automation.As(&options)) &&
          SUCCEEDED(options->put_ConnectionTimeout(
              kAutomationTimeoutMilliseconds)) &&
          SUCCEEDED(options->put_TransactionTimeout(
              kAutomationTimeoutMilliseconds));
      self->thread_ready.store(ready);
      SetEvent(self->ready_event);
      const HANDLE events[] = {self->stop_event, self->query_event};
      while (ready && !self->stopping.load() &&
             WaitForMultipleObjects(ARRAYSIZE(events), events, FALSE,
                                     INFINITE) == WAIT_OBJECT_0 + 1) {
        AcquireSRWLockExclusive(&self->query_lock);
        const POINT point = self->query_point;
        const ULONG_PTR generation = self->query_generation;
        ReleaseSRWLockExclusive(&self->query_lock);
        const bool candidate =
            IsShellFileItem(automation.Get(), point, self->stopping);
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
