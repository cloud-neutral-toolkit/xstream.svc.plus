// lib/screens/home_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';

import '../../utils/native_bridge.dart';
import '../../utils/global_config.dart'
    show GlobalState, GlobalApplicationConfig;
import '../../utils/app_logger.dart';
import '../l10n/app_localizations.dart';
import '../../services/vpn_config_service.dart';
import '../widgets/log_console.dart' show LogLevel;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _activeNode = '';
  List<VpnNode> vpnNodes = [];
  final Set<String> _selectedNodeNames = {};

  void _showMessage(String msg, {Color? bgColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bgColor));
  }

  @override
  void initState() {
    super.initState();
    _initializeConfig();
  }

  Future<void> _initializeConfig() async {
    await VpnConfig.load();
    if (!mounted) return;
    setState(() {
      vpnNodes = VpnConfig.nodes;
      _activeNode = GlobalState.activeNodeName.value;
    });
  }

  Future<void> _toggleNode(VpnNode node) async {
    final nodeName = node.name.trim();
    if (nodeName.isEmpty) return;

    // start or stop node service

    if (_activeNode == nodeName) {
      final msg = await NativeBridge.stopNodeService(nodeName);
      if (!mounted) return;
      setState(() => _activeNode = '');
      GlobalState.activeNodeName.value = '';
      _showMessage(msg);
    } else {
      if (_activeNode.isNotEmpty) {
        await NativeBridge.stopNodeService(_activeNode);
        if (!mounted) return;
        GlobalState.activeNodeName.value = '';
      }

      final isRunning = await NativeBridge.checkNodeStatus(nodeName);
      if (!mounted) return;
      if (isRunning) {
        setState(() => _activeNode = nodeName);
        GlobalState.activeNodeName.value = nodeName;
        _showMessage(context.l10n.get('serviceRunning'));
        return;
      }

      final msg = await NativeBridge.startNodeService(nodeName);
      if (!mounted) return;
      setState(() => _activeNode = nodeName);
      GlobalState.activeNodeName.value = nodeName;
      _showMessage(msg);
    }
  }

  Future<void> onSyncConfig() async {
    addAppLog('开始同步配置...');
    try {
      await VpnConfig.load();
      addAppLog('✅ 已同步配置文件');
      if (!mounted) return;
      setState(() {
        vpnNodes = VpnConfig.nodes;
      });
    } catch (e) {
      addAppLog('[错误] 同步失败: $e', level: LogLevel.error);
    }
  }

  Future<void> onDeleteConfig() async {
    final isUnlocked = GlobalState.isUnlocked.value;
    if (!isUnlocked) {
      addAppLog('请先解锁以删除配置', level: LogLevel.warning);
      return;
    }

    final names = _selectedNodeNames.toList();
    if (names.isEmpty) {
      addAppLog('未选择要删除的节点', level: LogLevel.warning);
      return;
    }

    addAppLog('开始删除配置...');
    try {
      int count = 0;
      for (final name in names) {
        final node = vpnNodes.firstWhere((n) => n.name == name);
        await VpnConfig.deleteNodeFiles(node);
        count++;
      }
      await VpnConfig.load();
      addAppLog('✅ 已删除 $count 个节点并更新配置');
      if (!mounted) return;
      setState(() {
        vpnNodes = VpnConfig.nodes;
        if (names.contains(_activeNode)) {
          _activeNode = '';
          GlobalState.activeNodeName.value = '';
        }
        _selectedNodeNames.clear();
      });
    } catch (e) {
      addAppLog('[错误] 删除失败: $e', level: LogLevel.error);
    }
  }

  Future<void> onSaveConfig() async {
    addAppLog('开始保存配置...');
    try {
      final path = await VpnConfig.getConfigPath();
      await VpnConfig.saveToFile();
      addAppLog('✅ 配置已保存到: $path');
    } catch (e) {
      addAppLog('[错误] 保存失败: $e', level: LogLevel.error);
    }
  }

  Future<void> onImportConfig() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.get('importConfig')),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '/path/to/backup.zip'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.get('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(context.l10n.get('confirm')),
            ),
          ],
        );
      },
    );
    if (path == null || path.trim().isEmpty) return;
    addAppLog('开始导入配置...');
    try {
      final file = File(path.trim());
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
      if (!mounted) return;
      setState(() {
        vpnNodes = VpnConfig.nodes;
        _selectedNodeNames.clear();
        _activeNode = '';
      });
      GlobalState.activeNodeName.value = '';
      addAppLog('✅ 已导入配置');
    } catch (e) {
      addAppLog('[错误] 导入失败: $e', level: LogLevel.error);
    }
  }

  Future<void> onExportConfig() async {
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
      _showMessage('已导出到: $backupPath');
    } catch (e) {
      addAppLog('[错误] 导出失败: $e', level: LogLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.isUnlocked,
      builder: (context, isUnlocked, _) {
        final content = vpnNodes.isEmpty
            ? Center(child: Text(context.l10n.get('noNodes')))
            : ListView.builder(
                itemCount: vpnNodes.length,
                itemBuilder: (context, index) {
                  final node = vpnNodes[index];
                  final isActive = _activeNode == node.name;
                  final isSelected = _selectedNodeNames.contains(node.name);
                  return ListTile(
                    title: Text(
                      '${node.countryCode.toUpperCase()} | ${node.name}',
                    ),
                    subtitle: Text(
                      '${node.protocol.toUpperCase()} | ${node.transport} | ${node.security}',
                    ),
                    leading: isUnlocked
                        ? Checkbox(
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedNodeNames.add(node.name);
                                } else {
                                  _selectedNodeNames.remove(node.name);
                                }
                              });
                            },
                          )
                        : null,
                    trailing: IconButton(
                      icon: Icon(
                        isActive ? Icons.stop_circle : Icons.play_circle_fill,
                        color: isActive ? Colors.red : Colors.green,
                      ),
                      onPressed: isUnlocked ? () => _toggleNode(node) : null,
                    ),
                  );
                },
              );

        return Stack(
          children: [
            content,
            Positioned(
              bottom: 16,
              // Leave space for the main FloatingActionButton
              right: 88,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: "sync",
                    onPressed: isUnlocked ? onSyncConfig : null,
                    tooltip: context.l10n.get('syncConfig'),
                    child: const Icon(Icons.sync),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: "import",
                    onPressed: onImportConfig,
                    tooltip: context.l10n.get('importConfig'),
                    child: const Icon(Icons.upload_file),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: "export",
                    onPressed: onExportConfig,
                    tooltip: context.l10n.get('exportConfig'),
                    child: const Icon(Icons.download),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: "delete",
                    onPressed: isUnlocked ? onDeleteConfig : null,
                    tooltip: context.l10n.get('deleteConfig'),
                    backgroundColor: Colors.red[400],
                    child: const Icon(Icons.delete_forever),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: "apply",
                    onPressed: onSaveConfig,
                    tooltip: context.l10n.get('saveConfig'),
                    child: const Icon(Icons.save),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
