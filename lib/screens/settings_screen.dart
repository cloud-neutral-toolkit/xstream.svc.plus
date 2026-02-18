import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import '../../utils/global_config.dart'
    show
        GlobalState,
        buildVersion,
        DnsConfig,
        TunDnsConfig,
        GlobalApplicationConfig;
import '../../utils/native_bridge.dart';
import '../l10n/app_localizations.dart';
import '../../services/vpn_config_service.dart';
import '../../services/update/update_checker.dart';
import '../../services/update/update_platform.dart';
import '../../services/telemetry/telemetry_service.dart';
import '../../services/session/session_manager.dart';
import '../../services/sync/desktop_sync_service.dart';
import '../../services/sync/sync_state.dart';
import '../../services/mcp/runtime_mcp_service.dart';
import '../../utils/app_logger.dart';
import '../widgets/log_console.dart' show LogLevel;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Timer? _xrayMonitorTimer;
  bool _tunBusy = false;
  PacketTunnelStatus _tunStatus =
      const PacketTunnelStatus(status: 'unknown', utunInterfaces: []);

  final SessionManager _sessionManager = SessionManager.instance;
  final DesktopSyncService _syncService = DesktopSyncService.instance;
  final RuntimeMcpService _runtimeMcpService = RuntimeMcpService.instance;
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mfaCodeController = TextEditingController();

  static const TextStyle _menuTextStyle = TextStyle(fontSize: 14);
  static final ButtonStyle _menuButtonStyle = ElevatedButton.styleFrom(
    minimumSize: const Size.fromHeight(36),
    textStyle: _menuTextStyle,
  );

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = _sessionManager.baseUrl.value;
    _usernameController.text = _sessionManager.currentUser.value ?? '';
    _sessionManager.baseUrl.addListener(_syncBaseUrlFromSession);
    _sessionManager.currentUser.addListener(_syncUsernameFromSession);
    _refreshTunStatus();
    _runtimeMcpService.init();
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    ButtonStyle? style,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: style ?? _menuButtonStyle,
        icon: Icon(icon),
        label: Text(label, style: _menuTextStyle),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }

  void _syncBaseUrlFromSession() {
    final value = _sessionManager.baseUrl.value;
    if (_baseUrlController.text != value) {
      _baseUrlController.text = value;
    }
  }

  void _syncUsernameFromSession() {
    final value = _sessionManager.currentUser.value ?? '';
    if (_usernameController.text != value) {
      _usernameController.text = value;
    }
  }

  String _formatDateTime(DateTime dt) {
    String twoDigits(int v) => v.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  String _formatTunStatusText(BuildContext context, PacketTunnelStatus status) {
    final label = switch (status.status) {
      'connected' => context.l10n.get('tunStatusConnected'),
      'connecting' => context.l10n.get('tunStatusConnecting'),
      'disconnected' => context.l10n.get('tunStatusDisconnected'),
      'disconnecting' => context.l10n.get('tunStatusDisconnecting'),
      'invalid' => context.l10n.get('tunStatusInvalid'),
      'reasserting' => context.l10n.get('tunStatusReasserting'),
      'not_configured' => context.l10n.get('tunStatusNotConfigured'),
      'unsupported' => context.l10n.get('tunStatusUnsupported'),
      _ => context.l10n.get('tunStatusUnknown'),
    };
    final utun = status.utunInterfaces.isNotEmpty
        ? ' (${status.utunInterfaces.join(', ')})'
        : '';
    return '${context.l10n.get('tunStatus')}: $label$utun';
  }

  Future<void> _handleLogin() async {
    final isMfaStep = _sessionManager.status.value == SessionStatus.mfaRequired;
    LoginResult result;
    if (isMfaStep) {
      final mfaCode = _mfaCodeController.text.trim();
      if (mfaCode.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.get('mfaCodeMissing'))),
        );
        return;
      }
      result = await _sessionManager.verifyMfaCode(mfaCode);
    } else {
      final baseUrl = _baseUrlController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.get('loginMissingFields'))),
        );
        return;
      }
      await _sessionManager.setBaseUrl(baseUrl);
      result = await _sessionManager.login(
        username: username,
        password: password,
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    if (result.success && _sessionManager.isLoggedIn) {
      _passwordController.clear();
      _mfaCodeController.clear();
      final syncResult = await _syncService.syncNow(manual: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(syncResult.message)),
      );
    }
  }

  Future<void> _handleLogout() async {
    await _sessionManager.logout();
    _mfaCodeController.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.get('logoutSuccess'))),
    );
  }

  Future<void> _handleSyncNow() async {
    final result = await _syncService.syncNow(manual: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Widget _buildDesktopSyncCard(BuildContext context) {
    return ValueListenableBuilder<SessionStatus>(
      valueListenable: _sessionManager.status,
      builder: (context, status, _) {
        final isLoggedIn = status == SessionStatus.loggedIn;
        final isMfaRequired = status == SessionStatus.mfaRequired;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.get('accountLogin'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: _sessionManager.loading,
                    builder: (context, loading, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _baseUrlController,
                            decoration: InputDecoration(
                              labelText: context.l10n.get('serverAddress'),
                            ),
                            onSubmitted: (_) => _sessionManager
                                .setBaseUrl(_baseUrlController.text),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _usernameController,
                            enabled: !loading && !isLoggedIn && !isMfaRequired,
                            decoration: InputDecoration(
                              labelText: context.l10n.get('username'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            enabled: !loading && !isLoggedIn && !isMfaRequired,
                            decoration: InputDecoration(
                              labelText: context.l10n.get('password'),
                            ),
                          ),
                          if (isMfaRequired) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _mfaCodeController,
                              enabled: !loading && !isLoggedIn,
                              decoration: InputDecoration(
                                labelText: context.l10n.get('mfaCode'),
                                helperText: context.l10n.get('mfaRequiredHint'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: loading
                                    ? null
                                    : (isLoggedIn
                                        ? _handleLogout
                                        : _handleLogin),
                                icon: Icon(
                                  isLoggedIn
                                      ? Icons.logout
                                      : (isMfaRequired
                                          ? Icons.verified
                                          : Icons.login),
                                ),
                                label: Text(
                                  context.l10n.get(isLoggedIn
                                      ? 'logout'
                                      : (isMfaRequired
                                          ? 'verifyMfa'
                                          : 'login')),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ValueListenableBuilder<bool>(
                                valueListenable: _syncService.syncing,
                                builder: (context, syncing, _) {
                                  return ElevatedButton.icon(
                                    onPressed: isLoggedIn && !syncing
                                        ? _handleSyncNow
                                        : null,
                                    icon: syncing
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.sync),
                                    label: Text(
                                      syncing
                                          ? context.l10n.get('syncInProgress')
                                          : context.l10n.get('syncNow'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<String?>(
                            valueListenable: _sessionManager.lastError,
                            builder: (context, error, _) {
                              if (error == null || isLoggedIn) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                error,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12),
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          ValueListenableBuilder<SyncSummary>(
                            valueListenable: SyncStateStore.instance.summary,
                            builder: (context, summary, _) {
                              final lastSync = summary.lastSuccessAt != null
                                  ? _formatDateTime(summary.lastSuccessAt!)
                                  : context.l10n.get('never');
                              final metadata = summary.subscriptionMetadata;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${context.l10n.get('lastSyncTime')}: $lastSync',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    '${context.l10n.get('configVersion')}: ${summary.configVersion}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (metadata != null && metadata.isNotEmpty)
                                    Text(
                                      '${context.l10n.get('subscriptionMetadata')}: $metadata',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (summary.lastError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        summary.lastError!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (!isLoggedIn)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        context.l10n.get('syncNotLoggedIn'),
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _currentVersion() {
    final match = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(buildVersion);
    return match?.group(1) ?? '0.0.0';
  }

  Future<void> _onSyncConfig() async {
    addAppLog('开始同步配置...');
    try {
      await VpnConfig.load();
      addAppLog('✅ 已同步配置文件');
    } catch (e) {
      addAppLog('[错误] 同步失败: $e', level: LogLevel.error);
    }
  }

  Future<void> _onSaveConfig() async {
    addAppLog('开始保存配置...');
    try {
      final path = await VpnConfig.getConfigPath();
      await VpnConfig.saveToFile();
      addAppLog('✅ 配置已保存到: $path');
    } catch (e) {
      addAppLog('[错误] 保存失败: $e', level: LogLevel.error);
    }
  }

  Future<void> _onImportConfig() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.get('importConfig')),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '/path/to/backup.zip 或 vless://...',
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
    if (input == null || input.isEmpty) return;

    addAppLog('开始导入配置...');
    try {
      if (input.startsWith('vless://')) {
        if (!GlobalState.isUnlocked.value) {
          addAppLog('请先解锁再导入 VLESS 配置', level: LogLevel.warning);
          return;
        }
        final password = GlobalState.sudoPassword.value;
        if (password.isEmpty) {
          addAppLog('无法获取 sudo 密码', level: LogLevel.error);
          return;
        }
        final bundleId = await GlobalApplicationConfig.getBundleId();
        final profile = VpnConfig.parseVlessUri(input);
        await VpnConfig.generateFromVlessUri(
          vlessUri: input,
          password: password,
          bundleId: bundleId,
          setMessage: (msg) => addAppLog(msg),
          logMessage: (msg) => addAppLog(msg),
        );
        await VpnConfig.load();
        GlobalState.activeNodeName.value = '';
        GlobalState.lastImportedNodeName.value = profile.name;
        GlobalState.nodeListRevision.value++;
        addAppLog('✅ 已从 VLESS 链接导入配置');
        return;
      }

      final existingNames = VpnConfig.nodes.map((e) => e.name).toSet();
      final file = File(input);
      if (!await file.exists()) {
        addAppLog('备份文件不存在', level: LogLevel.error);
        return;
      }
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive) {
        final name = entry.name;
        String dest;
        if (name == 'vpn_nodes.json') {
          dest = await VpnConfig.getConfigPath();
        } else if (name.endsWith('.json')) {
          final prefix = await GlobalApplicationConfig.getXrayConfigPath();
          dest = '$prefix$name';
        } else if (name.endsWith('.plist') ||
            name.endsWith('.service') ||
            name.endsWith('.schtasks')) {
          dest = await GlobalApplicationConfig.getServicePath(name);
        } else {
          continue;
        }
        final out = File(dest);
        await out.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>);
      }
      await VpnConfig.load();
      GlobalState.activeNodeName.value = '';
      final imported = VpnConfig.nodes
          .map((e) => e.name)
          .firstWhere((name) => !existingNames.contains(name), orElse: () {
        return VpnConfig.nodes.isNotEmpty ? VpnConfig.nodes.first.name : '';
      });
      GlobalState.lastImportedNodeName.value = imported;
      GlobalState.nodeListRevision.value++;
      addAppLog('✅ 已导入配置');
    } catch (e) {
      addAppLog('[错误] 导入失败: $e', level: LogLevel.error);
    }
  }

  Future<void> _onExportConfig() async {
    addAppLog('开始导出配置...');
    try {
      final configPath = await VpnConfig.getConfigPath();
      final dir = File(configPath).parent.path;
      final backupPath =
          '$dir/vpn_backup_${DateTime.now().millisecondsSinceEpoch}.zip';

      final encoder = ZipFileEncoder();
      encoder.create(backupPath);
      encoder.addFile(File(configPath), 'vpn_nodes.json');
      for (final node in VpnConfig.nodes) {
        final cfg = File(node.configPath);
        if (await cfg.exists()) {
          encoder.addFile(cfg, cfg.uri.pathSegments.last);
        }
        final servicePath = await GlobalApplicationConfig.getServicePath(
          node.serviceName,
        );
        final svc = File(servicePath);
        if (await svc.exists()) {
          encoder.addFile(svc, svc.uri.pathSegments.last);
        }
      }
      encoder.close();
      addAppLog('✅ 配置已导出: $backupPath');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出到: $backupPath')),
      );
    } catch (e) {
      addAppLog('[错误] 导出失败: $e', level: LogLevel.error);
    }
  }

  Future<void> _onDeleteConfig() async {
    if (!GlobalState.isUnlocked.value) {
      addAppLog('请先解锁以删除配置', level: LogLevel.warning);
      return;
    }

    await VpnConfig.load();
    final nodes = List<VpnNode>.from(VpnConfig.nodes);
    if (nodes.isEmpty) {
      addAppLog('暂无可删除节点', level: LogLevel.warning);
      return;
    }
    if (!mounted) return;

    final selected = <String>{};
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(context.l10n.get('deleteConfig')),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: nodes
                        .map(
                          (node) => CheckboxListTile(
                            value: selected.contains(node.name),
                            title: Text(node.name),
                            subtitle: Text(node.countryCode.toUpperCase()),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (checked) {
                              setStateDialog(() {
                                if (checked == true) {
                                  selected.add(node.name);
                                } else {
                                  selected.remove(node.name);
                                }
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.get('cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.get('confirm')),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldDelete != true || selected.isEmpty) {
      addAppLog('未选择要删除的节点', level: LogLevel.warning);
      return;
    }

    try {
      var count = 0;
      for (final name in selected) {
        final node = nodes.firstWhere((n) => n.name == name);
        await VpnConfig.deleteNodeFiles(node);
        count++;
      }
      await VpnConfig.load();
      if (selected.contains(GlobalState.activeNodeName.value)) {
        GlobalState.activeNodeName.value = '';
      }
      GlobalState.nodeListRevision.value++;
      addAppLog('✅ 已删除 $count 个节点并更新配置');
    } catch (e) {
      addAppLog('[错误] 删除失败: $e', level: LogLevel.error);
    }
  }

  void _onInitXray() async {
    final isUnlocked = GlobalState.isUnlocked.value;

    if (!isUnlocked) {
      addAppLog('请先解锁以初始化 Xray', level: LogLevel.warning);
      return;
    }

    addAppLog('开始初始化 Xray...');
    try {
      final output = await NativeBridge.initXray();
      addAppLog(output);
    } catch (e) {
      addAppLog('[错误] $e', level: LogLevel.error);
    }
  }

  void _onUpdateXray() async {
    final isUnlocked = GlobalState.isUnlocked.value;

    if (!isUnlocked) {
      addAppLog('请先解锁以更新 Xray', level: LogLevel.warning);
      return;
    }

    addAppLog('开始更新 Xray Core...');
    try {
      final output = await NativeBridge.updateXrayCore();
      addAppLog(output);
      if (output.startsWith('info:')) {
        GlobalState.xrayUpdating.value = true;
        _startMonitorXrayProgress();
      }
    } catch (e) {
      addAppLog('[错误] $e', level: LogLevel.error);
    }
  }

  void _startMonitorXrayProgress() {
    _xrayMonitorTimer?.cancel();
    _xrayMonitorTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final running = await NativeBridge.isXrayDownloading();
      GlobalState.xrayUpdating.value = running;
      if (!running) {
        _xrayMonitorTimer?.cancel();
      }
    });
  }

  void _onResetAll() async {
    final isUnlocked = GlobalState.isUnlocked.value;
    final password = GlobalState.sudoPassword.value;

    if (!isUnlocked) {
      addAppLog('请先解锁以执行重置操作', level: LogLevel.warning);
      return;
    }

    addAppLog('开始重置配置与文件...');
    try {
      final result = await NativeBridge.resetXrayAndConfig(password);
      addAppLog(result);
    } catch (e) {
      addAppLog('[错误] 重置失败: $e', level: LogLevel.error);
    }
  }

  void _onToggleGlobalProxy(bool enabled) async {
    final isUnlocked = GlobalState.isUnlocked.value;
    final password = GlobalState.sudoPassword.value;
    if (!isUnlocked) {
      addAppLog('请先解锁以切换全局代理', level: LogLevel.warning);
      return;
    }
    setState(() => GlobalState.globalProxy.value = enabled);
    final msg = await NativeBridge.setSystemProxy(enabled, password);
    addAppLog('全局代理: ${enabled ? "开启" : "关闭"}');
    addAppLog('[system proxy] $msg');
  }

  void _onToggleTunSettings(bool enabled) {
    final isUnlocked = GlobalState.isUnlocked.value;
    if (!isUnlocked) {
      addAppLog('请先解锁以切换 TUN 设置', level: LogLevel.warning);
      return;
    }
    _togglePacketTunnel(enabled);
  }

  void _onToggleDnsOverTls(bool enabled) {
    setState(() => TunDnsConfig.dotEnabled.value = enabled);
    addAppLog('DNS over TLS: ${enabled ? "开启" : "关闭"}');
  }

  void _onToggleTunnelProxyMode(bool tunnelMode) {
    final isUnlocked = GlobalState.isUnlocked.value;
    if (!isUnlocked) {
      addAppLog('请先解锁以切换连接模式', level: LogLevel.warning);
      return;
    }
    GlobalState.connectionMode.value = tunnelMode ? 'VPN' : '仅代理';
    if (tunnelMode) {
      _onToggleGlobalProxy(false);
      if (!GlobalState.tunSettingsEnabled.value) {
        _onToggleTunSettings(true);
      }
      addAppLog('模式切换: 隧道模式');
    } else {
      if (GlobalState.tunSettingsEnabled.value) {
        _onToggleTunSettings(false);
      }
      _onToggleGlobalProxy(true);
      addAppLog('模式切换: 代理模式');
    }
  }

  Future<void> _togglePacketTunnel(bool enabled) async {
    setState(() => _tunBusy = true);
    final msg = enabled
        ? await NativeBridge.startPacketTunnel()
        : await NativeBridge.stopPacketTunnel();
    addAppLog('[packet tunnel] $msg');
    await _refreshTunStatus();
    if (!mounted) return;
    setState(() => _tunBusy = false);
  }

  Future<void> _refreshTunStatus() async {
    final status = await NativeBridge.getPacketTunnelStatus();
    if (!mounted) return;
    final connected =
        status.status == 'connected' || status.status == 'connecting';
    setState(() {
      _tunStatus = status;
      GlobalState.tunSettingsEnabled.value = connected;
    });
  }

  void _onCheckUpdate() {
    addAppLog('开始检查更新...');
    UpdateChecker.manualCheck(
      context,
      currentVersion: _currentVersion(),
      channel: GlobalState.useDailyBuild.value
          ? UpdateChannel.latest
          : UpdateChannel.stable,
    );
  }

  Future<void> _toggleRuntimeMcp(bool enabled) async {
    final ok = enabled
        ? await _runtimeMcpService.start()
        : await _runtimeMcpService.stop();
    if (!mounted) return;
    final msg = ok
        ? (enabled
            ? context.l10n.get('runtimeMcpStarted')
            : context.l10n.get('runtimeMcpStopped'))
        : (_runtimeMcpService.lastError.value ??
            context.l10n.get('runtimeMcpToggleFailed'));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[100],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.get('settingsCenter'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 16),
            _buildSection(context.l10n.get('desktopSync'), [
              _buildDesktopSyncCard(context),
            ]),
            ValueListenableBuilder<bool>(
              valueListenable: GlobalState.isUnlocked,
              builder: (context, isUnlocked, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(context.l10n.get('xrayMgmt'), [
                      _buildButton(
                        icon: Icons.build,
                        label: context.l10n.get('initXray'),
                        onPressed: isUnlocked ? _onInitXray : null,
                      ),
                      _buildButton(
                        icon: Icons.update,
                        label: context.l10n.get('updateXray'),
                        onPressed: isUnlocked ? _onUpdateXray : null,
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: GlobalState.xrayUpdating,
                        builder: (context, downloading, _) {
                          return downloading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: LinearProgressIndicator(),
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                      _buildButton(
                        icon: Icons.sync,
                        label: context.l10n.get('syncConfig'),
                        onPressed: isUnlocked ? _onSyncConfig : null,
                      ),
                      _buildButton(
                        icon: Icons.upload_file,
                        label: context.l10n.get('importConfig'),
                        onPressed: _onImportConfig,
                      ),
                      _buildButton(
                        icon: Icons.download,
                        label: context.l10n.get('exportConfig'),
                        onPressed: _onExportConfig,
                      ),
                      _buildButton(
                        icon: Icons.delete_forever,
                        label: context.l10n.get('deleteConfig'),
                        style: _menuButtonStyle.copyWith(
                          backgroundColor:
                              WidgetStateProperty.all(Colors.red[400]),
                        ),
                        onPressed: isUnlocked ? _onDeleteConfig : null,
                      ),
                      _buildButton(
                        icon: Icons.save,
                        label: context.l10n.get('saveConfig'),
                        onPressed: _onSaveConfig,
                      ),
                    ]),
                    _buildSection(context.l10n.get('configMgmt'), [
                      _buildButton(
                        icon: Icons.security,
                        label: context.l10n.get('permissionGuide'),
                        onPressed: _showPermissionGuide,
                      ),
                      _buildButton(
                        icon: Icons.restore,
                        label: context.l10n.get('resetAll'),
                        style: _menuButtonStyle.copyWith(
                          backgroundColor:
                              WidgetStateProperty.all(Colors.red[400]),
                        ),
                        onPressed: isUnlocked ? _onResetAll : null,
                      ),
                    ]),
                    _buildSection(context.l10n.get('advancedConfig'), [
                      _buildButton(
                        icon: Icons.dns,
                        label: context.l10n.get('dnsConfig'),
                        onPressed: _showDnsDialog,
                      ),
                      ValueListenableBuilder<String>(
                        valueListenable: GlobalState.connectionMode,
                        builder: (context, mode, _) {
                          final vpnMode = mode == 'VPN';
                          return SizedBox(
                            width: double.infinity,
                            child: SwitchListTile(
                              secondary: const Icon(Icons.science),
                              title: Text(
                                context.l10n.get('tunnelProxyMode'),
                                style: _menuTextStyle,
                              ),
                              subtitle: Text(
                                vpnMode
                                    ? context.l10n.get('vpn')
                                    : context.l10n.get('proxyOnly'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              value: vpnMode,
                              onChanged: _tunBusy || !isUnlocked
                                  ? null
                                  : _onToggleTunnelProxyMode,
                            ),
                          );
                        },
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: SwitchListTile(
                          value: TunDnsConfig.dotEnabled.value,
                          onChanged: _onToggleDnsOverTls,
                          title: Text(
                            context.l10n.get('dnsOverTls'),
                            style: _menuTextStyle,
                          ),
                          subtitle: Text(
                            context.l10n.get('dnsOverTlsHint'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      _buildButton(
                        icon: Icons.dns_outlined,
                        label: context.l10n.get('tunDnsConfig'),
                        onPressed: _showTunDnsDialog,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, top: 4),
                        child: Text(
                          _formatTunStatusText(context, _tunStatus),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _runtimeMcpService.available,
                        builder: (context, available, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: _runtimeMcpService.running,
                            builder: (context, running, __) {
                              return ValueListenableBuilder<bool>(
                                valueListenable: _runtimeMcpService.loading,
                                builder: (context, loading, ___) {
                                  final subtitle = available
                                      ? (running
                                          ? context.l10n
                                              .get('runtimeMcpStatusRunning')
                                          : context.l10n
                                              .get('runtimeMcpStatusStopped'))
                                      : context.l10n
                                          .get('runtimeMcpStatusUnavailable');
                                  return SizedBox(
                                    width: double.infinity,
                                    child: SwitchListTile(
                                      value: running,
                                      onChanged: available && !loading
                                          ? _toggleRuntimeMcp
                                          : null,
                                      title: Text(
                                        context.l10n.get('runtimeMcpServer'),
                                        style: _menuTextStyle,
                                      ),
                                      subtitle: Text(
                                        loading
                                            ? context.l10n
                                                .get('runtimeMcpStatusLoading')
                                            : subtitle,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ]),
                    if (!isUnlocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          context.l10n.get('unlockFirst'),
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                  ],
                );
              },
            ),
            const Divider(height: 32),
            SwitchListTile(
              secondary: const Icon(Icons.bolt),
              title:
                  Text(context.l10n.get('upgradeDaily'), style: _menuTextStyle),
              value: GlobalState.useDailyBuild.value,
              onChanged: (v) {
                setState(() => GlobalState.useDailyBuild.value = v);
                addAppLog('升级 DailyBuild: ${v ? "开启" : "关闭"}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.stacked_line_chart),
              title: Text(context.l10n.get('viewCollected'),
                  style: _menuTextStyle),
              trailing: Switch(
                value: GlobalState.telemetryEnabled.value,
                onChanged: (v) {
                  setState(() => GlobalState.telemetryEnabled.value = v);
                  addAppLog('Telemetry: ${v ? "开启" : "关闭"}');
                },
              ),
              onTap: _showTelemetryData,
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title:
                  Text(context.l10n.get('checkUpdate'), style: _menuTextStyle),
              onTap: _onCheckUpdate,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _xrayMonitorTimer?.cancel();
    _sessionManager.baseUrl.removeListener(_syncBaseUrlFromSession);
    _sessionManager.currentUser.removeListener(_syncUsernameFromSession);
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  void _showDnsDialog() {
    final dns1Controller = TextEditingController(text: DnsConfig.dns1.value);
    final dns2Controller = TextEditingController(text: DnsConfig.dns2.value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.get('dnsConfig')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dns1Controller,
              decoration:
                  InputDecoration(labelText: context.l10n.get('primaryDns')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dns2Controller,
              decoration:
                  InputDecoration(labelText: context.l10n.get('secondaryDns')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.get('cancel')),
          ),
          TextButton(
            onPressed: () {
              DnsConfig.dns1.value = dns1Controller.text.trim();
              DnsConfig.dns2.value = dns2Controller.text.trim();
              Navigator.pop(context);
            },
            child: Text(context.l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showTunDnsDialog() {
    final dns1Controller = TextEditingController(text: TunDnsConfig.dns1.value);
    final dns2Controller = TextEditingController(text: TunDnsConfig.dns2.value);
    final tlsNameController =
        TextEditingController(text: TunDnsConfig.tlsServerName.value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.get('tunDnsConfig')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dns1Controller,
              decoration:
                  InputDecoration(labelText: context.l10n.get('primaryDns')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dns2Controller,
              decoration:
                  InputDecoration(labelText: context.l10n.get('secondaryDns')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tlsNameController,
              decoration: InputDecoration(
                labelText: context.l10n.get('dnsTlsServerName'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.get('cancel')),
          ),
          TextButton(
            onPressed: () {
              TunDnsConfig.dns1.value = dns1Controller.text.trim();
              TunDnsConfig.dns2.value = dns2Controller.text.trim();
              TunDnsConfig.tlsServerName.value = tlsNameController.text.trim();
              Navigator.pop(context);
            },
            child: Text(context.l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showTelemetryData() {
    final data = TelemetryService.collectData(appVersion: buildVersion);
    final json = const JsonEncoder.withIndent('  ').convert(data);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.get('collectedData')),
        content: SingleChildScrollView(
          child: SelectableText(json),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.get('close')),
          ),
        ],
      ),
    );
  }

  void _showPermissionGuide() {
    if (GlobalState.permissionGuideDone.value) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.get('permissionGuide')),
          content: Text(context.l10n.get('permissionFinished')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.get('close')),
            ),
          ],
        ),
      );
      return;
    }

    const text =
        '''1. 允许 ~/Library/Application Support/<bundle-id>/ 目录读写
2. 允许启动和停止 plist 服务
3. 允许修改系统代理与 DNS 设置''';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.get('permissionGuide')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.get('permissionGuideIntro')),
              const SizedBox(height: 8),
              const SelectableText(text),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _openSecurityPage,
                child: Text(context.l10n.get('openPrivacy')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              GlobalState.permissionGuideDone.value = true;
              Navigator.pop(context);
            },
            child: Text(context.l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _openSecurityPage() {
    if (Platform.isMacOS) {
      Process.run(
          'open', ['x-apple.systempreferences:com.apple.preference.security']);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', 'ms-settings:privacy']);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', ['settings://privacy']);
    }
  }
}
