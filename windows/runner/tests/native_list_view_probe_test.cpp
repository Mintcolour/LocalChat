#include "../shell_item_probe.h"
#include "../shell_uia_probe.h"
#include <wrl/client.h>

#include <commctrl.h>
#include <chrono>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {
WNDPROC original_list_procedure = nullptr;
LRESULT CALLBACK SlowListProcedure(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
  if (message == LVM_HITTEST) Sleep(350);
  return CallWindowProcW(original_list_procedure, window, message, wparam, lparam);
}
LRESULT CALLBACK FixtureProcedure(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
  if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcW(window, message, wparam, lparam);
}

int RunFixture(bool icons, bool slow) {
  INITCOMMONCONTROLSEX controls = {sizeof(controls), ICC_LISTVIEW_CLASSES};
  if (!InitCommonControlsEx(&controls)) return 1;
  WNDCLASSW cls = {};
  cls.lpfnWndProc = FixtureProcedure;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"LocalChatNativeListViewTest";
  if (!RegisterClassW(&cls)) return 1;
  HWND owner = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      cls.lpszClassName, L"LocalChat native list view test", WS_POPUP,
      40, 40, 320, 200, nullptr, nullptr, cls.hInstance, nullptr);
  HWND list = CreateWindowExW(0, WC_LISTVIEWW, L"", WS_CHILD | WS_VISIBLE |
      (icons ? LVS_ICON : LVS_REPORT) | LVS_NOCOLUMNHEADER | LVS_EDITLABELS,
      0, 0, 320, 200, owner, nullptr, cls.hInstance, nullptr);
  if (!owner || !list) return 1;
  LVCOLUMNW column = {};
  column.mask = LVCF_WIDTH;
  column.cx = 300;
  if (ListView_InsertColumn(list, 0, &column) < 0) return 1;
  const int image_size = icons ? 32 : 16;
  HIMAGELIST images = ImageList_Create(image_size, image_size, ILC_COLOR32, 1, 1);
  if (!images || ImageList_AddIcon(images, LoadIconW(nullptr, IDI_APPLICATION)) < 0)
    return 1;
  ListView_SetImageList(list, images, icons ? LVSIL_NORMAL : LVSIL_SMALL);
  LVITEMW item = {};
  wchar_t name[] = L"probe.txt";
  item.mask = LVIF_TEXT | LVIF_IMAGE;
  item.pszText = name;
  if (ListView_InsertItem(list, &item) < 0) return 1;
  // A filename editor is a separate HWND, as it is in Explorer.
  HWND edit = CreateWindowExW(0, L"EDIT", L"probe.txt", WS_CHILD | WS_VISIBLE,
      5, 100, 100, 20, list, nullptr, cls.hInstance, nullptr);
  if (!edit) return 1;
  ShowWindow(owner, SW_SHOWNOACTIVATE);
  UpdateWindow(owner);
  RECT label = {};
  if (!ListView_GetItemRect(list, 0, &label, LVIR_LABEL)) return 1;
  POINT on_item = {label.left + 10,
                   (label.top + label.bottom) / 2};
  HWND filename_label = CreateWindowExW(0, L"EDIT", L"probe.txt",
      WS_CHILD | WS_VISIBLE | ES_READONLY, label.left + 4, label.top,
      90, label.bottom - label.top, list, nullptr, cls.hInstance, nullptr);
  if (!filename_label) return 1;
  RECT icon = {};
  if (!ListView_GetItemRect(list, 0, &icon, LVIR_ICON)) return 1;
  POINT on_icon = {(icon.left + icon.right) / 2, (icon.top + icon.bottom) / 2};
  POINT blank = {280, 160};
  POINT on_edit = {15, 110};
  ClientToScreen(list, &on_item);
  ClientToScreen(list, &on_icon);
  ClientToScreen(list, &blank);
  ClientToScreen(list, &on_edit);
  if (slow) {
    original_list_procedure = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
        list, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(SlowListProcedure)));
    if (!original_list_procedure) return 1;
  }
  std::cout << reinterpret_cast<uintptr_t>(owner) << ' '
            << reinterpret_cast<uintptr_t>(list) << ' '
            << on_item.x << ' ' << on_item.y << ' ' << blank.x << ' ' << blank.y
            << ' ' << reinterpret_cast<uintptr_t>(edit) << ' '
            << on_edit.x << ' ' << on_edit.y
            << ' ' << on_icon.x << ' ' << on_icon.y
            << ' ' << reinterpret_cast<uintptr_t>(filename_label)
            << '\n' << std::flush;
  MSG message;
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  ImageList_Destroy(images);
  return 0;
}
}  // namespace

bool CheckCrossProcess(IUIAutomation* automation, bool icons, bool slow = false) {
  wchar_t path[32768] = {};
  GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  const std::wstring command = L"\"" + std::wstring(path) +
      (slow ? L"\" --fixture-slow" :
       icons ? L"\" --fixture-icons" : L"\" --fixture-report");
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  SECURITY_ATTRIBUTES attributes = {sizeof(attributes), nullptr, TRUE};
  HANDLE reader = nullptr, writer = nullptr;
  if (!CreatePipe(&reader, &writer, &attributes, 0)) return false;
  SetHandleInformation(reader, HANDLE_FLAG_INHERIT, 0);
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdOutput = writer;
  startup.hStdError = writer;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  PROCESS_INFORMATION process = {};
  if (!CreateProcessW(path, mutable_command.data(), nullptr, nullptr, TRUE,
                       CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    CloseHandle(reader); CloseHandle(writer); return false;
  }
  CloseHandle(writer);
  char output[256] = {};
  DWORD read = 0;
  const BOOL got_output = ReadFile(reader, output, sizeof(output) - 1, &read, nullptr);
  CloseHandle(reader);
  uintptr_t owner_id = 0, list_id = 0, edit_id = 0, filename_label_id = 0;
  POINT on_item = {}, blank = {}, on_edit = {}, on_icon = {};
  std::istringstream response(std::string(output, read));
  response >> owner_id >> list_id >> on_item.x >> on_item.y >> blank.x >> blank.y
           >> edit_id >> on_edit.x >> on_edit.y >> on_icon.x >> on_icon.y
           >> filename_label_id;
  HWND owner = reinterpret_cast<HWND>(owner_id);
  HWND list = reinterpret_cast<HWND>(list_id);
  HWND edit = reinterpret_cast<HWND>(edit_id);
  HWND filename_label = reinterpret_cast<HWND>(filename_label_id);
  DWORD owner_process = 0;
  GetWindowThreadProcessId(owner, &owner_process);
  bool passed = got_output && response && owner_process == process.dwProcessId;
  if (passed && slow) {
    const auto start = std::chrono::steady_clock::now();
    const auto first = shell_item_probe::ProbeNativeListView(list, on_item);
    const auto second = shell_item_probe::ProbeNativeListView(list, on_item);
    const auto elapsed = std::chrono::steady_clock::now() - start;
    passed = !first.is_item && !second.is_item &&
        std::string(first.native_query) == "native_query_failed_or_timed_out" &&
        std::string(second.native_query) == "owner_unavailable_or_timed_out" &&
        elapsed < std::chrono::milliseconds(250);
    std::cout << "Slow control timeout and retry checks: " << passed << '\n';
  } else if (passed) {
    const auto original_dpi = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE);
    const auto item = shell_item_probe::ProbeNativeListView(list, on_item);
    const auto empty = shell_item_probe::ProbeNativeListView(list, blank);
    const auto container = shell_item_probe::ProbeNativeListView(owner, on_item);
    const auto editor = shell_item_probe::ProbeNativeListView(edit, on_edit);
    const auto icon = shell_item_probe::ProbeNativeListView(list, on_icon);
    const std::atomic<bool> stopping{false};
    const auto uia_item = shell_uia_probe::Probe(automation, list, owner_process, on_item, stopping);
    const auto uia_blank = shell_uia_probe::Probe(automation, list, owner_process, blank, stopping);
    const auto uia_edit = shell_uia_probe::Probe(automation, edit, owner_process, on_edit, stopping);
    const auto other_process = shell_uia_probe::Probe(automation, list, owner_process + 1, on_item, stopping);
    SendMessageW(filename_label, EM_SETREADONLY, FALSE, 0);
    const auto rename = shell_uia_probe::Probe(automation, list, owner_process, on_item, stopping);
    SendMessageW(filename_label, EM_SETREADONLY, TRUE, 0);
    passed = item.is_item && item.definitive && empty.definitive &&
        std::string(item.native_query) == "native_hit_test" &&
        !empty.is_item && !container.is_item &&
        !editor.is_item && icon.is_item && !shell_item_probe::IsFileItem(edit, on_edit) &&
        uia_item.is_item && uia_item.definitive && !uia_blank.is_item &&
        uia_blank.definitive && !uia_edit.is_item &&
        std::string(uia_edit.reason) == "uia_writable_edit" &&
        !other_process.is_item && !other_process.definitive &&
        !rename.is_item && std::string(rename.reason) == "uia_writable_edit";
    std::cout << "Source-view UIA: " << uia_item.reason << " blank="
              << uia_blank.reason << " edit=" << uia_edit.reason
              << " candidates=" << uia_item.candidates << '\n';
    std::cout << (icons ? "Icons" : "Report") << " cross-process item: "
              << item.reason << ", blank: " << empty.reason << '\n';
    SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HWND overlay = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        L"LocalChatProbeOverlay", L"", WS_POPUP, on_item.x - 5, on_item.y - 5, 30, 30,
        nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    ShowWindow(overlay, SW_SHOWNOACTIVATE);
    SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE);
    const auto covered = shell_item_probe::ProbeNativeListView(list, on_item);
    const auto covered_uia = shell_uia_probe::Probe(automation, list, owner_process, on_item, stopping);
    passed = passed && covered.is_item && covered.definitive &&
        covered_uia.is_item && covered_uia.definitive &&
        WindowFromPhysicalPoint(on_item) == overlay &&
        AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(),
                                    DPI_AWARENESS_CONTEXT_UNAWARE);
    std::cout << "Covered original item: " << covered.reason << '\n';
    std::cout << "Direct=" << item.definitive << '/' << item.native_query
              << " empty=" << empty.definitive
              << " icon=" << icon.is_item << " edit=" << editor.is_item
              << " covered=" << covered.definitive
              << " overlay=" << (WindowFromPhysicalPoint(on_item) == overlay)
              << " restored=" << AreDpiAwarenessContextsEqual(
                  GetThreadDpiAwarenessContext(), DPI_AWARENESS_CONTEXT_UNAWARE)
              << '\n';
    DestroyWindow(overlay);
    if (original_dpi) SetThreadDpiAwarenessContext(original_dpi);
  }
  if (owner_process == process.dwProcessId) PostMessageW(owner, WM_CLOSE, 0, 0);
  if (WaitForSingleObject(process.hProcess, 3000) != WAIT_OBJECT_0) passed = false;
  DWORD exit_code = 1;
  if (!GetExitCodeProcess(process.hProcess, &exit_code) || exit_code != 0) passed = false;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return passed;
}

int wmain(int count, wchar_t* arguments[]) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  if (count == 2) {
    const std::wstring option(arguments[1]);
    if (option == L"--fixture-icons") return RunFixture(true, false);
    if (option == L"--fixture-report") return RunFixture(false, false);
    if (option == L"--fixture-slow") return RunFixture(false, true);
  }
  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return 1;
  WNDCLASSW overlay_class = {};
  overlay_class.lpfnWndProc = DefWindowProcW;
  overlay_class.hInstance = GetModuleHandleW(nullptr);
  overlay_class.lpszClassName = L"LocalChatProbeOverlay";
  if (!RegisterClassW(&overlay_class)) { CoUninitialize(); return 1; }
  Microsoft::WRL::ComPtr<IUIAutomation> automation;
  if (FAILED(CoCreateInstance(__uuidof(CUIAutomation8), nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&automation)))) { CoUninitialize(); return 1; }
  const bool report = CheckCrossProcess(automation.Get(), false);
  const bool icons = CheckCrossProcess(automation.Get(), true);
  const bool slow = CheckCrossProcess(automation.Get(), false, true);
  automation.Reset();
  CoUninitialize();
  const bool passed = report && icons && slow;
  std::cout << (passed ? "Native list view cross-process checks passed.\n"
                      : "Native list view cross-process checks failed.\n");
  return passed ? 0 : 1;
}
