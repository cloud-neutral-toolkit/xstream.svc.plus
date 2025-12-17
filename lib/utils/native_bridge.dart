import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import '../../services/vpn_config_service.dart'; // 引入新的 VpnConfig 类
import '../bindings/bridge_bindings.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('com.xstream/native');
  static const MethodChannel _loggerChannel =
      MethodChannel('com.xstream/logger');

  static final bool _useFfi =
      Platform.isWindows || Platform.isLinux || Platform.isIOS;
  static BridgeBindings? _bindings;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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

    if (!_isDesktop) return '当前平台暂不支持';

    // ✅ 新增：避免重复启动
    final isRunning = await checkNodeStatus(nodeName);
    if (isRunning) return '服务已在运行';

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
          {'serviceName': node.serviceName},
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
          {'serviceName': node.serviceName}, // 直接传递服务名称
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

  // 初始化 Xray：会触发原生 performAction:initXray
  static Future<String> initXray() async {
    if (!_isDesktop) return '当前平台暂不支持';
    if (_useFfi) {
      final actionPtr = 'initXray'.toNativeUtf8();
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
          {'action': 'initXray'},
        );
        return result ?? '初始化完成，但无返回内容';
      } on MissingPluginException {
        return '插件未实现';
      } catch (e) {
        return '初始化失败: $e';
      }
    }
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

  /// Start Packet Tunnel on macOS
  static Future<String> startPacketTunnel() async {
    if (!Platform.isMacOS) return '当前平台暂不支持';
    try {
      final result =
          await _channel.invokeMethod<String>('startPacketTunnel');
      return result ?? '启动请求已发送';
    } on MissingPluginException {
      return '插件未实现';
    } catch (e) {
      return '启动失败: $e';
    }
  }

  /// Stop Packet Tunnel on macOS
  static Future<String> stopPacketTunnel() async {
    if (!Platform.isMacOS) return '当前平台暂不支持';
    try {
      final result =
          await _channel.invokeMethod<String>('stopPacketTunnel');
      return result ?? '停止请求已发送';
    } on MissingPluginException {
      return '插件未实现';
    } catch (e) {
      return '停止失败: $e';
    }
  }

  /// Get Packet Tunnel status on macOS
  static Future<PacketTunnelStatus> getPacketTunnelStatus() async {
    if (!Platform.isMacOS) return _tunStatusFallback;
    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>(
              'getPacketTunnelStatus');
      if (result == null) {
        return _tunStatusFallback;
      }
      return PacketTunnelStatus.fromMap(result);
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

class PacketTunnelStatus {
  final String status;
  final List<String> utunInterfaces;

  const PacketTunnelStatus({
    required this.status,
    required this.utunInterfaces,
  });

  factory PacketTunnelStatus.fromMap(Map<Object?, Object?> map) {
    final status = map['status'] as String? ?? 'unknown';
    final utunRaw = map['utun'];
    final utunList = utunRaw is List
        ? utunRaw.whereType<String>().toList()
        : <String>[];
    return PacketTunnelStatus(status: status, utunInterfaces: utunList);
  }
}
