import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/help_screen.dart';
import 'screens/about_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'utils/app_theme.dart';
import 'utils/native_bridge.dart';
import 'utils/global_config.dart' show GlobalState, DnsConfig, TunDnsConfig;
import 'services/experimental/experimental_features.dart';
import 'utils/app_logger.dart';
import 'services/telemetry/telemetry_service.dart';
import 'services/vpn_config_service.dart';
import 'services/global_proxy_service.dart';
import 'services/permission_guide_service.dart';
import 'services/sync/desktop_sync_service.dart';
import 'services/tun_settings_service.dart';
import 'widgets/log_console.dart' show LogLevel;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await TelemetryService.init();
  await DnsConfig.init();
  await TunDnsConfig.init();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ✅ 注册生命周期观察器

    NativeBridge.initializeLogger((log) {
      addAppLog("[macOS] $log");
    });
    NativeBridge.initializeNativeMenuActions(_handleNativeMenuAction);

    GlobalState.connectionMode.addListener(_onConnectionModeChanged);
    GlobalState.activeNodeName.addListener(_syncNativeMenuState);
    _syncNativeMenuState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ 注销生命周期观察器
    GlobalState.connectionMode.removeListener(_onConnectionModeChanged);
    GlobalState.activeNodeName.removeListener(_syncNativeMenuState);
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

  Future<void> _promptUnlockDialog() async {
    String? password = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(context.l10n.get('unlockPrompt')),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration:
                InputDecoration(labelText: context.l10n.get('password')),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.get('cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: Text(context.l10n.get('confirm'))),
          ],
        );
      },
    );

    if (password != null && password.isNotEmpty) {
      GlobalState.isUnlocked.value = true;
      GlobalState.sudoPassword.value = password;
    }
  }

  void _lock() {
    GlobalState.isUnlocked.value = false;
    GlobalState.sudoPassword.value = '';
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
      case _AddNodeMenuAction.subscriptionLink:
        await _showSubscriptionLinkDialog();
        break;
      case _AddNodeMenuAction.scanQr:
        await _showQrInputDialog();
        break;
      case _AddNodeMenuAction.pickImage:
        _showComingSoon(context.l10n.get('addNodePickImage'));
        break;
      case _AddNodeMenuAction.pickFile:
        if (mounted) {
          setState(() => _currentIndex = 2);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.get('openSettingsImportHint'))),
          );
        }
        break;
      case _AddNodeMenuAction.readClipboard:
        await _importFromClipboard();
        break;
    }
  }

  Future<void> _showSubscriptionLinkDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.get('addNodeSubscriptionLink')),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'vless://...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.get('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(context.l10n.get('confirm')),
            ),
          ],
        );
      },
    );
    if (!mounted || value == null || value.isEmpty) return;
    _openAddConfigWithUri(value);
  }

  Future<void> _showQrInputDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.get('addNodeScanQr')),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: context.l10n.get('scanResultHint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.get('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(context.l10n.get('confirm')),
            ),
          ],
        );
      },
    );
    if (!mounted || value == null || value.isEmpty) return;
    if (!value.startsWith('vless://')) {
      _showComingSoon(context.l10n.get('vlessUriInvalid'));
      return;
    }
    _openAddConfigWithUri(value);
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

  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final current = GlobalState.locale.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<Locale>(
              value: const Locale('zh'),
              groupValue: current,
              title: const Text('中文'),
              onChanged: (loc) {
                if (loc != null) GlobalState.locale.value = loc;
                Navigator.pop(context);
              },
            ),
            RadioListTile<Locale>(
              value: const Locale('en'),
              groupValue: current,
              title: const Text('English'),
              onChanged: (loc) {
                if (loc != null) GlobalState.locale.value = loc;
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _onConnectionModeChanged() async {
    if (!GlobalState.isUnlocked.value) return;
    final mode = GlobalState.connectionMode.value;
    addAppLog('切换模式为 $mode');
    String msg;
    if (mode == 'VPN') {
      msg = await NativeBridge.startPacketTunnel();
    } else {
      msg = await NativeBridge.stopPacketTunnel();
    }
    addAppLog('[packet tunnel] $msg');
    _syncNativeMenuState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _handleNativeMenuAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    switch (action) {
      case 'showMainWindow':
        break;
      case 'openLogs':
        if (mounted) {
          setState(() => _currentIndex = 3);
        }
        break;
      case 'editRules':
        if (mounted) {
          setState(() => _currentIndex = 1);
        }
        break;
      case 'setProxyMode':
        final mode = (payload['mode'] as String?) ?? 'VPN';
        GlobalState.connectionMode.value = mode;
        break;
      case 'startAcceleration':
        await _startAccelerationFromMenu(payload);
        break;
      case 'stopAcceleration':
        await _stopAccelerationFromMenu(payload);
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
    final message = await NativeBridge.startNodeService(nodeName);
    final running = await NativeBridge.checkNodeStatus(nodeName);
    if (running) {
      GlobalState.activeNodeName.value = nodeName;
    }
    addAppLog('[menu] $message');
  }

  Future<void> _stopAccelerationFromMenu(Map<String, dynamic> payload) async {
    String nodeName = (payload['nodeName'] as String?)?.trim() ?? '';
    nodeName = nodeName.isEmpty ? GlobalState.activeNodeName.value : nodeName;
    if (nodeName.isEmpty) return;
    final message = await NativeBridge.stopNodeService(nodeName);
    GlobalState.activeNodeName.value = '';
    addAppLog('[menu] $message');
  }

  Future<void> _syncNativeMenuState() async {
    if (!Platform.isMacOS) return;
    final nodeName = GlobalState.activeNodeName.value.trim();
    final connected = nodeName.isNotEmpty;
    final mode =
        GlobalState.connectionMode.value == '仅代理' ? 'proxyOnly' : 'tun';
    await NativeBridge.updateMenuState(
      connected: connected,
      nodeName: connected ? nodeName : '-',
      proxyMode: mode,
    );
  }

  List<NavigationRailDestination> _buildDestinations(BuildContext context) {
    return [
      NavigationRailDestination(
          icon: const Icon(Icons.home), label: Text(context.l10n.get('home'))),
      NavigationRailDestination(
          icon: const Icon(Icons.link), label: Text(context.l10n.get('proxy'))),
      NavigationRailDestination(
          icon: const Icon(Icons.settings),
          label: Text(context.l10n.get('settings'))),
      NavigationRailDestination(
          icon: const Icon(Icons.article),
          label: Text(context.l10n.get('logs'))),
      NavigationRailDestination(
          icon: const Icon(Icons.help), label: Text(context.l10n.get('help'))),
      NavigationRailDestination(
          icon: const Icon(Icons.info), label: Text(context.l10n.get('about'))),
    ];
  }

  String _currentPageTitle(BuildContext context) {
    final labels = [
      context.l10n.get('home'),
      context.l10n.get('proxy'),
      context.l10n.get('settings'),
      context.l10n.get('logs'),
      context.l10n.get('help'),
      context.l10n.get('about'),
    ];
    return labels[_currentIndex.clamp(0, labels.length - 1)];
  }

  Drawer _buildMobileDrawer(BuildContext context) {
    final destinations = _buildDestinations(context);
    return Drawer(
      child: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: destinations.length,
          itemBuilder: (context, index) {
            final destination = destinations[index];
            return ListTile(
              leading: destination.icon,
              title: destination.label,
              selected: _currentIndex == index,
              onTap: () {
                setState(() => _currentIndex = index);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
    );
  }

  PopupMenuItem<_AddNodeMenuAction> _buildAddNodeItem(
    BuildContext context, {
    required _AddNodeMenuAction action,
    required IconData icon,
    required String text,
  }) {
    return PopupMenuItem<_AddNodeMenuAction>(
      value: action,
      height: 68,
      child: SizedBox(
        width: 220,
        child: Row(
          children: [
            Icon(icon, size: 30, color: const Color(0xFF434A55)),
            const SizedBox(width: 18),
            Text(
              text,
              style: const TextStyle(fontSize: 22, color: Color(0xFF1E2025)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomeScreen(),
      const SubscriptionScreen(),
      const SettingsScreen(),
      const LogsScreen(),
      const HelpScreen(),
      const AboutScreen(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhonePlatform = Platform.isIOS || Platform.isAndroid;
        final isMobile =
            isPhonePlatform && constraints.maxWidth < _mobileBreakpoint;
        final destinations = _buildDestinations(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(isMobile ? _currentPageTitle(context) : ''),
            actions: [
              IconButton(
                tooltip: context.l10n.get('language'),
                icon: const Icon(Icons.language),
                onPressed: _showLanguageSelector,
              ),
              PopupMenuButton<_AddNodeMenuAction>(
                tooltip: context.l10n.get('addConfig'),
                icon: const Icon(Icons.add),
                position: PopupMenuPosition.under,
                onSelected: _showAddNodeMenuAction,
                itemBuilder: (context) => [
                  _buildAddNodeItem(
                    context,
                    action: _AddNodeMenuAction.manualInput,
                    icon: Icons.edit,
                    text: context.l10n.get('addNodeManualInput'),
                  ),
                  _buildAddNodeItem(
                    context,
                    action: _AddNodeMenuAction.subscriptionLink,
                    icon: Icons.link,
                    text: context.l10n.get('addNodeSubscriptionLink'),
                  ),
                  _buildAddNodeItem(
                    context,
                    action: _AddNodeMenuAction.scanQr,
                    icon: Icons.qr_code_scanner,
                    text: context.l10n.get('addNodeScanQr'),
                  ),
                  _buildAddNodeItem(
                    context,
                    action: _AddNodeMenuAction.pickImage,
                    icon: Icons.image,
                    text: context.l10n.get('addNodePickImage'),
                  ),
                  _buildAddNodeItem(
                    context,
                    action: _AddNodeMenuAction.pickFile,
                    icon: Icons.file_open,
                    text: context.l10n.get('addNodePickFile'),
                  ),
                  _buildAddNodeItem(
                    context,
                    action: _AddNodeMenuAction.readClipboard,
                    icon: Icons.content_paste,
                    text: context.l10n.get('addNodeReadClipboard'),
                  ),
                ],
              ),
              ValueListenableBuilder<bool>(
                valueListenable: GlobalState.isUnlocked,
                builder: (context, unlocked, _) {
                  return IconButton(
                    icon: Icon(unlocked ? Icons.lock_open : Icons.lock),
                    onPressed: unlocked ? _lock : _promptUnlockDialog,
                  );
                },
              ),
            ],
          ),
          drawer: isMobile ? _buildMobileDrawer(context) : null,
          body: isMobile
              ? IndexedStack(index: _currentIndex, children: pages)
              : Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _currentIndex,
                      onDestinationSelected: (index) =>
                          setState(() => _currentIndex = index),
                      labelType: NavigationRailLabelType.all,
                      destinations: destinations,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child:
                          IndexedStack(index: _currentIndex, children: pages),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

enum _AddNodeMenuAction {
  manualInput,
  subscriptionLink,
  scanQr,
  pickImage,
  pickFile,
  readClipboard,
}
