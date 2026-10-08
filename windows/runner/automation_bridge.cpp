#include "automation_bridge.h"

#include <aclapi.h>
#include <sddl.h>
#include <shlobj.h>
#include <vector>

namespace automation {
namespace {
std::wstring published_path;

bool OwnerSecurityDescriptor(PSECURITY_DESCRIPTOR* descriptor) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> buffer(size);
  const BOOL got_user =
      GetTokenInformation(token, TokenUser, buffer.data(), size, &size);
  const DWORD token_error = GetLastError();
  CloseHandle(token);
  if (!got_user) {
    SetLastError(token_error);
    return false;
  }
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(
          reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &sid)) {
    return false;
  }
  const std::wstring sddl =
      L"D:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FA;;;" + std::wstring(sid) + L")";
  LocalFree(sid);
  return ConvertStringSecurityDescriptorToSecurityDescriptorW(
             sddl.c_str(), SDDL_REVISION_1, descriptor, nullptr) != FALSE;
}
}  // namespace

bool PublishDescriptor(const std::string& contents, std::wstring* path,
                       DWORD* error) {
  PWSTR app_data = nullptr;
  const HRESULT location = SHGetKnownFolderPath(
      FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &app_data);
  if (FAILED(location)) {
    *error = ERROR_PATH_NOT_FOUND;
    return false;
  }
  std::wstring directory = std::wstring(app_data) + L"\\LocalChat";
  CoTaskMemFree(app_data);
  return PublishDescriptorInDirectory(directory, contents, path, error);
}

bool PublishDescriptorInDirectory(std::wstring directory,
                                  const std::string& contents,
                                  std::wstring* path, DWORD* error) {
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!OwnerSecurityDescriptor(&descriptor)) {
    *error = GetLastError();
    return false;
  }
  SECURITY_ATTRIBUTES attributes = {sizeof(SECURITY_ATTRIBUTES), descriptor,
                                    FALSE};
  bool success = false;
  std::wstring temporary;
  do {
    if (!CreateDirectoryW(directory.c_str(), &attributes) &&
        GetLastError() != ERROR_ALREADY_EXISTS) {
      *error = GetLastError();
      break;
    }
    const DWORD flags = GetFileAttributesW(directory.c_str());
    if (flags == INVALID_FILE_ATTRIBUTES ||
        !(flags & FILE_ATTRIBUTE_DIRECTORY) ||
        (flags & FILE_ATTRIBUTE_REPARSE_POINT)) {
      *error = ERROR_ACCESS_DENIED;
      break;
    }
    PACL dacl = nullptr;
    BOOL present = FALSE;
    BOOL defaulted = FALSE;
    if (!GetSecurityDescriptorDacl(descriptor, &present, &dacl, &defaulted) ||
        !present) {
      *error = ERROR_INVALID_SECURITY_DESCR;
      break;
    }
    const DWORD secured = SetNamedSecurityInfoW(
        directory.data(), SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
        nullptr, nullptr, dacl, nullptr);
    if (secured != ERROR_SUCCESS) {
      *error = secured;
      break;
    }
    const std::wstring destination = directory + L"\\automation.json";
    temporary = destination + L"." + std::to_wstring(GetCurrentProcessId()) +
                L"." + std::to_wstring(GetTickCount64()) + L".tmp";
    HANDLE file = CreateFileW(
        temporary.c_str(), GENERIC_WRITE, 0, &attributes, CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
      *error = GetLastError();
      temporary.clear();
      break;
    }
    DWORD written = 0;
    const BOOL wrote = WriteFile(file, contents.data(),
                                static_cast<DWORD>(contents.size()), &written,
                                nullptr);
    *error = wrote ? ERROR_WRITE_FAULT : GetLastError();
    BOOL flushed = FALSE;
    if (wrote && written == contents.size()) {
      flushed = FlushFileBuffers(file);
      if (!flushed) *error = GetLastError();
    }
    CloseHandle(file);
    if (!flushed) break;
    if (!MoveFileExW(temporary.c_str(), destination.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
      *error = GetLastError();
      break;
    }
    temporary.clear();
    published_path = destination;
    *path = destination;
    *error = ERROR_SUCCESS;
    success = true;
  } while (false);
  if (!temporary.empty()) DeleteFileW(temporary.c_str());
  LocalFree(descriptor);
  return success;
}

void RemoveDescriptor() {
  if (!published_path.empty()) {
    DeleteFileW(published_path.c_str());
    published_path.clear();
  }
}
}  // namespace automation
