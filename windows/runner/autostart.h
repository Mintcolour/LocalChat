#ifndef RUNNER_AUTOSTART_H_
#define RUNNER_AUTOSTART_H_

#include <string>

// 读写 HKCU\Software\Microsoft\Windows\CurrentVersion\Run 下的 LocalChat 项，
// 实现开机自启开关。值为本程序 exe 的完整路径。
namespace autostart {

// 当前是否已写入注册表（路径与当前 exe 一致才算启用）。
bool IsEnabled();

// 写入或删除注册表项。成功返回 true。
bool SetEnabled(bool enabled);

}  // namespace autostart

#endif  // RUNNER_AUTOSTART_H_
