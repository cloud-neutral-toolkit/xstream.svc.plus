import 'dart:io';

import '../../services/vpn_config_service.dart';
import '../../utils/global_config.dart';

class XrayConfigWriter {
  static const _configFileName = 'desktop_sync.json';
  static const _defaultNodeName = 'Desktop Sync';
  static const _defaultServiceName = 'xstream.desktop.sync';
  static const _defaultCountryCode = 'SYNC';

  static Future<String> writeConfig(String json) async {
    final path =
        await GlobalApplicationConfig.getXrayConfigFilePath(_configFileName);
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(json);
    return path;
  }

  static Future<String> writeConfigForNode({
    required String json,
    required String nodeName,
    String? countryCode,
  }) async {
    final code = _normalizeNodeCode(
      (countryCode ?? '').trim().isNotEmpty ? countryCode! : nodeName,
    );
    final fileName = 'xray-vpn-node-$code.json';
    final path = await GlobalApplicationConfig.getXrayConfigFilePath(fileName);
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(json);
    return path;
  }

  static Future<String> registerNode({
    required String configPath,
    String? nodeName,
    String? countryCode,
    String? protocol,
    String? transport,
    String? security,
  }) async {
    final normalizedName = (nodeName ?? '').trim().isNotEmpty
        ? nodeName!.trim()
        : _defaultNodeName;
    final existing = VpnConfig.getNodeByName(normalizedName);

    if (existing == null) {
      final stale = VpnConfig.nodes
          .where((node) =>
              node.serviceName == _defaultServiceName &&
              node.name != normalizedName)
          .map((node) => node.name)
          .toList();
      for (final name in stale) {
        VpnConfig.removeNode(name);
      }
    }

    final node = VpnNode(
      name: normalizedName,
      countryCode: _normalizeCountryCode(
        countryCode,
        existing?.countryCode ?? _defaultCountryCode,
      ),
      configPath: configPath,
      serviceName: existing?.serviceName ?? _defaultServiceName,
      protocol: _pickValue(protocol, existing?.protocol),
      transport: _pickValue(transport, existing?.transport),
      security: _pickValue(security, existing?.security),
      enabled: existing?.enabled ?? true,
    );
    if (existing == null) {
      VpnConfig.addNode(node);
    } else {
      VpnConfig.updateNode(node);
    }
    await VpnConfig.saveToFile();
    return node.name;
  }

  static String _normalizeCountryCode(String? value, String fallback) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return fallback;
    if (raw.length > 12) return raw.substring(0, 12).toUpperCase();
    return raw.toUpperCase();
  }

  static String _pickValue(String? preferred, String? fallback) {
    final primary = (preferred ?? '').trim();
    if (primary.isNotEmpty) return primary.toLowerCase();
    final secondary = (fallback ?? '').trim();
    if (secondary.isNotEmpty) return secondary.toLowerCase();
    return '';
  }

  static String _normalizeNodeCode(String raw) {
    final lower = raw.trim().toLowerCase();
    final normalized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final compact = normalized.replaceAll(RegExp(r'-+'), '-');
    final trimmed = compact.replaceAll(RegExp(r'^-+|-+$'), '');
    if (trimmed.isEmpty) return 'node';
    if (trimmed.length > 24) return trimmed.substring(0, 24);
    return trimmed;
  }
}
