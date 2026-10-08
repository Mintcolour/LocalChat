#include "../automation_bridge.h"

#include <aclapi.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

namespace {
bool PrivateAcl(std::wstring path) {
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  PACL acl = nullptr;
  if (GetNamedSecurityInfoW(path.data(), SE_FILE_OBJECT,
                           DACL_SECURITY_INFORMATION, nullptr, nullptr, &acl,
                           nullptr, &descriptor) != ERROR_SUCCESS) return false;
  SECURITY_DESCRIPTOR_CONTROL control = 0;
  DWORD revision = 0;
  bool valid = GetSecurityDescriptorControl(descriptor, &control, &revision) &&
               (control & SE_DACL_PROTECTED) && acl && acl->AceCount == 3;
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    LocalFree(descriptor);
    return false;
  }
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> buffer(size);
  const BOOL got_user = GetTokenInformation(token, TokenUser, buffer.data(), size, &size);
  CloseHandle(token);
  bool owner = false, admin = false, system = false;
  if (valid && got_user) {
    PSID user = reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid;
    for (DWORD index = 0; index < acl->AceCount; ++index) {
      void* raw_ace = nullptr;
      if (!GetAce(acl, index, &raw_ace)) { valid = false; break; }
      auto* ace = static_cast<ACCESS_ALLOWED_ACE*>(raw_ace);
      if (ace->Header.AceType != ACCESS_ALLOWED_ACE_TYPE ||
          (ace->Mask & FILE_ALL_ACCESS) != FILE_ALL_ACCESS) {
        valid = false; break;
      }
      PSID sid = &ace->SidStart;
      if (EqualSid(sid, user)) owner = true;
      else if (IsWellKnownSid(sid, WinBuiltinAdministratorsSid)) admin = true;
      else if (IsWellKnownSid(sid, WinLocalSystemSid)) system = true;
      else valid = false;
    }
  }
  LocalFree(descriptor);
  return valid && owner && admin && system;
}

std::string Read(const std::wstring& path) {
  std::ifstream file(std::filesystem::path(path), std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(file), {});
}
}  // namespace

int wmain() {
  wchar_t temporary[MAX_PATH] = {};
  const DWORD length = GetTempPathW(MAX_PATH, temporary);
  if (length == 0 || length >= MAX_PATH) return 1;
  GUID guid;
  if (FAILED(CoCreateGuid(&guid))) return 1;
  wchar_t suffix[40] = {};
  StringFromGUID2(guid, suffix, 40);
  const std::wstring directory = std::wstring(temporary) + L"localchat-acl-" + suffix;
  std::wstring path;
  DWORD error = 0;
  bool passed = automation::PublishDescriptorInDirectory(
      directory, "first-test-descriptor", &path, &error);
  passed = passed && PrivateAcl(directory) && PrivateAcl(path) &&
           Read(path) == "first-test-descriptor";
  if (passed) {
    passed = automation::PublishDescriptorInDirectory(
        directory, "replacement-test-descriptor", &path, &error);
    passed = passed && PrivateAcl(path) && Read(path) == "replacement-test-descriptor";
  }
  automation::RemoveDescriptor();
  passed = passed && GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES;
  RemoveDirectoryW(directory.c_str());
  std::cout << (passed ? "Descriptor ACL, replacement and cleanup passed.\n"
                      : "Descriptor test failed.\n");
  return passed ? 0 : 1;
}
