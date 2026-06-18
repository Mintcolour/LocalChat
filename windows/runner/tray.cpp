#include "tray.h"

#include <shellapi.h>

#include "resource.h"

namespace {

// 托盘回调消息 ID。使用 WM_APP 基址避免与系统消息冲突。
UINT_PTR kCallbackMessage = WM_APP + 1;

constexpr const wchar_t kTrayTooltip[] = L"LocalChat";

}  // namespace

TrayController::TrayController() = default;

TrayController::~TrayController() { RemoveTrayIcon(); }

UINT_PTR TrayController::callback_message_id() {
  return kCallbackMessage;
}

bool TrayController::AddTrayIcon(HWND owner) {
  if (has_icon_) {
    return true;
  }
  if (owner == nullptr) {
    return false;
  }
  owner_ = owner;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = owner;
  nid.uID = IDI_APP_ICON;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = static_cast<UINT>(kCallbackMessage);
  nid.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(nid.szTip, kTrayTooltip, _TRUNCATE);
  if (!Shell_NotifyIconW(NIM_ADD, &nid)) {
    return false;
  }
  has_icon_ = true;
  return true;
}

void TrayController::RemoveTrayIcon() {
  if (!has_icon_ || owner_ == nullptr) {
    return;
  }
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = owner_;
  nid.uID = IDI_APP_ICON;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  has_icon_ = false;
}

bool TrayController::HandleCallback(WPARAM wparam, LPARAM lparam) {
  if (wparam != IDI_APP_ICON) {
    return false;
  }
  switch (LOWORD(lparam)) {
    case WM_LBUTTONDBLCLK:
      if (show_callback_) {
        show_callback_();
      }
      return true;
    case WM_RBUTTONUP:
      ShowContextMenu();
      return true;
    default:
      return false;
  }
}

void TrayController::ShowContextMenu() {
  if (owner_ == nullptr) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  AppendMenuW(menu, MF_STRING, 1, L"Show");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 2, L"Quit");

  POINT cursor;
  GetCursorPos(&cursor);
  // 右键菜单需要前台窗口才能正确显示。
  SetForegroundWindow(owner_);
  int selected = TrackPopupMenu(
      menu, TPM_NONOTIFY | TPM_RETURNCMD | TPM_LEFTALIGN | TPM_BOTTOMALIGN,
      cursor.x, cursor.y, 0, owner_, nullptr);
  DestroyMenu(menu);

  switch (selected) {
    case 1:
      if (show_callback_) {
        show_callback_();
      }
      break;
    case 2:
      if (quit_callback_) {
        quit_callback_();
      }
      break;
    default:
      break;
  }
}
