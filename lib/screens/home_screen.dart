// lib/screens/home_screen.dart

import 'package:flutter/material.dart';

import '../../utils/native_bridge.dart';
import '../../utils/global_config.dart' show GlobalState;
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

      final verifyMsg = await NativeBridge.verifySocks5Proxy();
      addAppLog('[socks5] $verifyMsg',
          level: verifyMsg.startsWith('success:')
              ? LogLevel.info
              : LogLevel.error);
      _showMessage(verifyMsg);
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
                  return ListTile(
                    title: Text(
                      '${node.countryCode.toUpperCase()} | ${node.name}',
                    ),
                    subtitle: Text(
                      '${node.protocol.toUpperCase()} | ${node.transport} | ${node.security}',
                    ),
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

        return content;
      },
    );
  }
}
