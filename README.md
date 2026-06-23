# LocalChat

LocalChat is a Flutter LAN direct-transfer tool for sending text, links, images, and files between Windows and Android devices through a chat-style interface.

LocalChat 是一个 Flutter 局域网直连传输工具，用聊天窗口的方式在 Windows 和 Android 设备之间发送文字、链接、图片和文件。

- [中文说明](#中文说明)
- [English](#english)

## 中文说明

### 下载

- GitHub Releases：<https://github.com/Mintcolour/LocalChat/releases>

### 项目定位

LocalChat 不是云盘，也不是公网 IM。它面向更常见的本地场景：电脑和手机处在同一网络环境时，可以快速、私密、可追踪地互传内容，不需要登录账号，也不依赖第三方中转服务器。

### 项目亮点

- 局域网直连：设备通过 UDP 广播发现彼此，传输走本地 HTTP 服务。
- 聊天式体验：文字、链接、图片和文件都落在同一条会话时间线里，方便回看发送记录、传输状态和保存位置。
- 首次可信配对：通过 6 位校验码建立信任关系，后续可信设备可直接通信。
- 应用层安全：请求签名使用 Ed25519，密钥协商使用 X25519，文字与文件分块使用 AES-GCM 加密。
- 跨端统一实现：Windows 和 Android 共享主要业务逻辑，便于继续扩展平台能力。

### 功能状态

已实现：

- 文件夹递归传输并保留目录结构，单文件和文件夹传输可共享会话历史。
- 手动填写 IP 和端口添加设备，支持跨网段直连场景。
- Windows 托盘、开机自启、单实例唤醒。
- 独立传输中心，集中查看进行中、已完成、失败或已取消的文件传输。
- 出站传输排队、整组进度展示和取消兼容能力。
- 发送前附件预览、排序、移除，支持多文件整理后统一发送。
- 图片发送前裁切、旋转、文字标注，编辑过程仅在本地完成。
- 接收文件支持重命名，并按会话、年月和文件类型分类归档。
- 传输历史支持打开文件、打开文件夹，以及对已保存接收文件重命名。
- 浅色、深色、跟随系统主题三种外观模式。
- 失败消息重试、聊天记录分页加载、日期分隔、未读数和消息搜索定位。
- 设备在线/离线状态使用独立图标显示，不会被最近消息预览覆盖。
- 设置页显示本机局域网 IP 和监听端口，便于手动连接。
- 移动端会话切换动画，以及返回键退出会话问题修复。
- Windows 拖拽发送、剪贴板文件或图片发送、Android 系统分享入口。
- Drift/SQLite 本地历史保存设备、会话、消息、传输和设置数据。

当前限制：

- 自动发现主要面向同一局域网；跨网段设备需要手动填写 IP 和端口。
- MVP 仍以本地前台收发为主，后台常驻和更完整的断点续传仍在规划中。

### 安装与开发

1. 按 Flutter 官方文档安装 Flutter SDK：<https://docs.flutter.dev/get-started/install>
2. 如需构建 Android，请按官方文档安装 Android toolchain：<https://docs.flutter.dev/get-started/install/windows/mobile>
3. 如需构建 Windows，请按官方文档启用 Windows desktop：<https://docs.flutter.dev/platform-integration/windows/setup>
4. 安装完成后执行 `flutter doctor`，确认依赖齐全。

仓库提供了 `scripts/flutter_env.ps1` 作为 PowerShell 环境辅助脚本。使用前请按本机实际工具链自行调整，不要把本地路径或私有环境信息写回文档或提交到仓库。

### 常用命令

安装依赖：

```powershell
flutter pub get
```

运行检查和测试：

```powershell
flutter analyze
flutter test
```

构建 Android Release APK：

```powershell
flutter build apk --release --split-per-abi
```

APK 输出目录：

```text
build\app\outputs\flutter-apk
```

构建 Windows Release：

```powershell
flutter build windows --release
```

Windows 输出目录：

```text
build\windows\x64\runner\Release
```

### 基本使用流程

1. 在两台设备上打开 LocalChat。
2. 在设备列表中找到对方设备，或手动输入对方的 IP 和端口。
3. 首次连接时确认 6 位校验码，建立信任关系。
4. 在会话中发送文字、链接、图片、文件或文件夹。
5. Windows 可拖拽文件到聊天区，也可以粘贴剪贴板中的文件或图片；Android 可通过系统分享菜单发送到 LocalChat。

### 适用场景

- 手机和电脑之间临时传截图、安装包、文档、链接。
- 不希望文件经过公网服务器的办公室或家庭局域网传输。
- 需要保留传输上下文和历史记录，而不只是一次性投递文件。
- 想研究 Flutter 跨端、局域网发现、安全传输和本地持久化组合实现的示例项目。

### Roadmap

- 更完整的断点续传和传输恢复能力。
- 更稳定的后台常驻、移动端保活和网络切换体验。
- 更多平台支持，以及更细的权限与设备管理能力。

## English

### Downloads

- GitHub Releases: <https://github.com/Mintcolour/LocalChat/releases>

### Overview

LocalChat is not a cloud drive or a public instant messenger. It is built for the more common local workflow: when your phone and computer are on the same network, you can quickly and privately exchange content without signing in, and without routing data through a third-party relay service.

### Highlights

- LAN direct transfer: devices discover each other with UDP broadcast and transfer data through a local HTTP service.
- Chat-style workflow: text, links, images, and files stay in one conversation timeline so status, sender, time, and saved location remain visible.
- Trusted first pairing: devices establish trust with a 6-digit verification code, then trusted peers can communicate directly.
- Application-level security: requests are signed with Ed25519, peers derive shared keys with X25519, and text plus file chunks are encrypted with AES-GCM.
- Shared cross-platform core: Windows and Android use the same main application logic, making future platform expansion easier.

### Current Status

Implemented:

- Recursive folder transfer with preserved directory structure, integrated into the same conversation history as regular files.
- Manual device add via IP and port for cross-subnet connections.
- Windows tray integration, startup launch, and single-instance activation.
- A dedicated transfer center for active, completed, failed, and canceled file transfers.
- Outbound transfer queueing, grouped progress, and cancel compatibility.
- Attachment preview, sorting, and removal before send.
- Local image crop, rotate, and text annotation before sending.
- Received-file rename support plus archiving by conversation, year/month, and file type.
- Transfer-history actions for opening files, opening folders, and renaming saved received files.
- Light, dark, and follow-system theme modes.
- Failed message retry, paginated chat history, date separators, unread counts, and message search positioning.
- Persistent online/offline device-status icons that stay visible alongside message previews.
- Local LAN IP and listening port display in settings for easier manual connection.
- Mobile conversation transition animations and a fix for the back-navigation exit issue.
- Windows drag-and-drop, clipboard file/image sending, and Android system share entry points.
- Drift/SQLite persistence for devices, conversations, messages, transfers, and settings.

Known limits:

- Automatic discovery is mainly designed for the same LAN; cross-subnet peers still require a manually entered IP and port.
- The current MVP is still centered on foreground transfers. Better background persistence and resumable transfer support are still on the roadmap.

### Setup

1. Install Flutter by following the official guide: <https://docs.flutter.dev/get-started/install>
2. For Android builds, set up the Android toolchain with the official Windows guide: <https://docs.flutter.dev/get-started/install/windows/mobile>
3. For Windows builds, enable Windows desktop support with the official guide: <https://docs.flutter.dev/platform-integration/windows/setup>
4. Run `flutter doctor` after setup and fix any reported dependency issues.

The repository includes `scripts/flutter_env.ps1` as a PowerShell environment helper. Adjust it for your own local toolchain before using it, and do not commit local paths or private environment details back into the repository documentation.

### Common Commands

Install dependencies:

```powershell
flutter pub get
```

Run analysis and tests:

```powershell
flutter analyze
flutter test
```

Build Android release APKs:

```powershell
flutter build apk --release --split-per-abi
```

APK output directory:

```text
build\app\outputs\flutter-apk
```

Build a Windows release:

```powershell
flutter build windows --release
```

Windows output directory:

```text
build\windows\x64\runner\Release
```

### Basic Workflow

1. Open LocalChat on two devices.
2. Find the peer device in the device list, or add it manually by IP and port.
3. Confirm the 6-digit verification code on first connection.
4. Send text, links, images, files, or folders from the conversation.
5. On Windows, drag files into the chat area or paste files and images from the clipboard. On Android, use the system share sheet to send content into LocalChat.

### Use Cases

- Quickly move screenshots, APKs, documents, and links between a phone and a computer.
- Transfer files inside a home or office LAN without using a public server.
- Keep transfer context and history instead of relying on one-off send tools.
- Study a practical Flutter example that combines cross-platform UI, LAN discovery, secure transfer, and local persistence.

### Roadmap

- More complete resumable transfer and recovery behavior.
- Stronger background persistence, mobile keep-alive behavior, and network-switch handling.
- More platforms and finer-grained permission and device management.
