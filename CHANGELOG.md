# CHANGELOG

This changelog is maintained in Chinese and English for the GitHub project page and release notes.

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
