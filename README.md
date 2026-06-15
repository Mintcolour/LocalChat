# LocalChat

LocalChat 是一个 Flutter MVP，用来在同一局域网里的 Windows 和 Android 设备之间做“聊天式”文字与文件传输。

## 已实现

- Windows/Android Flutter 项目骨架。
- 聊天式主界面：已信任设备、发现设备、会话时间线、文字/文件消息卡片。
- 文件入口：应用内多文件选择，Windows 桌面拖拽文件到聊天区，Android 系统分享入口。
- UDP 局域网发现：广播设备 ID、名称、平台、监听端口、公钥指纹。
- 首次信任配对：发现设备后可生成 6 位码发起信任，可信设备后续自动进入会话。
- HTTP 传输协议：`/v1/hello`、配对、消息、传输开始、分块、完成接口。
- 安全层：Ed25519 请求签名、X25519 共享密钥、AES-GCM 加密文本和文件分块、nonce/时间窗校验。
- Drift/SQLite 本地历史：devices、conversations、messages、transfers、settings。
- Android debug APK 已验证可构建。

## 本机环境

本机 Flutter SDK 安装在：

```powershell
C:\Users\DeepBluePC\.codex\tools\flutter_3.44.2\flutter
```

Android SDK 安装在：

```powershell
C:\Users\DeepBluePC\.codex\tools\android-sdk
```

为了避开 C 盘 pub cache 和 E 盘项目之间的 Kotlin 路径问题，建议使用同盘 pub cache：

```powershell
E:\VScode\codex\.pub-cache
```

可以先加载脚本：

```powershell
. .\scripts\flutter_env.ps1
```

然后运行：

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

APK 输出：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

## 当前限制

- MVP 只支持同一局域网内应用前台运行时发现和收发。
- 文件夹递归、后台常驻、托盘、开机自启、跨网段/中转服务暂未实现。
- Windows 原生构建当前被本机 Visual Studio 工具链注册问题阻塞：Flutter doctor 优先识别 VS 2026 Insiders，并报告缺少 Desktop C++ 组件。Android 构建已通过。
- 当前配对流程是发起方确认 6 位码后，接收端自动信任；后续可升级为接收端弹窗确认。
