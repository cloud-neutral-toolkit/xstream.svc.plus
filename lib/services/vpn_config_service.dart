// lib/services/vpn_config_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/global_config.dart';
import '../utils/native_bridge.dart';
import '../utils/validators.dart';
import '../templates/xray_config_template.dart';
import '../templates/xray_service_macos_template.dart';
import '../templates/xray_service_linux_template.dart';
import '../templates/xray_service_windows_template.dart';

class VlessUriProfile {
  final String name;
  final String domain;
  final String port;
  final String uuid;
  final String protocol;
  final String network;
  final String security;
  final String? sni;
  final String? fingerprint;
  final String? flow;
  final String? host;
  final String? path;
  final String? mode;
  final List<String> alpn;

  const VlessUriProfile({
    required this.name,
    required this.domain,
    required this.port,
    required this.uuid,
    this.protocol = 'vless',
    this.network = 'tcp',
    this.security = 'tls',
    this.sni,
    this.fingerprint,
    this.flow,
    this.host,
    this.path,
    this.mode,
    this.alpn = const [],
  });
}

class VpnNode {
  String name;
  String countryCode;
  String configPath;

  /// Cross-platform service identifier
  ///
  /// - macOS: LaunchAgent plist file name
  /// - Linux: systemd service name
  /// - Windows: SC service name
  String serviceName;
  String protocol;
  String transport;
  String security;
  bool enabled;

  VpnNode({
    required this.name,
    required this.countryCode,
    required this.configPath,
    required this.serviceName,
    this.protocol = 'vless',
    this.transport = 'tcp',
    this.security = 'tls',
    this.enabled = true,
  }) {
    checkNotEmpty(name, 'name');
    checkNotEmpty(countryCode, 'countryCode');
    checkNotEmpty(configPath, 'configPath');
    checkNotEmpty(serviceName, 'serviceName');
  }

  factory VpnNode.fromJson(Map<String, dynamic> json) {
    final name = json['name'] ?? '';
    final countryCode = json['countryCode'] ?? '';
    final configPath = json['configPath'] ?? '';
    final serviceName = json['serviceName'] ?? json['plistName'] ?? '';
    final protocol = json['protocol'] ?? 'vless';
    final transport = json['transport'] ?? 'tcp';
    final security = json['security'] ?? 'tls';

    checkNotEmpty(name, 'name');
    checkNotEmpty(countryCode, 'countryCode');
    checkNotEmpty(configPath, 'configPath');
    checkNotEmpty(serviceName, 'serviceName');

    return VpnNode(
      name: name,
      countryCode: countryCode,
      configPath: configPath,
      serviceName: serviceName,
      protocol: protocol,
      transport: transport,
      security: security,
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'countryCode': countryCode,
      'configPath': configPath,
      'serviceName': serviceName,
      'protocol': protocol,
      'transport': transport,
      'security': security,
      'enabled': enabled,
    };
  }
}

class VpnConfig {
  static List<VpnNode> _nodes = [];

  static Future<String> getConfigPath() async {
    return await GlobalApplicationConfig.getLocalConfigPath();
  }

  static Future<void> load() async {
    List<VpnNode> fromLocal = [];

    try {
      final path = await GlobalApplicationConfig.getLocalConfigPath();
      final file = File(path);
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final List<dynamic> jsonList = json.decode(jsonStr);
        fromLocal = jsonList.map((e) => VpnNode.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load local vpn_nodes.json: $e');
    }

    _nodes = fromLocal;
  }

  static List<VpnNode> get nodes => _nodes;

  static VpnNode? getNodeByName(String name) {
    checkNotEmpty(name, 'name');
    try {
      return _nodes.firstWhere((e) => e.name == name);
    } catch (_) {
      return null;
    }
  }

  static void addNode(VpnNode node) {
    checkNotEmpty(node.name, 'node.name');
    _nodes.add(node);
  }

  static void removeNode(String name) {
    checkNotEmpty(name, 'name');
    _nodes.removeWhere((e) => e.name == name);
  }

  static void updateNode(VpnNode updated) {
    checkNotEmpty(updated.name, 'updated.name');
    final index = _nodes.indexWhere((e) => e.name == updated.name);
    if (index != -1) {
      _nodes[index] = updated;
    }
  }

  static String exportToJson() {
    return json.encode(_nodes.map((e) => e.toJson()).toList());
  }

  static Future<String> saveToFile() async {
    final path = await GlobalApplicationConfig.getLocalConfigPath();
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(exportToJson());
    return path;
  }

  static Future<void> importFromJson(String jsonStr) async {
    checkNotEmpty(jsonStr, 'jsonStr');
    final List<dynamic> jsonList = json.decode(jsonStr);
    _nodes = jsonList.map((e) => VpnNode.fromJson(e)).toList();
    await saveToFile();
  }

  static Future<void> deleteNodeFiles(VpnNode node) async {
    checkNotEmpty(node.name, 'node.name');
    checkNotEmpty(node.configPath, 'node.configPath');
    checkNotEmpty(node.serviceName, 'node.serviceName');
    try {
      final jsonFile = File(node.configPath);
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }

      final servicePath = await GlobalApplicationConfig.getServicePath(
        node.serviceName,
      );
      final serviceFile = File(servicePath);
      if (await serviceFile.exists()) {
        await serviceFile.delete();
      }

      removeNode(node.name);
      await saveToFile();
    } catch (e) {
      debugPrint('⚠️ 删除节点文件失败: $e');
    }
  }

  static Future<void> generateDefaultNodes({
    required String password,
    required Function(String) setMessage,
    required Function(String) logMessage,
  }) async {
    checkNotEmpty(password, 'password');
    checkNotNull(setMessage, 'setMessage');
    checkNotNull(logMessage, 'logMessage');
    final bundleId = await GlobalApplicationConfig.getBundleId();

    const port = '1443';
    const uuid = '18d270a9-533d-4b13-b3f1-e7f55540a9b2';
    const nodes = [
      {'name': 'Global-Node', 'domain': 'trial-connector.onwalk.net'},
    ];

    for (final node in nodes) {
      await generateContent(
        nodeName: node['name']!,
        domain: node['domain']!,
        port: port,
        uuid: uuid,
        password: password,
        bundleId: bundleId,
        setMessage: setMessage,
        logMessage: logMessage,
      );
    }

    // Reload nodes from file to keep in-memory list in sync
    await load();
  }

  static Future<void> generateContent({
    required String nodeName,
    required String domain,
    required String port,
    required String uuid,
    required String password,
    required String bundleId,
    required Function(String) setMessage,
    required Function(String) logMessage,
    String protocol = 'vless',
    String network = 'tcp',
    String security = 'tls',
    String? sni,
    String? fingerprint = 'chrome',
    String? flow = 'xtls-rprx-vision',
    String? host,
    String? path,
    String? mode,
    List<String> alpn = const [],
  }) async {
    checkNotEmpty(nodeName, 'nodeName');
    checkNotEmpty(domain, 'domain');
    checkNotEmpty(port, 'port');
    checkNotEmpty(uuid, 'uuid');
    checkNotEmpty(password, 'password');
    checkNotEmpty(bundleId, 'bundleId');
    checkNotNull(setMessage, 'setMessage');
    checkNotNull(logMessage, 'logMessage');
    checkNotEmpty(protocol, 'protocol');
    checkNotEmpty(network, 'network');
    checkNotEmpty(security, 'security');
    final normalizedProtocol = protocol.trim().toLowerCase();
    final normalizedNetwork = network.trim().toLowerCase();
    final normalizedSecurity = security.trim().toLowerCase();
    final code = nodeName.split('-').first.toLowerCase();
    final prefix = await GlobalApplicationConfig.getXrayConfigPath();
    final xrayConfigPath = '${prefix}xray-vpn-node-$code.json';

    final xrayConfigContent = await _generateXrayJsonConfig(
      domain,
      port,
      uuid,
      setMessage,
      logMessage,
      protocol: normalizedProtocol,
      network: normalizedNetwork,
      security: normalizedSecurity,
      sni: sni,
      fingerprint: fingerprint,
      flow: flow,
      host: host,
      path: path,
      mode: mode,
      alpn: alpn,
    );
    if (xrayConfigContent.isEmpty) return;

    final serviceName = await GlobalApplicationConfig.serviceNameForRegion(
      code,
    );
    final servicePath = await GlobalApplicationConfig.getServicePath(
      serviceName,
    );

    final serviceContent = await _generateServiceContent(
      code,
      bundleId,
      xrayConfigPath,
      serviceName,
    );
    if (serviceContent.isEmpty) return;

    final vpnNodesConfigPath =
        await GlobalApplicationConfig.getLocalConfigPath();
    final vpnNodesConfigContent = await _generateVpnNodesJsonContent(
      nodeName,
      code,
      serviceName,
      xrayConfigPath,
      setMessage,
      logMessage,
      protocol: normalizedProtocol,
      transport: normalizedNetwork,
      security: normalizedSecurity,
    );

    try {
      await NativeBridge.writeConfigFiles(
        xrayConfigPath: xrayConfigPath,
        xrayConfigContent: xrayConfigContent,
        servicePath: servicePath,
        serviceContent: serviceContent,
        vpnNodesConfigPath: vpnNodesConfigPath,
        vpnNodesConfigContent: vpnNodesConfigContent,
        password: password,
      );

      setMessage('✅ 配置已保存: $xrayConfigPath');
      setMessage('✅ 服务项已生成: $servicePath');
      setMessage('✅ 菜单项已更新: $vpnNodesConfigPath');
      logMessage('配置已成功保存并生成');
      // Reload nodes from file so that the in-memory list stays updated
      await load();
    } catch (e) {
      setMessage('生成配置失败: $e');
      logMessage('生成配置失败: $e');
    }
  }

  static VlessUriProfile parseVlessUri(
    String rawUri, {
    String? fallbackNodeName,
  }) {
    checkNotEmpty(rawUri, 'rawUri');
    final trimmed = rawUri.trim();
    final uri = Uri.parse(trimmed);
    if (uri.scheme.toLowerCase() != 'vless') {
      throw const FormatException('Only vless:// links are supported');
    }

    final uuid = uri.userInfo.trim();
    final domain = uri.host.trim();
    if (uuid.isEmpty || domain.isEmpty) {
      throw const FormatException('Invalid vless:// link');
    }

    final query = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      query[key.toLowerCase()] = value.trim();
    });

    final uriName = Uri.decodeComponent(uri.fragment).trim();
    final nameCandidate = _firstNonEmpty(uriName, fallbackNodeName, domain);
    final network = _firstNonEmpty(query['type'], 'tcp').toLowerCase();
    final security = _firstNonEmpty(query['security'], 'tls').toLowerCase();
    final alpn = (query['alpn'] ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return VlessUriProfile(
      name: nameCandidate,
      domain: domain,
      port: uri.hasPort ? uri.port.toString() : '443',
      uuid: uuid,
      network: network,
      security: security,
      sni: _nullableValue(query['sni']),
      fingerprint: _nullableValue(query['fp'] ?? query['fingerprint']),
      flow: _nullableValue(query['flow']),
      host: _nullableValue(query['host']),
      path: _normalizePath(_nullableValue(query['path'])),
      mode: _nullableValue(query['mode']),
      alpn: alpn,
    );
  }

  static Future<void> generateFromVlessUri({
    required String vlessUri,
    String? fallbackNodeName,
    required String password,
    required String bundleId,
    required Function(String) setMessage,
    required Function(String) logMessage,
  }) async {
    final profile = parseVlessUri(
      vlessUri,
      fallbackNodeName: fallbackNodeName,
    );
    await generateContent(
      nodeName: profile.name,
      domain: profile.domain,
      port: profile.port,
      uuid: profile.uuid,
      password: password,
      bundleId: bundleId,
      setMessage: setMessage,
      logMessage: logMessage,
      protocol: profile.protocol,
      network: profile.network,
      security: profile.security,
      sni: profile.sni,
      fingerprint: profile.fingerprint,
      flow: profile.flow,
      host: profile.host,
      path: profile.path,
      mode: profile.mode,
      alpn: profile.alpn,
    );
  }

  static Future<String> _generateXrayJsonConfig(
    String domain,
    String port,
    String uuid,
    Function(String) setMessage,
    Function(String) logMessage, {
    String protocol = 'vless',
    String network = 'tcp',
    String security = 'tls',
    String? sni,
    String? fingerprint = 'chrome',
    String? flow = 'xtls-rprx-vision',
    String? host,
    String? path,
    String? mode,
    List<String> alpn = const [],
  }) async {
    checkNotEmpty(domain, 'domain');
    checkNotEmpty(port, 'port');
    checkNotEmpty(uuid, 'uuid');
    checkNotNull(setMessage, 'setMessage');
    checkNotNull(logMessage, 'logMessage');
    try {
      final replaced = defaultXrayJsonTemplate
          .replaceAll('<SERVER_DOMAIN>', domain)
          .replaceAll('<PORT>', port)
          .replaceAll('<UUID>', uuid)
          .replaceAll('<DNS1>', DnsConfig.dns1.value)
          .replaceAll('<DNS2>', DnsConfig.dns2.value);

      final jsonObj = Map<String, dynamic>.from(jsonDecode(replaced));
      final outbounds = List<dynamic>.from(
        (jsonObj['outbounds'] as List<dynamic>? ?? const []),
      );
      final proxyIndex = outbounds.indexWhere((e) {
        if (e is! Map) return false;
        return e['tag'] == 'proxy';
      });
      if (proxyIndex < 0) {
        throw const FormatException('Invalid xray outbound template');
      }

      final proxyOutbound = Map<String, dynamic>.from(
        outbounds[proxyIndex] as Map,
      );
      outbounds[proxyIndex] = proxyOutbound;
      jsonObj['outbounds'] = outbounds;
      final normalizedNetwork = network.trim().toLowerCase();
      final normalizedSecurity = security.trim().toLowerCase();

      proxyOutbound['protocol'] = protocol;
      final settings = Map<String, dynamic>.from(
        proxyOutbound['settings'] as Map? ?? const {},
      );
      proxyOutbound['settings'] = settings;
      final vnext = List<dynamic>.from(
        settings['vnext'] as List<dynamic>? ?? const [],
      );
      if (vnext.isEmpty) {
        throw const FormatException('Invalid vnext template');
      }

      final firstVnext = Map<String, dynamic>.from(vnext.first as Map);
      vnext[0] = firstVnext;
      settings['vnext'] = vnext;
      firstVnext['address'] = domain;
      firstVnext['port'] = int.tryParse(port) ?? 443;

      final users = List<dynamic>.from(
        firstVnext['users'] as List<dynamic>? ?? const [],
      );
      if (users.isEmpty) {
        throw const FormatException('Invalid users template');
      }
      final firstUser = Map<String, dynamic>.from(users.first as Map);
      users[0] = firstUser;
      firstVnext['users'] = users;
      firstUser['id'] = uuid;
      firstUser['encryption'] = 'none';
      if (_hasValue(flow)) {
        firstUser['flow'] = flow!.trim();
      } else {
        firstUser.remove('flow');
      }

      final streamSettings = Map<String, dynamic>.from(
        proxyOutbound['streamSettings'] as Map? ?? const {},
      );
      proxyOutbound['streamSettings'] = streamSettings;
      streamSettings['network'] = normalizedNetwork;
      streamSettings['security'] = normalizedSecurity;
      streamSettings.remove('xhttpSettings');

      if (normalizedSecurity == 'tls') {
        final tlsSettings = Map<String, dynamic>.from(
          streamSettings['tlsSettings'] as Map? ?? const {},
        );
        tlsSettings['allowInsecure'] = false;
        tlsSettings['serverName'] = _firstNonEmpty(sni, domain);
        if (_hasValue(fingerprint)) {
          tlsSettings['fingerprint'] = fingerprint!.trim();
        } else {
          tlsSettings.remove('fingerprint');
        }
        if (alpn.isNotEmpty) {
          tlsSettings['alpn'] = alpn;
        } else {
          tlsSettings.remove('alpn');
        }
        streamSettings['tlsSettings'] = tlsSettings;
      } else {
        streamSettings.remove('tlsSettings');
      }

      if (normalizedNetwork == 'xhttp') {
        final xhttpSettings = <String, dynamic>{
          'path': _firstNonEmpty(_normalizePath(path), '/'),
          'host': _firstNonEmpty(host, domain),
        };
        if (_hasValue(mode)) {
          xhttpSettings['mode'] = mode!.trim();
        }
        streamSettings['xhttpSettings'] = xhttpSettings;
      }

      final formatted = const JsonEncoder.withIndent('  ').convert(jsonObj);
      logMessage('✅ XrayJson 配置内容生成完成');
      return formatted;
    } catch (e) {
      setMessage('❌ XrayJson 生成失败: $e');
      logMessage('XrayJson 错误: $e');
      return '';
    }
  }

  static Future<String> _generateServiceContent(
    String nodeCode,
    String bundleId,
    String configPath,
    String serviceName,
  ) async {
    checkNotEmpty(nodeCode, 'nodeCode');
    checkNotEmpty(bundleId, 'bundleId');
    checkNotEmpty(configPath, 'configPath');
    checkNotEmpty(serviceName, 'serviceName');
    try {
      switch (Platform.operatingSystem) {
        case 'macos':
          final xrayPath = await GlobalApplicationConfig.getXrayExePath();
          return await renderXrayPlist(
            bundleId: bundleId,
            name: nodeCode.toLowerCase(),
            configPath: configPath,
            xrayPath: xrayPath,
          );
        case 'linux':
          final xrayPath = await GlobalApplicationConfig.getXrayExePath();
          return renderXrayService(xrayPath: xrayPath, configPath: configPath);
        case 'windows':
          final xrayPath = await GlobalApplicationConfig.getXrayExePath();
          return renderXrayServiceWindows(
            serviceName: serviceName.replaceAll('.schtasks', ''),
            xrayPath: xrayPath,
            configPath: configPath,
          );
        default:
          return '';
      }
    } catch (e) {
      return '';
    }
  }

  static Future<String> _generateVpnNodesJsonContent(
    String nodeName,
    String nodeCode,
    String serviceName,
    String xrayConfigPath,
    Function(String) setMessage,
    Function(String) logMessage, {
    String protocol = 'vless',
    String transport = 'tcp',
    String security = 'tls',
  }) async {
    checkNotEmpty(nodeName, 'nodeName');
    checkNotEmpty(nodeCode, 'nodeCode');
    checkNotEmpty(serviceName, 'serviceName');
    checkNotEmpty(xrayConfigPath, 'xrayConfigPath');
    checkNotNull(setMessage, 'setMessage');
    checkNotNull(logMessage, 'logMessage');

    // 创建新的 VPN 节点
    final newVpnNode = VpnNode(
      name: nodeName,
      countryCode: nodeCode,
      serviceName: serviceName,
      configPath: xrayConfigPath,
      protocol: protocol,
      transport: transport,
      security: security,
      enabled: true,
    );

    // 获取现有节点列表
    var currentNodes = List<VpnNode>.from(_nodes);

    // 检查是否已存在同名节点，如果存在则更新，否则添加
    final existingIndex = currentNodes.indexWhere(
      (node) => node.name == nodeName,
    );
    if (existingIndex != -1) {
      currentNodes[existingIndex] = newVpnNode;
      logMessage('更新现有节点: $nodeName');
    } else {
      currentNodes.add(newVpnNode);
      logMessage('添加新节点: $nodeName');
    }

    // 更新内存中的节点列表
    _nodes = currentNodes;

    // 生成完整的 JSON 内容
    final vpnNodesJsonContent = json.encode(
      currentNodes.map((e) => e.toJson()).toList(),
    );
    logMessage('✅ vpn_nodes.json 内容生成完成，总节点数: ${currentNodes.length}');
    return vpnNodesJsonContent;
  }

  static String _firstNonEmpty(String? first,
      [String? second, String fallback = '']) {
    if (first != null && first.trim().isNotEmpty) {
      return first.trim();
    }
    if (second != null && second.trim().isNotEmpty) {
      return second.trim();
    }
    return fallback;
  }

  static String? _nullableValue(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static bool _hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static String? _normalizePath(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim();
    if (normalized.startsWith('/')) return normalized;
    return '/$normalized';
  }
}
