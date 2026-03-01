import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';

import '../../utils/native_bridge.dart';
import '../../utils/global_config.dart' show GlobalState;
import '../../utils/app_logger.dart';
import '../l10n/app_localizations.dart';
import '../../services/permission_guide_service.dart';
import '../../services/vpn_config_service.dart';
import '../widgets/permission_guide_dialog.dart';
import '../widgets/log_console.dart' show LogLevel;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _LatencyVisual {
  final String value;
  final String label;
  final Color color;

  const _LatencyVisual({
    required this.value,
    required this.label,
    required this.color,
  });
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _emptyMetricValue = '— —';
  static final Uri _latencyProbeUri = Uri.parse('https://example.com/');
  String _activeNode = '';
  String _selectedNode = '';
  String _hoveredNode = '';
  String _highlightNode = '';
  bool _isSwitchingNode = false;
  bool _latencyProbeInFlight = false;
  List<VpnNode> vpnNodes = [];
  final Map<String, int> _latencyByNode = {};
  DateTime? _connectedAt;
  Timer? _durationTimer;
  Timer? _statusTimer;
  Timer? _metricsTimer;
  Timer? _latencyTimer;
  Duration _connectedDuration = Duration.zero;
  String _connectedLocation = '-';
  PacketTunnelStatus _packetTunnelStatus =
      const PacketTunnelStatus(status: 'unknown', utunInterfaces: []);
  PacketTunnelMetricsSnapshot _packetTunnelMetrics =
      const PacketTunnelMetricsSnapshot();
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  void _showMessage(String msg, {Color? bgColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bgColor));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GlobalState.nodeListRevision.addListener(_onNodeListRevisionChanged);
    GlobalState.activeNodeName.addListener(_onActiveNodeChanged);
    GlobalState.connectionMode.addListener(_onConnectionModeChanged);
    _initializeConfig();
    _updateMonitoringState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _statusTimer?.cancel();
    _metricsTimer?.cancel();
    _latencyTimer?.cancel();
    GlobalState.nodeListRevision.removeListener(_onNodeListRevisionChanged);
    GlobalState.activeNodeName.removeListener(_onActiveNodeChanged);
    GlobalState.connectionMode.removeListener(_onConnectionModeChanged);
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
      _updateMonitoringState();
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
    _updateMonitoringState();
    if (_shouldPollPacketTunnelStatus) {
      unawaited(_refreshPacketTunnelStatus());
    }
  }

  Future<void> _onNodeListRevisionChanged() async {
    await _initializeConfig();
  }

  void _onConnectionModeChanged() {
    _updateMonitoringState();
    if (_shouldPollPacketTunnelStatus) {
      unawaited(_refreshPacketTunnelStatus());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    _updateMonitoringState();
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
    _updateMonitoringState();
    if (_shouldPollPacketTunnelStatus) {
      unawaited(_refreshPacketTunnelStatus());
    }
    if (_shouldPollMetrics) {
      unawaited(_refreshPacketTunnelMetrics());
    }
    if (_shouldPollLatency) {
      unawaited(_refreshActiveNodeLatency());
    } else {
      _clearMonitoringData(clearLatency: true);
    }
  }

  bool get _requiresPacketTunnelStatus =>
      Platform.isIOS || (Platform.isMacOS && NativeBridge.isTunMode);

  bool get _packetTunnelExplicitlyUnavailable =>
      _packetTunnelStatus.status == 'disconnected' ||
      _packetTunnelStatus.status == 'disconnecting' ||
      _packetTunnelStatus.status == 'invalid' ||
      _packetTunnelStatus.status == 'not_configured';

  bool get _shouldPollPacketTunnelStatus =>
      _appLifecycleState == AppLifecycleState.resumed &&
      _activeNode.isNotEmpty &&
      _requiresPacketTunnelStatus;

  bool get _shouldPollMetrics =>
      _appLifecycleState == AppLifecycleState.resumed &&
      _activeNode.isNotEmpty &&
      !_packetTunnelExplicitlyUnavailable;

  bool get _shouldPollLatency {
    if (_appLifecycleState != AppLifecycleState.resumed ||
        _activeNode.isEmpty) {
      return false;
    }
    if (Platform.isMacOS && !NativeBridge.isTunMode) {
      return true;
    }
    if (_requiresPacketTunnelStatus) {
      return !_packetTunnelExplicitlyUnavailable;
    }
    return true;
  }

  void _updateMonitoringState() {
    if (_shouldPollPacketTunnelStatus) {
      _startStatusPolling();
    } else {
      _statusTimer?.cancel();
      _statusTimer = null;
    }

    if (_shouldPollMetrics) {
      _startMetricsPolling();
    } else {
      _metricsTimer?.cancel();
      _metricsTimer = null;
    }

    if (_shouldPollLatency) {
      _startLatencyPolling();
    } else {
      _latencyTimer?.cancel();
      _latencyTimer = null;
    }

    if (!_shouldPollMetrics || !_shouldPollLatency) {
      _clearMonitoringData(clearLatency: !_shouldPollLatency);
    }
  }

  void _clearMonitoringData({required bool clearLatency}) {
    final activeNode = _activeNode.trim();
    final hadMetrics = _packetTunnelMetrics.updatedAt != null ||
        _packetTunnelMetrics.downloadBytesPerSecond != null ||
        _packetTunnelMetrics.uploadBytesPerSecond != null ||
        _packetTunnelMetrics.memoryBytes != null ||
        _packetTunnelMetrics.cpuPercent != null;
    final hadLatency = clearLatency &&
        activeNode.isNotEmpty &&
        _latencyByNode.containsKey(activeNode);
    if (!hadMetrics && !hadLatency) {
      return;
    }
    setState(() {
      _packetTunnelMetrics = const PacketTunnelMetricsSnapshot();
      if (hadLatency) {
        _latencyByNode.remove(activeNode);
      }
    });
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    unawaited(_refreshPacketTunnelStatus());
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshPacketTunnelStatus());
    });
  }

  Future<void> _refreshPacketTunnelStatus() async {
    if (!_shouldPollPacketTunnelStatus) {
      return;
    }
    final status = await NativeBridge.getPacketTunnelStatus();
    if (!mounted) return;
    final changed = status.status != _packetTunnelStatus.status ||
        status.lastError != _packetTunnelStatus.lastError ||
        status.startedAt != _packetTunnelStatus.startedAt ||
        status.utunInterfaces.join(',') !=
            _packetTunnelStatus.utunInterfaces.join(',');
    if (!changed) {
      return;
    }
    setState(() {
      _packetTunnelStatus = status;
      if (_packetTunnelExplicitlyUnavailable) {
        _packetTunnelMetrics = const PacketTunnelMetricsSnapshot();
        final activeNode = _activeNode.trim();
        if (activeNode.isNotEmpty) {
          _latencyByNode.remove(activeNode);
        }
      }
    });
    _updateMonitoringState();
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

  void _startMetricsPolling() {
    _metricsTimer?.cancel();
    unawaited(_refreshPacketTunnelMetrics());
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshPacketTunnelMetrics());
    });
  }

  void _startLatencyPolling() {
    _latencyTimer?.cancel();
    unawaited(_refreshActiveNodeLatency());
    _latencyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshActiveNodeLatency());
    });
  }

  Future<void> _refreshPacketTunnelMetrics() async {
    if (!_shouldPollMetrics) {
      return;
    }
    final snapshot = await NativeBridge.getPacketTunnelMetrics();
    if (!mounted) return;
    final previous = _packetTunnelMetrics;
    final changed =
        previous.downloadBytesPerSecond != snapshot.downloadBytesPerSecond ||
            previous.uploadBytesPerSecond != snapshot.uploadBytesPerSecond ||
            previous.memoryBytes != snapshot.memoryBytes ||
            previous.cpuPercent != snapshot.cpuPercent ||
            previous.updatedAt != snapshot.updatedAt;
    if (!changed) return;
    setState(() {
      _packetTunnelMetrics = snapshot;
    });
  }

  Future<void> _refreshActiveNodeLatency() async {
    final nodeName = _activeNode.trim();
    if (nodeName.isEmpty || _latencyProbeInFlight || !_shouldPollLatency) {
      return;
    }

    _latencyProbeInFlight = true;
    try {
      final latency = await _probeActiveConnectionLatency();
      if (!mounted || _activeNode.trim() != nodeName) {
        return;
      }
      if (latency == null || latency < 0) {
        if (_latencyByNode.containsKey(nodeName)) {
          setState(() {
            _latencyByNode.remove(nodeName);
          });
        }
        return;
      }
      if (_latencyByNode[nodeName] == latency) {
        return;
      }
      setState(() {
        _latencyByNode[nodeName] = latency;
      });
    } finally {
      _latencyProbeInFlight = false;
    }
  }

  Future<int?> _probeActiveConnectionLatency() async {
    if (Platform.isMacOS && !NativeBridge.isTunMode) {
      final watch = Stopwatch()..start();
      final result = await NativeBridge.verifySocks5Proxy();
      watch.stop();
      if (result.startsWith('success:')) {
        return watch.elapsedMilliseconds;
      }
      return null;
    }
    return _probeSystemTunnelLatency();
  }

  Future<int?> _probeSystemTunnelLatency() async {
    if (_requiresPacketTunnelStatus && _packetTunnelExplicitlyUnavailable) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final watch = Stopwatch()..start();
      final request = await client.headUrl(_latencyProbeUri).timeout(
            const Duration(seconds: 4),
          );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response =
          await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      watch.stop();
      if (response.statusCode >= 200 && response.statusCode < 500) {
        return watch.elapsedMilliseconds;
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
    return null;
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
        // Prevent leaks if connection mode was changed during an active session by stopping both
        await NativeBridge.stopNodeForTunnel();
        final msg = await NativeBridge.stopNodeService(nodeName);
        if (!mounted) return;
        setState(() {
          _activeNode = '';
          _selectedNode = nodeName;
        });
        GlobalState.activeNodeName.value = '';
        _syncConnectedMeta();
        _showMessage(useTunMode ? 'Tunnel disconnected' : msg);
        return;
      }

      // ── Stop previous node if switching ───────────────────────────
      if (_activeNode.isNotEmpty) {
        await NativeBridge.stopNodeForTunnel();
        await NativeBridge.stopNodeService(_activeNode);
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
        if (useTunMode) {
          await _maybeShowPacketTunnelPermissionGuide(msg);
        }
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

  Future<void> _maybeShowPacketTunnelPermissionGuide(
    String failureMessage,
  ) async {
    final shouldShow =
        await PermissionGuideService.shouldPromptForPacketTunnelAuthorization(
      failureMessage: failureMessage,
    );
    if (!mounted || !shouldShow) return;
    await showPermissionGuideDialog(
      context,
      failureMessage: failureMessage,
    );
  }

  PacketTunnelMetricsSnapshot get _visibleMetrics {
    final updatedAt = _packetTunnelMetrics.updatedAt;
    if (_activeNode.isEmpty ||
        updatedAt == null ||
        !_requiresPacketTunnelStatus ||
        _packetTunnelExplicitlyUnavailable) {
      return const PacketTunnelMetricsSnapshot();
    }
    final age = DateTime.now().millisecondsSinceEpoch - updatedAt;
    if (age > 4500) {
      return const PacketTunnelMetricsSnapshot();
    }
    return _packetTunnelMetrics;
  }

  String _formatRate(int? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond < 0) {
      return _emptyMetricValue;
    }
    final value = bytesPerSecond.toDouble();
    if (value >= 1024 * 1024) {
      final mb = value / (1024 * 1024);
      final digits = mb >= 10 ? 1 : 2;
      return '${mb.toStringAsFixed(digits)} MB/s';
    }
    final kb = value / 1024;
    final digits = kb >= 100 ? 0 : 1;
    return '${kb.toStringAsFixed(digits)} KB/s';
  }

  String _formatMemory(int? memoryBytes) {
    if (memoryBytes == null || memoryBytes < 0) {
      return _emptyMetricValue;
    }
    final mb = memoryBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  String _formatCpu(double? cpuPercent) {
    if (cpuPercent == null || cpuPercent.isNaN) {
      return _emptyMetricValue;
    }
    return '${cpuPercent.toStringAsFixed(0)}%';
  }

  _LatencyVisual _latencyVisual(BuildContext context, int? latency) {
    if (latency == null || latency < 0) {
      return const _LatencyVisual(
        value: _emptyMetricValue,
        label: _emptyMetricValue,
        color: Color(0xFFB8BDC7),
      );
    }
    if (latency < 50) {
      return _LatencyVisual(
        value: '${latency}ms',
        label: context.l10n.get('homeStatusGood'),
        color: const Color(0xFF3E8F5A),
      );
    }
    if (latency <= 200) {
      return _LatencyVisual(
        value: '${latency}ms',
        label: context.l10n.get('homeStatusFair'),
        color: const Color(0xFFBF8A3A),
      );
    }
    return _LatencyVisual(
      value: '${latency}ms',
      label: context.l10n.get('homeStatusHigh'),
      color: const Color(0xFFC3655C),
    );
  }

  Widget _buildMetricValue(
    String value,
    TextStyle style, {
    TextAlign textAlign = TextAlign.left,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: Text(
        value,
        key: ValueKey(value),
        textAlign: textAlign,
        style: style,
      ),
    );
  }

  Widget _buildMonitoringCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EBEF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMetricBadge(IconData icon, Color color) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildMonitoringDashboard(BuildContext context) {
    final metrics = _visibleMetrics;
    final latency = _latencyVisual(
      context,
      _activeNode.isEmpty ? null : _latencyByNode[_activeNode],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMonitoringCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildMetricBadge(
                    Icons.south_rounded,
                    const Color(0xFF5677C8),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.get('homeStatusDownload'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF707784),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildMetricValue(
                _formatRate(metrics.downloadBytesPerSecond),
                const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF232833),
                  letterSpacing: -0.8,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.north_rounded,
                    size: 16,
                    color: Color(0xFFB26079),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildMetricValue(
                      '${context.l10n.get('homeStatusUpload')} ${_formatRate(metrics.uploadBytesPerSecond)}',
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7A8090),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMonitoringCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildMetricBadge(
                          Icons.network_ping_rounded,
                          latency.color,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          context.l10n.get('homeStatusLatency'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF707784),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildMetricValue(
                      latency.value,
                      TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: latency.color,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: latency.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          latency.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF7A8090),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMonitoringCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildMetricBadge(
                          Icons.developer_mode_outlined,
                          const Color(0xFF75809A),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          context.l10n.get('homeStatusCpu'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF707784),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildMetricValue(
                      _formatCpu(metrics.cpuPercent),
                      const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF232833),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      _emptyMetricValue,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFB8BDC7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildMonitoringCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              _buildMetricBadge(
                Icons.memory_rounded,
                const Color(0xFF8B74BA),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.get('homeStatusMemory'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF707784),
                  ),
                ),
              ),
              _buildMetricValue(
                _formatMemory(metrics.memoryBytes),
                const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileNodeListPanel(BuildContext context, bool isUnlocked) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dns_outlined,
                size: 20,
                color: Color(0xFF4A6572),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.get('nodeList'),
                style: const TextStyle(
                  color: Color(0xFF4A6572),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (vpnNodes.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
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
            )
          else
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: vpnNodes.length,
                itemBuilder: (context, index) {
                  final node = vpnNodes[index];
                  final isActive = _activeNode == node.name;
                  final isSelected = _selectedNode == node.name;
                  final latency = _latencyByNode[node.name];

                  return GestureDetector(
                    onTap: (isUnlocked && !_isSwitchingNode)
                        ? () => _selectNode(node)
                        : null,
                    child: Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFE8F5E9)
                            : (isSelected
                                ? const Color(0xFFE3F2FD)
                                : Colors.white),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? Colors.green.withValues(alpha: 0.5)
                              : (isSelected
                                  ? Colors.blue.withValues(alpha: 0.5)
                                  : Colors.grey.withValues(alpha: 0.2)),
                          width: (isActive || isSelected) ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  node.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isActive
                                        ? Colors.green[800]
                                        : const Color(0xFF222222),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isActive)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 18,
                                ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.speed,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  latency != null ? '${latency}ms' : '--',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopNodeListPanel(BuildContext context, bool isUnlocked) {
    if (vpnNodes.isEmpty) {
      return Center(child: Text(context.l10n.get('noNodes')));
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EBEF)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: vpnNodes.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final node = vpnNodes[index];
          final isActive = _activeNode == node.name;
          final isSelected = _selectedNode == node.name;
          final isHighlighted = _highlightNode == node.name || isSelected;
          final bgColor = isActive
              ? const Color(0xFFC8E6C9)
              : (isHighlighted ? const Color(0xFFCFE6FF) : Colors.transparent);
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
                                if (latency != null) _buildTag('${latency}ms'),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.isUnlocked,
      builder: (context, isUnlocked, _) {
        final desktopContent = SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMonitoringDashboard(context),
              const SizedBox(height: 18),
              _buildDesktopNodeListPanel(context, isUnlocked),
            ],
          ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMonitoringDashboard(context),
                        const SizedBox(height: 16),
                        _buildMobileNodeListPanel(context, isUnlocked),
                      ],
                    ),
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
