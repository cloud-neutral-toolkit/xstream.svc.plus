import 'package:flutter/material.dart';
import 'dart:async';

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
  String _selectedNode = '';
  String _hoveredNode = '';
  String _highlightNode = '';
  bool _isSwitchingNode = false;
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
    final loaded = List<VpnNode>.from(VpnConfig.nodes);
    if (loaded.isEmpty) {
      setState(() {
        vpnNodes = const [];
        _activeNode = '';
        _highlightNode = '';
        _selectedNode = '';
        _connectedAt = null;
        _connectedDuration = Duration.zero;
        _connectedLocation = '-';
      });
      _durationTimer?.cancel();
      _durationTimer = null;
      GlobalState.activeNodeName.value = '';
      GlobalState.lastImportedNodeName.value = '';
      return;
    }

    setState(() {
      vpnNodes = loaded;
      _activeNode = GlobalState.activeNodeName.value;
      _highlightNode = GlobalState.lastImportedNodeName.value;
      _selectedNode = _activeNode.isNotEmpty ? _activeNode : _highlightNode;
    });
    _syncConnectedMeta();
    _scheduleClearHighlight();
  }

  Future<void> _onNodeListRevisionChanged() async {
    await _initializeConfig();
  }

  void _onActiveNodeChanged() {
    if (!mounted) return;
    setState(() {
      _activeNode = GlobalState.activeNodeName.value;
      if (_activeNode.isNotEmpty) {
        _selectedNode = _activeNode;
        _highlightNode = _activeNode;
      }
    });
    _syncConnectedMeta();
  }

  void _syncConnectedMeta() {
    if (_activeNode.isEmpty) {
      _connectedAt = null;
      _connectedDuration = Duration.zero;
      _connectedLocation = '-';
      _durationTimer?.cancel();
      _durationTimer = null;
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

  String _formatDuration(Duration duration) {
    final secs = duration.inSeconds;
    if (secs < 60) return '$secs${context.l10n.get('secondsSuffix')}';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return '$mins m $rem${context.l10n.get('secondsSuffix')}';
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

  VpnNode? _resolveActionNode() {
    final selected = _selectedNode.trim();
    if (selected.isNotEmpty) {
      for (final node in vpnNodes) {
        if (node.name == selected) return node;
      }
    }
    final active = _activeNode.trim();
    if (active.isNotEmpty) {
      for (final node in vpnNodes) {
        if (node.name == active) return node;
      }
    }
    return vpnNodes.isNotEmpty ? vpnNodes.first : null;
  }

  void _selectNode(VpnNode node) {
    setState(() {
      _selectedNode = node.name;
      _highlightNode = node.name;
      GlobalState.lastImportedNodeName.value = node.name;
    });
    _scheduleClearHighlight();
  }

  Future<void> _toggleFromFloatingButton() async {
    if (_isSwitchingNode) return;
    final node = _resolveActionNode();
    if (node == null) {
      _showMessage(context.l10n.get('noNodes'));
      return;
    }
    await _toggleNode(node);
  }

  Future<void> _toggleNode(VpnNode node) async {
    if (_isSwitchingNode) return;
    final nodeName = node.name.trim();
    if (nodeName.isEmpty) return;
    setState(() => _isSwitchingNode = true);
    final useTunMode = NativeBridge.isTunMode;
    try {
      // ── Stop active node ──────────────────────────────────────────
      if (_activeNode == nodeName) {
        final msg = useTunMode
            ? await NativeBridge.stopNodeForTunnel()
            : await NativeBridge.stopNodeService(nodeName);
        if (!mounted) return;
        setState(() {
          _activeNode = '';
          _selectedNode = nodeName;
        });
        GlobalState.activeNodeName.value = '';
        _syncConnectedMeta();
        _showMessage(msg);
        return;
      }

      // ── Stop previous node if switching ───────────────────────────
      if (_activeNode.isNotEmpty) {
        if (useTunMode) {
          await NativeBridge.stopNodeForTunnel();
        } else {
          await NativeBridge.stopNodeService(_activeNode);
        }
        if (!mounted) return;
        GlobalState.activeNodeName.value = '';
      }

      // ── Check if already running (proxy mode only) ────────────────
      if (!useTunMode) {
        final isRunning = await NativeBridge.checkNodeStatus(nodeName);
        if (!mounted) return;
        if (isRunning) {
          setState(() {
            _activeNode = nodeName;
            _selectedNode = nodeName;
            _highlightNode = nodeName;
          });
          GlobalState.activeNodeName.value = nodeName;
          _syncConnectedMeta();
          _showMessage(context.l10n.get('serviceRunning'));
          return;
        }
      }

      // ── Start node ────────────────────────────────────────────────
      final startedAt = DateTime.now();
      final msg = useTunMode
          ? await NativeBridge.startNodeForTunnel(nodeName)
          : await NativeBridge.startNodeService(nodeName);
      if (!mounted) return;

      // Determine if start succeeded
      final startOk = useTunMode
          ? !msg.contains('失败')
          : await NativeBridge.checkNodeStatus(nodeName);
      if (!mounted) return;
      if (!startOk) {
        setState(() {
          _selectedNode = nodeName;
          _highlightNode = nodeName;
        });
        GlobalState.activeNodeName.value = '';
        _syncConnectedMeta();
        _showMessage(msg);
        _scheduleClearHighlight();
        return;
      }

      setState(() {
        _activeNode = nodeName;
        _selectedNode = nodeName;
        _highlightNode = nodeName;
      });
      GlobalState.activeNodeName.value = nodeName;
      _syncConnectedMeta();
      _showMessage(msg);
      _scheduleClearHighlight();

      // ── Verify connectivity ───────────────────────────────────────
      if (!useTunMode) {
        // Proxy mode: verify SOCKS5 proxy is reachable
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
      } else {
        // TUN mode: log the launch result
        addAppLog('[tunnel] $msg');
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitchingNode = false);
      } else {
        _isSwitchingNode = false;
      }
    }
  }

  Widget _buildMobileHeroCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.arrow_upward,
                iconColor: Colors.pinkAccent,
                title: context.l10n.get('homeStatusUpload'),
                value: '--',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.arrow_downward,
                iconColor: Colors.blueAccent,
                title: context.l10n.get('homeStatusDownload'),
                value: '--',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.memory,
                iconColor: Colors.purpleAccent,
                title: context.l10n.get('homeStatusMemory'),
                value: '--',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.route,
                iconColor: Colors.greenAccent,
                title: context.l10n.get('homeStatusConnections'),
                value: '--',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.explore, size: 20, color: Color(0xFF4A6572)),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.get('selectedNode'),
                    style: const TextStyle(
                      color: Color(0xFF4A6572),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_activeNode.isNotEmpty || _selectedNode.isNotEmpty)
                Center(
                  child: Text(
                    _activeNode.isNotEmpty ? _activeNode : _selectedNode,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF222222),
                    ),
                  ),
                )
              else
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        size: 36,
                        color: Colors.grey.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.get('addNodeHint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.recommend,
                    size: 20,
                    color: Color(0xFF4A6572),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.get('recommendedNode'),
                    style: const TextStyle(
                      color: Color(0xFF4A6572),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFD2E0FB),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(24),
                            bottomLeft: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check, size: 16),
                            const SizedBox(width: 4),
                            Text(context.l10n.get('speed')),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.speed, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              context.l10n.get('latency'),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  _activeNode.isNotEmpty ? _activeNode : 'No nodes available',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.isUnlocked,
      builder: (context, isUnlocked, _) {
        final desktopContent = vpnNodes.isEmpty
            ? Center(child: Text(context.l10n.get('noNodes')))
            : ListView.separated(
                itemCount: vpnNodes.length,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 72),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final node = vpnNodes[index];
                  final isActive = _activeNode == node.name;
                  final isSelected = _selectedNode == node.name;
                  final isHighlighted =
                      _highlightNode == node.name || isSelected;
                  final bgColor = isActive
                      ? const Color(0xFFC8E6C9)
                      : (isHighlighted
                          ? const Color(0xFFCFE6FF)
                          : Colors.transparent);
                  final latency = _latencyByNode[node.name];
                  final tags = <String>[
                    node.protocol.trim().toLowerCase(),
                    node.transport.trim().toLowerCase(),
                    node.security.trim().toLowerCase(),
                  ].where((e) => e.isNotEmpty).toList();

                  return MouseRegion(
                    onEnter: (_) => setState(() {
                      _hoveredNode = node.name;
                      _selectedNode = node.name;
                      _highlightNode = node.name;
                    }),
                    onExit: (_) => setState(() => _hoveredNode = ''),
                    child: InkWell(
                      onTap: (isUnlocked && !_isSwitchingNode)
                          ? () => _selectNode(node)
                          : null,
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
                                  if (tags.isNotEmpty || latency != null)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ...tags.map(_buildTag),
                                        if (latency != null)
                                          _buildTag('${latency}ms'),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

        final hoverHint = _hoveredNode.isNotEmpty
            ? '${context.l10n.get('hoverHintSelected')}: $_hoveredNode，'
                '${context.l10n.get('hoverHintClickToStart')}'
            : '';

        final showStatusBar = _activeNode.isNotEmpty;
        final activeLatency = _latencyByNode[_activeNode];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 900;
            if (isMobile) {
              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildMobileHeroCard(context),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: FloatingActionButton(
                      backgroundColor: const Color(0xFFD2E0FB),
                      elevation: 0,
                      onPressed:
                          _isSwitchingNode ? null : _toggleFromFloatingButton,
                      child: _isSwitchingNode
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _activeNode.isNotEmpty
                                  ? Icons.stop
                                  : Icons.play_arrow,
                              color: const Color(0xFF1E2025),
                              size: 32,
                            ),
                    ),
                  ),
                ],
              );
            }

            return Stack(
              children: [
                desktopContent,
                if (showStatusBar)
                  Positioned(
                    left: 16,
                    right: 86,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${context.l10n.get('homeStatusDuration')}: '
                              '${_formatDuration(_connectedDuration)} '
                              '${context.l10n.get('homeStatusLatency')}: '
                              '${activeLatency == null ? "--" : "${activeLatency}ms"} '
                              '${context.l10n.get('homeStatusLocation')}: '
                              '$_connectedLocation',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 22),
                        ],
                      ),
                    ),
                  ),
                if (hoverHint.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 76,
                    bottom: showStatusBar ? 76 : 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        hoverHint,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                if (vpnNodes.isNotEmpty)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      onPressed:
                          _isSwitchingNode ? null : _toggleFromFloatingButton,
                      child: Icon(
                        _activeNode.isNotEmpty
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
