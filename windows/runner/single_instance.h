#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

namespace single_instance {

inline constexpr wchar_t kMutexName[] =
    L"Local\\LocalChat.Desktop.SingleInstance";
inline constexpr wchar_t kActivationMessageName[] =
    L"LocalChat.Desktop.ActivateExistingWindow";

inline UINT ActivationMessage() {
  static const UINT message = RegisterWindowMessageW(kActivationMessageName);
  return message;
}

}  // namespace single_instance

#endif  // RUNNER_SINGLE_INSTANCE_H_
