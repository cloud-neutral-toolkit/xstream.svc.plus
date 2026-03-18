import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import '../../services/vpn_config_service.dart'; // 引入新的 VpnConfig 类
import '../bindings/bridge_bindings.dart';
import '../app/darwin_host_api.g.dart' as darwin_host;
import '../widgets/log_console.dart' show LogLevel;
import 'app_logger.dart';
import 'global_config.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('com.xstream/native');
  static const MethodChannel _loggerChannel = MethodChannel(
    'com.xstream/logger',
  );
  static final darwin_host.DarwinHostApi _darwinHostApi =
      darwin_host.DarwinHostApi();
  static bool _darwinFlutterApiReady = false;
  static Future<void> Function(String action, Map<String, dynamic> payload)?
  _nativeMenuActionHandler;
  static String? _mobileActiveNodeName;
  static String? _darwinAppGroupPathCache;
  static Future<void> _connectionLifecycleQueue = Future<void>.value();

  static final bool _useFfi =
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS ||
      Platform.isIOS ||
      Platform.isAndroid;
  static BridgeBindings? _bindings;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static bool get _isDarwin => Platform.isMacOS || Platform.isIOS;

  static bool get _isMobile => Platform.isIOS || Platform.isAndroid;

  static bool isTunnelStartAcceptedMessage(String? message) {
    final normalized = (message ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized.contains('启动失败') ||
        normalized.contains('停止失败') ||
        normalized.contains('当前平台暂不支持') ||
        normalized.contains('profile_missing') ||
        normalized.contains('config_missing') ||
        normalized.contains('xray_start_failed') ||
        normalized.contains('establish_failed') ||
        normalized.contains('native_bridge_unavailable')) {
      return false;
    }
    return normalized.contains('start_submitted') ||
        normalized.contains('vpn_permission_requested') ||
        normalized.contains('packet tunnel 启动请求已提交') ||
        normalized.contains('packet tunnel start request submitted') ||
        normalized.contains('已连接') ||
        normalized.contains('启动成功');
  }

  static bool looksLikePacketTunnelPermissionIssue(String? message) {
    final normalized = (message ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('vpn_permission_required') ||
        normalized.contains('vpn_permission_requested') ||
        normalized.contains('vpn_permission_denied') ||
        normalized.contains('permission denied') ||
        normalized.contains('authorization denied') ||
        normalized.contains('not authorized');
  }

  static String _platformErrorSummary(PlatformException e) {
    final parts = <String>[];
    if (e.code.isNotEmpty && e.code != 'error') {
      parts.add('code=${e.code}');
    }
    if (e.message != null && e.message!.trim().isNotEmpty) {
      parts.add('message=${e.message!.trim()}');
    }
    if (e.details != null && e.details.toString().trim().isNotEmpty) {
      parts.add('details=${e.details}');
    }
    return parts.isEmpty ? e.toString() : parts.join(', ');
  }

  static const _tunStatusFallback = PacketTunnelStatus(
    status: 'unsupported',
    utunInterfaces: [],
  );
  static const _tunMetricsFallback = PacketTunnelMetricsSnapshot();
  static bool _linuxDesktopInitialized = false;
  static const _desktopRuntimeSnapshotFallback = DesktopRuntimeSnapshot();

  static Future<T> _runSerializedConnectionOp<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _connectionLifecycleQueue = _connectionLifecycleQueue
        .then((_) async {
          try {
            completer.complete(await action());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((_) {});
    return completer.future;
  }

  static Future<Map<String, dynamic>> _invokeLinuxDesktopCommand(
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    if (!Platform.isLinux) {
      return <String, dynamic>{'ok': false, 'message': '当前平台暂不支持'};
    }
    final request = <String, dynamic>{'action': action, ...?payload};
    final requestPtr = jsonEncode(request).toNativeUtf8();
    try {
      final resPtr = _ffi.desktopIntegrationCommand(requestPtr.cast());
      final response = resPtr.cast<Utf8>().toDartString();
      _ffi.freeCString(resPtr);
      final decoded = jsonDecode(response);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      return <String, dynamic>{'ok': false, 'message': 'unexpected response'};
    } finally {
      malloc.free(requestPtr);
    }
  }

  static Future<void> initializeLinuxDesktopIntegration() async {
    if (!Platform.isLinux || _linuxDesktopInitialized) {
      return;
    }
    _linuxDesktopInitialized = true;
    if (_useFfi) {
      try {
        _ffi.initTray();
      } catch (_) {}
    }
  }

  static Future<LinuxDesktopIntegrationStatus>
  getLinuxDesktopIntegrationStatus() async {
    if (!Platform.isLinux) {
      return const LinuxDesktopIntegrationStatus(
        desktopEnvironment: 'unsupported',
        autostartEnabled: false,
        privilegeReady: false,
      );
    }
    final response = await _invokeLinuxDesktopCommand('getDesktopEnvironment');
    return LinuxDesktopIntegrationStatus.fromMap(response);
  }

  static Future<String> setLinuxAutostartEnabled(bool enabled) async {
    if (!Platform.isLinux) return '当前平台暂不支持';
    final response = await _invokeLinuxDesktopCommand(
      'setAutostartEnabled',
      payload: <String, dynamic>{
        'enable': enabled,
        'execPath': '/opt/xstream/xstream',
      },
    );
    return (response['message'] as String?) ??
        ((response['ok'] == true) ? 'success' : '操作失败');
  }

  static Future<bool> isLinuxAutostartEnabled() async {
    if (!Platform.isLinux) return false;
    final response = await _invokeLinuxDesktopCommand('isAutostartEnabled');
    return response['autostartEnabled'] == true;
  }

  static Future<String> ensureLinuxTunnelPrivileges() async {
    if (!Platform.isLinux) return '当前平台暂不支持';
    final response = await _invokeLinuxDesktopCommand('ensureTunnelPrivileges');
    return (response['message'] as String?) ??
        ((response['ok'] == true) ? 'success' : '操作失败');
  }

  static Future<void> _notifyLinuxDesktop(String title, String body) async {
    if (!Platform.isLinux) {
      return;
    }
    await _invokeLinuxDesktopCommand(
      'notify',
      payload: <String, dynamic>{'title': title, 'body': body},
    );
  }

  static BridgeBindings get _ffi {
    _bindings ??= _useFfi
        ? BridgeBindings(_openLib())
        : throw UnsupportedError('FFI not available');
    return _bindings!;
  }

  static ffi.DynamicLibrary _openLib() {
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('libgo_native_bridge.dll');
    } else if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libgo_native_bridge.so');
    } else if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libgo_native_bridge.so');
    } else if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('libxray_bridge.dylib');
    } else if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform');
  }

  static Future<String> writeConfigFiles({
    required String xrayConfigPath,
    required String xrayConfigContent,
    required String servicePath,
    required String serviceContent,
    required String vpnNodesConfigPath,
    required String vpnNodesConfigContent,
    required String password,
  }) async {
    if (_isMobile || Platform.isMacOS) {
      try {
        await File(xrayConfigPath).parent.create(recursive: true);
        await File(servicePath).parent.create(recursive: true);
        await File(vpnNodesConfigPath).parent.create(recursive: true);
        await File(xrayConfigPath).writeAsString(xrayConfigContent);
        await File(servicePath).writeAsString(serviceContent);
        await File(vpnNodesConfigPath).writeAsString(vpnNodesConfigContent);
        return 'success';
      } catch (e) {
        return '写入失败: $e';
      }
    }

    if (!_isDesktop) return '当前平台暂不支持';

    if (_useFfi) {
      final p1 = xrayConfigPath.toNativeUtf8();
      final p2 = xrayConfigContent.toNativeUtf8();
      final p3 = servicePath.toNativeUtf8();
      final p4 = serviceContent.toNativeUtf8();
      final p5 = vpnNodesConfigPath.toNativeUtf8();
      final p6 = vpnNodesConfigContent.toNativeUtf8();
      final pwd = password.toNativeUtf8();
      final resPtr = _ffi.writeConfigFiles(
        p1.cast(),
        p2.cast(),
        p3.cast(),
        p4.cast(),
        p5.cast(),
        p6.cast(),
        pwd.cast(),
      );
      final result = resPtr.cast<Utf8>().toDartString();
      _ffi.freeCString(resPtr);
      malloc.free(p1);
      malloc.free(p2);
      malloc.free(p3);
      malloc.free(p4);
      malloc.free(p5);
      malloc.free(p6);
      malloc.free(pwd);
      return result;
    } else {
      try {
        final result = await _channel.invokeMethod<String>('writeConfigFiles', {
          'xrayConfigPath': xrayConfigPath,
          'xrayConfigContent': xrayConfigContent,
          'servicePath': servicePath,
          'serviceContent': serviceContent,
          'vpnNodesConfigPath': vpnNodesConfigPath,
          'vpnNodesConfigContent': vpnNodesConfigContent,
          'password': password,
        });
        return result ?? 'success';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '写入失败: $e';
      }
    }
  }

  /// Whether the current connection mode is TUN (VPN / Packet Tunnel).
  static bool get isTunMode => GlobalState.isTunnelMode;

  /// Start node via Packet Tunnel (TUN mode).
  ///
  /// Platform routing:
  /// - **iOS**: Pigeon → `DarwinHostApi.savePacketTunnelProfile` + `startPacketTunnel`
  /// - **Android**: MethodChannel → `savePacketTunnelProfile` + `startPacketTunnel`
  /// - **macOS**: Pigeon → `DarwinHostApi.savePacketTunnelProfile` + `startPacketTunnel`
  /// - **Windows**: FFI → `startXray(configJson)` (TUN inbound handled by xray-core tun2socks)
  /// - **Linux**: FFI → `startXray(configJson)` (TUN inbound handled by xray-core tun2socks)
  static Future<String> startNodeForTunnel(String nodeName) {
    return _runSerializedConnectionOp(
      () => _startNodeForTunnelInternal(nodeName),
    );
  }

  static Future<String> _startNodeForTunnelInternal(String nodeName) async {
    final node = VpnConfig.getNodeByName(nodeName);
    if (node == null) return '未知节点: $nodeName';

    final sourceConfigPath = await _resolveNodeConfigSource(node);
    if (sourceConfigPath == null) {
      final configsPath = await GlobalApplicationConfig.getConfigsPath();
      return '启动失败: 节点配置文件不存在\n'
          '预期路径: node-${_normalizeConfigToken(node.countryCode)}-config.json\n'
          '搜索目录: $configsPath';
    }
    // Keep node.configPath in sync
    if (node.configPath != sourceConfigPath) {
      node.configPath = sourceConfigPath;
      VpnConfig.updateNode(node);
      await VpnConfig.saveToFile();
    }
    final runtimeConfigPath = await _prepareCanonicalTunnelConfigPath(
      sourceConfigPath,
      isTunMode: true,
    );

    // ── Android: MethodChannel → savePacketTunnelProfile + startPacketTunnel
    if (Platform.isAndroid) {
      try {
        await _ensurePacketTunnelStoppedBeforeStart();
        _mobileActiveNodeName = null;
        final profile = await _buildDefaultTunnelProfileMap(
          configPath: runtimeConfigPath,
        );
        await _channel.invokeMethod<String>('savePacketTunnelProfile', profile);
        final result = await _channel.invokeMethod<String>(
          'startPacketTunnel',
          profile,
        );
        if (isTunnelStartAcceptedMessage(result)) {
          _mobileActiveNodeName = nodeName;
        }
        return result ?? 'Packet Tunnel 启动请求已提交';
      } on PlatformException catch (e) {
        return '启动失败: ${_platformErrorSummary(e)}';
      } catch (e) {
        return '启动失败: $e';
      }
    }

    // ── Darwin: Pigeon → DarwinHostApi.savePacketTunnelProfile + startPacketTunnel
    if (_isDarwin) {
      _ensureDarwinFlutterApiReady();
      try {
        await _ensurePacketTunnelStoppedBeforeStart();
        await _stopIosLocalEngineIfNeeded();
        final profile = await _buildDefaultTunnelProfile(
          configPath: runtimeConfigPath,
        );
        final saveResult = Platform.isIOS
            ? await _saveIosPacketTunnelProfileIfNeeded(profile)
            : await _darwinHostApi.savePacketTunnelProfile(profile);
        await _darwinHostApi.startPacketTunnel();
        if (saveResult != 'profile_saved' &&
            saveResult != 'profile_unchanged') {
          return saveResult;
        }
        return _waitForDarwinPacketTunnelConnected(
          successMessage: 'TUN 模式启动成功 ($nodeName)',
        );
      } on PlatformException catch (e) {
        return '启动失败: ${_platformErrorSummary(e)}';
      } catch (e) {
        return '启动失败: $e';
      }
    }

    // ── Windows: FFI → startXray with TUN inbound (xray-core tun2socks) ──
    if (Platform.isWindows) {
      try {
        await _stopOtherRunningNodes(nodeName);
        final configJson = await File(runtimeConfigPath).readAsString();
        if (_useFfi) {
          final configPtr = configJson.toNativeUtf8();
          final resPtr = _ffi.startXray(configPtr.cast());
          final result = resPtr.cast<Utf8>().toDartString();
          _ffi.freeCString(resPtr);
          malloc.free(configPtr);
          return result.toLowerCase().startsWith('success')
              ? 'TUN 模式启动成功 ($nodeName)'
              : '启动失败: $result';
        }
        return '启动失败: FFI 不可用';
      } catch (e) {
        return '启动失败: $e';
      }
    }

    // ── Linux: FFI → startXray with TUN inbound (xray-core tun2socks) ────
    if (Platform.isLinux) {
      try {
        final privilegeMessage = await ensureLinuxTunnelPrivileges();
        if (!privilegeMessage.toLowerCase().contains('ready') &&
            !privilegeMessage.toLowerCase().contains('success')) {
          return '启动失败: $privilegeMessage';
        }
        final helperResult = await _invokeLinuxDesktopCommand(
          'startTunnelHelper',
          payload: <String, dynamic>{'mode': 'tun'},
        );
        if (helperResult['ok'] != true) {
          return '启动失败: ${(helperResult['message'] as String?) ?? 'tunnel helper failed'}';
        }
        await _stopOtherRunningNodes(nodeName);
        final configJson = await File(runtimeConfigPath).readAsString();
        if (_useFfi) {
          final configPtr = configJson.toNativeUtf8();
          final resPtr = _ffi.startXray(configPtr.cast());
          final result = resPtr.cast<Utf8>().toDartString();
          _ffi.freeCString(resPtr);
          malloc.free(configPtr);
          if (result.toLowerCase().startsWith('success')) {
            await _notifyLinuxDesktop(
              'Xstream',
              'Tunnel Mode connected: $nodeName',
            );
            return 'TUN 模式启动成功 ($nodeName)';
          }
          await _invokeLinuxDesktopCommand(
            'stopTunnelHelper',
            payload: <String, dynamic>{'mode': 'tun'},
          );
          return '启动失败: $result';
        }
        return '启动失败: FFI 不可用';
      } catch (e) {
        return '启动失败: $e';
      }
    }

    return '当前平台暂不支持 TUN 模式';
  }

  /// Stop node via Packet Tunnel (TUN mode).
  ///
  /// Platform routing:
  /// - **iOS**: Pigeon → `DarwinHostApi.stopPacketTunnel`
  /// - **Android**: MethodChannel → `stopPacketTunnel`
  /// - **macOS**: Pigeon → `DarwinHostApi.stopPacketTunnel`
  /// - **Windows**: FFI → `stopXray()`
  /// - **Linux**: FFI → `stopXray()`
  static Future<String> stopNodeForTunnel() {
    return _runSerializedConnectionOp(_stopNodeForTunnelInternal);
  }

  static Future<String> _stopNodeForTunnelInternal() async {
    // ── Darwin: delegate to official Packet Tunnel control path ────
    if (_isDarwin) {
      final result = await _stopPacketTunnelInternal();
      _mobileActiveNodeName = null;
      return result;
    }

    // ── Windows / Linux: FFI stopXray ───────────────────────────────
    if (Platform.isWindows || Platform.isLinux) {
      try {
        if (_useFfi) {
          final resPtr = _ffi.stopXray();
          final result = resPtr.cast<Utf8>().toDartString();
          _ffi.freeCString(resPtr);
          if (Platform.isLinux) {
            await _invokeLinuxDesktopCommand(
              'stopTunnelHelper',
              payload: <String, dynamic>{'mode': 'tun'},
            );
            await _notifyLinuxDesktop('Xstream', 'Tunnel Mode disconnected');
          }
          return result.toLowerCase().startsWith('success')
              ? 'TUN 模式已停止'
              : '停止失败: $result';
        }
        return '停止失败: FFI 不可用';
      } catch (e) {
        return '停止失败: $e';
      }
    }

    // ── Android: delegate to existing stopPacketTunnel ──────────────
    final result = await _stopPacketTunnelInternal();
    _mobileActiveNodeName = null;
    return result;
  }

  // 启动节点服务（防止重复启动）— 代理模式
  static Future<String> startNodeService(String nodeName) {
    return _runSerializedConnectionOp(
      () => _startNodeServiceInternal(nodeName),
    );
  }

  static Future<String> _startNodeServiceInternal(String nodeName) async {
    final node = VpnConfig.getNodeByName(nodeName);
    if (node == null) return '未知节点: $nodeName';
    final sourceConfigPath = await _resolveNodeConfigSource(node);
    if (sourceConfigPath == null) {
      final configsPath = await GlobalApplicationConfig.getConfigsPath();
      return '启动失败: 节点配置文件不存在\n'
          '预期: node-${_normalizeConfigToken(node.countryCode)}-config.json\n'
          '搜索目录: $configsPath';
    }
    if (node.configPath != sourceConfigPath) {
      node.configPath = sourceConfigPath;
      VpnConfig.updateNode(node);
      await VpnConfig.saveToFile();
    }
    final runtimeConfigPath = await _prepareCanonicalTunnelConfigPath(
      sourceConfigPath,
      isTunMode: false,
    );

    if (_isMobile || Platform.isMacOS) {
      if (Platform.isAndroid) {
        final tunStatus = await getPacketTunnelStatus();
        if (tunStatus.status == 'connected' ||
            tunStatus.status == 'connecting') {
          return 'Packet Tunnel 已在运行，请先停止';
        }
      }
      if (await checkNodeStatus(nodeName)) return '服务已在运行';
      try {
        await _stopOtherRunningNodes(nodeName);
        if (_mobileActiveNodeName != null &&
            _mobileActiveNodeName != nodeName) {
          stopXray();
          _mobileActiveNodeName = null;
        }

        final configJson = await File(runtimeConfigPath).readAsString();
        final result = startXray(configJson);
        if (result.toLowerCase().startsWith('success')) {
          _mobileActiveNodeName = nodeName;
        }
        return result;
      } catch (e) {
        return '启动失败: $e';
      }
    }

    if (!_isDesktop) return '当前平台暂不支持';

    // ✅ 新增：避免重复启动
    final isRunning = await checkNodeStatus(nodeName);
    if (isRunning) return '服务已在运行';
    await _stopOtherRunningNodes(nodeName);

    if (_useFfi) {
      final namePtr = node.serviceName.toNativeUtf8();
      final resPtr = _ffi.startNodeService(namePtr.cast());
      final result = resPtr.cast<Utf8>().toDartString();
      _ffi.freeCString(resPtr);
      malloc.free(namePtr);
      if (Platform.isLinux && result.toLowerCase().startsWith('success')) {
        await _invokeLinuxDesktopCommand('setSystemProxy');
        await _notifyLinuxDesktop('Xstream', 'Proxy Mode connected: $nodeName');
      }
      return result;
    } else {
      try {
        final result = await _channel.invokeMethod<String>('startNodeService', {
          'serviceName': node.serviceName,
          'nodeName': node.name,
          'configPath': runtimeConfigPath,
        });
        return result ?? '启动成功';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '启动失败: $e';
      }
    }
  }

  // 停止节点服务
  static Future<String> stopNodeService(String nodeName) {
    return _runSerializedConnectionOp(() => _stopNodeServiceInternal(nodeName));
  }

  static Future<String> _stopNodeServiceInternal(String nodeName) async {
    final node = VpnConfig.getNodeByName(nodeName);
    if (node == null) return '未知节点: $nodeName';

    if (_isMobile || Platform.isMacOS) {
      if (_mobileActiveNodeName != nodeName) {
        return 'success';
      }
      try {
        final result = stopXray();
        if (result.toLowerCase().startsWith('success')) {
          _mobileActiveNodeName = null;
        }
        return result;
      } catch (e) {
        return '停止失败: $e';
      }
    }

    if (!_isDesktop) return '当前平台暂不支持';

    if (_useFfi) {
      final namePtr = node.serviceName.toNativeUtf8();
      final resPtr = _ffi.stopNodeService(namePtr.cast());
      final result = resPtr.cast<Utf8>().toDartString();
      _ffi.freeCString(resPtr);
      malloc.free(namePtr);
      if (Platform.isLinux && result.toLowerCase().startsWith('success')) {
        await _invokeLinuxDesktopCommand('clearSystemProxy');
        await _notifyLinuxDesktop('Xstream', 'Proxy Mode disconnected');
      }
      return result;
    } else {
      try {
        final result = await _channel.invokeMethod<String>('stopNodeService', {
          'serviceName': node.serviceName,
        });
        return result ?? '已停止';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '停止失败: $e';
      }
    }
  }

  // 检查节点状态
  static Future<bool> checkNodeStatus(String nodeName) async {
    final node = VpnConfig.getNodeByName(nodeName);
    if (node == null) return false;

    if (_isMobile || Platform.isMacOS) {
      return _mobileActiveNodeName == nodeName;
    }

    if (!_isDesktop) return false;
    if (_useFfi) {
      final namePtr = node.serviceName.toNativeUtf8();
      final res = _ffi.checkNodeStatus(namePtr.cast());
      malloc.free(namePtr);
      return res == 1;
    } else {
      try {
        final result = await _channel.invokeMethod<bool>('checkNodeStatus', {
          'serviceName': node.serviceName,
          'nodeName': node.name,
          'configPath': node.configPath,
        });
        return result ?? false;
      } on MissingPluginException {
        return false;
      } catch (_) {
        return false;
      }
    }
  }

  // 初始化日志监听（用于原生发送 log 到 Dart）
  static void initializeLogger(Function(String log) onLog) {
    _loggerChannel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        final log = call.arguments;
        if (log is String) onLog(log);
      }
    });
  }

  static void initializeNativeMenuActions(
    Future<void> Function(String action, Map<String, dynamic> payload) onAction,
  ) {
    _nativeMenuActionHandler = onAction;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nativeMenuAction') {
        final args =
            (call.arguments as Map?)?.cast<Object?, Object?>() ??
            <Object?, Object?>{};
        final action = (args['action'] as String?) ?? '';
        final payloadRaw =
            (args['payload'] as Map?)?.cast<Object?, Object?>() ??
            <Object?, Object?>{};
        final payload = <String, dynamic>{};
        payloadRaw.forEach((key, value) {
          if (key is String) {
            payload[key] = value;
          }
        });
        if (action.isNotEmpty) {
          final handler = _nativeMenuActionHandler;
          if (handler != null) {
            await handler(action, payload);
          }
        }
      }
    });
  }

  static Future<void> updateMenuState({
    required bool connected,
    required String nodeName,
    required String proxyMode,
    required String languageCode,
  }) async {
    if (!(Platform.isMacOS || Platform.isWindows)) return;
    try {
      await _channel.invokeMethod<String>('updateMenuState', {
        'connected': connected,
        'nodeName': nodeName,
        'proxyMode': proxyMode,
        'languageCode': languageCode,
      });
    } catch (_) {}
  }

  /// 查询 Xray Core 是否正在下载
  static Future<bool> isXrayDownloading() async {
    if (!_isDesktop || Platform.isMacOS) return false;
    if (_useFfi) {
      final res = _ffi.isXrayDownloading();
      return res == 1;
    } else {
      try {
        final result = await _channel.invokeMethod<String>('performAction', {
          'action': 'isXrayDownloading',
        });
        return result == '1';
      } on MissingPluginException {
        return false;
      } catch (_) {
        return false;
      }
    }
  }

  // 重置配置和 Xray 文件：触发 performAction:resetXrayAndConfig
  static Future<String> resetXrayAndConfig(String password) async {
    if (!_isDesktop || Platform.isMacOS) return '当前平台暂不支持';
    if (_useFfi) {
      final actionPtr = 'resetXrayAndConfig'.toNativeUtf8();
      final pwdPtr = password.toNativeUtf8();
      final resPtr = _ffi.performAction(actionPtr.cast(), pwdPtr.cast());
      final result = resPtr.cast<Utf8>().toDartString();
      _ffi.freeCString(resPtr);
      malloc.free(actionPtr);
      malloc.free(pwdPtr);
      return result;
    } else {
      try {
        final result = await _channel.invokeMethod<String>('performAction', {
          'action': 'resetXrayAndConfig',
          'password': password,
        });
        return result ?? '重置完成';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '重置失败: $e';
      }
    }
  }

  /// Enable or disable system proxy on desktop platforms.
  static Future<String> setSystemProxy(bool enable, String password) async {
    if (Platform.isLinux) {
      final response = await _invokeLinuxDesktopCommand(
        enable ? 'setSystemProxy' : 'clearSystemProxy',
      );
      return (response['message'] as String?) ??
          ((response['ok'] == true) ? 'success' : '操作失败');
    }
    if (!Platform.isMacOS) return '当前平台暂不支持';
    try {
      final result = await _channel.invokeMethod<String>('setSystemProxy', {
        'enable': enable,
        'password': password,
      });
      return result ?? 'success';
    } on MissingPluginException {
      return '插件未实现';
    } catch (e) {
      return '操作失败: $e';
    }
  }

  static Future<String> verifySocks5Proxy() async {
    if (Platform.isMacOS) {
      try {
        final result = await _channel.invokeMethod<String>('verifySocks5Proxy');
        return result ?? '验证失败: 无返回';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '验证失败: $e';
      }
    }

    if (_isDesktop) {
      try {
        final port = int.tryParse(GlobalState.socksPort.value) ?? 1080;
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 3),
        );
        await socket.close();
        return 'success: local SOCKS proxy is reachable';
      } catch (e) {
        return '验证失败: $e';
      }
    }

    return '当前平台暂不支持';
  }

  static Future<DesktopRuntimeSnapshot> getDesktopRuntimeSnapshot() async {
    if (!(Platform.isWindows || Platform.isLinux)) {
      return _desktopRuntimeSnapshotFallback;
    }
    if (!_useFfi) {
      return _desktopRuntimeSnapshotFallback;
    }
    final getter = _ffi.getDesktopRuntimeSnapshot;
    if (getter == null) {
      return _desktopRuntimeSnapshotFallback;
    }
    try {
      final resPtr = getter();
      final result = resPtr.cast<Utf8>().toDartString();
      _ffi.freeCString(resPtr);
      return DesktopRuntimeSnapshot.fromJsonString(result);
    } catch (e) {
      addAppLog(
        'Desktop runtime snapshot query failed: $e',
        level: LogLevel.error,
      );
      return _desktopRuntimeSnapshotFallback;
    }
  }

  static Future<darwin_host.TunnelProfile> _buildDefaultTunnelProfile({
    required String configPath,
  }) async {
    return darwin_host.TunnelProfile(
      mtu: 1500,
      tun46Setting: 2,
      defaultNicSupport6: true,
      dnsServers4: DnsConfig.systemTunnelDnsServers4(),
      dnsServers6: DnsConfig.systemTunnelDnsServers6(),
      ipv4Addresses: <String>['10.0.0.2'],
      ipv4SubnetMasks: <String>['255.255.255.0'],
      ipv4IncludedRoutes: <darwin_host.TunnelRouteV4>[
        darwin_host.TunnelRouteV4(
          destinationAddress: '0.0.0.0',
          subnetMask: '0.0.0.0',
        ),
      ],
      ipv4ExcludedRoutes: <darwin_host.TunnelRouteV4>[],
      ipv6Addresses: <String>['fd00::2'],
      ipv6NetworkPrefixLengths: <int>[120],
      ipv6IncludedRoutes: <darwin_host.TunnelRouteV6>[
        darwin_host.TunnelRouteV6(
          destinationAddress: '::',
          networkPrefixLength: 0,
        ),
      ],
      ipv6ExcludedRoutes: <darwin_host.TunnelRouteV6>[],
      configPath: configPath,
    );
  }

  static Future<Map<String, Object?>> _buildDefaultTunnelProfileMap({
    String? configPath,
  }) async {
    return <String, Object?>{
      'mtu': 1500,
      'tun46Setting': 2,
      'defaultNicSupport6': true,
      'dnsServers4': DnsConfig.systemTunnelDnsServers4(),
      'dnsServers6': DnsConfig.systemTunnelDnsServers6(),
      'ipv4Addresses': <String>['10.0.0.2'],
      'ipv4SubnetMasks': <String>['255.255.255.0'],
      'ipv4IncludedRoutes': <Map<String, String>>[
        const <String, String>{
          'destinationAddress': '0.0.0.0',
          'subnetMask': '0.0.0.0',
        },
      ],
      'ipv4ExcludedRoutes': <Map<String, String>>[],
      'ipv6Addresses': <String>['fd00::2'],
      'ipv6NetworkPrefixLengths': <int>[120],
      'ipv6IncludedRoutes': <Map<String, Object?>>[
        const <String, Object?>{
          'destinationAddress': '::',
          'networkPrefixLength': 0,
        },
      ],
      'ipv6ExcludedRoutes': <Map<String, Object?>>[],
      'configPath': configPath ?? '',
    };
  }

  static Future<String?> _resolveTunnelConfigPath() async {
    try {
      await VpnConfig.load();
    } catch (_) {}

    final active = _mobileActiveNodeName;
    if (active != null && active.trim().isNotEmpty) {
      final node = VpnConfig.getNodeByName(active);
      if (node != null) {
        final resolved = await _resolveNodeConfigSource(node);
        if (resolved != null) {
          if (node.configPath != resolved) {
            node.configPath = resolved;
            VpnConfig.updateNode(node);
            await VpnConfig.saveToFile();
          }
          return resolved;
        }
      }
    }

    for (final node in VpnConfig.nodes) {
      if (!node.enabled) continue;
      final resolved = await _resolveNodeConfigSource(node);
      if (resolved != null) {
        if (node.configPath != resolved) {
          node.configPath = resolved;
          VpnConfig.updateNode(node);
          await VpnConfig.saveToFile();
        }
        return resolved;
      }
    }

    for (final node in VpnConfig.nodes) {
      final resolved = await _resolveNodeConfigSource(node);
      if (resolved != null) {
        if (node.configPath != resolved) {
          node.configPath = resolved;
          VpnConfig.updateNode(node);
          await VpnConfig.saveToFile();
        }
        return resolved;
      }
    }
    return null;
  }

  static Future<String> _resolveOrBootstrapIosTunnelConfigPath() async {
    final resolved = await _resolveTunnelConfigPath();
    if (resolved != null) {
      return _prepareCanonicalTunnelConfigPath(resolved, isTunMode: true);
    }
    return _bootstrapNodeConfigPath(isTunMode: true);
  }

  static Future<String> _darwinTunnelConfigsPath() async {
    if (!Platform.isIOS) {
      return GlobalApplicationConfig.getConfigsPath();
    }

    _ensureDarwinFlutterApiReady();
    try {
      final root =
          _darwinAppGroupPathCache ?? await _darwinHostApi.appGroupPath();
      _darwinAppGroupPathCache = root;
      final dir = Directory('$root/configs');
      await dir.create(recursive: true);
      return dir.path;
    } on MissingPluginException {
      return GlobalApplicationConfig.getConfigsPath();
    } on PlatformException {
      return GlobalApplicationConfig.getConfigsPath();
    }
  }

  static Future<String> _prepareCanonicalTunnelConfigPath(
    String sourcePath, {
    required bool isTunMode,
  }) async {
    final normalized = sourcePath.trim();
    if (normalized.isEmpty) return sourcePath;
    final sourceFile = File(normalized);
    if (!await sourceFile.exists()) return sourcePath;

    try {
      final sourceJsonStr = await sourceFile.readAsString();
      final sourceJson = jsonDecode(sourceJsonStr) as Map<String, dynamic>;

      final disableLocalProxyInPacketTunnel = Platform.isIOS && isTunMode;
      final newInboundsStr = VpnConfig.generateInboundsConfig(
        enableSocksProxy: !disableLocalProxyInPacketTunnel,
        enableHttpProxy: !disableLocalProxyInPacketTunnel,
        enableTunnelMode: isTunMode,
      );
      sourceJson['inbounds'] = jsonDecode(newInboundsStr);

      final updatedJsonStr = const JsonEncoder.withIndent(
        '  ',
      ).convert(sourceJson);
      if (sourceJsonStr != updatedJsonStr) {
        await sourceFile.writeAsString(updatedJsonStr);
      }
      await _removeLegacyCanonicalConfigIfNeeded(keepPath: normalized);
      return normalized;
    } catch (_) {
      return normalized;
    }
  }

  static Future<void> _removeLegacyCanonicalConfigIfNeeded({
    required String keepPath,
  }) async {
    final configsPath = await _darwinTunnelConfigsPath();
    final legacyPath = '$configsPath/config.json';
    if (legacyPath == keepPath) return;
    try {
      final linkType = await FileSystemEntity.type(
        legacyPath,
        followLinks: false,
      );
      if (linkType == FileSystemEntityType.link) {
        await Link(legacyPath).delete();
      } else if (linkType == FileSystemEntityType.file) {
        await File(legacyPath).delete();
      } else if (linkType == FileSystemEntityType.directory) {
        await Directory(legacyPath).delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<String> _bootstrapNodeConfigPath({
    required bool isTunMode,
  }) async {
    final configsPath = await _darwinTunnelConfigsPath();
    await Directory(configsPath).create(recursive: true);
    final bootstrapPath = '$configsPath/node-default-config.json';
    final file = File(bootstrapPath);
    if (!await file.exists()) {
      await file.writeAsString(
        _buildBootstrapNodeConfigString(isTunMode: isTunMode),
      );
    }
    await _removeLegacyCanonicalConfigIfNeeded(keepPath: bootstrapPath);
    return bootstrapPath;
  }

  static String _buildBootstrapNodeConfigString({required bool isTunMode}) {
    final disableLocalProxyInPacketTunnel = Platform.isIOS && isTunMode;
    final inboundsStr = VpnConfig.generateInboundsConfig(
      enableSocksProxy: !disableLocalProxyInPacketTunnel,
      enableHttpProxy: !disableLocalProxyInPacketTunnel,
      enableTunnelMode: isTunMode,
    );
    final root = <String, dynamic>{
      'log': <String, dynamic>{'loglevel': 'warning'},
      'dns': <String, dynamic>{
        'servers': <String>['1.1.1.1', '8.8.8.8'],
        'queryStrategy': 'UseIPv4',
      },
      'inbounds': jsonDecode(inboundsStr),
      'outbounds': <Map<String, dynamic>>[
        <String, dynamic>{'protocol': 'freedom', 'tag': 'direct'},
        <String, dynamic>{'protocol': 'blackhole', 'tag': 'block'},
        <String, dynamic>{'protocol': 'dns', 'tag': 'dns'},
      ],
      'routing': <String, dynamic>{'rules': <Object>[]},
    };
    return const JsonEncoder.withIndent('  ').convert(root);
  }

  static Future<String?> _resolveNodeConfigSource(VpnNode node) async {
    final rawPath = node.configPath.trim();
    if (rawPath.isNotEmpty && await File(rawPath).exists()) {
      return rawPath;
    }
    return _findFallbackConfigPath(node);
  }

  static Future<String?> _findFallbackConfigPath(VpnNode node) async {
    final configsPath = await GlobalApplicationConfig.getConfigsPath();
    final dir = Directory(configsPath);
    if (!await dir.exists()) return null;

    final code = _normalizeConfigToken(node.countryCode);
    final nameToken = _normalizeConfigToken(node.name);
    final candidates = <String>[
      '$configsPath/node-$code-config.json',
      if (nameToken.isNotEmpty) '$configsPath/node-$nameToken-config.json',
    ];

    for (final file in candidates) {
      if (await File(file).exists()) {
        return file;
      }
    }

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (RegExp(r'^node-[a-z0-9-]+-config\.json$').hasMatch(name)) {
        return entity.path;
      }
    }
    return null;
  }

  static String _normalizeConfigToken(String raw) {
    final token = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return token.isEmpty ? 'node' : token;
  }

  static Future<void> _stopOtherRunningNodes(String targetNodeName) async {
    for (final candidate in VpnConfig.nodes) {
      if (candidate.name == targetNodeName) continue;
      final running = await checkNodeStatus(candidate.name);
      if (!running) continue;
      await _stopNodeServiceInternal(candidate.name);
    }
  }

  static Future<void> _stopIosLocalEngineIfNeeded() async {
    if (!Platform.isIOS) return;

    try {
      final result = stopXray().trim().toLowerCase();
      if (result.startsWith('success')) {
        addAppLog(
          'iOS local engine stopped before Packet Tunnel startup',
          level: LogLevel.info,
        );
      }
    } catch (_) {
      // Ignore cleanup failures here. Packet Tunnel startup will report the
      // real runtime error if anything is still wrong.
    } finally {
      _mobileActiveNodeName = null;
    }
  }

  static void _ensureDarwinFlutterApiReady() {
    if (!_isDarwin || _darwinFlutterApiReady) return;
    darwin_host.DarwinFlutterApi.setUp(_DarwinFlutterApiImpl());
    _darwinFlutterApiReady = true;
  }

  static Future<String> prepareNodeForTunnel(String nodeName) async {
    if (!Platform.isIOS) {
      return '当前平台无需预注册 Packet Tunnel 配置';
    }

    final node = VpnConfig.getNodeByName(nodeName);
    if (node == null) return '未知节点: $nodeName';

    final sourceConfigPath = await _resolveNodeConfigSource(node);
    if (sourceConfigPath == null) {
      final configsPath = await GlobalApplicationConfig.getConfigsPath();
      return '保存失败: 节点配置文件不存在\n'
          '预期路径: node-${_normalizeConfigToken(node.countryCode)}-config.json\n'
          '搜索目录: $configsPath';
    }

    if (node.configPath != sourceConfigPath) {
      node.configPath = sourceConfigPath;
      VpnConfig.updateNode(node);
      await VpnConfig.saveToFile();
    }

    final runtimeConfigPath = await _prepareCanonicalTunnelConfigPath(
      sourceConfigPath,
      isTunMode: true,
    );

    _ensureDarwinFlutterApiReady();
    try {
      final profile = await _buildDefaultTunnelProfile(
        configPath: runtimeConfigPath,
      );
      final saveResult = await _saveIosPacketTunnelProfileIfNeeded(profile);
      return saveResult == 'profile_saved' || saveResult == 'profile_unchanged'
          ? 'iOS Packet Tunnel 配置已保存到系统 VPN 列表'
          : saveResult;
    } on MissingPluginException {
      return '插件未实现';
    } on PlatformException catch (e) {
      return '保存失败: ${_platformErrorSummary(e)}';
    } catch (e) {
      return '保存失败: $e';
    }
  }

  static Future<String> ensureIosSystemVpnProfileRegistered() async {
    if (!Platform.isIOS) {
      return '当前平台无需注册 System VPN 配置';
    }

    _ensureDarwinFlutterApiReady();
    try {
      final configPath = await _resolveOrBootstrapIosTunnelConfigPath();
      final profile = await _buildDefaultTunnelProfile(configPath: configPath);
      final saveResult = await _saveIosPacketTunnelProfileIfNeeded(
        profile,
        force: true,
      );
      return saveResult == 'profile_saved' || saveResult == 'profile_unchanged'
          ? 'iOS System VPN 配置已注册到系统列表'
          : saveResult;
    } on MissingPluginException {
      return '插件未实现';
    } on PlatformException catch (e) {
      return '注册失败: ${_platformErrorSummary(e)}';
    } catch (e) {
      return '注册失败: $e';
    }
  }

  /// Start Packet Tunnel on Darwin platforms.
  static Future<String> startPacketTunnel() {
    return _runSerializedConnectionOp(_startPacketTunnelInternal);
  }

  static Future<String> _startPacketTunnelInternal() async {
    if (Platform.isAndroid) {
      try {
        await _ensurePacketTunnelStoppedBeforeStart();
        final configPath = await _resolveTunnelConfigPath();
        if (configPath == null) {
          return '未找到可用的节点配置';
        }
        final canonicalPath = await _prepareCanonicalTunnelConfigPath(
          configPath,
          isTunMode: true,
        );
        stopXray();
        _mobileActiveNodeName = null;
        final profile = await _buildDefaultTunnelProfileMap(
          configPath: canonicalPath,
        );
        await _channel.invokeMethod<String>('savePacketTunnelProfile', profile);
        final result = await _channel.invokeMethod<String>(
          'startPacketTunnel',
          profile,
        );
        return result ?? 'Packet Tunnel start request submitted';
      } on MissingPluginException {
        return '插件未实现';
      } on PlatformException catch (e) {
        return '启动失败: ${_platformErrorSummary(e)}';
      } catch (e) {
        return '启动失败: $e';
      }
    }

    if (!_isDarwin) return '当前平台暂不支持';
    _ensureDarwinFlutterApiReady();
    try {
      await _ensurePacketTunnelStoppedBeforeStart();
      await _stopIosLocalEngineIfNeeded();
      final configPath = await _resolveTunnelConfigPath();
      if (configPath == null) {
        return '未找到可用的节点配置';
      }
      final canonicalPath = await _prepareCanonicalTunnelConfigPath(
        configPath,
        isTunMode: true,
      );
      final profile = await _buildDefaultTunnelProfile(
        configPath: canonicalPath,
      );
      final saveResult = Platform.isIOS
          ? await _saveIosPacketTunnelProfileIfNeeded(profile)
          : await _darwinHostApi.savePacketTunnelProfile(profile);
      await _darwinHostApi.startPacketTunnel();
      if (saveResult != 'profile_saved' && saveResult != 'profile_unchanged') {
        return saveResult;
      }
      return _waitForDarwinPacketTunnelConnected(
        successMessage: 'Packet Tunnel 已连接',
      );
    } on MissingPluginException {
      return '插件未实现';
    } on PlatformException catch (e) {
      return '启动失败: ${_platformErrorSummary(e)}';
    } catch (e) {
      return '启动失败: $e';
    }
  }

  /// Stop Packet Tunnel on Darwin platforms.
  static Future<String> stopPacketTunnel() {
    return _runSerializedConnectionOp(_stopPacketTunnelInternal);
  }

  static Future<String> _stopPacketTunnelInternal() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('stopPacketTunnel');
        return result ?? 'Packet Tunnel stop request submitted';
      } on MissingPluginException {
        return '插件未实现';
      } on PlatformException catch (e) {
        return '停止失败: ${_platformErrorSummary(e)}';
      } catch (e) {
        return '停止失败: $e';
      }
    }

    if (!_isDarwin) return '当前平台暂不支持';
    _ensureDarwinFlutterApiReady();
    try {
      await _darwinHostApi.stopPacketTunnel();
      return 'Packet Tunnel stop request submitted';
    } on MissingPluginException {
      return '插件未实现';
    } on PlatformException catch (e) {
      return '停止失败: ${_platformErrorSummary(e)}';
    } catch (e) {
      return '停止失败: $e';
    }
  }

  static Future<void> _ensurePacketTunnelStoppedBeforeStart() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<String>('stopPacketTunnel');
      } catch (_) {}
      return;
    }

    if (!_isDarwin) return;
    _ensureDarwinFlutterApiReady();
    try {
      final status = await _darwinHostApi.getPacketTunnelStatus();
      const activeStates = <String>{
        'connected',
        'connecting',
        'reasserting',
        'disconnecting',
      };
      if (activeStates.contains(status.state)) {
        await _darwinHostApi.stopPacketTunnel();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } catch (_) {}
  }

  /// Get Packet Tunnel status on Darwin platforms.
  static Future<PacketTunnelStatus> getPacketTunnelStatus() async {
    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getPacketTunnelStatus',
        );
        if (raw == null) return _tunStatusFallback;
        final map = <Object?, Object?>{};
        raw.forEach((key, value) {
          map[key] = value;
        });
        return PacketTunnelStatus.fromMap(map);
      } on MissingPluginException {
        return _tunStatusFallback;
      } catch (_) {
        return _tunStatusFallback;
      }
    }

    if (Platform.isWindows || Platform.isLinux) {
      final snapshot = await getDesktopRuntimeSnapshot();
      return PacketTunnelStatus(
        status: snapshot.running ? 'connected' : 'disconnected',
        utunInterfaces: const [],
      );
    }

    if (!_isDarwin) return _tunStatusFallback;
    _ensureDarwinFlutterApiReady();
    try {
      final status = await _darwinHostApi.getPacketTunnelStatus();
      return PacketTunnelStatus(
        status: status.state,
        utunInterfaces: status.utunInterfaces,
        lastError: status.lastError,
        startedAt: status.startedAt,
      );
    } on MissingPluginException {
      addAppLog(
        'Packet Tunnel status query unavailable: DarwinHostApi channel missing',
        level: LogLevel.error,
      );
      return _tunStatusFallback;
    } catch (e) {
      addAppLog('Packet Tunnel status query failed: $e', level: LogLevel.error);
      return _tunStatusFallback;
    }
  }

  static Future<String> openVpnSettings() async {
    if (!Platform.isAndroid) return '当前平台暂不支持';
    try {
      final result = await _channel.invokeMethod<String>('openVpnSettings');
      return result ?? 'opened';
    } on MissingPluginException {
      return '插件未实现';
    } catch (e) {
      return 'failed: $e';
    }
  }

  static Future<PacketTunnelMetricsSnapshot> getPacketTunnelMetrics() async {
    if (Platform.isWindows || Platform.isLinux) {
      final snapshot = await getDesktopRuntimeSnapshot();
      return PacketTunnelMetricsSnapshot(
        downloadBytesPerSecond: snapshot.downloadBytesPerSecond,
        uploadBytesPerSecond: snapshot.uploadBytesPerSecond,
        memoryBytes: snapshot.memoryBytes,
        cpuPercent: snapshot.cpuPercent,
        updatedAt: snapshot.updatedAt,
      );
    }

    if (!_isDarwin) return _tunMetricsFallback;
    _ensureDarwinFlutterApiReady();
    try {
      final snapshot = await _darwinHostApi.getPacketTunnelMetrics();
      return PacketTunnelMetricsSnapshot(
        downloadBytesPerSecond: snapshot.downloadBytesPerSecond,
        uploadBytesPerSecond: snapshot.uploadBytesPerSecond,
        memoryBytes: snapshot.memoryBytes,
        cpuPercent: snapshot.cpuPercent,
        updatedAt: snapshot.updatedAt,
      );
    } on MissingPluginException {
      addAppLog(
        'Packet Tunnel metrics query unavailable: DarwinHostApi channel missing',
        level: LogLevel.error,
      );
      return _tunMetricsFallback;
    } catch (e) {
      addAppLog(
        'Packet Tunnel metrics query failed: $e',
        level: LogLevel.error,
      );
      return _tunMetricsFallback;
    }
  }

  static Future<String> _waitForDarwinPacketTunnelConnected({
    required String successMessage,
    Duration timeout = const Duration(seconds: 12),
    bool allowIosProfileRepair = true,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var lastStatus = _tunStatusFallback;

    while (DateTime.now().isBefore(deadline)) {
      lastStatus = await getPacketTunnelStatus();
      final state = lastStatus.status;
      final error = lastStatus.lastError?.trim();

      if (state == 'connected') {
        return successMessage;
      }
      if ((state == 'disconnected' || state == 'invalid') &&
          error != null &&
          error.isNotEmpty) {
        if (Platform.isIOS &&
            allowIosProfileRepair &&
            _looksLikeIosPluginRegistrationError(error)) {
          final repairResult = await ensureIosSystemVpnProfileRegistered();
          addAppLog('iOS System VPN profile repair: $repairResult');
          try {
            await _darwinHostApi.startPacketTunnel();
          } on PlatformException catch (e) {
            return '启动失败: ${_platformErrorSummary(e)}';
          } catch (e) {
            return '启动失败: $e';
          }
          return _waitForDarwinPacketTunnelConnected(
            successMessage: successMessage,
            timeout: timeout,
            allowIosProfileRepair: false,
          );
        }
        return '启动失败: $error';
      }

      await Future.delayed(const Duration(milliseconds: 250));
    }

    final error = lastStatus.lastError?.trim();
    if (error != null && error.isNotEmpty) {
      return '启动失败: $error';
    }
    final utunDetail = lastStatus.utunInterfaces.isEmpty
        ? ''
        : ' (${lastStatus.utunInterfaces.join(", ")})';
    return '启动失败: Packet Tunnel 状态未就绪: ${lastStatus.status}$utunDetail';
  }

  static bool _looksLikeIosPluginRegistrationError(String error) {
    final normalized = error.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized.contains('domain=nevpnconnectionerrordomain') &&
        normalized.contains('code=14')) {
      return true;
    }
    if (normalized.contains(
      'the vpn app used by the vpn configuration is not installed',
    )) {
      return true;
    }
    if (normalized.contains('needed to be updated')) {
      return true;
    }
    return false;
  }

  static Future<String> _saveIosPacketTunnelProfileIfNeeded(
    darwin_host.TunnelProfile profile, {
    bool force = false,
  }) async {
    if (!Platform.isIOS) {
      return _darwinHostApi.savePacketTunnelProfile(profile);
    }
    final result = await _darwinHostApi.savePacketTunnelProfile(profile);
    if (force) {
      return result;
    }
    // The Packet Tunnel profile can be modified outside Flutter during tests
    // and extension reconnects, so app-side signature caching is not reliable.
    return result;
  }

  /// Start embedded xray-core via FFI on iOS
  static String startXray(String configJson) {
    if (!_useFfi) {
      throw UnsupportedError('FFI not available');
    }
    final conf = configJson.toNativeUtf8();
    final resPtr = _ffi.startXray(conf.cast());
    final result = resPtr.cast<Utf8>().toDartString();
    _ffi.freeCString(resPtr);
    malloc.free(conf);
    return result;
  }

  /// Stop embedded xray-core instance on iOS
  static String stopXray() {
    if (!_useFfi) {
      throw UnsupportedError('FFI not available');
    }
    final resPtr = _ffi.stopXray();
    final result = resPtr.cast<Utf8>().toDartString();
    _ffi.freeCString(resPtr);
    return result;
  }
}

class LinuxDesktopIntegrationStatus {
  final String desktopEnvironment;
  final bool autostartEnabled;
  final bool privilegeReady;
  final String? message;

  const LinuxDesktopIntegrationStatus({
    required this.desktopEnvironment,
    required this.autostartEnabled,
    required this.privilegeReady,
    this.message,
  });

  factory LinuxDesktopIntegrationStatus.fromMap(Map<String, dynamic> map) {
    return LinuxDesktopIntegrationStatus(
      desktopEnvironment: (map['desktopEnvironment'] as String?) ?? 'unknown',
      autostartEnabled: map['autostartEnabled'] == true,
      privilegeReady: map['privilegeReady'] == true,
      message: map['message'] as String?,
    );
  }
}

class _DarwinFlutterApiImpl extends darwin_host.DarwinFlutterApi {
  @override
  void onPacketTunnelError(String code, String message) {
    addAppLog('Packet Tunnel error ($code): $message', level: LogLevel.error);
  }

  @override
  void onPacketTunnelStateChanged(darwin_host.TunnelStatus status) {
    addAppLog(
      'Packet Tunnel state changed: ${status.state}',
      level: LogLevel.info,
    );
  }

  @override
  void onSystemWillRestart() {}

  @override
  void onSystemWillShutdown() {}

  @override
  void onSystemWillSleep() {}
}

class PacketTunnelStatus {
  final String status;
  final List<String> utunInterfaces;
  final String? lastError;
  final int? startedAt;

  const PacketTunnelStatus({
    required this.status,
    required this.utunInterfaces,
    this.lastError,
    this.startedAt,
  });

  factory PacketTunnelStatus.fromMap(Map<Object?, Object?> map) {
    final status = map['status'] as String? ?? 'unknown';
    final utunRaw = map['utun'];
    final utunList = utunRaw is List
        ? utunRaw.whereType<String>().toList()
        : <String>[];
    final lastError = map['lastError'] as String?;
    final startedAtRaw = map['startedAt'];
    final startedAt = startedAtRaw is int ? startedAtRaw : null;
    return PacketTunnelStatus(
      status: status,
      utunInterfaces: utunList,
      lastError: lastError,
      startedAt: startedAt,
    );
  }
}

class DesktopRuntimeSnapshot {
  final bool running;
  final int? downloadBytesPerSecond;
  final int? uploadBytesPerSecond;
  final int? memoryBytes;
  final double? cpuPercent;
  final int? updatedAt;

  const DesktopRuntimeSnapshot({
    this.running = false,
    this.downloadBytesPerSecond,
    this.uploadBytesPerSecond,
    this.memoryBytes,
    this.cpuPercent,
    this.updatedAt,
  });

  factory DesktopRuntimeSnapshot.fromJsonString(String jsonString) {
    if (jsonString.trim().isEmpty) {
      return const DesktopRuntimeSnapshot();
    }

    try {
      final raw = jsonDecode(jsonString);
      if (raw is! Map<String, dynamic>) {
        return const DesktopRuntimeSnapshot();
      }
      return DesktopRuntimeSnapshot(
        running: raw['running'] == true,
        downloadBytesPerSecond: (raw['downloadBytesPerSecond'] as num?)
            ?.toInt(),
        uploadBytesPerSecond: (raw['uploadBytesPerSecond'] as num?)?.toInt(),
        memoryBytes: (raw['memoryBytes'] as num?)?.toInt(),
        cpuPercent: (raw['cpuPercent'] as num?)?.toDouble(),
        updatedAt: (raw['updatedAt'] as num?)?.toInt(),
      );
    } catch (_) {
      return const DesktopRuntimeSnapshot();
    }
  }
}

class PacketTunnelMetricsSnapshot {
  final int? downloadBytesPerSecond;
  final int? uploadBytesPerSecond;
  final int? memoryBytes;
  final double? cpuPercent;
  final int? updatedAt;

  const PacketTunnelMetricsSnapshot({
    this.downloadBytesPerSecond,
    this.uploadBytesPerSecond,
    this.memoryBytes,
    this.cpuPercent,
    this.updatedAt,
  });
}
