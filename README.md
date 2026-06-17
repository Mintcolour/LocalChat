# LocalChat

LocalChat 是一个 Flutter 局域网直连传输工具，用聊天窗口的方式在 Windows 和 Android 设备之间发送文字、链接、图片和文件。

它的目标不是做云盘或公网 IM，而是解决一个更常见的本地场景：电脑和手机在同一个 Wi-Fi 下，需要快速、私密、可追踪地互相传一点东西，不想登录账号、不想经过第三方服务器，也不想反复打开文件传输工具。

## 项目亮点

- 局域网直连：设备通过 UDP 广播发现彼此，传输走本地 HTTP 服务，不依赖云端中转。
- 聊天式体验：文字和文件都落在同一个会话时间线里，发送记录、接收状态、文件进度更容易回看。
- 首次可信配对：发现设备后通过 6 位校验码建立信任关系，后续可信设备会自动进入可发送状态。
- 端到端安全层：请求使用 Ed25519 签名，双方通过 X25519 派生共享密钥，文字和文件分块使用 AES-GCM 加密，并校验 nonce 与时间窗。
- 文件传输更贴近日常操作：支持应用内多文件选择、Windows 拖拽到聊天区、从剪贴板粘贴文件或图片、Android 系统分享入口。
- 本地历史和索引：使用 Drift/SQLite 保存设备、会话、消息、传输和设置，接收文件会按会话与年月归档。
- 断线重连：可信设备离线后发送时会尝试重新发现并恢复连接，降低移动设备切换网络时的失败率。
- 跨端 Flutter 实现：同一套主要业务逻辑覆盖 Windows 和 Android，便于继续扩展到更多桌面或移动端。

## 独到之处

LocalChat 把“文件传输”和“聊天上下文”放在一起。相比只弹出发送窗口的工具，它保留了谁发的、什么时候发的、是否成功、文件保存在哪里等上下文；相比公网聊天软件，它又不需要账号、服务器或外部网络。

安全设计也不是只做简单内网明文传输。项目在应用层维护设备身份、信任关系、签名验证、密钥协商、加密分块和完整性校验，即使底层传输是局域网 HTTP，请求内容和文件块也会经过加密与认证。

## 功能状态

已实现：

- Windows/Android Flutter 项目骨架。
- 响应式聊天主界面：已信任设备、发现设备、会话时间线、文字和文件消息卡片。
- UDP 局域网设备发现，广播设备 ID、名称、平台、监听端口和公钥指纹。
- 6 位码首次配对和可信设备管理。
- HTTP 传输协议：`/v1/hello`、配对、消息、传输开始、加密流、分块、完成接口。
- Ed25519 请求签名、X25519 共享密钥、AES-GCM 加密文本和文件分块。
- Drift/SQLite 本地历史：`devices`、`conversations`、`messages`、`transfers`、`settings`。
- Windows 拖拽文件发送、剪贴板文件/图片发送、Android 系统分享入口。
- 接收文字自动复制到剪贴板，可在设置中关闭。
- 接收文件保存到 Downloads/LocalChat，并按会话和年月归档。

当前限制：

- MVP 主要面向同一局域网内、应用前台运行时的发现和收发。
- 文件夹递归、后台常驻、托盘、开机自启、跨网段和中转服务暂未实现。
- Android 和 Windows release 包已验证可构建。

## 技术栈

- Flutter / Dart
- Drift / SQLite
- shelf / shelf_router
- dio
- cryptography
- file_picker
- desktop_drop
- receive_sharing_intent

## 安装环境

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

## 使用方法

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

## 适合场景

- 手机和电脑之间临时传截图、安装包、文档、链接。
- 不希望文件经过公网服务器的办公室或家庭局域网传输。
- 需要保留传输上下文和历史记录，而不只是一次性投递文件。
- 想研究 Flutter 跨端、局域网发现、安全传输和本地持久化组合实现的示例项目。

## 后续计划

- 后台常驻与托盘模式。
- 文件夹递归发送。
- 更完整的传输失败重试和断点续传。
- 更多平台支持和更细的设备权限管理。
