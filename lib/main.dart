import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/help_screen.dart';
import 'screens/about_screen.dart';
import 'screens/login_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'utils/app_theme.dart';
import 'utils/native_bridge.dart';
import 'services/app_version_service.dart';
import 'utils/app_logger.dart';
import 'utils/global_config.dart'
    show GlobalState, DnsConfig, XhttpAdvancedConfig;
import 'services/experimental/experimental_features.dart';
import 'services/telemetry/telemetry_service.dart';
import 'services/vpn_config_service.dart';
import 'services/global_proxy_service.dart';
import 'services/permission_guide_service.dart';
import 'services/sync/desktop_sync_service.dart';
import 'services/tun_settings_service.dart';
import 'widgets/permission_guide_dialog.dart';
import 'widgets/log_console.dart' show LogLevel;
import 'widgets/app_breadcrumb.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'widgets/take_picture.dart';

String getQrCodeData(img.Image image) {
  final source = RGBLuminanceSource(
      image.width,
      image.height,
      image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List());
  // decode qr code
  final bitMap = BinaryBitmap(GlobalHistogramBinarizer(source));
  final qr = QRCodeReader().decode(bitMap);
  return qr.text;
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppVersionService.init();
  await TelemetryService.init();
  await DnsConfig.init();
  await XhttpAdvancedConfig.init();
  await GlobalProxyService.init();
  await PermissionGuideService.init();
  await ExperimentalFeatures.init();
  await TunSettingsService.init();
  await DesktopSyncService.instance.init();
  final debug = args.contains('--debug') ||
      Platform.executableArguments.contains('--debug');
  GlobalState.debugMode.value = debug;
  if (debug) {
    debugPrint('🚀 Flutter main() started in debug mode');
  }
  await VpnConfig.load(); // ✅ 启动时加载 assets + 本地配置
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: GlobalState.locale,
      builder: (context, locale, _) {
        return MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          title: 'XStream',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const MainPage(),
        );
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  static const double _mobileBreakpoint = 900;
  int _currentIndex = 0;

  bool _isMobileLayout(BuildContext context) {
    final isPhonePlatform = Platform.isIOS || Platform.isAndroid;
    return isPhonePlatform &&
        MediaQuery.of(context).size.width < _mobileBreakpoint;
  }



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ✅ 注册生命周期观察器
    if (Platform.isIOS) {
      GlobalState.setTunnelModeEnabled(true);
    }

    NativeBridge.initializeLogger((log) {
      addAppLog("[macOS] $log");
    });
    NativeBridge.initializeNativeMenuActions(_handleNativeMenuAction);

    GlobalState.connectionMode.addListener(_onConnectionModeChanged);
    GlobalState.activeNodeName.addListener(_syncNativeMenuState);
    GlobalState.locale.addListener(_onLocaleChanged);
    _syncNativeMenuState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ 注销生命周期观察器
    GlobalState.connectionMode.removeListener(_onConnectionModeChanged);
    GlobalState.activeNodeName.removeListener(_syncNativeMenuState);
    GlobalState.locale.removeListener(_onLocaleChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      // ✅ 退出前自动保存配置
      VpnConfig.saveToFile();
    }
  }



  void _openAddConfig() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
  }

  void _openAddConfigWithUri(String uri) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriptionScreen(initialVlessUri: uri),
      ),
    );
  }

  Future<void> _showAddNodeMenuAction(_AddNodeMenuAction action) async {
    switch (action) {
      case _AddNodeMenuAction.manualInput:
        _openAddConfig();
        break;
      case _AddNodeMenuAction.scanQr:
        if (Platform.isAndroid || Platform.isIOS) {
          final result = await showModalBottomSheet<String>(
            context: context,
            builder: (BuildContext ctx) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.camera_alt),
                      title: Text(context.l10n.get('camera')),
                      onTap: () async {
                        Navigator.pop(ctx, 'camera');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library),
                      title: Text(context.l10n.get('gallery')),
                      onTap: () {
                        Navigator.pop(ctx, 'gallery');
                      },
                    ),
                  ],
                ),
              );
            },
          );
          if (result == 'camera') {
            await _showQrScanner();
          } else if (result == 'gallery') {
            await _pickImageAndScan();
          }
        } else {
           await _pickImageAndScan();
        }
        break;

      case _AddNodeMenuAction.readClipboard:
        await _importFromClipboard();
        break;
    }
  }
  Future<void> _showQrScanner() async {
    final barcode = await Navigator.of(context, rootNavigator: true)
        .push<Barcode?>(MaterialPageRoute(builder: (ctx) {
      return const ScanQrCode();
    }));
    if (barcode == null || barcode.displayValue == null) {
      return;
    }
    if (!mounted) return;
    _openAddConfigWithUri(barcode.displayValue!);
  }

  Future<void> _pickImageAndScan() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final imageBytes = result.files.first.bytes;
    if (imageBytes == null) {
      return;
    }

    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      final data = getQrCodeData(image);
      if (data.isEmpty) {
        throw Exception('Failed to find QR code');
      }
      if (!mounted) return;
      if (!data.startsWith('vless://')) {
        _showComingSoon(context.l10n.get('vlessUriInvalid'));
        return;
      }
      _openAddConfigWithUri(data);
    } catch (e) {
      addAppLog('decode qr code error: $e', level: LogLevel.error);
      if (mounted) {
        _showComingSoon(context.l10n.get('decodeQrCodeFailed'));
      }
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = (data?.text ?? '').trim();
    if (!mounted) return;
    if (!raw.startsWith('vless://')) {
      _showComingSoon(context.l10n.get('clipboardNoVless'));
      return;
    }
    _openAddConfigWithUri(raw);
  }

  void _showComingSoon(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _toggleLanguage() {
    final current = GlobalState.locale.value;
    GlobalState.locale.value =
        current.languageCode == 'zh' ? const Locale('en') : const Locale('zh');
  }

  Future<void> _onConnectionModeChanged() async {
    final mode = GlobalState.connectionMode.value;
    final tunnelEnabled = GlobalState.isTunnelModeValue(mode);
    if (GlobalState.tunnelProxyEnabled.value != tunnelEnabled) {
      GlobalState.tunnelProxyEnabled.value = tunnelEnabled;
    }
    addAppLog('切换连接模式为 $mode');

    // Stop the active connection in the old mode so the user re-connects
    // cleanly in the new mode, then auto reconnect using the same node.
    final activeNode = GlobalState.activeNodeName.value.trim();
    if (activeNode.isNotEmpty) {
      String stopMsg;
      if (tunnelEnabled) {
        // Was in proxy mode → stop proxy service
        stopMsg = await NativeBridge.stopNodeService(activeNode);
      } else {
        // Was in TUN mode → stop packet tunnel
        stopMsg = await NativeBridge.stopNodeForTunnel();
      }
      GlobalState.activeNodeName.value = '';
      addAppLog('[mode switch] $stopMsg');

      final startMsg = tunnelEnabled
          ? await NativeBridge.startNodeForTunnel(activeNode)
          : await NativeBridge.startNodeService(activeNode);
      final running = tunnelEnabled
          ? !startMsg.contains('失败')
          : await NativeBridge.checkNodeStatus(activeNode);
      addAppLog('[mode switch] $startMsg');

      if (running) {
        GlobalState.activeNodeName.value = activeNode;
      } else if (tunnelEnabled) {
        final shouldShow = await PermissionGuideService
            .shouldPromptForPacketTunnelAuthorization(
          failureMessage: startMsg,
        );
        if (mounted && shouldShow) {
          await showPermissionGuideDialog(
            context,
            failureMessage: startMsg,
          );
        }
      }
    }

    _syncNativeMenuState();
    if (mounted) {
      final label = tunnelEnabled ? 'TUN 模式' : '代理模式';
      final suffix = activeNode.isNotEmpty ? '，已自动重连' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到$label$suffix')),
      );
    }
  }

  Future<void> _handleNativeMenuAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    switch (action) {
      case 'showMainWindow':
        break;
      case 'setProxyMode':
        final mode = (payload['mode'] as String?) ?? 'VPN';
        GlobalState.setConnectionMode(mode);
        break;
      case 'startAcceleration':
        await _startAccelerationFromMenu(payload);
        break;
      case 'stopAcceleration':
        await _stopAccelerationFromMenu(payload);
        break;
      case 'reconnectAcceleration':
        await _stopAccelerationFromMenu(payload);
        await _startAccelerationFromMenu(payload);
        break;
      case 'connectionStateChanged':
        final connected = payload['connected'] == true;
        final nodeName = (payload['nodeName'] as String?) ?? '';
        if (!connected) {
          GlobalState.activeNodeName.value = '';
        } else if (nodeName.isNotEmpty) {
          GlobalState.activeNodeName.value = nodeName;
        }
        break;
      default:
        break;
    }
    _syncNativeMenuState();
  }

  Future<void> _startAccelerationFromMenu(Map<String, dynamic> payload) async {
    String nodeName = (payload['nodeName'] as String?)?.trim() ?? '';
    if (nodeName.isEmpty) {
      await VpnConfig.load();
      if (VpnConfig.nodes.isEmpty) {
        addAppLog('[menu] 未找到可用节点', level: LogLevel.warning);
        return;
      }
      nodeName = VpnConfig.nodes.first.name;
    }
    final useTunMode = NativeBridge.isTunMode;
    final message = useTunMode
        ? await NativeBridge.startNodeForTunnel(nodeName)
        : await NativeBridge.startNodeService(nodeName);
    final running = useTunMode
        ? !message.contains('失败')
        : await NativeBridge.checkNodeStatus(nodeName);
    if (running) {
      GlobalState.activeNodeName.value = nodeName;
    }
    addAppLog('[menu] $message');
    if (useTunMode && !running) {
      final shouldShow =
          await PermissionGuideService.shouldPromptForPacketTunnelAuthorization(
        failureMessage: message,
      );
      if (mounted && shouldShow) {
        await showPermissionGuideDialog(
          context,
          failureMessage: message,
        );
      }
    }
  }

  Future<void> _stopAccelerationFromMenu(Map<String, dynamic> payload) async {
    String nodeName = (payload['nodeName'] as String?)?.trim() ?? '';
    nodeName = nodeName.isEmpty ? GlobalState.activeNodeName.value : nodeName;
    if (nodeName.isEmpty) return;
    final useTunMode = NativeBridge.isTunMode;
    final message = useTunMode
        ? await NativeBridge.stopNodeForTunnel()
        : await NativeBridge.stopNodeService(nodeName);
    GlobalState.activeNodeName.value = '';
    addAppLog('[menu] $message');
  }

  Future<void> _onLocaleChanged() async {
    await _syncNativeMenuState();
  }

  Future<void> _syncNativeMenuState() async {
    if (!Platform.isMacOS) return;
    final nodeName = GlobalState.activeNodeName.value.trim();
    final connected = nodeName.isNotEmpty;
    final mode = GlobalState.isTunnelMode ? 'tun' : 'proxyOnly';
    await NativeBridge.updateMenuState(
      connected: connected,
      nodeName: connected ? nodeName : '-',
      proxyMode: mode,
      languageCode: GlobalState.locale.value.languageCode,
    );
  }

  List<NavigationRailDestination> _buildDestinations(BuildContext context) {
    return [
      NavigationRailDestination(
          icon: const Icon(Icons.home), label: Text(context.l10n.get('home'))),
      NavigationRailDestination(
          icon: const Icon(Icons.link), label: Text(context.l10n.get('proxy'))),
      NavigationRailDestination(
          icon: const Icon(Icons.account_circle),
          label: Text(context.l10n.get('accountLogin'))),
      NavigationRailDestination(
          icon: const Icon(Icons.settings),
          label: Text(context.l10n.get('settings'))),
      NavigationRailDestination(
          icon: const Icon(Icons.help), label: Text(context.l10n.get('help'))),
      NavigationRailDestination(
          icon: const Icon(Icons.info), label: Text(context.l10n.get('about'))),
    ];
  }

  List<_NavigationDestination> _buildMobileDestinations(BuildContext context) {
    return [
      _NavigationDestination(
        icon: const Icon(Icons.home),
        label: Text(context.l10n.get('home')),
      ),
      _NavigationDestination(
        icon: const Icon(Icons.link),
        label: Text(context.l10n.get('proxy')),
      ),
      _NavigationDestination(
        icon: const Icon(Icons.account_circle),
        label: Text(context.l10n.get('accountLogin')),
      ),
      _NavigationDestination(
        icon: const Icon(Icons.settings),
        label: Text(context.l10n.get('settings')),
      ),
    ];
  }

  String _currentPageTitle(BuildContext context) {
    final labels = _isMobileLayout(context)
        ? [
            context.l10n.get('home'),
            context.l10n.get('proxy'),
            context.l10n.get('accountLogin'),
            context.l10n.get('settings'),
          ]
        : [
            context.l10n.get('home'),
            context.l10n.get('proxy'),
            context.l10n.get('accountLogin'),
            context.l10n.get('settings'),
            context.l10n.get('help'),
            context.l10n.get('about'),
          ];
    return labels[_currentIndex.clamp(0, labels.length - 1)];
  }

  List<String> _currentBreadcrumbItems(BuildContext context) {
    final current = _currentPageTitle(context);
    final home = context.l10n.get('home');
    if (current == home) {
      return [home];
    }
    return [home, current];
  }

  // Drawer removed in favor of NavigationBar

  PopupMenuItem<_AddNodeMenuAction> _buildAddNodeItem(
    BuildContext context, {
    required _AddNodeMenuAction action,
    required IconData icon,
    required String text,
  }) {
    return PopupMenuItem<_AddNodeMenuAction>(
      value: action,
      height: 52,
      child: SizedBox(
        width: 200,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktopPages = <Widget>[
      const HomeScreen(),
      const SubscriptionScreen(),
      const LoginScreen(),
      const SettingsScreen(),
      const HelpScreen(),
      const AboutScreen(),
    ];

    final mobilePages = <Widget>[
      const HomeScreen(),
      const SubscriptionScreen(),
      const LoginScreen(),
      const SettingsScreen(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhonePlatform = Platform.isIOS || Platform.isAndroid;
        final isMobile =
            isPhonePlatform && constraints.maxWidth < _mobileBreakpoint;
        final destinations = _buildDestinations(context);

        return Scaffold(
          appBar: AppBar(
            title: AppBreadcrumb(
              items: _currentBreadcrumbItems(context),
              compact: isMobile,
            ),
            actions: [
              ValueListenableBuilder<Locale>(
                valueListenable: GlobalState.locale,
                builder: (context, locale, _) {
                  final label = locale.languageCode == 'zh' ? '中' : 'EN';
                  return IconButton(
                    tooltip: context.l10n.get('language'),
                    icon: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: _toggleLanguage,
                  );
                },
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: PopupMenuButton<_AddNodeMenuAction>(
                  tooltip: context.l10n.get('addConfig'),
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                   color: Theme.of(context).colorScheme.surface,
                  onSelected: _showAddNodeMenuAction,
                  itemBuilder: (context) => [
                    _buildAddNodeItem(
                      context,
                      action: _AddNodeMenuAction.manualInput,
                      icon: Icons.edit,
                      text: context.l10n.get('addNodeManualInput'),
                    ),
                    if (Platform.isAndroid || Platform.isIOS)
                      _buildAddNodeItem(
                        context,
                        action: _AddNodeMenuAction.scanQr,
                        icon: Icons.qr_code_scanner,
                        text: context.l10n.get('addNodeScanQr'),
                      ),

                    _buildAddNodeItem(
                      context,
                      action: _AddNodeMenuAction.readClipboard,
                      icon: Icons.content_paste,
                      text: context.l10n.get('addNodeReadClipboard'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5B8DEF), Color(0xFF6C63FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF5B8DEF).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 20),
                        const SizedBox(width: 4),
                        Icon(Icons.dns_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
          bottomNavigationBar: isMobile
              ? NavigationBar(
                  selectedIndex:
                      _clampIndex(isMobile, mobilePages, desktopPages),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) =>
                      setState(() => _currentIndex = index),
                  destinations: _buildMobileDestinations(context).map((d) {
                    return NavigationDestination(
                      icon: d.icon,
                      label: (d.label as Text).data ?? '',
                    );
                  }).toList(),
                )
              : null,
          body: isMobile
              ? IndexedStack(
                  index: _clampIndex(isMobile, mobilePages, desktopPages),
                  children: mobilePages)
              : Row(
                  children: [
                    NavigationRail(
                      selectedIndex:
                          _clampIndex(isMobile, mobilePages, desktopPages),
                      onDestinationSelected: (index) =>
                          setState(() => _currentIndex = index),
                      labelType: NavigationRailLabelType.all,
                      destinations: destinations,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: IndexedStack(
                          index:
                              _clampIndex(isMobile, mobilePages, desktopPages),
                          children: desktopPages),
                    ),
                  ],
                ),
        );
      },
    );
  }

  int _clampIndex(
      bool isMobile, List<Widget> mobilePages, List<Widget> desktopPages) {
    if (isMobile && _currentIndex >= mobilePages.length) {
      return mobilePages.length - 1;
    }
    if (!isMobile && _currentIndex >= desktopPages.length) {
      return desktopPages.length - 1;
    }
    return _currentIndex;
  }
}

class _NavigationDestination {
  final Widget icon;
  final Widget label;

  _NavigationDestination({required this.icon, required this.label});
}

enum _AddNodeMenuAction {
  manualInput,
  scanQr,

  readClipboard,
}
