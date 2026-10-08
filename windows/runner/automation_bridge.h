#ifndef RUNNER_AUTOMATION_BRIDGE_H_
#define RUNNER_AUTOMATION_BRIDGE_H_

#include <windows.h>
#include <string>

namespace automation {
bool PublishDescriptor(const std::string& contents, std::wstring* path,
                       DWORD* error);
// Shared file publisher for isolated native tests. The method channel always
// uses PublishDescriptor and never accepts a path supplied by a caller.
bool PublishDescriptorInDirectory(std::wstring directory,
                                  const std::string& contents,
                                  std::wstring* path, DWORD* error);
void RemoveDescriptor();
}  // namespace automation

#endif  // RUNNER_AUTOMATION_BRIDGE_H_
