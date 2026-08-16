# CHANGELOG

This changelog is maintained in Chinese and English for the GitHub project page and release notes.

## 1.3.6 - 2026-08-17

### 中文

- 新增大文件分块断点续传：失败的传输在重试时从接收端已收到的分块继续，不再整文件重传；对旧版本设备自动回退整传。
- 配对校验码改为由双方设备密钥指纹共同派生，接收方需输入与对方屏幕显示一致的校验码才能允许配对，可防范局域网中间人配对攻击；对旧版本设备回退原流程。
- 修复加密信封防重放缓存可被无效签名的请求污染、进而重放有效消息的问题。
- 新增 GitHub Actions CI：推送与 Pull Request 自动执行格式校验、静态分析与全部测试。
- 收紧静态分析规则、排除生成代码并统一代码格式；将主界面与对话框等巨型源码文件按职责拆分为多个模块，行为不变。
- 修正 Android 应用名大小写显示为 LocalChat。

### English

- Added resumable chunked transfers for large files: failed transfers retry from the chunks the receiver already has instead of restarting from scratch; peers on older versions fall back to full re-transfer.
- Pairing codes are now derived from both devices' key fingerprints, and the receiver must enter the code shown on the other device before pairing is allowed, defeating man-in-the-middle pairing on the LAN; older peers fall back to the previous flow.
- Fixed the anti-replay nonce cache being polluted by requests with invalid signatures, which could have allowed replaying captured messages.
- Added GitHub Actions CI running format checks, static analysis, and the full test suite on pushes and pull requests.
- Tightened static analysis rules, excluded generated code, unified formatting, and split the oversized UI and dialog source files into focused modules with no behavior change.
- Fixed the Android app label casing to display as LocalChat.

## 1.3.5 - 2026-07-03

### 中文

- 修复 Windows UDP 发现端口报错 `10013` 时导致整个应用启动失败的问题；主端口不可用时会自动尝试备用端口。
- 扩展 Windows 备用发现端口到 `59641-59645` 和 `61071-61075`，降低系统保留端口、虚拟网卡或安全软件占用默认端口时无法自动发现的概率。
- 改进多网卡环境下的局域网发现，分别通过活动私网 IPv4 网卡广播，并按数据包来源端口回复。
- 新增“网络诊断与日志”，可查看发现端口、广播网卡和 Windows 防火墙状态，并支持一键修复本地子网入站规则。
- 新增自动轮转的基础诊断日志与导出功能，不记录聊天正文、文件内容、私钥、配对码或令牌。
- 修复 Windows 安全存储无法解密或缺失本机身份密钥时启动停在“身份初始化中”的问题；旧明文密钥存在时会重新迁移，否则自动重置本机身份并提示重新配对。
- 修复手动 IP 连接后收到配对请求时，聊天窗口没有自动切换到请求设备，导致内嵌配对卡片不可见的问题。

### English

- Fixed Windows startup failures caused by UDP discovery error `10013`; LocalChat now tries fallback discovery ports when the preferred port is unavailable.
- Expanded Windows fallback discovery ports to `59641-59645` and `61071-61075`, reducing automatic discovery failures when default ports are reserved or blocked by adapters or security software.
- Improved LAN discovery on multi-adapter systems by broadcasting through active private IPv4 interfaces and replying to each datagram's source port.
- Added Network Diagnostics and Logs with discovery, adapter, and Windows Firewall status plus one-click local-subnet firewall repair.
- Added rotating diagnostic logs and export support without recording chat text, file contents, private keys, pairing codes, or tokens.
- Fixed startup getting stuck at identity initialization when Windows cannot decrypt or no longer has saved local identity keys; LocalChat re-migrates legacy plaintext keys when available, otherwise resets the local identity and asks the user to pair devices again.
- Fixed incoming pairing requests after manual IP connection not switching the chat view to the requesting device, which could hide the inline pairing card.

## 1.3.4 - 2026-06-27

### 中文

- 新增“关于 LocalChat”页面，集中展示版本号、作者、开源社区地址、发布页、问题反馈入口和开源协议。
- 新增 GitHub Releases 检查更新功能，支持手动检查，并可选择开启每日自动检查。
- 新增 MIT 开源协议文件，并在应用内提供第三方开源许可入口。

### English

- Added an About LocalChat page with version, author, open-source community, releases, issue tracker, and license details.
- Added GitHub Releases update checks, with manual checks and an optional daily automatic check.
- Added the MIT license file and an in-app entry for third-party open-source licenses.

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
