#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE instance_mutex =
      CreateMutexW(nullptr, TRUE, single_instance::kMutexName);
  if (instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(instance_mutex);
    const UINT activation_message = single_instance::ActivationMessage();
    for (int attempt = 0; attempt < 40; ++attempt) {
      HWND existing = FindWindowW(nullptr, L"localchat");
      if (existing == nullptr) {
        existing = FindWindowW(nullptr, L"LocalChat");
      }
      if (existing != nullptr) {
        PostMessageW(existing, activation_message, 0, 0);
        return EXIT_SUCCESS;
      }
      Sleep(50);
    }
    PostMessageW(HWND_BROADCAST, activation_message, 0, 0);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"localchat", origin, size)) {
    return EXIT_FAILURE;
  }
  // 关窗不再直接退出进程：由托盘菜单/quit 通道触发真正退出。
  // FlutterWindow 默认开启关窗隐藏到托盘。
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(instance_mutex);
  CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
