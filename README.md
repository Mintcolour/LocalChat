# LocalChat 📦

LocalChat is a Flutter LAN direct-transfer tool for sending text, links, images, and files between Windows and Android devices through a chat-style interface.

LocalChat 是一个 Flutter 局域网直连传输工具，用聊天窗口的方式在 Windows 和 Android 设备之间发送文字、链接、图片和文件。

- [中文说明](#中文说明)
- [English](#english)

## 中文说明

### 项目定位 🧭

LocalChat 不是云盘，也不是公网 IM。它解决的是更常见的本地场景：电脑和手机在同一个 Wi-Fi 下，需要快速、私密、可追踪地互传内容，不想登录账号、不想经过第三方服务器，也不想反复打开临时文件传输工具。

### 项目亮点 ✨

- 局域网直连：设备通过 UDP 广播发现彼此，传输走本地 HTTP 服务，不依赖云端中转。
- 聊天式体验：文字和文件都落在同一个会话时间线里，发送记录、接收状态、文件进度更容易回看。
- 首次可信配对：发现设备后通过 6 位校验码建立信任关系，后续可信设备会自动进入可发送状态。
- 端到端安全层：请求使用 Ed25519 签名，双方通过 X25519 派生共享密钥，文字和文件分块使用 AES-GCM 加密，并校验 nonce 与时间窗。
- 文件传输更贴近日常操作：支持应用内多文件选择、Windows 拖拽到聊天区、从剪贴板粘贴文件或图片、Android 系统分享入口。
- 发送前图片轻编辑：直接发送的图片会先统一预览，可在本地裁切、旋转并添加文字，不上传云端且不覆盖源文件。
- 本地历史和索引：使用 Drift/SQLite 保存设备、会话、消息、传输和设置，接收文件会按会话与年月归档。
- 自动文件管理：零散文件按类型归档，文件夹保持原层级；收到的文件可在消息卡片中重命名。
- 断线重连：可信设备离线后发送时会尝试重新发现并恢复连接，降低移动设备切换网络时的失败率。
- 跨端 Flutter 实现：同一套主要业务逻辑覆盖 Windows 和 Android，便于继续扩展到更多桌面或移动端。

### 独到之处 🔐

LocalChat 把“文件传输”和“聊天上下文”放在一起。相比只弹出发送窗口的工具，它保留了谁发的、什么时候发的、是否成功、文件保存在哪里等上下文；相比公网聊天软件，它又不需要账号、服务器或外部网络。

安全设计也不是只做简单内网明文传输。项目在应用层维护设备身份、信任关系、签名验证、密钥协商、加密分块和完整性校验，即使底层传输是局域网 HTTP，请求内容和文件块也会经过加密与认证。

### 功能状态 ⚙️

已实现：

- Windows/Android Flutter 项目骨架。
- 响应式聊天主界面：已信任设备、发现设备、会话时间线、文字和文件消息卡片。
- UDP 局域网设备发现，广播设备 ID、名称、平台、监听端口和公钥指纹。
- 6 位码首次配对和可信设备管理。
- HTTP 传输协议：`/v1/hello`、配对、消息、传输开始、加密流、分块、完成接口。
- Ed25519 请求签名、X25519 共享密钥、AES-GCM 加密文本和文件分块。
- Drift/SQLite 本地历史：`devices`、`conversations`、`messages`、`transfers`、`settings`。
- Windows 拖拽文件发送、剪贴板文件/图片发送、Android 系统分享入口。
- Windows/Android 发送前附件预览，以及图片裁切、旋转和文字标注。
- 接收文字自动复制到剪贴板，可在设置中关闭。
- 接收文件保存到 Downloads/LocalChat，并按会话、年月和文件类型归档；支持接收后重命名。
- Windows 托盘、开机自启和单实例唤醒。

当前限制：

- MVP 主要面向同一局域网内、应用前台运行时的发现和收发。
- 跨网段自动发现和公网中转服务暂未实现；跨网段设备需要手动填写 IP 与端口。
- Android 和 Windows release 包已验证可构建。

### 技术栈 🧩

- Flutter / Dart
- Drift / SQLite
- shelf / shelf_router
- dio
- cryptography
- file_picker
- desktop_drop
- receive_sharing_intent

### 安装环境 🛠️

需要先安装 Flutter，并配置 Android 或 Windows 桌面构建环境。

本项目当前开发机使用的 Flutter SDK 路径为：

```powershell
C:\Users\DeepBluePC\.codex\tools\flutter_3.44.2\flutter
```

Android SDK 路径为：

```powershell
C:\Users\DeepBluePC\.codex\tools\android-sdk
```

如果你也在 Windows 上开发，并且希望复用仓库内脚本，可以先加载环境：

```powershell
. .\scripts\flutter_env.ps1
```

### 使用方法 🚀

安装依赖：

```powershell
flutter pub get
```

运行代码检查和测试：

```powershell
flutter analyze
flutter test
```

构建 Android debug APK：

```powershell
flutter build apk --debug
```

APK 输出路径：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

构建 Windows release：

```powershell
flutter build windows --release
```

Windows release 输出目录：

```text
build\windows\x64\runner\Release
```

Windows 运行入口：

```powershell
.\scripts\run_windows.ps1
```

基本使用流程：

1. 在两台处于同一 Wi-Fi 的设备上打开 LocalChat。
2. 在设备列表中找到对方设备。
3. 点击配对，并在接收端确认 6 位校验码。
4. 配对成功后，像聊天一样发送文字、链接或文件。
5. Windows 可直接拖拽文件到聊天区，也可以粘贴剪贴板中的文件或图片；Android 可通过系统分享菜单发送到 LocalChat。

### 适合场景 📚

- 手机和电脑之间临时传截图、安装包、文档、链接。
- 不希望文件经过公网服务器的办公室或家庭局域网传输。
- 需要保留传输上下文和历史记录，而不只是一次性投递文件。
- 想研究 Flutter 跨端、局域网发现、安全传输和本地持久化组合实现的示例项目。

### 后续计划 🗺️

- 后台常驻与托盘模式。
- 文件夹递归发送。
- 更完整的传输失败重试和断点续传。
- 更多平台支持和更细的设备权限管理。

## English

### Overview 🧭

LocalChat is not a cloud drive or a public instant messenger. It focuses on a local workflow: when your phone and computer are on the same Wi-Fi network, you can quickly send small pieces of text, links, screenshots, documents, or APKs without signing in to a service or routing data through a third-party server.

### Highlights ✨

- LAN direct transfer: devices discover each other with UDP broadcast and transfer data through a local HTTP service.
- Chat-style workflow: text and files share one conversation timeline, so status, progress, sender, time, and saved location remain visible.
- Trusted first pairing: discovered devices establish trust with a 6-digit verification code, then trusted peers can send directly.
- Application-level security: requests are signed with Ed25519, peers derive shared keys with X25519, and text plus file chunks are encrypted with AES-GCM.
- Everyday file entry points: in-app multi-file picker, Windows drag-and-drop, clipboard file/image paste, and Android system share integration.
- Local image editing before send: direct image attachments can be reviewed, cropped, rotated, and annotated without uploading or overwriting the source.
- Local history and index: Drift/SQLite stores devices, conversations, messages, transfers, and settings.
- Automatic file management: standalone files are grouped by type, folder transfers retain their hierarchy, and received files can be renamed from the message card.
- Reconnect behavior: trusted offline peers are rediscovered before sending, reducing failures when mobile devices switch network state.
- Cross-platform Flutter core: the main logic is shared between Windows and Android and can be extended to more platforms.

### What Makes It Different 🔐

LocalChat combines file transfer with chat context. Instead of a one-off send dialog, it keeps a useful history: who sent the item, when it was sent, whether it succeeded, and where the file was saved. Compared with public chat apps, it does not require an account, a public server, or external network access.

The security model is also stronger than plain LAN HTTP transfer. LocalChat maintains device identity, trust relationships, signed requests, key exchange, encrypted file chunks, nonce checks, and timestamp validation at the application layer.

### Current Status ⚙️

Implemented:

- Windows and Android Flutter project structure.
- Responsive chat UI with trusted devices, discovered devices, conversation timeline, text cards, and file cards.
- UDP LAN discovery with device ID, display name, platform, listen port, and public key fingerprint.
- 6-digit first pairing and trusted device management.
- HTTP transfer protocol: `/v1/hello`, pairing, messages, transfer start, encrypted stream, chunks, and completion endpoints.
- Ed25519 request signatures, X25519 shared keys, and AES-GCM encryption for text and file chunks.
- Drift/SQLite local history tables: `devices`, `conversations`, `messages`, `transfers`, and `settings`.
- Windows drag-and-drop, clipboard file/image sending, and Android system share support.
- Attachment review plus local crop, rotate, and text annotation on Windows and Android.
- Optional automatic clipboard copy for received text.
- Received files are saved under Downloads/LocalChat and grouped by conversation, year/month, and file type, with post-receive rename support.
- Windows tray mode, startup launch, and single-instance activation.

Known limits:

- The MVP is designed mainly for same-LAN usage while the app is running in the foreground.
- Automatic cross-subnet discovery and public relay services are not implemented; remote peers require a manually entered IP and port.
- Android and Windows release builds have been verified.

### Tech Stack 🧩

- Flutter / Dart
- Drift / SQLite
- shelf / shelf_router
- dio
- cryptography
- file_picker
- desktop_drop
- receive_sharing_intent

### Setup 🛠️

Install Flutter and configure either the Android toolchain or the Windows desktop build toolchain.

The current development machine uses this Flutter SDK path:

```powershell
C:\Users\DeepBluePC\.codex\tools\flutter_3.44.2\flutter
```

Android SDK path:

```powershell
C:\Users\DeepBluePC\.codex\tools\android-sdk
```

On Windows, you can load the provided environment helper:

```powershell
. .\scripts\flutter_env.ps1
```

### Usage 🚀

Install dependencies:

```powershell
flutter pub get
```

Run checks and tests:

```powershell
flutter analyze
flutter test
```

Build an Android debug APK:

```powershell
flutter build apk --debug
```

APK output:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

Build a Windows release:

```powershell
flutter build windows --release
```

Windows release output:

```text
build\windows\x64\runner\Release
```

Run on Windows:

```powershell
.\scripts\run_windows.ps1
```

Basic workflow:

1. Open LocalChat on two devices connected to the same Wi-Fi network.
2. Find the peer device in the device list.
3. Start pairing and confirm the 6-digit verification code on the receiving side.
4. After pairing, send text, links, or files like a chat message.
5. On Windows, drag files into the chat area or paste files/images from the clipboard. On Android, send items through the system share sheet.

### Use Cases 📚

- Quickly transfer screenshots, APKs, documents, and links between a phone and a computer.
- Move files inside a home or office LAN without sending them through a public server.
- Keep transfer context and history instead of using one-off file drops.
- Study a practical Flutter example that combines cross-platform UI, LAN discovery, secure transfer, and local persistence.

### Roadmap 🗺️

- Background resident mode and tray integration.
- Recursive folder sending.
- More complete retry and resumable transfer behavior.
- More platforms and finer-grained device permissions.
