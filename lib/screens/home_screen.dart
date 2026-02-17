// lib/screens/home_screen.dart

import 'dart:async';
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
  String _highlightNode = '';
  List<VpnNode> vpnNodes = [];
  final Map<String, int> _latencyByNode = {};
  DateTime? _connectedAt;
  Timer? _durationTimer;
  Duration _connectedDuration = Duration.zero;
  String _connectedLocation = '-';

  void _showMessage(String msg, {Color? bgColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bgColor));
  }

  @override
  void initState() {
    super.initState();
    GlobalState.nodeListRevision.addListener(_onNodeListRevisionChanged);
    GlobalState.activeNodeName.addListener(_onActiveNodeChanged);
    _initializeConfig();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    GlobalState.nodeListRevision.removeListener(_onNodeListRevisionChanged);
    GlobalState.activeNodeName.removeListener(_onActiveNodeChanged);
    super.dispose();
  }

  Future<void> _initializeConfig() async {
    await VpnConfig.load();
    if (!mounted) return;
    setState(() {
      vpnNodes = VpnConfig.nodes;
      _activeNode = GlobalState.activeNodeName.value;
      _highlightNode = GlobalState.lastImportedNodeName.value;
    });
    _ensureActiveNodeMeta();
    _scheduleClearHighlight();
  }

  Future<void> _onNodeListRevisionChanged() async {
    await _initializeConfig();
  }

  void _onActiveNodeChanged() {
    if (!mounted) return;
    setState(() {
      _activeNode = GlobalState.activeNodeName.value;
    });
    _ensureActiveNodeMeta();
  }

  void _ensureActiveNodeMeta() {
    if (_activeNode.isEmpty) {
      _connectedAt = null;
      _connectedDuration = Duration.zero;
      _connectedLocation = '-';
      _durationTimer?.cancel();
      return;
    }

    _connectedAt ??= DateTime.now();
    final node = vpnNodes.cast<VpnNode?>().firstWhere(
          (n) => n?.name == _activeNode,
          orElse: () => null,
        );
    _connectedLocation = (node?.countryCode ?? '-').toUpperCase();
    _durationTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() {
        _connectedDuration = DateTime.now().difference(_connectedAt!);
      });
    });
  }

  void _scheduleClearHighlight() {
    if (_highlightNode.isEmpty) return;
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (!mounted) return;
      if (_highlightNode == GlobalState.lastImportedNodeName.value) {
        setState(() {
          _highlightNode = '';
        });
      }
    });
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF666666),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final secs = duration.inSeconds;
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return '${mins}m ${rem}s';
  }

  Future<void> _openNodeMenu(VpnNode node) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final isRunning = _activeNode == node.name;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isRunning ? Icons.stop_circle : Icons.play_circle_fill,
                ),
                title: Text(context.l10n
                    .get(isRunning ? 'stopAcceleration' : 'startAcceleration')),
                onTap: () async {
                  Navigator.pop(context);
                  await _toggleNode(node);
                },
              ),
              ListTile(
                leading: const Icon(Icons.highlight),
                title: Text(context.l10n.get('highlightNode')),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _highlightNode = node.name;
                    GlobalState.lastImportedNodeName.value = node.name;
                  });
                  _scheduleClearHighlight();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleNode(VpnNode node) async {
    final nodeName = node.name.trim();
    if (nodeName.isEmpty) return;

    // start or stop node service

    if (_activeNode == nodeName) {
      final msg = await NativeBridge.stopNodeService(nodeName);
      if (!mounted) return;
      setState(() {
        _activeNode = '';
      });
      GlobalState.activeNodeName.value = '';
      _connectedAt = null;
      _connectedDuration = Duration.zero;
      _durationTimer?.cancel();
      _durationTimer = null;
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

      final startedAt = DateTime.now();
      final msg = await NativeBridge.startNodeService(nodeName);
      if (!mounted) return;
      setState(() {
        _activeNode = nodeName;
        _highlightNode = nodeName;
        _connectedAt = DateTime.now();
        _connectedDuration = Duration.zero;
        _connectedLocation = node.countryCode.toUpperCase();
      });
      GlobalState.activeNodeName.value = nodeName;
      _showMessage(msg);
      _scheduleClearHighlight();

      final verifyMsg = await NativeBridge.verifySocks5Proxy();
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      if (verifyMsg.startsWith('success:')) {
        _latencyByNode[nodeName] = elapsed;
      }
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
            : ListView.separated(
                itemCount: vpnNodes.length,
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  _activeNode.isEmpty ? 12 : 100,
                ),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final node = vpnNodes[index];
                  final isActive = _activeNode == node.name;
                  final isHighlighted = _highlightNode == node.name;
                  final bgColor = isActive
                      ? const Color(0xFFC8E6C9)
                      : (isHighlighted
                          ? const Color(0xFFCFE6FF)
                          : Colors.transparent);
                  final latency = _latencyByNode[node.name];

                  return InkWell(
                    onTap: isUnlocked ? () => _toggleNode(node) : null,
                    child: Container(
                      color: bgColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  node.name,
                                  style: const TextStyle(
                                    fontSize: 40 / 1.6,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF222222),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildTag(node.protocol.toLowerCase()),
                                    _buildTag(node.transport.toLowerCase()),
                                    _buildTag(node.security.toLowerCase()),
                                    if (latency != null)
                                      _buildTag('${latency}ms'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _openNodeMenu(node),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

        if (_activeNode.isEmpty) return content;

        final latency = _latencyByNode[_activeNode];
        return Stack(
          children: [
            content,
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${context.l10n.get('homeStatusDuration')}: '
                        '${_formatDuration(_connectedDuration)}  '
                        '${context.l10n.get('homeStatusLatency')}: '
                        '${latency == null ? "--" : "${latency}ms"}  '
                        '${context.l10n.get('homeStatusLocation')}: '
                        '$_connectedLocation',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
