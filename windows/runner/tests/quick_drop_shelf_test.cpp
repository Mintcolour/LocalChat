#include "../quick_drop_shelf.h"

#include <shellapi.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

struct QuickDropShelfTestAccess {
  static HWND Window(const QuickDropShelf& shelf) { return shelf.hwnd_; }
  static bool Enabled(const QuickDropShelf& shelf) { return shelf.enabled_; }
  static bool Hidden(const QuickDropShelf& shelf) {
    return shelf.state_ == QuickDropShelf::State::hidden &&
           !IsWindowVisible(shelf.hwnd_);
  }
  static bool Expanded(const QuickDropShelf& shelf) {
    return shelf.state_ == QuickDropShelf::State::devices;
  }
  // Behavior checks run against settled frames; the preview modes keep the
  // live animation.
  static void Settle(QuickDropShelf& shelf) { shelf.FinishAnimations(); }
  static bool Animated(const QuickDropShelf& shelf) { return shelf.animate_; }
  static void ShowAnimated(QuickDropShelf& shelf, POINT point) {
    shelf.ShowForDrag(point);
  }
  static void Show(QuickDropShelf& shelf, POINT point) {
    shelf.ShowForDrag(point);
    Settle(shelf);
  }
  static void Hide(QuickDropShelf& shelf) { shelf.Hide(); }
  static void BeginHide(QuickDropShelf& shelf) { shelf.BeginHide(); }
  // Model the first hover frame, before any highlight intensity is visible.
  // Pin its value to zero so immediate release is deterministic, independent
  // of the machine's tick resolution and scheduler.
  static void PrepareImmediateRelease(QuickDropShelf& shelf, int index) {
    shelf.animate_ = true;
    shelf.SetHover(index);
    shelf.hover_[index] = {};
  }
  static void Expand(QuickDropShelf& shelf) { shelf.SetExpanded(true); }
  static void StopMonitor(QuickDropShelf& shelf) { shelf.drag_monitor_.Stop(); }
  static int Scale(const QuickDropShelf& shelf, int value) {
    return shelf.Scale(value);
  }
  static IDropTarget* Target(QuickDropShelf& shelf) {
    return shelf.drop_target_;
  }
  static POINT ScreenPoint(const QuickDropShelf& shelf, int x, int y) {
    POINT point = {shelf.Scale(x), shelf.Scale(y)};
    ClientToScreen(shelf.hwnd_, &point);
    return point;
  }
  static POINT Footer(const QuickDropShelf& shelf) {
    RECT rect = {};
    GetClientRect(shelf.hwnd_, &rect);
    POINT point = {rect.right / 2, rect.bottom - shelf.Scale(26)};
    ClientToScreen(shelf.hwnd_, &point);
    return point;
  }
  static POINT Card(const QuickDropShelf& shelf, int index) {
    const RECT rect = shelf.CardRect(index);
    POINT point = {(rect.left + rect.right) / 2,
                   (rect.top + rect.bottom) / 2};
    ClientToScreen(shelf.hwnd_, &point);
    return point;
  }
  static std::vector<std::string> VisibleIds(const QuickDropShelf& shelf) {
    std::vector<std::string> result;
    for (const auto& device : shelf.drag_devices_) result.push_back(device.id);
    return result;
  }
  static int Hit(const QuickDropShelf& shelf, POINT point) {
    return shelf.HitTest(point);
  }
  static int DropIndex(const QuickDropShelf& shelf, POINT point) {
    return shelf.DropIndex(point);
  }
  static void SetScroll(QuickDropShelf& shelf, int value) {
    shelf.scroll_x_ = value;
  }
  static int Scroll(const QuickDropShelf& shelf) { return shelf.scroll_x_; }
  static int MaxScroll(const QuickDropShelf& shelf) { return shelf.MaxScroll(); }
  static void ScrollToward(QuickDropShelf& shelf, POINT point) {
    shelf.ScrollToward(point);
  }
};

namespace {

using Access = QuickDropShelfTestAccess;
using Microsoft::WRL::ComPtr;

// A real CF_HDROP medium with UTF-16, double-NUL-terminated paths. No source
// files are opened: the test verifies the native dispatch boundary only.
class FileDataObject : public IDataObject {
 public:
  explicit FileDataObject(std::vector<std::wstring> paths, bool files = true)
      : paths_(std::move(paths)), files_(files) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDataObject) return E_NOINTERFACE;
    *result = static_cast<IDataObject*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&references_));
  }
  ULONG STDMETHODCALLTYPE Release() override {
    const LONG count = InterlockedDecrement(&references_);
    if (count == 0) delete this;
    return static_cast<ULONG>(count);
  }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* format) override {
    if (!format) return E_POINTER;
    if (!files_ || format->cfFormat != CF_HDROP) return DV_E_FORMATETC;
    if ((format->tymed & TYMED_HGLOBAL) == 0) return DV_E_TYMED;
    if (format->dwAspect != DVASPECT_CONTENT) return DV_E_DVASPECT;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format,
                                    STGMEDIUM* medium) override {
    if (!medium) return E_POINTER;
    *medium = {};
    const HRESULT supported = QueryGetData(format);
    if (FAILED(supported)) return supported;
    size_t characters = 1;
    for (const auto& path : paths_) characters += path.size() + 1;
    if (paths_.empty()) ++characters;
    const SIZE_T bytes = sizeof(DROPFILES) + characters * sizeof(wchar_t);
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes);
    if (!memory) return E_OUTOFMEMORY;
    auto* header = static_cast<DROPFILES*>(GlobalLock(memory));
    if (!header) {
      GlobalFree(memory);
      return E_OUTOFMEMORY;
    }
    header->pFiles = sizeof(DROPFILES);
    header->fWide = TRUE;
    auto* target = reinterpret_cast<wchar_t*>(
        reinterpret_cast<BYTE*>(header) + sizeof(DROPFILES));
    for (const auto& path : paths_) {
      std::memcpy(target, path.c_str(), (path.size() + 1) * sizeof(wchar_t));
      target += path.size() + 1;
    }
    GlobalUnlock(memory);
    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = memory;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*,
                                                  FORMATETC* result) override {
    if (result) result->ptd = nullptr;
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD, IEnumFORMATETC** result) override {
    if (result) *result = nullptr;
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*,
                                    DWORD*) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA** result) override {
    if (result) *result = nullptr;
    return OLE_E_ADVISENOTSUPPORTED;
  }

 private:
  LONG references_ = 1;
  std::vector<std::wstring> paths_;
  bool files_ = true;
};

QuickDropDevice Device(const std::string& id, const std::string& title,
                        const std::string& initial, const std::string& color) {
  return {id, title, "windows", initial, color, false};
}

std::vector<QuickDropDevice> DemoDevices() {
  return {Device("phone", u8"我的手机", u8"手", "#238B74"),
          Device("desktop", u8"工作电脑", u8"电", "#4677BE"),
          Device("tablet", u8"平板", u8"板", "#8A61B6")};
}

POINTL OlePoint(POINT point) { return {point.x, point.y}; }

DWORD Enter(QuickDropShelf& shelf, IDataObject* object,
            DWORD allowed = DROPEFFECT_COPY) {
  DWORD effect = allowed;
  Access::Target(shelf)->DragEnter(object, MK_LBUTTON,
                                   OlePoint(Access::Footer(shelf)), &effect);
  Access::Settle(shelf);
  return effect;
}

DWORD Drop(QuickDropShelf& shelf, IDataObject* object, POINT point) {
  DWORD effect = DROPEFFECT_COPY;
  Access::Target(shelf)->Drop(object, 0, OlePoint(point), &effect);
  Access::Settle(shelf);
  return effect;
}

class Checks {
 public:
  void Expect(bool passed, const char* description) {
    if (!passed) {
      ++failed_;
      std::cerr << "FAIL: " << description << '\n';
    }
    ++total_;
  }
  int Finish() const {
    std::cout << (total_ - failed_) << '/' << total_
              << " quick drop checks passed.\n";
    return failed_ == 0 ? 0 : 1;
  }
 private:
  int failed_ = 0;
  int total_ = 0;
};

int RunChecks() {
  Checks checks;
  QuickDropShelf shelf;
  const auto devices = DemoDevices();
  shelf.UpdateDevices(devices);
  shelf.SetEnabled(true, nullptr);
  checks.Expect(Access::Enabled(shelf), "monitor starts");
  if (!Access::Enabled(shelf)) return checks.Finish();
  checks.Expect(Access::Hidden(shelf), "enabled shelf is hidden while idle");
  Access::StopMonitor(shelf);

  POINT cursor = {};
  GetCursorPos(&cursor);
  const HWND foreground = GetForegroundWindow();
  Access::Show(shelf, cursor);
  checks.Expect(IsWindowVisible(Access::Window(shelf)) != FALSE,
                "drag hint becomes visible");
  checks.Expect(GetForegroundWindow() == foreground,
                "showing hint does not activate it");
  checks.Expect(SendMessageW(Access::Window(shelf), WM_MOUSEACTIVATE, 0, 0) ==
                    MA_NOACTIVATE,
                "hint declines mouse activation");
  MONITORINFO monitor = {};
  monitor.cbSize = sizeof(monitor);
  GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST), &monitor);
  RECT bounds = {};
  GetWindowRect(Access::Window(shelf), &bounds);
  const LONG shelf_center = (bounds.left + bounds.right) / 2;
  const LONG work_center = (monitor.rcWork.left + monitor.rcWork.right) / 2;
  checks.Expect(std::abs(shelf_center - work_center) <= 1 &&
                    bounds.bottom == monitor.rcWork.bottom - Access::Scale(shelf, 28),
                "hint is anchored at the current work area's bottom center");
  checks.Expect(bounds.right - bounds.left == Access::Scale(shelf, 244) &&
                    bounds.bottom - bounds.top == Access::Scale(shelf, 44),
                "drag prompt stays compact at the active monitor DPI");

  struct Received {
    std::string device;
    std::vector<std::string> paths;
  };
  std::vector<Received> received;
  shelf.SetDropCallback([&](const std::string& device,
                            const std::vector<std::string>& paths) {
    received.push_back({device, paths});
  });
  ComPtr<IDataObject> files;
  files.Attach(new FileDataObject({L"C:\\资料\\多行 报告.pdf",
                                   L"D:\\work files\\image.png"}));
  ComPtr<IDataObject> text;
  text.Attach(new FileDataObject({}, false));
  ComPtr<IDataObject> empty;
  empty.Attach(new FileDataObject({}));

  const auto reset = [&](std::vector<QuickDropDevice> current) {
    Access::Hide(shelf);
    shelf.UpdateDevices(std::move(current));
    Access::Show(shelf, cursor);
  };

  checks.Expect(Enter(shelf, text.Get()) == DROPEFFECT_NONE &&
                    !Access::Expanded(shelf),
                "text data does not expand or accept a drop");
  checks.Expect(Drop(shelf, text.Get(), Access::Footer(shelf)) == DROPEFFECT_NONE &&
                    received.empty(),
                "text data never dispatches files");
  reset(devices);
  checks.Expect(Enter(shelf, files.Get(), DROPEFFECT_MOVE) == DROPEFFECT_NONE &&
                    !Access::Expanded(shelf),
                "move-only source is rejected");
  checks.Expect(Drop(shelf, files.Get(), Access::Footer(shelf)) == DROPEFFECT_NONE &&
                    received.empty(),
                "move-only source never dispatches files");

  reset(devices);
  Enter(shelf, files.Get());
  checks.Expect(Access::Expanded(shelf), "CF_HDROP expands the device panel");
  GetWindowRect(Access::Window(shelf), &bounds);
  checks.Expect(bounds.right - bounds.left == Access::Scale(shelf, 280) &&
                    bounds.bottom - bounds.top == Access::Scale(shelf, 132),
                "three devices fit the compact expanded panel");
  checks.Expect(GetForegroundWindow() == foreground,
                "expanding does not activate the panel");
  checks.Expect(Drop(shelf, files.Get(), Access::Card(shelf, 1)) == DROPEFFECT_COPY,
                "device card accepts a file copy");
  checks.Expect(received.size() == 1 && received.back().device == "desktop" &&
                    received.back().paths == std::vector<std::string>{
                        u8"C:\\资料\\多行 报告.pdf", "D:\\work files\\image.png"},
                "callback preserves both Unicode and spaced file paths");
  checks.Expect(Access::Hidden(shelf), "successful drop hides the panel");

  reset(devices);
  Enter(shelf, files.Get());
  Access::BeginHide(shelf);
  checks.Expect(!Access::Animated(shelf) ||
                    IsWindowVisible(Access::Window(shelf)) != FALSE,
                "hiding fades out instead of disappearing at once");
  checks.Expect(Drop(shelf, files.Get(), Access::Card(shelf, 1)) == DROPEFFECT_NONE &&
                    received.size() == 1,
                "a fading panel no longer accepts drops");
  checks.Expect(Access::Hidden(shelf), "fade-out ends with the panel hidden");

  reset(devices);
  Enter(shelf, files.Get());
  Access::PrepareImmediateRelease(shelf, 1);
  Access::BeginHide(shelf);
  checks.Expect(IsWindowVisible(Access::Window(shelf)) != FALSE,
                "immediate release on the first hover frame preserves fade-out");
  checks.Expect(Access::DropIndex(shelf, Access::Card(shelf, 1)) == -1,
                "immediate release disables drops while the fade is visible");
  Access::Settle(shelf);
  checks.Expect(Access::Hidden(shelf),
                "immediate-release fade completes and hides the panel");

  reset({devices.front()});
  Enter(shelf, files.Get());
  checks.Expect(Drop(shelf, files.Get(), Access::Footer(shelf)) == DROPEFFECT_COPY &&
                    received.size() == 2 && received.back().device == "phone",
                "a single device accepts a direct footer drop");

  reset(devices);
  Enter(shelf, files.Get());
  checks.Expect(Drop(shelf, files.Get(), Access::Footer(shelf)) == DROPEFFECT_NONE &&
                    received.size() == 2,
                "multiple devices require an explicit card, not the footer");

  reset({devices[0], devices[1]});
  Enter(shelf, files.Get());
  const POINT original_first_card = Access::Card(shelf, 0);
  shelf.UpdateDevices({devices[1], devices[2], devices[0]});
  checks.Expect(Access::VisibleIds(shelf) ==
                    std::vector<std::string>{"phone", "desktop"},
                "device refresh freezes the gesture's original card order");
  checks.Expect(Drop(shelf, files.Get(), original_first_card) == DROPEFFECT_COPY &&
                    received.size() == 3 && received.back().device == "phone",
                "refresh cannot move another recipient under the pointer");

  reset({devices[0], devices[1]});
  Enter(shelf, files.Get());
  const POINT removed_card = Access::Card(shelf, 0);
  shelf.UpdateDevices({devices[1]});
  checks.Expect(Access::Hit(shelf, removed_card) == -1 &&
                    Access::DropIndex(shelf, removed_card) == -1,
                "offline card is unavailable without moving surviving cards");
  DWORD effect = DROPEFFECT_COPY;
  Access::Target(shelf)->DragOver(MK_LBUTTON, OlePoint(removed_card), &effect);
  checks.Expect(effect == DROPEFFECT_NONE &&
                    Drop(shelf, files.Get(), removed_card) == DROPEFFECT_NONE &&
                    received.size() == 3,
                "offline recipient rejects DragOver and Drop");

  reset({devices[0]});
  Enter(shelf, empty.Get());
  checks.Expect(Drop(shelf, empty.Get(), Access::Card(shelf, 0)) == DROPEFFECT_NONE &&
                    received.size() == 3,
                "empty CF_HDROP does not dispatch a job");

  std::vector<QuickDropDevice> many;
  for (int index = 0; index < 7; ++index) {
    many.push_back(Device("device-" + std::to_string(index), "Device", "D",
                           "#238B74"));
  }
  reset(many);
  Enter(shelf, files.Get());
  Access::SetScroll(shelf, 20);
  checks.Expect(Access::Hit(shelf, Access::ScreenPoint(shelf, 20, 50)) == -1 &&
                    Access::Hit(shelf, Access::ScreenPoint(shelf, 260, 50)) == -1,
                "clipped card edges cannot receive drops");
  checks.Expect(Access::Hit(shelf, Access::ScreenPoint(shelf, 29, 50)) == 0,
                "visible portion of a partially clipped card remains usable");
  for (int count = 0; count < 200; ++count) {
    Access::ScrollToward(shelf, Access::ScreenPoint(shelf, 265, 50));
  }
  checks.Expect(Access::Scroll(shelf) == Access::MaxScroll(shelf),
                "right edge scrolling stops at the content boundary");
  checks.Expect(Access::Hit(shelf, Access::Card(shelf, 6)) == 6,
                "last recipient is reachable after scrolling the compact panel");
  Access::ScrollToward(shelf, Access::ScreenPoint(shelf, 15, 110));
  checks.Expect(Access::Scroll(shelf) == Access::MaxScroll(shelf),
                "footer movement does not scroll recipients");
  for (int count = 0; count < 200; ++count) {
    Access::ScrollToward(shelf, Access::ScreenPoint(shelf, 15, 50));
  }
  checks.Expect(Access::Scroll(shelf) == 0,
                "left edge scrolling stops at the first recipient");

  shelf.SetEnabled(false, nullptr);
  checks.Expect(Access::Hidden(shelf) && !Access::Enabled(shelf),
                "disabling hides the shelf and stops monitoring");
  checks.Expect(Drop(shelf, files.Get(), cursor) == DROPEFFECT_NONE &&
                    received.size() == 3,
                "a pending drop after disable cannot dispatch files");
  Access::Show(shelf, cursor);
  checks.Expect(Access::Hidden(shelf), "disabled shelf cannot be shown");
  shelf.Destroy();
  shelf.Destroy();
  return checks.Finish();
}

int RunInteractive(const std::wstring& mode) {
  QuickDropShelf shelf;
  shelf.UpdateDevices(DemoDevices());
  shelf.SetDropCallback([](const std::string&,
                            const std::vector<std::string>& paths) {
    std::cout << "Drop received: " << paths.size()
              << " path(s); test mode does not send.\n" << std::flush;
  });
  shelf.SetEnabled(true, nullptr);
  if (!Access::Enabled(shelf)) {
    std::cerr << "Unable to enable Shell drag monitoring.\n";
    return 1;
  }
  if (mode != L"--observe") {
    Access::StopMonitor(shelf);
    POINT cursor = {};
    GetCursorPos(&cursor);
    Access::ShowAnimated(shelf, cursor);
    if (mode == L"--preview-expanded") Access::Expand(shelf);
  }
  std::cout << (mode == L"--observe" ? "Observing Shell file drag gestures.\n"
                                     : "Quick drop preview ready.\n")
            << std::flush;
  MSG message = {};
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  return 0;
}

}  // namespace

int wmain(int count, wchar_t* arguments[]) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  if (count == 1) return RunChecks();
  if (count == 2) {
    const std::wstring mode = arguments[1];
    if (mode == L"--preview" || mode == L"--preview-expanded" ||
        mode == L"--observe") {
      return RunInteractive(mode);
    }
  }
  std::cerr << "Usage: quick_drop_shelf_test [--preview|--preview-expanded|--observe]\n";
  return 2;
}
