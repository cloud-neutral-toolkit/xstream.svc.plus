import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import '../../utils/global_config.dart'
    show GlobalState, DnsConfig, GlobalApplicationConfig, XhttpAdvancedConfig;
import '../../utils/native_bridge.dart';
import '../../services/app_version_service.dart';
import '../l10n/app_localizations.dart';
import '../../services/vpn_config_service.dart';
import '../../services/telemetry/telemetry_service.dart';
import '../../services/session/session_manager.dart';
import '../../services/mcp/runtime_mcp_service.dart';
import '../../utils/app_logger.dart';
import '../screens/about_screen.dart';
import '../screens/help_screen.dart';
import '../screens/logs_screen.dart';
import '../widgets/permission_guide_dialog.dart';
import '../widgets/log_console.dart' show LogLevel;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PacketTunnelStatus _tunStatus =
      const PacketTunnelStatus(status: 'unknown', utunInterfaces: []);

  final SessionManager _sessionManager = SessionManager.instance;
  final RuntimeMcpService _runtimeMcpService = RuntimeMcpService.instance;
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mfaCodeController = TextEditingController();
  String _draftXhttpMode = XhttpAdvancedConfig.mode.value;
  Set<String> _draftXhttpAlpn = <String>{...XhttpAdvancedConfig.alpn.value};
  bool _xhttpAdvancedDirty = false;

  static const TextStyle _menuTextStyle = TextStyle(fontSize: 14);
  static final ButtonStyle _menuButtonStyle = ElevatedButton.styleFrom(
    minimumSize: const Size.fromHeight(36),
    textStyle: _menuTextStyle,
  );

  @override
  void initState() {
    super.initState();
    _loadXhttpAdvancedDraft();
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

  Future<void> _openHelpPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HelpScreen(
          breadcrumbItems: [
            context.l10n.get('settings'),
            context.l10n.get('help'),
          ],
        ),
      ),
    );
  }

  Future<void> _openAboutPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AboutScreen(
          breadcrumbItems: [
            context.l10n.get('settings'),
            context.l10n.get('about'),
          ],
        ),
      ),
    );
  }

  Future<void> _openLogsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LogsScreen(
          breadcrumbItems: [
            context.l10n.get('settings'),
            context.l10n.get('logs'),
          ],
        ),
      ),
    );
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

  Future<void> _prepareImportedNodeForIos(String nodeName) async {
    if (!Platform.isIOS) return;
    final targetName = nodeName.trim();
    if (targetName.isEmpty) return;
    addAppLog(await NativeBridge.prepareNodeForTunnel(targetName));
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
        final bundleId = await GlobalApplicationConfig.getBundleId();
        final profile = VpnConfig.parseVlessUri(input);
        await VpnConfig.generateFromVlessUri(
          vlessUri: input,
          password: '',
          bundleId: bundleId,
          setMessage: (msg) => addAppLog(msg),
          logMessage: (msg) => addAppLog(msg),
        );
        await VpnConfig.load();
        GlobalState.activeNodeName.value = '';
        GlobalState.lastImportedNodeName.value = profile.name;
        GlobalState.nodeListRevision.value++;
        addAppLog('✅ 已从 VLESS 链接导入配置');
        await _prepareImportedNodeForIos(profile.name);
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
      await _prepareImportedNodeForIos(imported);
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

  void _onResetAll() async {
    addAppLog('开始重置配置与文件...');
    try {
      final result = await NativeBridge.resetXrayAndConfig('');
      addAppLog(result);
    } catch (e) {
      addAppLog('[错误] 重置失败: $e', level: LogLevel.error);
    }
  }

  void _onToggleDnsOverHttps(bool enabled) {
    setState(() => DnsConfig.setDohEnabled(enabled));
    addAppLog('代理 DNS / DoH: ${enabled ? "开启" : "关闭"}');
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

  void _loadXhttpAdvancedDraft() {
    _draftXhttpMode = XhttpAdvancedConfig.mode.value;
    _draftXhttpAlpn = <String>{...XhttpAdvancedConfig.alpn.value};
    _xhttpAdvancedDirty = false;
  }

  void _setDraftXhttpMode(String value) {
    if (_draftXhttpMode == value) return;
    setState(() {
      _draftXhttpMode = value;
      _xhttpAdvancedDirty = true;
    });
  }

  void _toggleDraftXhttpAlpn(String value, bool enabled) {
    final next = <String>{..._draftXhttpAlpn};
    if (enabled) {
      next.add(value);
    } else {
      next.remove(value);
    }
    final changed = next.length != _draftXhttpAlpn.length ||
        next.any((item) => !_draftXhttpAlpn.contains(item));
    if (!changed) return;
    setState(() {
      _draftXhttpAlpn = next;
      _xhttpAdvancedDirty = true;
    });
  }

  void _resetXhttpAdvancedDraft() {
    setState(() {
      _loadXhttpAdvancedDraft();
    });
  }

  void _saveAndApplyXhttpAdvanced() {
    final orderedAlpn = <String>[
      for (final candidate in XhttpAdvancedConfig.allowedAlpn)
        if (_draftXhttpAlpn.contains(candidate)) candidate,
    ];
    XhttpAdvancedConfig.setMode(_draftXhttpMode);
    XhttpAdvancedConfig.setAlpn(orderedAlpn);
    setState(() {
      _xhttpAdvancedDirty = false;
    });
    addAppLog(
      'XHTTP advanced config saved: '
      'mode=${XhttpAdvancedConfig.mode.value}, '
      'alpn=${XhttpAdvancedConfig.alpn.value.join(",")}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.get('xhttpSavedApplied'))),
    );
  }

  Widget _buildXhttpAdvancedConfig(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.get('xhttpAdvancedTitle'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.get('xhttpAdvancedHint'),
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.get('xhttpModeLabel'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              DropdownButton<String>(
                value: _draftXhttpMode,
                items: [
                  DropdownMenuItem(
                    value: XhttpAdvancedConfig.modeStreamUp,
                    child: Text(context.l10n.get('xhttpModeStreamUp')),
                  ),
                  DropdownMenuItem(
                    value: XhttpAdvancedConfig.modeAuto,
                    child: Text(context.l10n.get('xhttpModeAuto')),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _setDraftXhttpMode(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.get('xhttpAlpnLabel'),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: Text(context.l10n.get('xhttpAlpnH3')),
                selected: _draftXhttpAlpn.contains(XhttpAdvancedConfig.alpnH3),
                onSelected: (enabled) => _toggleDraftXhttpAlpn(
                  XhttpAdvancedConfig.alpnH3,
                  enabled,
                ),
              ),
              FilterChip(
                label: Text(context.l10n.get('xhttpAlpnH2')),
                selected: _draftXhttpAlpn.contains(XhttpAdvancedConfig.alpnH2),
                onSelected: (enabled) => _toggleDraftXhttpAlpn(
                  XhttpAdvancedConfig.alpnH2,
                  enabled,
                ),
              ),
              FilterChip(
                label: Text(context.l10n.get('xhttpAlpnHttp11')),
                selected: _draftXhttpAlpn.contains(
                  XhttpAdvancedConfig.alpnHttp11,
                ),
                onSelected: (enabled) => _toggleDraftXhttpAlpn(
                  XhttpAdvancedConfig.alpnHttp11,
                  enabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed:
                    _xhttpAdvancedDirty ? _resetXhttpAdvancedDraft : null,
                child: Text(context.l10n.get('xhttpResetDraft')),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed:
                    _xhttpAdvancedDirty ? _saveAndApplyXhttpAdvanced : null,
                icon: const Icon(Icons.save),
                label: Text(context.l10n.get('xhttpSaveApply')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSettingsView(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.get('settingsCenter'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.get('advancedConfig'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            // Sniffing / Fallback toggles card
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: GlobalState.sniffingEnabled,
                    builder: (context, enabled, _) {
                      return SwitchListTile(
                        value: enabled,
                        onChanged: (value) {
                          setState(
                              () => GlobalState.sniffingEnabled.value = value);
                          addAppLog('嗅探: ${value ? "开启" : "关闭"}');
                        },
                        title: Text(context.l10n.get('sniffing')),
                        subtitle: Text(
                          context.l10n.get('sniffingHint'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // System Proxy Ports card
            Text(
              context.l10n.get('proxySettings'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(
                            text: GlobalState.socksPort.value,
                          ),
                          decoration: InputDecoration(
                            labelText: context.l10n.get('socksPort'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => GlobalState.socksPort.value = v,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(
                            text: GlobalState.httpPort.value,
                          ),
                          decoration: InputDecoration(
                            labelText: context.l10n.get('httpPort'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => GlobalState.httpPort.value = v,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Config management buttons
            Text(
              context.l10n.get('configMgmt'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: Text(context.l10n.get('syncConfig')),
                    onTap: _onSyncConfig,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: Text(context.l10n.get('importConfig')),
                    onTap: _onImportConfig,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: Text(context.l10n.get('exportConfig')),
                    onTap: _onExportConfig,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red[400]),
                    title: Text(context.l10n.get('deleteConfig'),
                        style: TextStyle(color: Colors.red[400])),
                    onTap: _onDeleteConfig,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // DNS & Tunnel
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dns),
                    title: Text(context.l10n.get('proxyDnsConfig')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showProxyDnsDialog,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(context.l10n.get('directDnsConfig')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showDirectDnsDialog,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.vpn_lock),
                    value: DnsConfig.dohEnabled,
                    onChanged: _onToggleDnsOverHttps,
                    title: Text(context.l10n.get('dnsOverHttps')),
                    subtitle: Text(
                      context.l10n.get('dnsOverHttpsHint'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: _buildXhttpAdvancedConfig(context),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  if (!Platform.isIOS)
                    ValueListenableBuilder<bool>(
                      valueListenable: GlobalState.tunnelProxyEnabled,
                      builder: (context, enabled, _) {
                        return SwitchListTile(
                          value: enabled,
                          onChanged: (value) {
                            setState(() {
                              GlobalState.setTunnelModeEnabled(value);
                            });
                            addAppLog('系统级网络隧道: ${value ? "开启" : "关闭"}');
                            _refreshTunStatus();
                          },
                          title: const Text('隧道模式',
                              style: TextStyle(fontSize: 16)),
                          subtitle: const Text(
                            '启用系统级网络隧道',
                            style: TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    )
                  else
                    const ListTile(
                      leading: Icon(Icons.vpn_lock),
                      title: Text('Packet Tunnel'),
                      subtitle: Text('iOS 默认使用系统级 Packet Tunnel'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Runtime MCP Server
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: ValueListenableBuilder<bool>(
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
                                  ? context.l10n.get('runtimeMcpStatusRunning')
                                  : context.l10n.get('runtimeMcpStatusStopped'))
                              : context.l10n.get('runtimeMcpStatusUnavailable');
                          return SwitchListTile(
                            value: running,
                            onChanged: available && !loading
                                ? _toggleRuntimeMcp
                                : null,
                            title: Text(context.l10n.get('runtimeMcpServer'),
                                style: const TextStyle(fontSize: 16)),
                            subtitle: Text(
                              loading
                                  ? context.l10n.get('runtimeMcpStatusLoading')
                                  : subtitle,
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // About / Updates
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(context.l10n.get('logs')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openLogsPage,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text(context.l10n.get('help')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openHelpPage,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(context.l10n.get('about')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openAboutPage,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Permission Guide & Reset
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.security),
                label: Text(context.l10n.get('permissionGuide'),
                    style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.05),
                  foregroundColor: Colors.deepPurple,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _showPermissionGuide,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.restore),
                label: Text(context.l10n.get('resetAll'),
                    style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                   backgroundColor: Theme.of(context).colorScheme.error,
                   foregroundColor: Theme.of(context).colorScheme.onError,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _onResetAll,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSettingsView(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSection(context.l10n.get('xrayMgmt'), [
                  _buildButton(
                    icon: Icons.sync,
                    label: context.l10n.get('syncConfig'),
                    onPressed: _onSyncConfig,
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
                      backgroundColor: WidgetStateProperty.all(Colors.red[400]),
                    ),
                    onPressed: _onDeleteConfig,
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
                      backgroundColor: WidgetStateProperty.all(Colors.red[400]),
                    ),
                    onPressed: _onResetAll,
                  ),
                ]),
                _buildSection(context.l10n.get('advancedConfig'), [
                  _buildButton(
                    icon: Icons.dns,
                    label: context.l10n.get('proxyDnsConfig'),
                    onPressed: _showProxyDnsDialog,
                  ),
                  _buildButton(
                    icon: Icons.dns_outlined,
                    label: context.l10n.get('directDnsConfig'),
                    onPressed: _showDirectDnsDialog,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: SwitchListTile(
                      value: DnsConfig.dohEnabled,
                      onChanged: _onToggleDnsOverHttps,
                      title: Text(
                        context.l10n.get('dnsOverHttps'),
                        style: _menuTextStyle,
                      ),
                      subtitle: Text(
                        context.l10n.get('dnsOverHttpsHint'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: _buildXhttpAdvancedConfig(context),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: GlobalState.socksProxyEnabled,
                    builder: (context, enabled, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SwitchListTile(
                          value: enabled,
                          onChanged: (value) {
                            setState(() =>
                                GlobalState.socksProxyEnabled.value = value);
                            addAppLog('SOCKS 代理: ${value ? "开启" : "关闭"}');
                          },
                          title: const Text(
                            'SOCKS 代理',
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: const Text(
                            '启用 SOCKS 代理服务 (127.0.0.1:1080)',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: GlobalState.httpProxyEnabled,
                    builder: (context, enabled, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SwitchListTile(
                          value: enabled,
                          onChanged: (value) {
                            setState(() =>
                                GlobalState.httpProxyEnabled.value = value);
                            addAppLog('HTTP 代理: ${value ? "开启" : "关闭"}');
                          },
                          title: const Text(
                            'HTTP 代理',
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: const Text(
                            '启用 HTTP 代理服务 (127.0.0.1:1081)',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: GlobalState.tunnelProxyEnabled,
                    builder: (context, enabled, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SwitchListTile(
                          value: enabled,
                          onChanged: (value) {
                            setState(() {
                              GlobalState.setTunnelModeEnabled(value);
                            });
                            addAppLog(
                              '系统级网络隧道: ${value ? "开启" : "关闭"}',
                            );
                            _refreshTunStatus();
                          },
                          title: const Text(
                            '隧道模式',
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: const Text(
                            '启用系统级网络隧道',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, top: 4),
                    child: Text(
                      _formatTunStatusText(context, _tunStatus),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              ],
            ),
            const Divider(height: 32),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        if (isMobile) {
          return _buildMobileSettingsView(context);
        }
        return _buildDesktopSettingsView(context);
      },
    );
  }

  @override
  void dispose() {
    _sessionManager.baseUrl.removeListener(_syncBaseUrlFromSession);
    _sessionManager.currentUser.removeListener(_syncUsernameFromSession);
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  void _showProxyDnsDialog() {
    final dns1Controller =
        TextEditingController(text: DnsConfig.proxyDns1.value);
    final dns2Controller =
        TextEditingController(text: DnsConfig.proxyDns2.value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.get('proxyDnsConfig')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                DnsConfig.dohEnabled
                    ? context.l10n.get('dnsDialogHintDoh')
                    : context.l10n.get('dnsDialogHintPlain'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
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
              DnsConfig.updateProxyServers(
                primary: dns1Controller.text,
                secondary: dns2Controller.text,
              );
              Navigator.pop(context);
            },
            child: Text(context.l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showDirectDnsDialog() {
    final dns1Controller =
        TextEditingController(text: DnsConfig.directDns1.value);
    final dns2Controller =
        TextEditingController(text: DnsConfig.directDns2.value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.get('directDnsConfig')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.get('dnsDialogHintDirect'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
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
              DnsConfig.updateDirectServers(
                primary: dns1Controller.text,
                secondary: dns2Controller.text,
              );
              Navigator.pop(context);
            },
            child: Text(context.l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showTelemetryData() {
    final data =
        TelemetryService.collectData(appVersion: AppVersionService.shortLabel);
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

  Future<void> _showPermissionGuide() async {
    await showPermissionGuideDialog(context);
  }
}
