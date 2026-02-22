// lib/templates/xray_service_windows_template.dart

const String defaultXrayServiceWindowsTemplate =
    r'''schtasks /Create /TN <SERVICE_NAME> /SC ONSTART /RL HIGHEST /TR "<XRAY_PATH> run -c <CONFIG_PATH>" /F''';

String renderXrayServiceWindows({
  required String serviceName,
  required String xrayPath,
  required String configPath,
}) {
  return defaultXrayServiceWindowsTemplate
      .replaceAll('<SERVICE_NAME>', serviceName)
      .replaceAll('<XRAY_PATH>', xrayPath)
      .replaceAll('<CONFIG_PATH>', configPath);
}
