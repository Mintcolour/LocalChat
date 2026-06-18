#include "autostart.h"

#include <windows.h>

#include <vector>

namespace {

constexpr const wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kValueName[] = L"LocalChat";

// 取当前 exe 完整路径，用引号包裹以便处理含空格的路径。
std::wstring CurrentExeCommand() {
  wchar_t path[MAX_PATH] = {0};
  DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return L"";
  }
  return std::wstring(L"\"") + path + L"\"";
}

// 读取注册表中已存储的命令字符串。
std::wstring ReadStoredCommand() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return L"";
  }
  std::wstring result;
  wchar_t buffer[MAX_PATH * 2] = {0};
  DWORD size = sizeof(buffer);
  DWORD type = 0;
  LSTATUS status = RegQueryValueExW(key, kValueName, nullptr, &type,
                                    reinterpret_cast<LPBYTE>(buffer), &size);
  RegCloseKey(key);
  if (status == ERROR_SUCCESS && type == REG_SZ && size > 0) {
    // size 含末尾 null，转换为字符数。
    result.assign(buffer, size / sizeof(wchar_t));
    if (!result.empty() && result.back() == L'\0') {
      result.pop_back();
    }
  }
  return result;
}

}  // namespace

namespace autostart {

bool IsEnabled() { return ReadStoredCommand() == CurrentExeCommand(); }

bool SetEnabled(bool enabled) {
  if (enabled) {
    const std::wstring command = CurrentExeCommand();
    if (command.empty()) {
      return false;
    }
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
        ERROR_SUCCESS) {
      return false;
    }
    LSTATUS status = RegSetValueExW(
        key, kValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
    return status == ERROR_SUCCESS;
  }
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  LSTATUS status = RegDeleteValueW(key, kValueName);
  RegCloseKey(key);
  // 值不存在视为已删除成功。
  return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
}

}  // namespace autostart
