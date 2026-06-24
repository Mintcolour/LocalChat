#include "quick_drop_shelf.h"

#include <objidl.h>
#include <ole2.h>
#include <shellapi.h>

#include <algorithm>
#include <sstream>

namespace {

constexpr const wchar_t kShelfClassName[] = L"LocalChatQuickDropShelf";
constexpr int kCollapsedHeight = 8;
constexpr int kExpandedHeight = 128;
constexpr int kCardWidth = 220;
constexpr int kCardHeight = 88;
constexpr int kCardGap = 12;
constexpr int kSidePadding = 24;
constexpr int kTopPadding = 20;
constexpr int kAutoscrollEdge = 72;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return L"";
  int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.length()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.length()), result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.length()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.length()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

COLORREF ColorFromHex(const std::string& value, COLORREF fallback) {
  std::string clean = value;
  if (!clean.empty() && clean[0] == '#') {
    clean = clean.substr(1);
  }
  if (clean.length() != 6) return fallback;
  unsigned int color = 0;
  std::stringstream stream;
  stream << std::hex << clean;
  if (!(stream >> color)) return fallback;
  return RGB((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF);
}

void FillRoundRect(HDC hdc, const RECT& rect, int radius, COLORREF color) {
  HBRUSH brush = CreateSolidBrush(color);
  HPEN pen = CreatePen(PS_SOLID, 1, color);
  HGDIOBJ old_brush = SelectObject(hdc, brush);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);
}

void StrokeRoundRect(HDC hdc, const RECT& rect, int radius, COLORREF color,
                     int width) {
  HBRUSH brush = static_cast<HBRUSH>(GetStockObject(NULL_BRUSH));
  HPEN pen = CreatePen(PS_SOLID, width, color);
  HGDIOBJ old_brush = SelectObject(hdc, brush);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(pen);
}

HFONT CreateUiFont(int size, int weight = FW_NORMAL) {
  return CreateFontW(-size, 0, 0, 0, weight, FALSE, FALSE, FALSE,
                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                     L"Segoe UI");
}

int MaxScroll(int device_count, int window_width) {
  if (device_count <= 0) return 0;
  const int content_width = kSidePadding * 2 + device_count * kCardWidth +
                            (device_count - 1) * kCardGap;
  return (std::max)(0, content_width - window_width);
}

std::vector<std::string> ReadDropPaths(IDataObject* data_object) {
  std::vector<std::string> paths;
  FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (data_object->QueryGetData(&format) != S_OK ||
      data_object->GetData(&format, &medium) != S_OK) {
    return paths;
  }

  HDROP drop = static_cast<HDROP>(GlobalLock(medium.hGlobal));
  if (drop != nullptr) {
    UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT index = 0; index < count; ++index) {
      UINT length = DragQueryFileW(drop, index, nullptr, 0);
      std::wstring path(length + 1, L'\0');
      DragQueryFileW(drop, index, path.data(), length + 1);
      path.resize(length);
      paths.push_back(WideToUtf8(path));
    }
    GlobalUnlock(medium.hGlobal);
  }
  ReleaseStgMedium(&medium);
  return paths;
}

class WindowClassRegistrar {
 public:
  static const wchar_t* GetClassName() {
    static bool registered = false;
    if (!registered) {
      WNDCLASSW window_class = {};
      window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
      window_class.lpszClassName = kShelfClassName;
      window_class.hInstance = GetModuleHandle(nullptr);
      window_class.hbrBackground = nullptr;
      window_class.lpfnWndProc = QuickDropShelf::WndProc;
      RegisterClassW(&window_class);
      registered = true;
    }
    return kShelfClassName;
  }
};

}  // namespace

class QuickDropShelf::DropTarget : public IDropTarget {
 public:
  explicit DropTarget(QuickDropShelf* shelf) : shelf_(shelf) {}

  HRESULT DragEnter(IDataObject* data_object,
                    DWORD key_state,
                    POINTL point,
                    DWORD* effect) override {
    shelf_->SetExpanded(true);
    POINT screen_point = {point.x, point.y};
    shelf_->hover_index_ = shelf_->HitTest(screen_point);
    *effect = shelf_->devices_.empty() ? DROPEFFECT_NONE : DROPEFFECT_COPY;
    InvalidateRect(shelf_->hwnd_, nullptr, TRUE);
    return S_OK;
  }

  HRESULT DragOver(DWORD key_state, POINTL point, DWORD* effect) override {
    POINT screen_point = {point.x, point.y};
    shelf_->ScrollToward(screen_point);
    shelf_->hover_index_ = shelf_->HitTest(screen_point);
    *effect = shelf_->devices_.empty() ? DROPEFFECT_NONE : DROPEFFECT_COPY;
    InvalidateRect(shelf_->hwnd_, nullptr, TRUE);
    return S_OK;
  }

  HRESULT DragLeave() override {
    shelf_->hover_index_ = -1;
    shelf_->SetExpanded(false);
    return S_OK;
  }

  HRESULT Drop(IDataObject* data_object,
               DWORD key_state,
               POINTL point,
               DWORD* effect) override {
    POINT screen_point = {point.x, point.y};
    int index = shelf_->HitTest(screen_point);
    if (index < 0 && shelf_->devices_.size() == 1) {
      index = 0;
    }
    const auto paths = ReadDropPaths(data_object);
    if (index >= 0 && !paths.empty()) {
      shelf_->NotifyDrop(index, paths);
      *effect = DROPEFFECT_COPY;
    } else {
      *effect = DROPEFFECT_NONE;
    }
    shelf_->hover_index_ = -1;
    shelf_->SetExpanded(false);
    return S_OK;
  }

  HRESULT QueryInterface(const IID& iid, void** object) override {
    if (iid == IID_IUnknown || iid == IID_IDropTarget) {
      *object = static_cast<IDropTarget*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG AddRef() override {
    return InterlockedIncrement(&ref_count_);
  }

  ULONG Release() override {
    LONG count = InterlockedDecrement(&ref_count_);
    return static_cast<ULONG>(count);
  }

 private:
  QuickDropShelf* shelf_;
  LONG ref_count_ = 1;
};

QuickDropShelf::QuickDropShelf() = default;

QuickDropShelf::~QuickDropShelf() {
  Destroy();
}

void QuickDropShelf::SetDropCallback(DropCallback callback) {
  drop_callback_ = std::move(callback);
}

void QuickDropShelf::SetEnabled(bool enabled, HWND owner) {
  enabled_ = enabled;
  owner_ = owner;
  if (!enabled_) {
    if (hwnd_ != nullptr) {
      ShowWindow(hwnd_, SW_HIDE);
    }
    return;
  }
  if (hwnd_ == nullptr && !Create(owner)) {
    return;
  }
  LayoutCollapsed();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
}

void QuickDropShelf::UpdateDevices(std::vector<QuickDropDevice> devices) {
  devices_ = std::move(devices);
  scroll_x_ = 0;
  if (hwnd_ != nullptr) {
    RECT rect = {};
    GetClientRect(hwnd_, &rect);
    scroll_x_ = (std::min)(scroll_x_,
                           MaxScroll(static_cast<int>(devices_.size()),
                                     rect.right - rect.left));
    InvalidateRect(hwnd_, nullptr, TRUE);
  }
}

void QuickDropShelf::Destroy() {
  RevokeDropTarget();
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  if (ole_initialized_) {
    OleUninitialize();
    ole_initialized_ = false;
  }
}

bool QuickDropShelf::Create(HWND owner) {
  owner_ = owner;
  if (!ole_initialized_) {
    const HRESULT result = OleInitialize(nullptr);
    ole_initialized_ = SUCCEEDED(result);
  }
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
      WindowClassRegistrar::GetClassName(), L"LocalChat quick drop shelf",
      WS_POPUP, 0, 0, 1, 1, nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (hwnd_ == nullptr) {
    return false;
  }
  SetLayeredWindowAttributes(hwnd_, 0, 246, LWA_ALPHA);
  RegisterDropTarget();
  return true;
}

void QuickDropShelf::RegisterDropTarget() {
  if (hwnd_ == nullptr || drop_target_ != nullptr) return;
  drop_target_ = new DropTarget(this);
  HRESULT result = RegisterDragDrop(hwnd_, drop_target_);
  if (FAILED(result)) {
    delete drop_target_;
    drop_target_ = nullptr;
  }
}

void QuickDropShelf::RevokeDropTarget() {
  if (hwnd_ != nullptr && drop_target_ != nullptr) {
    RevokeDragDrop(hwnd_);
    delete drop_target_;
    drop_target_ = nullptr;
  }
}

void QuickDropShelf::LayoutCollapsed() {
  expanded_ = false;
  hover_index_ = -1;
  HMONITOR monitor = MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  SetWindowPos(hwnd_, HWND_TOPMOST, work.left, work.bottom - kCollapsedHeight,
               work.right - work.left, kCollapsedHeight,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void QuickDropShelf::LayoutExpanded() {
  expanded_ = true;
  HMONITOR monitor = MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  SetWindowPos(hwnd_, HWND_TOPMOST, work.left, work.bottom - kExpandedHeight,
               work.right - work.left, kExpandedHeight,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void QuickDropShelf::SetExpanded(bool expanded) {
  if (hwnd_ == nullptr) return;
  if (expanded == expanded_) return;
  if (expanded) {
    LayoutExpanded();
  } else {
    LayoutCollapsed();
  }
}

void QuickDropShelf::Paint() {
  PAINTSTRUCT ps = {};
  HDC hdc = BeginPaint(hwnd_, &ps);
  RECT client = {};
  GetClientRect(hwnd_, &client);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;

  HBRUSH background = CreateSolidBrush(expanded_ ? RGB(248, 250, 252)
                                                  : RGB(31, 163, 122));
  FillRect(hdc, &client, background);
  DeleteObject(background);

  if (!expanded_) {
    EndPaint(hwnd_, &ps);
    return;
  }

  HPEN top_line = CreatePen(PS_SOLID, 1, RGB(203, 213, 225));
  HGDIOBJ old_pen = SelectObject(hdc, top_line);
  MoveToEx(hdc, 0, 0, nullptr);
  LineTo(hdc, width, 0);
  SelectObject(hdc, old_pen);
  DeleteObject(top_line);

  SetBkMode(hdc, TRANSPARENT);
  HFONT title_font = CreateUiFont(15, FW_SEMIBOLD);
  HFONT meta_font = CreateUiFont(12, FW_NORMAL);
  HFONT avatar_font = CreateUiFont(18, FW_BOLD);

  if (devices_.empty()) {
    HFONT empty_font = CreateUiFont(15, FW_SEMIBOLD);
    HGDIOBJ old_font = SelectObject(hdc, empty_font);
    SetTextColor(hdc, RGB(71, 85, 105));
    RECT text_rect = {0, 0, width, height};
    DrawTextW(hdc, L"No online trusted devices", -1, &text_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    SelectObject(hdc, old_font);
    DeleteObject(empty_font);
    DeleteObject(title_font);
    DeleteObject(meta_font);
    DeleteObject(avatar_font);
    EndPaint(hwnd_, &ps);
    return;
  }

  scroll_x_ = (std::min)(scroll_x_,
                         MaxScroll(static_cast<int>(devices_.size()), width));
  scroll_x_ = (std::max)(0, scroll_x_);

  for (int i = 0; i < static_cast<int>(devices_.size()); ++i) {
    const auto& device = devices_[i];
    RECT card = CardRect(i);
    if (card.right < 0 || card.left > width) continue;

    const bool hover = i == hover_index_;
    const COLORREF border = device.selected
                                ? RGB(31, 163, 122)
                                : (hover ? RGB(15, 118, 110)
                                         : RGB(203, 213, 225));
    FillRoundRect(hdc, card, 8, hover ? RGB(236, 253, 245)
                                      : RGB(255, 255, 255));
    StrokeRoundRect(hdc, card, 8, border, device.selected || hover ? 2 : 1);

    RECT avatar = {card.left + 14, card.top + 18, card.left + 62,
                   card.top + 66};
    HBRUSH avatar_brush =
        CreateSolidBrush(ColorFromHex(device.avatar_color, RGB(37, 99, 235)));
    HPEN avatar_pen = CreatePen(PS_SOLID, 1,
                                ColorFromHex(device.avatar_color,
                                             RGB(37, 99, 235)));
    HGDIOBJ old_brush = SelectObject(hdc, avatar_brush);
    old_pen = SelectObject(hdc, avatar_pen);
    Ellipse(hdc, avatar.left, avatar.top, avatar.right, avatar.bottom);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(avatar_brush);
    DeleteObject(avatar_pen);

    HGDIOBJ old_font = SelectObject(hdc, avatar_font);
    SetTextColor(hdc, RGB(255, 255, 255));
    RECT avatar_text = avatar;
    const std::wstring initial = Utf8ToWide(device.avatar_initial);
    DrawTextW(hdc, initial.c_str(), -1, &avatar_text,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    RECT name_rect = {card.left + 74, card.top + 15, card.right - 16,
                      card.top + 50};
    SelectObject(hdc, title_font);
    SetTextColor(hdc, RGB(15, 23, 42));
    const std::wstring name = Utf8ToWide(device.display_name);
    DrawTextW(hdc, name.c_str(), -1, &name_rect,
              DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS);

    RECT platform_rect = {card.left + 90, card.top + 56, card.right - 16,
                          card.bottom - 14};
    SelectObject(hdc, meta_font);
    SetTextColor(hdc, RGB(71, 85, 105));
    const std::wstring platform = Utf8ToWide(device.platform);
    DrawTextW(hdc, platform.c_str(), -1, &platform_rect,
              DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS);

    HBRUSH online_brush = CreateSolidBrush(RGB(16, 185, 129));
    old_brush = SelectObject(hdc, online_brush);
    HPEN online_pen = CreatePen(PS_SOLID, 1, RGB(16, 185, 129));
    old_pen = SelectObject(hdc, online_pen);
    Ellipse(hdc, card.left + 74, card.top + 59, card.left + 84,
            card.top + 69);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(online_brush);
    DeleteObject(online_pen);

    SelectObject(hdc, old_font);
  }

  DeleteObject(title_font);
  DeleteObject(meta_font);
  DeleteObject(avatar_font);
  EndPaint(hwnd_, &ps);
}

int QuickDropShelf::HitTest(POINT screen_point) const {
  if (hwnd_ == nullptr || devices_.empty()) return -1;
  POINT client_point = screen_point;
  ScreenToClient(hwnd_, &client_point);
  for (int i = 0; i < static_cast<int>(devices_.size()); ++i) {
    RECT card = CardRect(i);
    if (client_point.x >= card.left && client_point.x <= card.right &&
        client_point.y >= card.top && client_point.y <= card.bottom) {
      return i;
    }
  }
  return -1;
}

RECT QuickDropShelf::CardRect(int index) const {
  const int left = kSidePadding + index * (kCardWidth + kCardGap) - scroll_x_;
  return {left, kTopPadding, left + kCardWidth, kTopPadding + kCardHeight};
}

void QuickDropShelf::ScrollToward(POINT screen_point) {
  if (hwnd_ == nullptr || devices_.empty()) return;
  POINT client_point = screen_point;
  ScreenToClient(hwnd_, &client_point);
  RECT client = {};
  GetClientRect(hwnd_, &client);
  const int width = client.right - client.left;
  const int max_scroll = MaxScroll(static_cast<int>(devices_.size()), width);
  int next_scroll = scroll_x_;
  if (client_point.x < kAutoscrollEdge) {
    next_scroll -= 24;
  } else if (client_point.x > width - kAutoscrollEdge) {
    next_scroll += 24;
  }
  next_scroll = (std::max)(0, (std::min)(next_scroll, max_scroll));
  if (next_scroll != scroll_x_) {
    scroll_x_ = next_scroll;
    InvalidateRect(hwnd_, nullptr, TRUE);
  }
}

void QuickDropShelf::NotifyDrop(
    int device_index,
    const std::vector<std::string>& paths) {
  if (device_index < 0 ||
      device_index >= static_cast<int>(devices_.size()) ||
      !drop_callback_) {
    return;
  }
  drop_callback_(devices_[device_index].id, paths);
}

LRESULT CALLBACK QuickDropShelf::WndProc(HWND hwnd,
                                         UINT message,
                                         WPARAM wparam,
                                         LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto create_struct = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto shelf = static_cast<QuickDropShelf*>(create_struct->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(shelf));
  }
  auto shelf = reinterpret_cast<QuickDropShelf*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (shelf != nullptr) {
    return shelf->HandleMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT QuickDropShelf::HandleMessage(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  switch (message) {
    case WM_PAINT:
      Paint();
      return 0;
    case WM_MOUSEWHEEL: {
      RECT client = {};
      GetClientRect(hwnd_, &client);
      const int width = client.right - client.left;
      const int max_scroll = MaxScroll(static_cast<int>(devices_.size()), width);
      const int delta = GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? -64 : 64;
      scroll_x_ = (std::max)(0, (std::min)(scroll_x_ + delta, max_scroll));
      InvalidateRect(hwnd_, nullptr, TRUE);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_NCHITTEST:
      return HTCLIENT;
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}
