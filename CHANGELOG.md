# CHANGELOG

This changelog is maintained in Chinese and English for the GitHub project page and release notes.

## 1.3.3 - 2026-06-24

### 中文

- 新增 Windows 快传托盘（Quick Drop Shelf）：将文件拖到悬浮设备卡片即可快速发送，无需打开主窗口。
- 设置页新增快传开关，开启后自动同步在线设备列表，并在发送失败或目标离线时给出状态提示。

### English

- Added Windows Quick Drop Shelf: drag files onto a floating device card to send them instantly without opening the main window.
- Added a quick-send toggle in settings; enabling it syncs the online device list and surfaces status feedback when a send fails or the target goes offline.

## 1.3.2 - 2026-06-24

### 中文

- Windows 设置页新增默认存储路径配置，支持仅影响后续接收文件或迁移已索引的旧文件。
- 旧文件迁移会保留原目录结构、避开重名覆盖，并在缺失或失败时继续保留旧路径引用。
- 优化设备列表在线/离线分组、状态标识和长设备名显示。
- 文件消息新增删除记录或同时删除本地文件的确认流程。
- 简化设置页网络诊断入口，统一手动添加设备时的连接测试与排查文案。
- 更新 Android、Windows 和展示页图标资源，并重新生成发布包。

### English

- Added Windows default storage path settings, with options to affect only future received files or migrate indexed existing files.
- Existing-file migration preserves the folder layout, avoids overwriting conflicts, and keeps old path references when a file is missing or fails to move.
- Improved device-list online/offline grouping, status indicators, and long device-name display.
- Added file-message deletion choices for deleting only the record or deleting the local file too.
- Simplified network diagnostics in settings and unified connectivity-test guidance during manual peer add.
- Updated Android, Windows, and showcase icon assets, then rebuilt release packages.

## 1.3.1 - 2026-06-24

### 中文

- 优化配对流程：功能移至聊天内嵌卡片交互，并支持 65 秒超时过期及多并发配对请求管理。
- 新增校园网网络诊断：手动添加设备时提供连接测试、网络状态分析和诊断引导。
- 新增系统通知与后台保活配置：设置页支持管理通知状态（含消息预览开关）与后台保活。
- 修复未读计数查询逻辑，解决当 lastReadAt 与消息生成时间完全一致时计入未读数的问题。
- Windows 端增强前台状态检测，并拦截 MissingPluginException 异常提升测试环境兼容性。

### English

- Redesigned pairing workflow: replaced popup dialogs with inline chat cards, supporting 65s timeouts and concurrent requests.
- Added campus network diagnostics: provides connectivity tests and troubleshooting advice during manual peer addition.
- Added system notifications and keep-alive settings: supports native notifications (with message preview toggle) and background keep-alive.
- Fixed unread counts when lastReadAt exactly matches a message's createdAt.
- Enhanced Windows foreground state detection and caught MissingPluginException on method channels for test environments.

## 1.3.0 - 2026-06-23

### 中文

- 强化可信设备安全底座，增加公钥固定、身份变化拦截、nonce 重放防护和数据库 v5 迁移。
- 增加独立传输中心，支持出站排队、整组进度、取消兼容能力和失败/中断状态展示。
- 增强聊天页历史体验，支持分页加载、日期分隔、未读数、消息搜索定位、链接识别和附件托盘。
- 重构设置控制器和细粒度操作状态，减少文件传输期间对输入区的阻塞。
- 重做绿色系视觉风格，优化微信式聊天气泡、设备状态图标和文件消息可读性。
- 增加私钥迁移到系统安全存储和 Android 固定 release 签名。
- 设置页显示本机局域网 IP/端口，传输历史支持打开、打开文件夹和接收文件重命名。

### English

- Strengthened the trusted-device security base with key pinning, identity-change blocking, nonce replay protection, and database v5 migration.
- Added a dedicated transfer center with outbound queueing, grouped progress, cancel compatibility, and failed/interrupted status display.
- Improved chat history with pagination, date separators, unread counts, message search positioning, link detection, and an attachment tray.
- Refactored settings control and fine-grained operation state so file transfers no longer block the composer globally.
- Redesigned the green visual style with chat-style bubbles, persistent device-status icons, and more readable file messages.
- Added private-key migration to platform secure storage plus fixed Android release signing.
- Added local LAN IP/port display in settings and transfer-history actions for open, open folder, and received-file rename.

## 1.2.0 - 2026-06-22

### 中文

- 新增文件夹递归传输，发送时保留目录结构。
- 新增跨网段手动加好友，支持直接填写 IP 和端口。
- 新增 Windows 托盘、开机自启和单实例唤醒能力。
- 新增发送前附件预览、排序、移除，以及图片裁切、旋转、文字标注。
- 新增浅色、深色、跟随系统主题三种外观模式，并支持失败消息重试。
- 优化移动端体验，增加会话切换动画并修复返回键退出会话问题。

### English

- Added recursive folder transfer with preserved directory structure.
- Added manual peer add by IP and port for cross-subnet connections.
- Added Windows tray integration, startup launch, and single-instance activation.
- Added attachment preview, sorting, removal, plus image crop, rotate, and text annotation before send.
- Added light, dark, and follow-system theme modes, plus failed message retry support.
- Improved mobile experience with conversation transition animations and a fix for the back-navigation exit issue.

## 1.1.0 - 2026-06-17

### 中文

- 增加应用内中英文切换。
- 同步更新中英文 README 展示说明。
- 补充 Windows 发布说明，完善发布交付信息。

### English

- Added in-app Chinese and English language switching.
- Updated the bilingual README presentation.
- Expanded the Windows release instructions and delivery notes.

## 1.0.0 - 2026-06-17

### 中文

- 发布 LocalChat 首个 Flutter MVP 版本，覆盖 Windows 和 Android。
- 完成局域网设备发现、首次配对、消息与文件传输的基础链路。
- 增加设备在线状态、重连体验、设备列表管理和传输进度优化。
- 支持 Windows 剪贴板文件或图片发送，以及接收文件按会话与年月归档。

### English

- Released the first LocalChat Flutter MVP for Windows and Android.
- Delivered the core flow for LAN device discovery, first-time pairing, messages, and file transfer.
- Added online-status awareness, reconnect handling, device-list management, and transfer progress improvements.
- Added Windows clipboard file/image sending and received-file archiving by conversation and year/month.
