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
  bool enabled;

  VpnNode({
    required this.name,
    required this.countryCode,
    required this.configPath,
    required this.serviceName,
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

    checkNotEmpty(name, 'name');
    checkNotEmpty(countryCode, 'countryCode');
    checkNotEmpty(configPath, 'configPath');
    checkNotEmpty(serviceName, 'serviceName');

    return VpnNode(
      name: name,
      countryCode: countryCode,
      configPath: configPath,
      serviceName: serviceName,
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'countryCode': countryCode,
      'configPath': configPath,
      'serviceName': serviceName,
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
  }) async {
    checkNotEmpty(nodeName, 'nodeName');
    checkNotEmpty(domain, 'domain');
    checkNotEmpty(port, 'port');
    checkNotEmpty(uuid, 'uuid');
    checkNotEmpty(password, 'password');
    checkNotEmpty(bundleId, 'bundleId');
    checkNotNull(setMessage, 'setMessage');
    checkNotNull(logMessage, 'logMessage');
    final code = nodeName.split('-').first.toLowerCase();
    final prefix = await GlobalApplicationConfig.getXrayConfigPath();
    final xrayConfigPath = '${prefix}xray-vpn-node-$code.json';

    final xrayConfigContent = await _generateXrayJsonConfig(
      domain,
      port,
      uuid,
      setMessage,
      logMessage,
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

  static Future<String> _generateXrayJsonConfig(
    String domain,
    String port,
    String uuid,
    Function(String) setMessage,
    Function(String) logMessage,
  ) async {
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

      final jsonObj = jsonDecode(replaced);
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
    Function(String) logMessage,
  ) async {
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
}
