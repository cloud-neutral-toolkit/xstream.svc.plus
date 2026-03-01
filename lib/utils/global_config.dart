import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/log_console.dart';

const String kArtifactBaseUrl = 'https://artifact.svc.plus';
const String kUpdateBaseUrl = '$kArtifactBaseUrl/';

// LogConsole Global Key
final GlobalKey<LogConsoleState> logConsoleKey = GlobalKey<LogConsoleState>();

/// 当前构建版本号，可在应用各处引用
final String buildVersion = (() {
  const branch = String.fromEnvironment('BRANCH_NAME', defaultValue: '');
  const buildId = String.fromEnvironment('BUILD_ID', defaultValue: 'local');
  const buildDate =
      String.fromEnvironment('BUILD_DATE', defaultValue: 'unknown');

  if (branch.startsWith('release/')) {
    final version = branch.replaceFirst('release/', '');
    return 'v$version-$buildDate-$buildId';
  }
  if (branch == 'main') {
    return 'latest-$buildDate-$buildId';
  }
  return 'dev-$buildDate-$buildId';
})();

/// 基础系统信息，用于匿名统计等场景
Map<String, String> collectSystemInfo() => {
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dartVersion': Platform.version,
    };

/// 全局应用状态管理（使用 ValueNotifier 实现响应式绑定）
class GlobalState {
  static const String tunnelConnectionMode = 'VPN';
  static const String proxyOnlyConnectionMode = '仅代理';

  /// 解锁状态（true 表示已解锁）
  static final ValueNotifier<bool> isUnlocked = ValueNotifier<bool>(false);

  /// 当前解锁使用的 sudo 密码（可供原生调用或配置操作使用）
  static final ValueNotifier<String> sudoPassword = ValueNotifier<String>('');

  /// 升级渠道：true 表示检查 DailyBuild，false 只检查 release
  static final ValueNotifier<bool> useDailyBuild = ValueNotifier<bool>(false);

  /// 调试模式开关，由 `--debug` 参数控制
  static final ValueNotifier<bool> debugMode = ValueNotifier<bool>(false);

  /// 遥测开关：true 表示发送匿名统计信息
  static final ValueNotifier<bool> telemetryEnabled =
      ValueNotifier<bool>(false);

  /// 全局代理开关
  static final ValueNotifier<bool> globalProxy = ValueNotifier<bool>(false);

  /// 隧道模式开关
  static final ValueNotifier<bool> tunnelProxyEnabled =
      ValueNotifier<bool>(false);

  /// TUN 设置开关
  static final ValueNotifier<bool> tunSettingsEnabled =
      ValueNotifier<bool>(false);

  /// Xray Core 下载状态
  static final ValueNotifier<bool> xrayUpdating = ValueNotifier<bool>(false);

  /// 系统权限向导是否已完成
  static final ValueNotifier<bool> permissionGuideDone =
      ValueNotifier<bool>(false);

  /// 当前连接模式，可在底部弹出栏中切换（如 VPN / 仅代理）
  static final ValueNotifier<String> connectionMode =
      ValueNotifier<String>(tunnelConnectionMode);

  /// 当前活跃节点名称（桌面菜单栏/主界面共享）
  static final ValueNotifier<String> activeNodeName = ValueNotifier<String>('');

  /// 最近导入/新增的节点名称（用于主界面高亮）
  static final ValueNotifier<String> lastImportedNodeName =
      ValueNotifier<String>('');

  /// 节点列表修订号（导入/删除后递增，用于触发主界面刷新）
  static final ValueNotifier<int> nodeListRevision = ValueNotifier<int>(0);

  /// 当前语言环境，默认中文
  static final ValueNotifier<Locale> locale =
      ValueNotifier<Locale>(const Locale('zh'));

  /// SOCKS 代理模式开关（默认开启）
  static final ValueNotifier<bool> socksProxyEnabled =
      ValueNotifier<bool>(true);

  /// HTTP 代理模式开关（默认开启）
  static final ValueNotifier<bool> httpProxyEnabled = ValueNotifier<bool>(true);

  /// 嗅探开关（Sniffing）
  static final ValueNotifier<bool> sniffingEnabled = ValueNotifier<bool>(true);

  /// 回退到代理（Fallback to Proxy）
  static final ValueNotifier<bool> fallbackToProxy = ValueNotifier<bool>(false);

  /// 回退到域名（Fallback to Domain）
  static final ValueNotifier<bool> fallbackToDomain =
      ValueNotifier<bool>(false);

  /// IPv6 to Domain
  static final ValueNotifier<bool> ipv6ToDomain = ValueNotifier<bool>(false);

  /// 系统代理 SOCKS 端口
  static final ValueNotifier<String> socksPort = ValueNotifier<String>('1080');

  /// 系统代理 HTTP 端口
  static final ValueNotifier<String> httpPort = ValueNotifier<String>('1081');

  static String normalizeConnectionMode(String? value) {
    if (Platform.isIOS) {
      return tunnelConnectionMode;
    }
    return value == proxyOnlyConnectionMode
        ? proxyOnlyConnectionMode
        : tunnelConnectionMode;
  }

  static bool isTunnelModeValue(String? value) {
    return normalizeConnectionMode(value) == tunnelConnectionMode;
  }

  static bool get isTunnelMode {
    return isTunnelModeValue(connectionMode.value);
  }

  static void setConnectionMode(String? mode) {
    final normalized = normalizeConnectionMode(mode);
    final tunnelEnabled = normalized == tunnelConnectionMode;
    if (connectionMode.value != normalized) {
      connectionMode.value = normalized;
    }
    if (tunnelProxyEnabled.value != tunnelEnabled) {
      tunnelProxyEnabled.value = tunnelEnabled;
    }
  }

  static void setTunnelModeEnabled(bool enabled) {
    if (Platform.isIOS) {
      setConnectionMode(tunnelConnectionMode);
      return;
    }
    setConnectionMode(
      enabled ? tunnelConnectionMode : proxyOnlyConnectionMode,
    );
  }
}

/// 管理 DNS 配置，支持保存到本地
enum DnsTransportMode {
  plain('plain'),
  doh('doh');

  const DnsTransportMode(this.storageValue);
  final String storageValue;

  static DnsTransportMode fromStorage(String? value) {
    return value == DnsTransportMode.plain.storageValue
        ? DnsTransportMode.plain
        : DnsTransportMode.doh;
  }
}

class DnsConfig {
  static const _proxyDns1Key = 'dnsServer1';
  static const _proxyDns2Key = 'dnsServer2';
  static const _directDns1Key = 'directDnsServer1';
  static const _directDns2Key = 'directDnsServer2';
  static const _transportModeKey = 'dnsTransportMode';
  static const _legacyDotEnabledKey = 'tunDnsOverTls';
  static const _defaultPlainDns1 = '1.1.1.1';
  static const _defaultPlainDns2 = '8.8.8.8';
  static const _defaultDohDns1 = 'https://1.1.1.1/dns-query';
  static const _defaultDohDns2 = 'https://8.8.8.8/dns-query';
  static const _defaultDirectDns6Servers = <String>[
    '2606:4700:4700::1111',
    '2001:4860:4860::8888',
  ];
  static const _packetTunnelLocalDns4Servers = <String>['10.0.0.53'];
  static const _packetTunnelLocalDns6Servers = <String>['fd00::53'];

  static final ValueNotifier<String> proxyDns1 =
      ValueNotifier<String>(_defaultDohDns1);
  static final ValueNotifier<String> proxyDns2 =
      ValueNotifier<String>(_defaultDohDns2);
  static final ValueNotifier<String> directDns1 =
      ValueNotifier<String>(_defaultPlainDns1);
  static final ValueNotifier<String> directDns2 =
      ValueNotifier<String>(_defaultPlainDns2);
  static final ValueNotifier<DnsTransportMode> transportMode =
      ValueNotifier<DnsTransportMode>(DnsTransportMode.doh);

  static bool get dohEnabled => transportMode.value == DnsTransportMode.doh;

  static String get proxyPrimaryDefault =>
      dohEnabled ? _defaultDohDns1 : _defaultPlainDns1;

  static String get proxySecondaryDefault =>
      dohEnabled ? _defaultDohDns2 : _defaultPlainDns2;

  static String get directPrimaryDefault => _defaultPlainDns1;

  static String get directSecondaryDefault => _defaultPlainDns2;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyDotEnabled = prefs.getBool(_legacyDotEnabledKey);
    transportMode.value = DnsTransportMode.fromStorage(
      prefs.getString(_transportModeKey) ??
          ((legacyDotEnabled ?? true)
              ? DnsTransportMode.doh.storageValue
              : DnsTransportMode.plain.storageValue),
    );
    proxyDns1.value = _normalizeProxyEndpoint(
      prefs.getString(_proxyDns1Key),
      transportMode.value,
      primary: true,
    );
    proxyDns2.value = _normalizeProxyEndpoint(
      prefs.getString(_proxyDns2Key),
      transportMode.value,
      primary: false,
    );
    directDns1.value = _normalizeDirectEndpoint(
      prefs.getString(_directDns1Key),
      primary: true,
    );
    directDns2.value = _normalizeDirectEndpoint(
      prefs.getString(_directDns2Key),
      primary: false,
    );

    proxyDns1
        .addListener(() => prefs.setString(_proxyDns1Key, proxyDns1.value));
    proxyDns2
        .addListener(() => prefs.setString(_proxyDns2Key, proxyDns2.value));
    directDns1
        .addListener(() => prefs.setString(_directDns1Key, directDns1.value));
    directDns2
        .addListener(() => prefs.setString(_directDns2Key, directDns2.value));
    transportMode.addListener(() {
      prefs.setString(_transportModeKey, transportMode.value.storageValue);
    });
  }

  static void setDohEnabled(bool enabled) {
    final nextMode = enabled ? DnsTransportMode.doh : DnsTransportMode.plain;
    if (transportMode.value == nextMode) {
      return;
    }

    transportMode.value = nextMode;
    proxyDns1.value =
        _normalizeProxyEndpoint(proxyDns1.value, nextMode, primary: true);
    proxyDns2.value =
        _normalizeProxyEndpoint(proxyDns2.value, nextMode, primary: false);
  }

  static void updateProxyServers({
    required String primary,
    required String secondary,
  }) {
    proxyDns1.value =
        _normalizeProxyEndpoint(primary, transportMode.value, primary: true);
    proxyDns2.value =
        _normalizeProxyEndpoint(secondary, transportMode.value, primary: false);
  }

  static void updateDirectServers({
    required String primary,
    required String secondary,
  }) {
    directDns1.value = _normalizeDirectEndpoint(primary, primary: true);
    directDns2.value = _normalizeDirectEndpoint(secondary, primary: false);
  }

  static List<String> proxyResolversForXray() {
    return <String>[proxyDns1.value, proxyDns2.value]
        .map((value) =>
            _normalizeProxyEndpoint(value, transportMode.value, primary: true))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  static List<String> directResolversForXray() {
    final servers = <String>[
      _normalizeDirectEndpoint(directDns1.value, primary: true),
      _normalizeDirectEndpoint(directDns2.value, primary: false),
    ].where((server) => server.isNotEmpty).toList();
    return servers.toSet().toList();
  }

  static List<String> effectiveTunnelDnsServers4() => directResolversForXray();

  static List<String> get effectiveTunnelDnsServers6 =>
      _defaultDirectDns6Servers;

  static List<String> get darwinPacketTunnelDnsServers4 =>
      List<String>.from(_packetTunnelLocalDns4Servers);

  static List<String> get darwinPacketTunnelDnsServers6 =>
      List<String>.from(_packetTunnelLocalDns6Servers);

  static String _normalizeProxyEndpoint(
    String? rawValue,
    DnsTransportMode mode, {
    required bool primary,
  }) {
    final fallback = primary
        ? (mode == DnsTransportMode.doh ? _defaultDohDns1 : _defaultPlainDns1)
        : (mode == DnsTransportMode.doh ? _defaultDohDns2 : _defaultPlainDns2);
    final trimmed = rawValue?.trim() ?? '';
    if (trimmed.isEmpty) {
      return fallback;
    }

    final uri = Uri.tryParse(trimmed);
    if (mode == DnsTransportMode.doh) {
      if (uri != null && uri.hasScheme && uri.scheme == 'https') {
        final normalizedPath =
            uri.path.isEmpty || uri.path == '/' ? '/dns-query' : uri.path;
        return uri.replace(path: normalizedPath).toString();
      }
      final host = uri != null && uri.host.isNotEmpty ? uri.host : trimmed;
      return Uri(scheme: 'https', host: host, path: '/dns-query').toString();
    }

    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return uri.host;
    }
    return trimmed;
  }

  static String _normalizeDirectEndpoint(
    String? endpoint, {
    required bool primary,
  }) {
    final trimmed = endpoint?.trim() ?? '';
    if (trimmed.isEmpty) {
      return primary ? _defaultPlainDns1 : _defaultPlainDns2;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final host = uri.host;
      if (host.isNotEmpty) {
        return host;
      }
    }
    return trimmed;
  }
}

/// 用于获取应用相关的配置信息
class GlobalApplicationConfig {
  /// 沙盒化应用目录结构管理
  static Future<String> getSandboxBasePath() async {
    final baseDir = await getApplicationSupportDirectory();
    return baseDir.path;
  }

  /// 获取二进制文件目录路径
  static Future<String> getBinariesPath() async {
    final basePath = await getSandboxBasePath();
    final binDir = Directory('$basePath/bin');
    await binDir.create(recursive: true);
    return binDir.path;
  }

  /// 获取配置文件目录路径
  static Future<String> getConfigsPath() async {
    final basePath = await getSandboxBasePath();
    final configDir = Directory('$basePath/configs');
    await configDir.create(recursive: true);
    return configDir.path;
  }

  /// 获取服务文件目录路径
  static Future<String> getServicesPath() async {
    final basePath = await getSandboxBasePath();
    final servicesDir = Directory('$basePath/services');
    await servicesDir.create(recursive: true);
    return servicesDir.path;
  }

  /// 获取临时文件目录路径
  static Future<String> getTempPath() async {
    final basePath = await getSandboxBasePath();
    final tempDir = Directory('$basePath/temp');
    await tempDir.create(recursive: true);
    return tempDir.path;
  }

  /// 获取日志文件目录路径
  static Future<String> getLogsPath() async {
    final basePath = await getSandboxBasePath();
    final logsDir = Directory('$basePath/logs');
    await logsDir.create(recursive: true);
    return logsDir.path;
  }

  /// 获取设备指纹文件路径（用于桌面同步设备标识）
  static Future<String> getDeviceFingerprintFilePath() async {
    final basePath = await getSandboxBasePath();
    final deviceDir = Directory('$basePath/device');
    await deviceDir.create(recursive: true);
    return '${deviceDir.path}/fingerprint.bin';
  }

  /// 获取特定类型文件的完整路径
  static Future<String> getVpnNodesConfigPath() async {
    final basePath = await getSandboxBasePath();
    return '$basePath/vpn_nodes.json';
  }

  /// 获取Xray配置文件的完整路径
  static Future<String> getXrayConfigFilePath(String filename) async {
    final configsPath = await getConfigsPath();
    return '$configsPath/$filename';
  }

  /// 获取plist文件的完整路径
  static Future<String> getPlistFilePath(String plistName) async {
    final servicesPath = await getServicesPath();
    return '$servicesPath/$plistName';
  }

  /// 获取二进制文件的完整路径
  static Future<String> getBinaryFilePath(String binaryName) async {
    final binariesPath = await getBinariesPath();
    return '$binariesPath/$binaryName';
  }

  /// 获取日志文件的完整路径
  static Future<String> getLogFilePath(String logName) async {
    final logsPath = await getLogsPath();
    return '$logsPath/$logName';
  }

  /// Windows 平台默认安装目录
  static String get windowsBasePath {
    final program = Platform.environment['ProgramFiles'];
    if (program != null) {
      final path = '$program\\Xstream';
      try {
        Directory(path).createSync(recursive: true);
        return path;
      } catch (_) {
        // ignore and fall back
      }
    }
    final local = Platform.environment['LOCALAPPDATA'] ?? '.';
    final alt = '$local\\Xstream';
    Directory(alt).createSync(recursive: true);
    return alt;
  }

  /// Xray 可执行文件路径 - 使用沙盒安全路径
  static Future<String> getXrayExePath() async {
    switch (Platform.operatingSystem) {
      case 'macos':
        // Use sandboxed Application Support directory for App Store compliance
        final baseDir = await getApplicationSupportDirectory();
        final binDir = Directory('${baseDir.path}/bin');
        await binDir.create(recursive: true);
        return '${binDir.path}/xray';
      case 'windows':
        return '$windowsBasePath\\xray.exe';
      case 'linux':
        final home = Platform.environment['HOME'] ?? '~';
        return '$home/.local/bin/xray';
      default:
        final baseDir = await getApplicationSupportDirectory();
        final binDir = Directory('${baseDir.path}/bin');
        await binDir.create(recursive: true);
        return '${binDir.path}/xray';
    }
  }

  /// 从配置文件或默认值中获取 PRODUCT_BUNDLE_IDENTIFIER
  static Future<String> getBundleId() async {
    if (Platform.isMacOS) {
      try {
        // 读取 macOS 配置文件，获取 PRODUCT_BUNDLE_IDENTIFIER
        final config = await rootBundle
            .loadString('macos/Runner/Configs/AppInfo.xcconfig');
        final line = config
            .split('\n')
            .firstWhere((l) => l.startsWith('PRODUCT_BUNDLE_IDENTIFIER='));
        return line.split('=').last.trim();
      } catch (_) {
        // macOS 下若读取失败返回默认值
        return 'com.xstream';
      }
    }

    // 其他平台直接返回默认值
    return 'com.xstream';
  }

  /// 返回各平台下存放 Xray 配置文件的目录，末尾已包含分隔符
  static Future<String> getXrayConfigPath() async {
    switch (Platform.operatingSystem) {
      case 'macos':
        // Use sandboxed configs directory for App Store compliance
        final configsPath = await getConfigsPath();
        return '$configsPath/';
      case 'windows':
        final base =
            Platform.environment['ProgramFiles'] ?? 'C:\\Program Files';
        return '$base\\Xstream\\';
      case 'linux':
        return '/opt/etc/';
      default:
        final configsPath = await getConfigsPath();
        return '$configsPath/';
    }
  }

  /// 根据平台返回本地配置文件路径
  static Future<String> getLocalConfigPath() async {
    switch (Platform.operatingSystem) {
      case 'macos':
        // Use getVpnNodesConfigPath for consistent sandbox compliance
        return await getVpnNodesConfigPath();

      case 'windows':
        final xstreamDir = Directory(windowsBasePath);
        await xstreamDir.create(recursive: true);
        return '${xstreamDir.path}\\vpn_nodes.json';

      case 'linux':
        final home = Platform.environment['HOME'] ??
            (await getApplicationSupportDirectory()).path;
        final xstreamDir = Directory('$home/.config/xstream');
        await xstreamDir.create(recursive: true);
        return '${xstreamDir.path}/vpn_nodes.json';

      default:
        return await getVpnNodesConfigPath();
    }
  }

  /// 根据 region 生成各平台的启动控制文件或任务名称
  static Future<String> serviceNameForRegion(String region) async {
    final code = region.toLowerCase();
    switch (Platform.operatingSystem) {
      case 'macos':
        final bundleId = await getBundleId();
        return '$bundleId.xray-node-$code.plist';
      case 'linux':
        return 'xray-node-$code.service';
      case 'windows':
        return 'ray-node-$code.schtasks';
      default:
        return 'xray-node-$code';
    }
  }

  /// 根据平台和服务名称返回服务配置文件路径
  static Future<String> getServicePath(String serviceName) async {
    switch (Platform.operatingSystem) {
      case 'macos':
        // Use sandboxed services directory for App Store compliance
        final servicesPath = await getServicesPath();
        return '$servicesPath/$serviceName';
      case 'linux':
        return '/etc/systemd/system/$serviceName';
      case 'windows':
        return '$windowsBasePath\\$serviceName';
      default:
        final servicesPath = await getServicesPath();
        return '$servicesPath/$serviceName';
    }
  }
}
