// lib/templates/xray_plist_template.dart

import '../utils/global_config.dart';

const String defaultXrayPlistTemplate =
    r'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string><BUNDLE_ID>.xray-node-<NAME></string>
  <key>ProgramArguments</key>
  <array>
    <string><XRAY_PATH></string>
    <string>run</string>
    <string>-c</string>
    <string><CONFIG_PATH></string>
  </array>
  <key>StandardOutPath</key>
  <string><LOG_PATH>/xray-vpn-<NAME>-node.log</string>
  <key>StandardErrorPath</key>
  <string><LOG_PATH>/xray-vpn-<NAME>-node.err</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
''';

Future<String> renderXrayPlist({
  required String bundleId,
  required String name,
  required String configPath,
  required String xrayPath,
  String? logPath,
}) async {
  final logsPath = logPath ?? await GlobalApplicationConfig.getLogsPath();
  return defaultXrayPlistTemplate
      .replaceAll('<BUNDLE_ID>', bundleId)
      .replaceAll('<NAME>', name)
      .replaceAll('<CONFIG_PATH>', configPath)
      .replaceAll('<XRAY_PATH>', xrayPath)
      .replaceAll('<LOG_PATH>', logsPath);
}
