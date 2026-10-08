#include "quick_drop_shelf.h"
#include "resource.h"

#include <ole2.h>
#include <shellapi.h>
#include <algorithm>
#include <sstream>
#include <utility>

namespace {
constexpr wchar_t kShelfClassName[] = L"LocalChatQuickDropShelf";
constexpr UINT kDragChanged = WM_APP + 0x341;
constexpr UINT_PTR kWatchTimer = 1;
constexpr UINT_PTR kEndTimer = 2;
constexpr UINT_PTR kLeaveTimer = 3;
constexpr int kPromptWidth = 360;
constexpr int kExpandedWidth = 420;
constexpr int kPromptHeight = 52;
constexpr int kExpandedHeight = 168;
constexpr BYTE kOpacity = 248;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
      result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
      result.data(), size, nullptr, nullptr);
  return result;
}

COLORREF ColorFromHex(const std::string& value) {
  std::string clean = value;
  if (!clean.empty() && clean[0] == '#') clean.erase(0, 1);
  unsigned int color = 0;
  std::stringstream stream;
  stream << std::hex << clean;
  if (clean.size() != 6 || !(stream >> color)) return RGB(31, 163, 122);
  return RGB((color >> 16) & 255, (color >> 8) & 255, color & 255);
}

void RoundFill(HDC dc, RECT rect, int radius, COLORREF color) {
  HBRUSH brush = CreateSolidBrush(color);
  HGDIOBJ old_brush = SelectObject(dc, brush);
  HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
  RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(brush);
}

HFONT UiFont(int height, int weight = FW_NORMAL) {
  return CreateFontW(-height, 0, 0, 0, weight, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
}

bool HasFiles(IDataObject* object) {
  if (!object) return false;
  FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  return object->QueryGetData(&format) == S_OK;
}

std::vector<std::string> ReadDropPaths(IDataObject* object) {
  std::vector<std::string> paths;
  if (!object) return paths;
  FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (FAILED(object->GetData(&format, &medium))) return paths;
  if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal) {
    const HDROP drop = static_cast<HDROP>(medium.hGlobal);
    const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT index = 0; index < count; ++index) {
      const UINT length = DragQueryFileW(drop, index, nullptr, 0);
      std::wstring path(length + 1, L'\0');
      if (DragQueryFileW(drop, index, path.data(), length + 1) > 0) {
        path.resize(length);
        paths.push_back(WideToUtf8(path));
      }
    }
  }
  ReleaseStgMedium(&medium);
  return paths;
}
}  // namespace

class QuickDropShelf::DropTarget : public IDropTarget {
 public:
  explicit DropTarget(QuickDropShelf* shelf) : shelf_(shelf) {}
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* object, DWORD, POINTL point,
                                       DWORD* effect) override {
    accepted_ = HasFiles(object) && ((*effect & DROPEFFECT_COPY) != 0);
    *effect = DROPEFFECT_NONE;
    if (!accepted_ || !shelf_->enabled_) return S_OK;
    KillTimer(shelf_->hwnd_, kEndTimer);
    KillTimer(shelf_->hwnd_, kLeaveTimer);
    shelf_->ole_drag_active_ = true;
    shelf_->SetExpanded(true);
    return DragOver(0, point, effect);
  }
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL point, DWORD* effect) override {
    *effect = DROPEFFECT_NONE;
    if (!accepted_ || !shelf_->enabled_) return S_OK;
    const POINT cursor = {point.x, point.y};
    shelf_->ScrollToward(cursor);
    const int hover = shelf_->HitTest(cursor);
    if (hover != shelf_->hover_index_) {
      shelf_->hover_index_ = hover;
      InvalidateRect(shelf_->hwnd_, nullptr, FALSE);
    }
    if (shelf_->DropIndex(cursor) >= 0) *effect = DROPEFFECT_COPY;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragLeave() override {
    accepted_ = false;
    shelf_->ole_drag_active_ = false;
    shelf_->hover_index_ = -1;
    SetTimer(shelf_->hwnd_, kLeaveTimer, 120, nullptr);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* object, DWORD, POINTL point,
                                  DWORD* effect) override {
    *effect = DROPEFFECT_NONE;
    const int index = shelf_->DropIndex({point.x, point.y});
    if (accepted_ && shelf_->enabled_ && index >= 0) {
      const auto paths = ReadDropPaths(object);
      if (!paths.empty()) {
        shelf_->NotifyDrop(index, paths);
        *effect = DROPEFFECT_COPY;
      }
    }
    accepted_ = false;
    shelf_->ole_drag_active_ = false;
    shelf_->Hide();
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDropTarget) return E_NOINTERFACE;
    *result = static_cast<IDropTarget*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&refs_);
  }
  ULONG STDMETHODCALLTYPE Release() override {
    const LONG count = InterlockedDecrement(&refs_);
    if (!count) delete this;
    return static_cast<ULONG>(count);
  }
 private:
  QuickDropShelf* shelf_;
  LONG refs_ = 1;
  bool accepted_ = false;
};

QuickDropShelf::QuickDropShelf() = default;
QuickDropShelf::~QuickDropShelf() { Destroy(); }
void QuickDropShelf::SetDropCallback(DropCallback callback) {
  drop_callback_ = std::move(callback);
}

void QuickDropShelf::SetEnabled(bool enabled, HWND owner) {
  owner_ = owner;
  if (enabled == enabled_) return;
  if (!enabled) {
    enabled_ = false;
    drag_monitor_.Stop();
    Hide();
    return;
  }
  if (!hwnd_ && !Create(owner)) return;
  enabled_ = drag_monitor_.Start(hwnd_, kDragChanged);
  // Remain invisible until a Shell item drag has been observed.
}

bool QuickDropShelf::Create(HWND owner) {
  owner_ = owner;
  if (!ole_initialized_) {
    if (FAILED(OleInitialize(nullptr))) return false;
    ole_initialized_ = true;
  }
  WNDCLASSW cls = {};
  cls.hCursor = LoadCursor(nullptr, IDC_ARROW);
  cls.lpszClassName = kShelfClassName;
  cls.hInstance = GetModuleHandle(nullptr);
  cls.lpfnWndProc = WndProc;
  if (!RegisterClassW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
      kShelfClassName, L"LocalChat 文件投递", WS_POPUP,
      0, 0, 1, 1, nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (!hwnd_) return false;
  app_icon_ = static_cast<HICON>(LoadImageW(GetModuleHandle(nullptr),
      MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON, 48, 48, LR_DEFAULTCOLOR));
  drop_target_ = new DropTarget(this);
  if (FAILED(RegisterDragDrop(hwnd_, drop_target_))) {
    drop_target_->Release();
    drop_target_ = nullptr;
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    return false;
  }
  SetLayeredWindowAttributes(hwnd_, 0, kOpacity, LWA_ALPHA);
  return true;
}

void QuickDropShelf::Destroy() {
  enabled_ = false;
  drag_monitor_.Stop();
  Hide();
  if (hwnd_ && drop_target_) RevokeDragDrop(hwnd_);
  if (drop_target_) { drop_target_->Release(); drop_target_ = nullptr; }
  if (hwnd_) { DestroyWindow(hwnd_); hwnd_ = nullptr; }
  if (app_icon_) { DestroyIcon(app_icon_); app_icon_ = nullptr; }
  if (ole_initialized_) { OleUninitialize(); ole_initialized_ = false; }
}

void QuickDropShelf::UpdateDevices(std::vector<QuickDropDevice> devices) {
  devices_ = std::move(devices);
  if (state_ != State::hidden) {
    for (auto& shown : drag_devices_) {
      const auto latest = std::find_if(devices_.begin(), devices_.end(),
          [&](const QuickDropDevice& item) { return item.id == shown.id; });
      if (latest != devices_.end()) shown = *latest;
    }
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

int QuickDropShelf::Scale(int value) const { return MulDiv(value, dpi_, 96); }

void QuickDropShelf::ShowForDrag(POINT point) {
  if (!enabled_ || !hwnd_) return;
  KillTimer(hwnd_, kEndTimer);
  if (state_ != State::hidden) return;
  drag_devices_ = devices_;
  state_ = State::prompt;
  scroll_x_ = 0;
  hover_index_ = -1;
  shown_at_ = GetTickCount64();
  Layout(point);
  SetLayeredWindowAttributes(hwnd_, 0, 0, LWA_ALPHA);
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  SetTimer(hwnd_, kWatchTimer, 30, nullptr);
  InvalidateRect(hwnd_, nullptr, FALSE);
  UpdateWindow(hwnd_);
}

void QuickDropShelf::Hide() {
  if (!hwnd_) return;
  KillTimer(hwnd_, kWatchTimer);
  KillTimer(hwnd_, kEndTimer);
  KillTimer(hwnd_, kLeaveTimer);
  ShowWindow(hwnd_, SW_HIDE);
  state_ = State::hidden;
  hover_index_ = -1;
  ole_drag_active_ = false;
  drag_devices_.clear();
}

void QuickDropShelf::SetExpanded(bool expanded) {
  if (state_ == State::hidden) return;
  state_ = expanded ? State::devices : State::prompt;
  hover_index_ = -1;
  POINT point;
  GetCursorPos(&point);
  Layout(point);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void QuickDropShelf::Layout(POINT point) {
  if (laying_out_) return;
  laying_out_ = true;
  monitor_ = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(info)};
  if (!GetMonitorInfoW(monitor_, &info)) { laying_out_ = false; return; }
  // Move onto the destination monitor before reading its effective window DPI.
  // NOREDRAW prevents an intermediate frame at the positioning probe.
  SetWindowPos(hwnd_, HWND_TOPMOST, info.rcWork.left + 1, info.rcWork.top + 1,
      0, 0, SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOREDRAW);
  dpi_ = GetDpiForWindow(hwnd_);
  if (!dpi_) dpi_ = 96;
  const int width = Scale(state_ == State::devices ? kExpandedWidth : kPromptWidth);
  const int height = Scale(state_ == State::devices ? kExpandedHeight : kPromptHeight);
  const int x = (std::max)(info.rcWork.left, info.rcWork.right - width - Scale(16));
  const int y = (std::max)(info.rcWork.top, info.rcWork.bottom - height - Scale(16));
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
  SetWindowRgn(hwnd_, CreateRoundRectRgn(0, 0, width + 1, height + 1,
      Scale(14), Scale(14)), TRUE);
  laying_out_ = false;
}

bool QuickDropShelf::IsAvailable(const std::string& id) const {
  return std::any_of(devices_.begin(), devices_.end(),
      [&](const QuickDropDevice& device) { return device.id == id; });
}
RECT QuickDropShelf::CardsClip() const {
  return {Scale(28), Scale(8), Scale(kExpandedWidth - 28), Scale(108)};
}
RECT QuickDropShelf::CardRect(int index) const {
  const int count = static_cast<int>(drag_devices_.size());
  const int start = count <= 4
      ? (kExpandedWidth - count * 80 - (count - 1) * 10) / 2 : 32;
  const int left = Scale(start + index * 90 - scroll_x_);
  return {left, Scale(12), left + Scale(80), Scale(104)};
}
int QuickDropShelf::MaxScroll() const {
  const int count = static_cast<int>(drag_devices_.size());
  return count <= 4 ? 0 : (std::max)(0, count * 80 + (count - 1) * 10 - 356);
}
int QuickDropShelf::HitTest(POINT point) const {
  if (state_ != State::devices) return -1;
  ScreenToClient(hwnd_, &point);
  const RECT clip = CardsClip();
  if (!PtInRect(&clip, point)) return -1;
  for (int index = 0; index < static_cast<int>(drag_devices_.size()); ++index) {
    const RECT rect = CardRect(index);
    if (PtInRect(&rect, point) && IsAvailable(drag_devices_[index].id)) return index;
  }
  return -1;
}
int QuickDropShelf::DropIndex(POINT point) const {
  const int index = HitTest(point);
  if (index >= 0) return index;
  if (state_ != State::hidden && drag_devices_.size() == 1 &&
      IsAvailable(drag_devices_.front().id)) {
    RECT rect;
    GetWindowRect(hwnd_, &rect);
    if (PtInRect(&rect, point)) return 0;
  }
  return -1;
}
void QuickDropShelf::ScrollToward(POINT point) {
  if (state_ != State::devices || MaxScroll() == 0) return;
  ScreenToClient(hwnd_, &point);
  if (point.y < Scale(8) || point.y > Scale(108)) return;
  int next = scroll_x_;
  if (point.x < Scale(48)) next -= 8;
  if (point.x > Scale(kExpandedWidth - 48)) next += 8;
  next = (std::clamp)(next, 0, MaxScroll());
  if (next != scroll_x_) {
    scroll_x_ = next;
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
}
void QuickDropShelf::NotifyDrop(int index, const std::vector<std::string>& paths) {
  if (index < 0 || index >= static_cast<int>(drag_devices_.size()) ||
      !IsAvailable(drag_devices_[index].id) || !drop_callback_) return;
  drop_callback_(drag_devices_[index].id, paths);
}

void QuickDropShelf::Paint() {
  PAINTSTRUCT paint;
  HDC target = BeginPaint(hwnd_, &paint);
  RECT client;
  GetClientRect(hwnd_, &client);
  HDC dc = CreateCompatibleDC(target);
  HBITMAP bitmap = CreateCompatibleBitmap(target, client.right, client.bottom);
  HGDIOBJ old_bitmap = SelectObject(dc, bitmap);
  HBRUSH background = CreateSolidBrush(RGB(39, 43, 47));
  FillRect(dc, &client, background);
  DeleteObject(background);
  SetBkMode(dc, TRANSPARENT);
  const int footer = client.bottom - Scale(kPromptHeight);
  HFONT body = UiFont(Scale(13));
  HGDIOBJ old_font = SelectObject(dc, body);
  SetTextColor(dc, RGB(232, 237, 241));
  DrawIconEx(dc, Scale(16), footer + Scale(16), app_icon_, Scale(20), Scale(20),
      0, nullptr, DI_NORMAL);
  RECT label = {Scale(48), footer, client.right - Scale(14), client.bottom};
  const wchar_t* prompt = state_ == State::prompt
      ? L"拖到这里，发送到其他设备" : L"拖到设备上松开，即可发送";
  if (drag_devices_.empty()) prompt = L"暂无在线设备，打开 LocalChat 配对";
  DrawTextW(dc, prompt, -1, &label,
      DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);

  if (state_ == State::devices) {
    RECT divider = {Scale(16), footer, client.right - Scale(16), footer + 1};
    HBRUSH line = CreateSolidBrush(RGB(65, 70, 75));
    FillRect(dc, &divider, line);
    DeleteObject(line);
    if (drag_devices_.empty()) {
      RECT empty = {Scale(20), Scale(18), client.right - Scale(20), footer - Scale(8)};
      SetTextColor(dc, RGB(162, 174, 183));
      DrawTextW(dc, L"请先配对设备，并保持两端在线", -1, &empty,
          DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }
    const RECT clip = CardsClip();
    const int saved = SaveDC(dc);
    IntersectClipRect(dc, clip.left, clip.top, clip.right, clip.bottom);
    HFONT name = UiFont(Scale(12));
    HFONT initial = UiFont(Scale(16), FW_SEMIBOLD);
    for (int index = 0; index < static_cast<int>(drag_devices_.size()); ++index) {
      const auto& device = drag_devices_[index];
      const bool available = IsAvailable(device.id);
      const RECT rect = CardRect(index);
      if (index == hover_index_ && available) {
        RoundFill(dc, rect, Scale(12), RGB(31, 120, 96));
      }
      const int center = (rect.left + rect.right) / 2;
      const RECT avatar = {center - Scale(18), rect.top + Scale(7),
          center + Scale(18), rect.top + Scale(43)};
      RoundFill(dc, avatar, Scale(14), available ? ColorFromHex(device.avatar_color)
                                               : RGB(76, 81, 87));
      SelectObject(dc, initial);
      SetTextColor(dc, RGB(255, 255, 255));
      RECT initial_rect = avatar;
      const std::wstring letter = Utf8ToWide(device.avatar_initial);
      DrawTextW(dc, letter.c_str(), -1, &initial_rect,
          DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
      SelectObject(dc, name);
      SetTextColor(dc, available ? RGB(232, 237, 241) : RGB(133, 140, 146));
      RECT text = {rect.left + Scale(3), rect.top + Scale(49),
          rect.right - Scale(3), rect.bottom};
      const std::wstring title = available ? Utf8ToWide(device.display_name) : L"设备已离线";
      DrawTextW(dc, title.c_str(), -1, &text,
          DT_CENTER | DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX);
    }
    RestoreDC(dc, saved);
    DeleteObject(name);
    DeleteObject(initial);
    if (MaxScroll() > 0) {
      SetTextColor(dc, RGB(172, 182, 190));
      RECT left = {Scale(5), Scale(24), Scale(25), Scale(88)};
      RECT right = {client.right - Scale(25), Scale(24), client.right - Scale(5), Scale(88)};
      if (scroll_x_ > 0) DrawTextW(dc, L"‹", -1, &left, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      if (scroll_x_ < MaxScroll()) DrawTextW(dc, L"›", -1, &right, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    }
  }
  SelectObject(dc, old_font);
  DeleteObject(body);
  BitBlt(target, 0, 0, client.right, client.bottom, dc, 0, 0, SRCCOPY);
  SelectObject(dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(dc);
  EndPaint(hwnd_, &paint);
}

LRESULT CALLBACK QuickDropShelf::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                         LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* shelf = reinterpret_cast<QuickDropShelf*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  return shelf ? shelf->HandleMessage(hwnd, message, wparam, lparam)
               : DefWindowProcW(hwnd, message, wparam, lparam);
}
LRESULT QuickDropShelf::HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  switch (message) {
    case kDragChanged: {
      if (!enabled_) return 0;
      if (drag_monitor_.IsDragging()) {
        POINT cursor;
        GetCursorPos(&cursor);
        ShowForDrag(cursor);
      } else if (state_ != State::hidden) {
        // OLE can deliver Drop after the low-level button-up notification.
        SetTimer(hwnd_, kEndTimer, 120, nullptr);
      }
      return 0;
    }
    case WM_TIMER:
      if (wparam == kEndTimer) { Hide(); return 0; }
      if (wparam == kLeaveTimer) {
        KillTimer(hwnd, kLeaveTimer);
        if (!ole_drag_active_) {
          if (drag_monitor_.IsDragging()) SetExpanded(false);
          else Hide();
        }
        return 0;
      }
      if (wparam == kWatchTimer && state_ != State::hidden) {
        const ULONGLONG elapsed = (std::min)(GetTickCount64() - shown_at_, 120ULL);
        SetLayeredWindowAttributes(hwnd, 0, static_cast<BYTE>(kOpacity * elapsed / 120), LWA_ALPHA);
        POINT cursor;
        GetCursorPos(&cursor);
        if (MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST) != monitor_) Layout(cursor);
        if (ole_drag_active_) {
          ScrollToward(cursor);
          hover_index_ = HitTest(cursor);
          InvalidateRect(hwnd, nullptr, FALSE);
        }
      }
      return 0;
    case WM_DPICHANGED:
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
      if (state_ != State::hidden && !laying_out_) {
        POINT cursor;
        GetCursorPos(&cursor);
        Layout(cursor);
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
    case WM_NCHITTEST: return HTCLIENT;
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: Paint(); return 0;
    case WM_CLOSE: Hide(); return 0;
    default: return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}
