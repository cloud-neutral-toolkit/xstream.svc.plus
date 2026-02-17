import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../utils/global_config.dart'
    show GlobalState, buildVersion, DnsConfig, TunDnsConfig;
import '../../utils/native_bridge.dart';
import '../l10n/app_localizations.dart';
import '../../services/vpn_config_service.dart';
import '../../services/update/update_checker.dart';
import '../../services/update/update_platform.dart';
import '../../services/telemetry/telemetry_service.dart';
import '../../services/session/session_manager.dart';
import '../../services/sync/desktop_sync_service.dart';
import '../../services/sync/sync_state.dart';
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

  void _onGenerateDefaultNodes() async {
    final isUnlocked = GlobalState.isUnlocked.value;
    final password = GlobalState.sudoPassword.value;

    if (!isUnlocked) {
      addAppLog('请先解锁以执行生成操作', level: LogLevel.warning);
      return;
    }

    addAppLog('开始生成默认节点...');
    await VpnConfig.generateDefaultNodes(
      password: password,
      setMessage: (msg) => addAppLog(msg),
      logMessage: (msg) => addAppLog(msg),
    );
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
                    ]),
                    _buildSection(context.l10n.get('configMgmt'), [
                      _buildButton(
                        icon: Icons.settings,
                        label: context.l10n.get('genDefaultNodes'),
                        onPressed: isUnlocked ? _onGenerateDefaultNodes : null,
                      ),
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
                      SizedBox(
                        width: double.infinity,
                        child: SwitchListTile(
                          value: GlobalState.globalProxy.value,
                          onChanged: _onToggleGlobalProxy,
                          title: Text(
                            context.l10n.get('globalProxy'),
                            style: _menuTextStyle,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: SwitchListTile(
                          value: GlobalState.tunSettingsEnabled.value,
                          onChanged: _tunBusy ? null : _onToggleTunSettings,
                          title: Text(
                            context.l10n.get('tunSettings'),
                            style: _menuTextStyle,
                          ),
                        ),
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
                    ]),
                    _buildSection(context.l10n.get('experimentalFeatures'), [
                      SizedBox(
                        width: double.infinity,
                        child: SwitchListTile(
                          secondary: const Icon(Icons.science),
                          title: Text(context.l10n.get('tunnelProxyMode'),
                              style: _menuTextStyle),
                          value: GlobalState.tunnelProxyEnabled.value,
                          onChanged: (v) {
                            setState(
                                () => GlobalState.tunnelProxyEnabled.value = v);
                          },
                        ),
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
        '''1. 允许 /opt/homebrew/、/Library/LaunchDaemons/、~/Library/Application Support/ 目录读写
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
