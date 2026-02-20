import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import '../../utils/global_config.dart' show GlobalState;
import '../../utils/native_bridge.dart';
import '../session/session_manager.dart';
import 'device_fingerprint.dart';
import 'sync_state.dart';
import 'xray_config_writer.dart';

class DesktopSyncResult {
  final bool success;
  final String message;

  const DesktopSyncResult({
    required this.success,
    required this.message,
  });
}

class SyncedNodeMetadata {
  final String name;
  final String? countryCode;
  final String? protocol;
  final String? transport;
  final String? security;

  const SyncedNodeMetadata({
    required this.name,
    this.countryCode,
    this.protocol,
    this.transport,
    this.security,
  });
}

class DesktopSyncService {
  DesktopSyncService._();

  static final DesktopSyncService instance = DesktopSyncService._();

  static const _syncPath = '/api/auth/sync/config';
  static const _ackPath = '/api/auth/sync/ack';
  static const _autoInterval = Duration(minutes: 10);
  static const _fallbackNodeName = 'Desktop Sync';

  final ValueNotifier<bool> syncing = ValueNotifier<bool>(false);

  Timer? _timer;
  bool _initialized = false;
  bool _syncing = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await SessionManager.instance.init();
    await SyncStateStore.instance.init();
    SessionManager.instance.status.addListener(_handleSessionChange);
    _handleSessionChange();
  }

  void dispose() {
    _timer?.cancel();
    SessionManager.instance.status.removeListener(_handleSessionChange);
    _initialized = false;
  }

  Future<DesktopSyncResult> syncNow({bool manual = false}) async {
    if (!SessionManager.instance.isLoggedIn) {
      return const DesktopSyncResult(success: false, message: '请先登录');
    }
    if (_syncing) {
      return const DesktopSyncResult(success: false, message: '同步进行中');
    }

    _syncing = true;
    syncing.value = true;
    try {
      const maxAttempts = 3;
      var attempt = 0;
      DesktopSyncResult? finalResult;
      while (attempt < (manual ? 1 : maxAttempts)) {
        attempt += 1;
        final result = await _performSync();
        finalResult = result;
        if (result.success) {
          break;
        }
        final delay = Duration(seconds: pow(2, attempt).toInt());
        await Future.delayed(delay);
      }
      return finalResult ??
          const DesktopSyncResult(success: false, message: '同步失败');
    } finally {
      _syncing = false;
      syncing.value = false;
    }
  }

  void _handleSessionChange() {
    _timer?.cancel();
    if (SessionManager.instance.isLoggedIn) {
      _timer = Timer.periodic(_autoInterval, (_) {
        unawaited(syncNow(manual: false));
      });
      unawaited(syncNow(manual: false));
    }
  }

  Future<DesktopSyncResult> _performSync() async {
    final session = SessionManager.instance;
    final token = (session.sessionToken ?? '').trim();
    final cookie = (session.cookie ?? '').trim();
    if (token.isEmpty && cookie.isEmpty) {
      const message = '缺少会话信息，请重新登录';
      await SyncStateStore.instance.recordError(message);
      await session.logout();
      return const DesktopSyncResult(success: false, message: message);
    }

    try {
      final uri = session.buildEndpoint(
        '$_syncPath?since_version=${SyncStateStore.instance.lastConfigVersion}',
      );
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      if (cookie.isNotEmpty) {
        headers['Cookie'] = cookie;
      }

      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 404) {
        const message = '桌面同步未启用 (404)';
        await SyncStateStore.instance.recordError(message);
        return const DesktopSyncResult(success: false, message: message);
      }
      if (response.statusCode == 401) {
        const message = '会话已过期，请重新登录';
        await SyncStateStore.instance.recordError(message);
        await session.logout();
        return const DesktopSyncResult(success: false, message: message);
      }
      if (response.statusCode == 403) {
        const message = '账号没有桌面同步权限';
        await SyncStateStore.instance.recordError(message);
        return const DesktopSyncResult(success: false, message: message);
      }
      if (response.statusCode != 200) {
        final message = '同步接口返回 ${response.statusCode}';
        await SyncStateStore.instance.recordError(message);
        return DesktopSyncResult(success: false, message: message);
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final changed = payload['changed'] == true;
      final configVersion = (payload['version'] as num?)?.toInt() ?? 0;
      final metadata = _extractMetadata(payload);
      final nodeMetadata = _extractNodeMetadata(payload);

      if (!changed ||
          configVersion <= SyncStateStore.instance.lastConfigVersion) {
        await SyncStateStore.instance.recordSuccess(
          configVersion: SyncStateStore.instance.lastConfigVersion,
          metadata: metadata,
        );
        return const DesktopSyncResult(success: true, message: '配置已是最新版本');
      }

      final configJson = (payload['rendered_json'] as String?)?.trim() ?? '{}';
      final configPath = await XrayConfigWriter.writeConfig(configJson);
      final syncedNodeName = await XrayConfigWriter.registerNode(
        configPath: configPath,
        nodeName: nodeMetadata.name,
        countryCode: nodeMetadata.countryCode,
        protocol: nodeMetadata.protocol,
        transport: nodeMetadata.transport,
        security: nodeMetadata.security,
      );
      GlobalState.nodeListRevision.value++;

      await _sendAck(
        session: session,
        token: token,
        cookie: cookie,
        version: configVersion,
      );

      await SyncStateStore.instance.recordSuccess(
        configVersion: configVersion,
        metadata: metadata,
      );
      addAppLog('桌面配置已同步至 $configPath (节点 $syncedNodeName, 版本 $configVersion)');
      await _restartNodeIfPossible(syncedNodeName);
      return DesktopSyncResult(
        success: true,
        message: '同步成功 (版本 $configVersion)',
      );
    } catch (e) {
      final message = '同步失败: $e';
      await SyncStateStore.instance.recordError(message);
      return DesktopSyncResult(success: false, message: message);
    }
  }

  Future<void> _sendAck({
    required SessionManager session,
    required String token,
    required String cookie,
    required int version,
  }) async {
    final fingerprint = await DeviceFingerprint.loadOrCreate();
    final deviceID = _hexEncode(fingerprint);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    await http.post(
      session.buildEndpoint(_ackPath),
      headers: headers,
      body: jsonEncode({
        'version': version,
        'device_id': deviceID,
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> _restartNodeIfPossible(String nodeName) async {
    try {
      if (!GlobalState.isUnlocked.value) {
        addAppLog('同步成功，等待解锁后手动重启服务');
        return;
      }
      await NativeBridge.stopNodeService(nodeName);
      await Future.delayed(const Duration(seconds: 1));
      await NativeBridge.startNodeService(nodeName);
      addAppLog('已重启 $nodeName 服务');
    } catch (e) {
      addAppLog('重启 $nodeName 失败: $e');
    }
  }

  String? _extractMetadata(Map<String, dynamic> payload) {
    final meta = payload['meta'];
    if (meta is Map<String, dynamic>) {
      final digest = (meta['digest'] as String?)?.trim();
      if (digest != null && digest.isNotEmpty) {
        return digest;
      }
    }
    final digest = (payload['digest'] as String?)?.trim();
    if (digest != null && digest.isNotEmpty) {
      return digest;
    }
    return null;
  }

  SyncedNodeMetadata _extractNodeMetadata(Map<String, dynamic> payload) {
    final nodes = payload['nodes'];
    if (nodes is List) {
      for (final item in nodes) {
        if (item is! Map) continue;
        final node = item.cast<Object?, Object?>();
        final name = _firstNonEmptyString([
          node['name'],
          node['remark'],
          node['id'],
        ]);
        if (name.isEmpty) continue;
        return SyncedNodeMetadata(
          name: name,
          protocol: _nullableString(_firstNonEmptyString([node['protocol']])),
          transport: _nullableString(
            _firstNonEmptyString([node['transport'], node['network']]),
          ),
          security: _nullableString(_firstNonEmptyString([node['security']])),
        );
      }
    }

    return const SyncedNodeMetadata(name: _fallbackNodeName);
  }

  String _firstNonEmptyString(List<Object?> candidates) {
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return '';
  }

  String? _nullableString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  String _hexEncode(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
