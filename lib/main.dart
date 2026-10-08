import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'services/diagnostic_log_service.dart';
import 'services/secure_key_store.dart';
import 'ui/attachment_preview.dart';
import 'ui/banners.dart';
import 'ui/chat_pane.dart';
import 'ui/device_pane.dart';
import 'ui/dialogs/settings_dialog.dart';
import 'ui/transfer_center_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnosticLogService = DiagnosticLogService();
  await diagnosticLogService.initialize();
  FlutterError.onError = (details) {
    diagnosticLogService.error(
      'flutter.uncaught_error',
      details.exception,
      details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    diagnosticLogService.error('platform.uncaught_error', error, stackTrace);
    return true;
  };
  // 生产环境启用系统安全存储（Android Keystore / Windows DPAPI）保存身份私钥。
  final controller = AppController(
    secureKeyStore: const SecureKeyStore(),
    diagnosticLogService: diagnosticLogService,
    enableAutomation: true,
  );
  await controller.initialize();
  runApp(LocalChatApp(controller: controller));
}

class LocalChatApp extends StatelessWidget {
  const LocalChatApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LocalChat',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1FA37A), // LocalChat 自有绿色系，非微信品牌。
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1FA37A),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: switch (controller.themeModeCode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: LocalChatHome(controller: controller),
      ),
    );
  }
}

class LocalChatHome extends StatefulWidget {
  const LocalChatHome({super.key, required this.controller});

  final AppController controller;

  @override
  State<LocalChatHome> createState() => _LocalChatHomeState();
}

class _LocalChatHomeState extends State<LocalChatHome>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  bool _dragging = false;
  int _shownNotificationSerial = 0;
  int? _shownAttachmentBatchId;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.setAppForeground(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setAppForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.setAppForeground(false);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.notificationSerial != _shownNotificationSerial &&
            controller.notificationText != null) {
          _shownNotificationSerial = controller.notificationSerial;
          final message = controller.notificationText!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          });
        }
        final attachmentBatch = controller.pendingAttachmentBatch;
        if (attachmentBatch == null) {
          _shownAttachmentBatchId = null;
        } else if (_shownAttachmentBatchId != attachmentBatch.id) {
          _shownAttachmentBatchId = attachmentBatch.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => AttachmentPreviewPage(
                  controller: controller,
                  batch: attachmentBatch,
                ),
              ),
            );
          });
        }
        final inConversation = controller.selectedDevice != null;
        return PopScope(
          canPop: !inConversation,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && controller.selectedDevice != null) {
              controller.closeConversation();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(controller.text.appTitle),
              actions: [
                IconButton(
                  tooltip: controller.text.transferCenter,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TransferCenterPage(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.swap_vert),
                ),
                IconButton(
                  tooltip: controller.text.rescan,
                  onPressed: controller.rescan,
                  icon: const Icon(Icons.travel_explore),
                ),
                IconButton(
                  tooltip: controller.text.settings,
                  onPressed: () => showSettingsDialog(context, controller),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 820;
                  final devicePane = DevicePane(controller: controller);
                  final chatPane = ChatPane(
                    key: ValueKey(
                      'chat-${controller.selectedDevice?.id ?? 'none'}',
                    ),
                    controller: controller,
                    textController: _textController,
                    dragging: _dragging,
                    onDragState: (value) => setState(() => _dragging = value),
                    showHeader: !narrow,
                  );
                  if (narrow) {
                    final selectedDevice = controller.selectedDevice;
                    final page = selectedDevice == null
                        ? KeyedSubtree(
                            key: const ValueKey('mobile-device-list'),
                            child: devicePane,
                          )
                        : KeyedSubtree(
                            key: ValueKey(
                              'mobile-conversation-${selectedDevice.id}',
                            ),
                            child: Column(
                              children: [
                                MobilePeerHeader(controller: controller),
                                Expanded(child: chatPane),
                              ],
                            ),
                          );
                    return AnimatedSwitcher(
                      key: const ValueKey('mobile-page-transition'),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      reverseDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final enteringConversation =
                            child.key is ValueKey<String> &&
                            (child.key! as ValueKey<String>).value.startsWith(
                              'mobile-conversation-',
                            );
                        final offset = enteringConversation
                            ? const Offset(0.08, 0)
                            : const Offset(-0.04, 0);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: offset,
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: page,
                    );
                  }
                  return Row(
                    children: [
                      // 桌面端会话列表约 300px + 内容区（计划：导航栏 64 + 会话列表 ~300 + 内容区）。
                      SizedBox(width: 300, child: devicePane),
                      const VerticalDivider(width: 1),
                      Expanded(child: chatPane),
                    ],
                  );
                },
              ),
            ),
            bottomNavigationBar: StatusBar(controller: controller),
          ),
        );
      },
    );
  }
}
