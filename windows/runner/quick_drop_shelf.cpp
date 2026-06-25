#include "quick_drop_shelf.h"
#include "resource.h"

#include <objidl.h>
#include <ole2.h>
#include <shellapi.h>

#include <algorithm>
#include <sstream>

namespace {

constexpr const wchar_t kShelfClassName[] = L"LocalChatQuickDropShelf";
constexpr int kCollapsedWidth = 56;
constexpr int kCollapsedHeight = 56;
constexpr int kExpandedWidth = 480;
constexpr int kExpandedHeight = 120;

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

int MaxScroll(int device_count, int card_width) {
  if (device_count <= 5) return 0;
  const int content_width = device_count * 72 + (device_count - 1) * 12;
  const int visible_width = card_width - 40;
  return (std::max)(0, content_width - visible_width);
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
    KillTimer(shelf_->hwnd_, 4);
    shelf_->drag_leave_pending_ = false;
    if (shelf_->state_ == STATE_HIDDEN_BAR) {
      KillTimer(shelf_->hwnd_, 3);
    }
    shelf_->SetExpanded(true);
    shelf_->hover_index_ = -1;
    *effect = shelf_->devices_.empty() ? DROPEFFECT_NONE : DROPEFFECT_COPY;
    InvalidateRect(shelf_->hwnd_, nullptr, TRUE);
    return S_OK;
  }

  HRESULT DragOver(DWORD key_state, POINTL point, DWORD* effect) override {
    POINT screen_point = {point.x, point.y};
    POINT client_point = screen_point;
    ScreenToClient(shelf_->hwnd_, &client_point);

    RECT card_rect = {10, 10, kExpandedWidth - 10, kExpandedHeight - 10};

    if (shelf_->state_ == STATE_PROMPT && PtInRect(&card_rect, client_point)) {
      shelf_->state_ = STATE_DEVICES;
      InvalidateRect(shelf_->hwnd_, nullptr, TRUE);
    }

    if (shelf_->state_ == STATE_DEVICES) {
      shelf_->ScrollToward(screen_point);
      shelf_->hover_index_ = shelf_->HitTest(screen_point);
    } else {
      shelf_->hover_index_ = -1;
    }

    *effect = DROPEFFECT_NONE;
    if (!shelf_->devices_.empty()) {
      if (shelf_->hover_index_ >= 0 || (shelf_->devices_.size() == 1 && PtInRect(&card_rect, client_point))) {
        *effect = DROPEFFECT_COPY;
      }
    }

    InvalidateRect(shelf_->hwnd_, nullptr, TRUE);
    return S_OK;
  }

  HRESULT DragLeave() override {
    shelf_->hover_index_ = -1;
    shelf_->drag_leave_pending_ = true;
    SetTimer(shelf_->hwnd_, 4, 150, nullptr);
    return S_OK;
  }

  HRESULT Drop(IDataObject* data_object,
               DWORD key_state,
               POINTL point,
               DWORD* effect) override {
    KillTimer(shelf_->hwnd_, 4);
    shelf_->drag_leave_pending_ = false;
    POINT screen_point = {point.x, point.y};
    POINT client_point = screen_point;
    ScreenToClient(shelf_->hwnd_, &client_point);
    RECT card_rect = {10, 10, kExpandedWidth - 10, kExpandedHeight - 10};

    int index = shelf_->HitTest(screen_point);
    if (index < 0 && shelf_->devices_.size() == 1 && PtInRect(&card_rect, client_point)) {
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

void QuickDropShelf::SetHideCallback(HideCallback callback) {
  hide_callback_ = std::move(callback);
}

void QuickDropShelf::SetAutoHide(bool auto_hide) {
  auto_hide_ = auto_hide;
  if (!auto_hide_ && state_ == STATE_HIDDEN_BAR) {
    WakeUp();
  }
}

void QuickDropShelf::SetEnabled(bool enabled, HWND owner) {
  enabled_ = enabled;
  owner_ = owner;
  if (!enabled_) {
    if (hwnd_ != nullptr) {
      KillTimer(hwnd_, 2);
      KillTimer(hwnd_, 3);
      ShowWindow(hwnd_, SW_HIDE);
    }
    return;
  }
  if (hwnd_ == nullptr && !Create(owner)) {
    return;
  }
  LayoutCollapsed();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);

  SetTimer(hwnd_, 2, 1000, nullptr);
  last_active_time_ = GetTickCount64();
}

void QuickDropShelf::UpdateDevices(std::vector<QuickDropDevice> devices) {
  if (devices.size() == devices_.size()) {
    bool same_ids = true;
    for (const auto& new_dev : devices) {
      bool found = false;
      for (const auto& old_dev : devices_) {
        if (old_dev.id == new_dev.id) {
          found = true;
          break;
        }
      }
      if (!found) {
        same_ids = false;
        break;
      }
    }
    if (same_ids) {
      for (auto& old_dev : devices_) {
        for (const auto& new_dev : devices) {
          if (old_dev.id == new_dev.id) {
            old_dev.display_name = new_dev.display_name;
            old_dev.platform = new_dev.platform;
            old_dev.avatar_initial = new_dev.avatar_initial;
            old_dev.avatar_color = new_dev.avatar_color;
            old_dev.selected = new_dev.selected;
            break;
          }
        }
      }
      if (hwnd_ != nullptr) {
        InvalidateRect(hwnd_, nullptr, TRUE);
      }
      return;
    }
  }

  devices_ = std::move(devices);
  scroll_x_ = 0;
  if (hwnd_ != nullptr) {
    scroll_x_ = (std::min)(scroll_x_,
                           MaxScroll(static_cast<int>(devices_.size()),
                                     kExpandedWidth - 20));
    InvalidateRect(hwnd_, nullptr, TRUE);
  }
}

void QuickDropShelf::Destroy() {
  RevokeDropTarget();
  if (hwnd_ != nullptr) {
    KillTimer(hwnd_, 1);
    KillTimer(hwnd_, 2);
    KillTimer(hwnd_, 3);
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  if (app_icon_ != nullptr) {
    DestroyIcon(app_icon_);
    app_icon_ = nullptr;
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
  app_icon_ = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr),
      MAKEINTRESOURCE(IDI_APP_ICON),
      IMAGE_ICON,
      24, 24,
      LR_DEFAULTCOLOR));
  SetLayeredWindowAttributes(hwnd_, RGB(10, 20, 30), 150, LWA_COLORKEY | LWA_ALPHA);
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
  state_ = STATE_COLLAPSED;
  hover_index_ = -1;

  if (x_ == -1 && y_ == -1) {
    HMONITOR monitor = MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(monitor_info);
    GetMonitorInfoW(monitor, &monitor_info);
    const RECT work = monitor_info.rcWork;
    x_ = work.right - kCollapsedWidth - 100;
    y_ = work.bottom - kCollapsedHeight - 150;
  }

  SetWindowPos(hwnd_, HWND_TOPMOST, x_, y_, kCollapsedWidth, kCollapsedHeight,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  SetLayeredWindowAttributes(hwnd_, RGB(10, 20, 30), 150, LWA_COLORKEY | LWA_ALPHA);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void QuickDropShelf::LayoutExpanded() {
  expanded_ = true;
  state_ = STATE_PROMPT;
  hover_index_ = -1;

  if (x_ == -1 && y_ == -1) {
    LayoutCollapsed();
  }

  const int cx = x_ + kCollapsedWidth / 2;
  const int cy = y_ + kCollapsedHeight / 2;

  int ex = cx - kExpandedWidth / 2;
  int ey = cy - kExpandedHeight / 2;

  HMONITOR monitor = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;

  if (ex < work.left + 10) ex = work.left + 10;
  if (ex + kExpandedWidth > work.right - 10) ex = work.right - kExpandedWidth - 10;
  if (ey < work.top + 10) ey = work.top + 10;
  if (ey + kExpandedHeight > work.bottom - 10) ey = work.bottom - kExpandedHeight - 10;

  SetWindowPos(hwnd_, HWND_TOPMOST, ex, ey, kExpandedWidth, kExpandedHeight,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  SetLayeredWindowAttributes(hwnd_, RGB(10, 20, 30), 240, LWA_COLORKEY | LWA_ALPHA);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void QuickDropShelf::SetExpanded(bool expanded) {
  if (hwnd_ == nullptr) return;
  if (expanded == expanded_) return;
  
  StartAnimation(expanded);
}

void QuickDropShelf::StartAnimation(bool expanding) {
  if (hwnd_ == nullptr) return;

  if (x_ == -1 && y_ == -1) {
    HMONITOR monitor = MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(monitor_info);
    GetMonitorInfoW(monitor, &monitor_info);
    const RECT work = monitor_info.rcWork;
    x_ = work.right - kCollapsedWidth - 100;
    y_ = work.bottom - kCollapsedHeight - 150;
  }

  anim_active_ = true;
  anim_expanding_ = expanding;
  anim_start_time_ = GetTickCount64();

  RECT current_rect = {};
  GetWindowRect(hwnd_, &current_rect);
  anim_start_x_ = current_rect.left;
  anim_start_y_ = current_rect.top;
  anim_start_w_ = current_rect.right - current_rect.left;
  anim_start_h_ = current_rect.bottom - current_rect.top;
  anim_start_alpha_ = expanded_ ? 240 : 150;

  expanded_ = expanding;
  if (expanding) {
    state_ = STATE_PROMPT;

    const int cx = x_ + kCollapsedWidth / 2;
    const int cy = y_ + kCollapsedHeight / 2;

    int ex = cx - kExpandedWidth / 2;
    int ey = cy - kExpandedHeight / 2;

    HMONITOR monitor = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(monitor_info);
    GetMonitorInfoW(monitor, &monitor_info);
    const RECT work = monitor_info.rcWork;

    if (ex < work.left + 10) ex = work.left + 10;
    if (ex + kExpandedWidth > work.right - 10) ex = work.right - kExpandedWidth - 10;
    if (ey < work.top + 10) ey = work.top + 10;
    if (ey + kExpandedHeight > work.bottom - 10) ey = work.bottom - kExpandedHeight - 10;

    anim_target_x_ = ex;
    anim_target_y_ = ey;
    anim_target_w_ = kExpandedWidth;
    anim_target_h_ = kExpandedHeight;
    anim_target_alpha_ = 240;
  } else {
    anim_target_x_ = x_;
    anim_target_y_ = y_;
    anim_target_w_ = kCollapsedWidth;
    anim_target_h_ = kCollapsedHeight;
    anim_target_alpha_ = 150;
  }

  SetTimer(hwnd_, 1, 10, nullptr);
}

void QuickDropShelf::AnimateStep() {
  if (!anim_active_ || hwnd_ == nullptr) {
    KillTimer(hwnd_, 1);
    return;
  }

  ULONGLONG elapsed = GetTickCount64() - anim_start_time_;
  double progress = static_cast<double>(elapsed) / 150.0;

  if (progress >= 1.0) {
    progress = 1.0;
    anim_active_ = false;
    KillTimer(hwnd_, 1);
  }

  double eased = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress);

  int w = static_cast<int>(anim_start_w_ + (anim_target_w_ - anim_start_w_) * eased);
  int h = static_cast<int>(anim_start_h_ + (anim_target_h_ - anim_start_h_) * eased);

  int x = static_cast<int>(anim_start_x_ + (anim_target_x_ - anim_start_x_) * eased);
  int y = static_cast<int>(anim_start_y_ + (anim_target_y_ - anim_start_y_) * eased);

  int alpha = static_cast<int>(anim_start_alpha_ + (anim_target_alpha_ - anim_start_alpha_) * eased);

  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
  SetLayeredWindowAttributes(hwnd_, RGB(10, 20, 30), static_cast<BYTE>(alpha), LWA_COLORKEY | LWA_ALPHA);

  if (!anim_active_ && !anim_expanding_) {
    state_ = STATE_COLLAPSED;
    hover_index_ = -1;
  }

  InvalidateRect(hwnd_, nullptr, TRUE);
}

void QuickDropShelf::WakeUp() {
  if (state_ != STATE_HIDDEN_BAR || hwnd_ == nullptr) return;

  KillTimer(hwnd_, 3);
  state_ = STATE_COLLAPSED;
  last_active_time_ = GetTickCount64();

  SetWindowPos(hwnd_, HWND_TOPMOST, x_, y_, kCollapsedWidth, kCollapsedHeight, SWP_NOACTIVATE);
  SetLayeredWindowAttributes(hwnd_, RGB(10, 20, 30), 150, LWA_COLORKEY | LWA_ALPHA);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void QuickDropShelf::TransitionToHiddenBar() {
  if (state_ != STATE_COLLAPSED || hwnd_ == nullptr) return;

  state_ = STATE_HIDDEN_BAR;
  pulse_angle_ = 0.0;

  HMONITOR monitor = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;

  int bx = x_;
  int by = y_;
  int bw = kCollapsedWidth;
  int bh = kCollapsedHeight;

  if (x_ <= work.left + 5) {
    bw = 8;
    bh = 60;
    by = y_ + (kCollapsedHeight - 60) / 2;
  } else if (x_ >= work.right - kCollapsedWidth - 5) {
    bw = 8;
    bh = 60;
    bx = work.right - 8;
    by = y_ + (kCollapsedHeight - 60) / 2;
  } else if (y_ <= work.top + 5) {
    bw = 60;
    bh = 8;
    bx = x_ + (kCollapsedWidth - 60) / 2;
  } else if (y_ >= work.bottom - kCollapsedHeight - 5) {
    bw = 60;
    bh = 8;
    bx = x_ + (kCollapsedWidth - 60) / 2;
    by = work.bottom - 8;
  } else {
    state_ = STATE_COLLAPSED;
    return;
  }

  SetWindowPos(hwnd_, HWND_TOPMOST, bx, by, bw, bh, SWP_NOACTIVATE);
  SetLayeredWindowAttributes(hwnd_, RGB(10, 20, 30), 220, LWA_COLORKEY | LWA_ALPHA);

  SetTimer(hwnd_, 3, 30, nullptr);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void QuickDropShelf::Paint() {
  PAINTSTRUCT ps = {};
  HDC hdc = BeginPaint(hwnd_, &ps);
  RECT client = {};
  GetClientRect(hwnd_, &client);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;

  if (state_ == STATE_HIDDEN_BAR) {
    HBRUSH bg_brush = CreateSolidBrush(RGB(10, 20, 30));
    FillRect(hdc, &client, bg_brush);
    DeleteObject(bg_brush);

    double factor = (sin(pulse_angle_) + 1.0) / 2.0;
    int r = 13 + static_cast<int>((45 - 13) * factor);
    int g = 70 + static_cast<int>((212 - 70) * factor);
    int b = 70 + static_cast<int>((191 - 70) * factor);

    RECT bar_rect = { 0, 0, width, height };
    FillRoundRect(hdc, bar_rect, 4, RGB(r, g, b));

    EndPaint(hwnd_, &ps);
    return;
  }

  if (state_ == STATE_COLLAPSED && !anim_active_) {
    HBRUSH bg_brush = CreateSolidBrush(RGB(10, 20, 30));
    FillRect(hdc, &client, bg_brush);
    DeleteObject(bg_brush);

    int r = 25;
    RECT circle_rect = { width / 2 - r, height / 2 - r, width / 2 + r, height / 2 + r };

    HBRUSH circle_brush = CreateSolidBrush(RGB(13, 148, 136));
    HPEN circle_pen = CreatePen(PS_SOLID, 1, RGB(13, 148, 136));
    HGDIOBJ old_brush = SelectObject(hdc, circle_brush);
    HGDIOBJ old_pen = SelectObject(hdc, circle_pen);
    Ellipse(hdc, circle_rect.left, circle_rect.top, circle_rect.right, circle_rect.bottom);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(circle_brush);
    DeleteObject(circle_pen);

    if (app_icon_ != nullptr) {
      DrawIconEx(hdc, width / 2 - 12, height / 2 - 12, app_icon_, 24, 24, 0, nullptr, DI_NORMAL);
    } else {
      HFONT icon_font = CreateUiFont(16, FW_BOLD);
      HGDIOBJ old_font = SelectObject(hdc, icon_font);
      SetTextColor(hdc, RGB(255, 255, 255));
      SetBkMode(hdc, TRANSPARENT);
      RECT text_rect = circle_rect;
      text_rect.top += 1;
      text_rect.bottom += 1;
      DrawTextW(hdc, L"✈", -1, &text_rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      SelectObject(hdc, old_font);
      DeleteObject(icon_font);
    }

    EndPaint(hwnd_, &ps);
    return;
  }

  HBRUSH bg_brush = CreateSolidBrush(RGB(10, 20, 30));
  FillRect(hdc, &client, bg_brush);
  DeleteObject(bg_brush);

  RECT card_rect = {10, 10, width - 10, height - 10};
  FillRoundRect(hdc, card_rect, 12, RGB(255, 255, 255));
  StrokeRoundRect(hdc, card_rect, 12, RGB(226, 232, 240), 1);

  SetBkMode(hdc, TRANSPARENT);

  if (state_ == STATE_PROMPT) {
    if (width > 200) {
      HFONT prompt_font = CreateUiFont(15, FW_NORMAL);
      HGDIOBJ old_font = SelectObject(hdc, prompt_font);
      SetTextColor(hdc, RGB(100, 116, 139));
      DrawTextW(hdc, L"可以放入文件来分享", -1, &card_rect,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      SelectObject(hdc, old_font);
      DeleteObject(prompt_font);
    }
  } else if (state_ == STATE_DEVICES) {
    if (devices_.empty()) {
      HFONT empty_font = CreateUiFont(14, FW_NORMAL);
      HGDIOBJ old_font = SelectObject(hdc, empty_font);
      SetTextColor(hdc, RGB(100, 116, 139));
      DrawTextW(hdc, L"无在线的信任设备", -1, &card_rect,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      SelectObject(hdc, old_font);
      DeleteObject(empty_font);
    } else {
      IntersectClipRect(hdc, 20, 10, width - 20, height - 10);

      const int n = static_cast<int>(devices_.size());
      const int item_width = 80;
      const int item_height = 82;
      const int item_gap = 10;

      int start_x = 0;
      if (n <= 5) {
        const int total_items_width = n * item_width + (n - 1) * item_gap;
        start_x = (width - total_items_width) / 2;
      } else {
        start_x = 30 - scroll_x_;
      }

      HFONT name_font = CreateUiFont(12, FW_NORMAL);
      HFONT avatar_font = CreateUiFont(16, FW_BOLD);

      for (int i = 0; i < n; ++i) {
        const auto& device = devices_[i];
        const int item_left = start_x + i * (item_width + item_gap);
        const int item_top = 22;
        RECT item_rect = {item_left, item_top, item_left + item_width, item_top + item_height};

        if (item_rect.right < 20 || item_rect.left > width - 20) continue;

        const bool hover = (i == hover_index_);

        if (hover) {
          RECT hover_rect = {item_left, 14, item_left + item_width, 108};
          FillRoundRect(hdc, hover_rect, 8, RGB(240, 253, 250));
          StrokeRoundRect(hdc, hover_rect, 8, RGB(45, 212, 191), 1);
        }

        RECT avatar = {item_left + 18, item_top, item_left + 62, item_top + 44};
        COLORREF av_color = ColorFromHex(device.avatar_color, RGB(37, 99, 235));
        HBRUSH av_brush = CreateSolidBrush(av_color);
        HPEN av_pen = CreatePen(PS_SOLID, 1, av_color);
        HGDIOBJ old_brush = SelectObject(hdc, av_brush);
        HGDIOBJ old_pen = SelectObject(hdc, av_pen);
        Ellipse(hdc, avatar.left, avatar.top, avatar.right, avatar.bottom);
        SelectObject(hdc, old_brush);
        SelectObject(hdc, old_pen);
        DeleteObject(av_brush);
        DeleteObject(av_pen);

        HGDIOBJ old_font = SelectObject(hdc, avatar_font);
        SetTextColor(hdc, RGB(255, 255, 255));
        RECT avatar_text_rect = avatar;
        const std::wstring initial = Utf8ToWide(device.avatar_initial);
        DrawTextW(hdc, initial.c_str(), -1, &avatar_text_rect,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);

        SelectObject(hdc, name_font);
        SetTextColor(hdc, RGB(51, 65, 85));
        RECT name_rect = {item_left, item_top + 46, item_left + item_width, item_top + 82};
        const std::wstring name = Utf8ToWide(device.display_name);
        DrawTextW(hdc, name.c_str(), -1, &name_rect,
                  DT_CENTER | DT_NOPREFIX | DT_WORDBREAK | DT_END_ELLIPSIS);

        SelectObject(hdc, old_font);
      }

      DeleteObject(name_font);
      DeleteObject(avatar_font);

      SelectClipRgn(hdc, nullptr);
    }
  }

  EndPaint(hwnd_, &ps);
}

int QuickDropShelf::HitTest(POINT screen_point) const {
  if (hwnd_ == nullptr || devices_.empty() || state_ != STATE_DEVICES) return -1;
  POINT client_point = screen_point;
  ScreenToClient(hwnd_, &client_point);

  const int n = static_cast<int>(devices_.size());
  const int item_width = 80;
  const int item_height = 82;
  const int item_gap = 10;

  int start_x = 0;
  if (n <= 5) {
    const int total_items_width = n * item_width + (n - 1) * item_gap;
    start_x = (kExpandedWidth - total_items_width) / 2;
  } else {
    start_x = 30 - scroll_x_;
  }

  for (int i = 0; i < n; ++i) {
    const int item_left = start_x + i * (item_width + item_gap);
    const int item_top = 22;
    RECT item_rect = {item_left, item_top, item_left + item_width, item_top + item_height};

    if (client_point.x >= item_rect.left && client_point.x <= item_rect.right &&
        client_point.y >= item_rect.top && client_point.y <= item_rect.bottom) {
      return i;
    }
  }
  return -1;
}

void QuickDropShelf::ScrollToward(POINT screen_point) {
  if (hwnd_ == nullptr || devices_.empty() || state_ != STATE_DEVICES) return;
  POINT client_point = screen_point;
  ScreenToClient(hwnd_, &client_point);

  const int max_scroll = MaxScroll(static_cast<int>(devices_.size()), kExpandedWidth - 20);
  if (max_scroll <= 0) return;

  int next_scroll = scroll_x_;
  if (client_point.x > 10 && client_point.x < 70) {
    next_scroll -= 8;
  } else if (client_point.x < kExpandedWidth - 10 && client_point.x > kExpandedWidth - 70) {
    next_scroll += 8;
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

void QuickDropShelf::ShowContextMenu(int x, int y) {
  if (anim_active_) return;
  last_active_time_ = GetTickCount64();
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, 1, L"隐藏拖拽悬浮窗");
  SetForegroundWindow(hwnd_);
  int track_flags = TPM_LEFTALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY;
  int cmd = TrackPopupMenu(menu, track_flags, x, y, 0, hwnd_, nullptr);
  DestroyMenu(menu);
  if (cmd == 1) {
    if (hide_callback_) {
      hide_callback_();
    }
  }
}

LRESULT QuickDropShelf::HandleMessage(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  switch (message) {
    case WM_PAINT:
      Paint();
      return 0;
    case WM_CONTEXTMENU: {
      if (anim_active_) return 0;
      int x = static_cast<short>(LOWORD(lparam));
      int y = static_cast<short>(HIWORD(lparam));
      if (x == -1 && y == -1) {
        POINT pt;
        GetCursorPos(&pt);
        x = pt.x;
        y = pt.y;
      }
      ShowContextMenu(x, y);
      return 0;
    }
    case WM_NCRBUTTONUP: {
      if (state_ == STATE_COLLAPSED && !anim_active_) {
        int x = static_cast<short>(LOWORD(lparam));
        int y = static_cast<short>(HIWORD(lparam));
        ShowContextMenu(x, y);
        return 0;
      }
      return DefWindowProcW(hwnd, message, wparam, lparam);
    }
    case WM_NCHITTEST: {
      if (state_ == STATE_COLLAPSED && !anim_active_) {
        last_active_time_ = GetTickCount64();
        return HTCAPTION;
      }
      return HTCLIENT;
    }
    case WM_MOUSEMOVE: {
      last_active_time_ = GetTickCount64();
      if (state_ == STATE_HIDDEN_BAR) {
        WakeUp();
      }
      return 0;
    }
    case WM_EXITSIZEMOVE: {
      if (state_ == STATE_COLLAPSED && !anim_active_) {
        RECT rect = {};
        GetWindowRect(hwnd, &rect);
        x_ = rect.left;
        y_ = rect.top;

        HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
        MONITORINFO monitor_info = {};
        monitor_info.cbSize = sizeof(monitor_info);
        GetMonitorInfoW(monitor, &monitor_info);
        const RECT work = monitor_info.rcWork;

        bool snapped = false;
        if (x_ < work.left + 20) {
          x_ = work.left;
          snapped = true;
        } else if (x_ > work.right - kCollapsedWidth - 20) {
          x_ = work.right - kCollapsedWidth;
          snapped = true;
        }

        if (y_ < work.top + 20) {
          y_ = work.top;
          snapped = true;
        } else if (y_ > work.bottom - kCollapsedHeight - 20) {
          y_ = work.bottom - kCollapsedHeight;
          snapped = true;
        }

        if (snapped) {
          SetWindowPos(hwnd, HWND_TOPMOST, x_, y_, kCollapsedWidth, kCollapsedHeight,
                       SWP_NOACTIVATE);
        }
      }
      return 0;
    }
    case WM_TIMER: {
      if (wparam == 1) {
        AnimateStep();
      } else if (wparam == 2) {
        if (state_ == STATE_COLLAPSED && !anim_active_ && enabled_) {
          HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
          MONITORINFO monitor_info = {};
          monitor_info.cbSize = sizeof(monitor_info);
          GetMonitorInfoW(monitor, &monitor_info);
          const RECT work = monitor_info.rcWork;

          bool is_docked = (x_ <= work.left + 5 || x_ >= work.right - kCollapsedWidth - 5 ||
                             y_ <= work.top + 5 || y_ >= work.bottom - kCollapsedHeight - 5);
          
          if (auto_hide_ && is_docked && (GetTickCount64() - last_active_time_ > 30000)) {
            TransitionToHiddenBar();
          }
        }
      } else if (wparam == 3) {
        if (state_ == STATE_HIDDEN_BAR) {
          pulse_angle_ += 0.08;
          InvalidateRect(hwnd, nullptr, FALSE);
        }
      } else if (wparam == 4) {
        KillTimer(hwnd, 4);
        if (drag_leave_pending_) {
          drag_leave_pending_ = false;
          SetExpanded(false);
        }
      }
      return 0;
    }
    case WM_MOUSEWHEEL: {
      const int max_scroll = MaxScroll(static_cast<int>(devices_.size()), kExpandedWidth - 20);
      const int delta = GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? -48 : 48;
      scroll_x_ = (std::max)(0, (std::min)(scroll_x_ + delta, max_scroll));
      InvalidateRect(hwnd_, nullptr, TRUE);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}
