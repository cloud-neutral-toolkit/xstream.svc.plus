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
  static const MethodChannel _loggerChannel =
      MethodChannel('com.xstream/logger');
  static final darwin_host.DarwinHostApi _darwinHostApi =
      darwin_host.DarwinHostApi();
  static bool _darwinFlutterApiReady = false;
  static Future<void> Function(String action, Map<String, dynamic> payload)?
      _nativeMenuActionHandler;
  static String? _mobileActiveNodeName;

  static final bool _useFfi = Platform.isWindows ||
      Platform.isLinux ||
      Platform.isIOS ||
      Platform.isAndroid;
  static BridgeBindings? _bindings;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static bool get _isDarwin => Platform.isMacOS || Platform.isIOS;

  static bool get _isMobile => Platform.isIOS || Platform.isAndroid;

  static const _tunStatusFallback = PacketTunnelStatus(
    status: 'unsupported',
    utunInterfaces: [],
  );

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
    if (_isMobile) {
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
      final resPtr = _ffi.writeConfigFiles(p1.cast(), p2.cast(), p3.cast(),
          p4.cast(), p5.cast(), p6.cast(), pwd.cast());
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

  // 启动节点服务（防止重复启动）
  static Future<String> startNodeService(String nodeName) async {
    final node = VpnConfig.getNodeByName(nodeName);
    if (node == null) return '未知节点: $nodeName';
    final configOk = await _ensureNodeConfigReady(node);
    if (!configOk) {
      return '启动失败: 节点配置文件不存在 (${node.configPath})';
    }

    if (_isMobile) {
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

        final configJson = await File(node.configPath).readAsString();
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
      return result;
    } else {
      try {
        final result = await _channel.invokeMethod<String>(
          'startNodeService',
          {
            'serviceName': node.serviceName,
            'nodeName': node.name,
            'configPath': node.configPath,
          },
        );
        return result ?? '启动成功';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '启动失败: $e';
      }
    }
  }

  // 停止节点服务
  static Future<String> stopNodeService(String nodeName) async {
    final node = VpnConfig.getNodeByName(nodeName);
    if (node == null) return '未知节点: $nodeName';

    if (_isMobile) {
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
      return result;
    } else {
      try {
        final result = await _channel.invokeMethod<String>(
          'stopNodeService',
          {'serviceName': node.serviceName},
        );
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

    if (_isMobile) {
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
        final result = await _channel.invokeMethod<bool>(
          'checkNodeStatus',
          {
            'serviceName': node.serviceName,
            'nodeName': node.name,
            'configPath': node.configPath,
          },
        );
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
        final args = (call.arguments as Map?)?.cast<Object?, Object?>() ??
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
  }) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<String>('updateMenuState', {
        'connected': connected,
        'nodeName': nodeName,
        'proxyMode': proxyMode,
      });
    } catch (_) {}
  }

  /// 更新 Xray Core：触发 performAction:updateXrayCore
  static Future<String> updateXrayCore() async {
    if (!_isDesktop) return '当前平台暂不支持';
    if (_useFfi) {
      final actionPtr = 'updateXrayCore'.toNativeUtf8();
      final empty = ''.toNativeUtf8();
      final resPtr = _ffi.performAction(actionPtr.cast(), empty.cast());
      final result = resPtr.cast<Utf8>().toDartString();
      _ffi.freeCString(resPtr);
      malloc.free(actionPtr);
      malloc.free(empty);
      return result;
    } else {
      try {
        final result = await _channel.invokeMethod<String>(
          'performAction',
          {'action': 'updateXrayCore'},
        );
        return result ?? '更新完成';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '更新失败: $e';
      }
    }
  }

  /// 查询 Xray Core 是否正在下载
  static Future<bool> isXrayDownloading() async {
    if (!_isDesktop) return false;
    if (_useFfi) {
      final res = _ffi.isXrayDownloading();
      return res == 1;
    } else {
      try {
        final result = await _channel.invokeMethod<String>(
          'performAction',
          {'action': 'isXrayDownloading'},
        );
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
    if (!_isDesktop) return '当前平台暂不支持';
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
        final result = await _channel.invokeMethod<String>(
          'performAction',
          {
            'action': 'resetXrayAndConfig',
            'password': password,
          },
        );
        return result ?? '重置完成';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '重置失败: $e';
      }
    }
  }

  /// Enable or disable system SOCKS proxy on macOS
  static Future<String> setSystemProxy(bool enable, String password) async {
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
    if (!Platform.isMacOS) return '当前平台暂不支持';
    try {
      final result = await _channel.invokeMethod<String>('verifySocks5Proxy');
      return result ?? '验证失败: 无返回';
    } on MissingPluginException {
      return '插件未实现';
    } catch (e) {
      return '验证失败: $e';
    }
  }

  static Future<darwin_host.TunnelProfile> _buildDefaultTunnelProfile({
    required String configPath,
  }) async {
    final dns4 = <String>[
      TunDnsConfig.dns1.value.trim(),
      TunDnsConfig.dns2.value.trim(),
    ].where((s) => s.isNotEmpty).toList();

    return darwin_host.TunnelProfile(
      mtu: 1500,
      tun46Setting: 2,
      defaultNicSupport6: true,
      dnsServers4: dns4.isEmpty ? <String>['1.1.1.1', '8.8.8.8'] : dns4,
      dnsServers6: <String>['2606:4700:4700::1111', '2001:4860:4860::8888'],
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
    final dns4 = <String>[
      TunDnsConfig.dns1.value.trim(),
      TunDnsConfig.dns2.value.trim(),
    ].where((s) => s.isNotEmpty).toList();

    return <String, Object?>{
      'mtu': 1500,
      'tun46Setting': 2,
      'defaultNicSupport6': true,
      'dnsServers4': dns4.isEmpty ? <String>['1.1.1.1', '8.8.8.8'] : dns4,
      'dnsServers6': <String>['2606:4700:4700::1111', '2001:4860:4860::8888'],
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
      if (node != null && await _ensureNodeConfigReady(node)) {
        final path = node.configPath.trim();
        if (path.isNotEmpty) {
          return path;
        }
      }
    }

    for (final node in VpnConfig.nodes) {
      final path = node.configPath.trim();
      if (node.enabled &&
          path.isNotEmpty &&
          await _ensureNodeConfigReady(node)) {
        return path;
      }
    }

    for (final node in VpnConfig.nodes) {
      final path = node.configPath.trim();
      if (path.isNotEmpty && await _ensureNodeConfigReady(node)) {
        return path;
      }
    }
    return null;
  }

  static Future<String> _prepareCanonicalTunnelConfigPath(
    String sourcePath,
  ) async {
    final normalized = sourcePath.trim();
    if (normalized.isEmpty) return sourcePath;
    final sourceFile = File(normalized);
    if (!await sourceFile.exists()) return sourcePath;

    final configsPath = await GlobalApplicationConfig.getConfigsPath();
    final canonicalPath = '$configsPath/config.json';
    if (canonicalPath == normalized) {
      return normalized;
    }

    try {
      final linkType = await FileSystemEntity.type(
        canonicalPath,
        followLinks: false,
      );
      if (linkType == FileSystemEntityType.link) {
        await Link(canonicalPath).delete();
      } else if (linkType == FileSystemEntityType.file) {
        await File(canonicalPath).delete();
      } else if (linkType == FileSystemEntityType.directory) {
        await Directory(canonicalPath).delete(recursive: true);
      }
      await Link(canonicalPath).create(normalized, recursive: true);
      return canonicalPath;
    } catch (_) {
      return normalized;
    }
  }

  static Future<bool> _ensureNodeConfigReady(VpnNode node) async {
    final rawPath = node.configPath.trim();
    if (rawPath.isEmpty) {
      return false;
    }
    if (await File(rawPath).exists()) {
      return true;
    }

    final repairedPath = await _findFallbackConfigPath(node);
    if (repairedPath == null) {
      return false;
    }

    node.configPath = repairedPath;
    VpnConfig.updateNode(node);
    await VpnConfig.saveToFile();
    addAppLog('已自动修复节点配置路径: ${node.name} -> $repairedPath');
    return true;
  }

  static Future<String?> _findFallbackConfigPath(VpnNode node) async {
    final configsPath = await GlobalApplicationConfig.getConfigsPath();
    final dir = Directory(configsPath);
    if (!await dir.exists()) return null;

    final candidates = <String>[
      '$configsPath/xray-vpn-node-${node.countryCode.toLowerCase()}.json',
      '$configsPath/config.json',
      '$configsPath/xray_config.json',
      '$configsPath/desktop_sync.json',
    ];

    for (final file in candidates) {
      if (await File(file).exists()) {
        return file;
      }
    }

    final slug = node.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isNotEmpty) {
      final file = '$configsPath/xray-vpn-node-$slug.json';
      if (await File(file).exists()) {
        return file;
      }
    }

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('xray-vpn-node-') && name.endsWith('.json')) {
        return entity.path;
      }
    }
    return null;
  }

  static Future<void> _stopOtherRunningNodes(String targetNodeName) async {
    for (final candidate in VpnConfig.nodes) {
      if (candidate.name == targetNodeName) continue;
      final running = await checkNodeStatus(candidate.name);
      if (!running) continue;
      await stopNodeService(candidate.name);
    }
  }

  static void _ensureDarwinFlutterApiReady() {
    if (!_isDarwin || _darwinFlutterApiReady) return;
    darwin_host.DarwinFlutterApi.setUp(_DarwinFlutterApiImpl());
    _darwinFlutterApiReady = true;
  }

  /// Start Packet Tunnel on Darwin platforms.
  static Future<String> startPacketTunnel() async {
    if (Platform.isAndroid) {
      try {
        final configPath = await _resolveTunnelConfigPath();
        if (configPath == null) {
          return '未找到可用的节点配置';
        }
        final canonicalPath =
            await _prepareCanonicalTunnelConfigPath(configPath);
        stopXray();
        _mobileActiveNodeName = null;
        final profile = await _buildDefaultTunnelProfileMap(
          configPath: canonicalPath,
        );
        await _channel.invokeMethod<String>('savePacketTunnelProfile', profile);
        final result =
            await _channel.invokeMethod<String>('startPacketTunnel', profile);
        return result ?? 'Packet Tunnel start request submitted';
      } on MissingPluginException {
        return '插件未实现';
      } on PlatformException catch (e) {
        return '启动失败: ${e.message ?? e.code}';
      } catch (e) {
        return '启动失败: $e';
      }
    }

    if (!_isDarwin) return '当前平台暂不支持';
    _ensureDarwinFlutterApiReady();
    try {
      final configPath = await _resolveTunnelConfigPath();
      if (configPath == null) {
        return '未找到可用的节点配置';
      }
      final canonicalPath = await _prepareCanonicalTunnelConfigPath(configPath);
      final profile = await _buildDefaultTunnelProfile(
        configPath: canonicalPath,
      );
      final saveResult = await _darwinHostApi.savePacketTunnelProfile(profile);
      await _darwinHostApi.startPacketTunnel();
      return saveResult == 'profile_saved'
          ? 'Packet Tunnel start request submitted'
          : saveResult;
    } on MissingPluginException {
      return '插件未实现';
    } on PlatformException catch (e) {
      return '启动失败: ${e.message ?? e.code}';
    } catch (e) {
      return '启动失败: $e';
    }
  }

  /// Stop Packet Tunnel on Darwin platforms.
  static Future<String> stopPacketTunnel() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('stopPacketTunnel');
        return result ?? 'Packet Tunnel stop request submitted';
      } on MissingPluginException {
        return '插件未实现';
      } on PlatformException catch (e) {
        return '停止失败: ${e.message ?? e.code}';
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
      return '停止失败: ${e.message ?? e.code}';
    } catch (e) {
      return '停止失败: $e';
    }
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
      return _tunStatusFallback;
    } catch (_) {
      return _tunStatusFallback;
    }
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

class _DarwinFlutterApiImpl extends darwin_host.DarwinFlutterApi {
  @override
  void onPacketTunnelError(String code, String message) {
    addAppLog(
      'Packet Tunnel error ($code): $message',
      level: LogLevel.error,
    );
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
    final utunList =
        utunRaw is List ? utunRaw.whereType<String>().toList() : <String>[];
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
