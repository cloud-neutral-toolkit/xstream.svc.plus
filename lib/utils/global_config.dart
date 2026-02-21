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
      ValueNotifier<String>('VPN');

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
}

/// 管理 DNS 配置，支持保存到本地
class DnsConfig {
  static const _dns1Key = 'dnsServer1';
  static const _dns2Key = 'dnsServer2';

  static final ValueNotifier<String> dns1 =
      ValueNotifier<String>('https://1.1.1.1/dns-query');
  static final ValueNotifier<String> dns2 =
      ValueNotifier<String>('https://8.8.8.8/dns-query');

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    dns1.value = prefs.getString(_dns1Key) ?? dns1.value;
    dns2.value = prefs.getString(_dns2Key) ?? dns2.value;

    dns1.addListener(() => prefs.setString(_dns1Key, dns1.value));
    dns2.addListener(() => prefs.setString(_dns2Key, dns2.value));
  }
}

/// Packet Tunnel DNS settings (DoT optional, always through tunnel)
class TunDnsConfig {
  static const _dns1Key = 'tunDnsServer1';
  static const _dns2Key = 'tunDnsServer2';
  static const _tlsNameKey = 'tunDnsTlsServerName';
  static const _dotEnabledKey = 'tunDnsOverTls';

  static final ValueNotifier<String> dns1 = ValueNotifier<String>('1.1.1.1');
  static final ValueNotifier<String> dns2 = ValueNotifier<String>('8.8.8.8');
  static final ValueNotifier<String> tlsServerName =
      ValueNotifier<String>('cloudflare-dns.com');
  static final ValueNotifier<bool> dotEnabled = ValueNotifier<bool>(true);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    dns1.value = prefs.getString(_dns1Key) ?? dns1.value;
    dns2.value = prefs.getString(_dns2Key) ?? dns2.value;
    tlsServerName.value = prefs.getString(_tlsNameKey) ?? tlsServerName.value;
    dotEnabled.value = prefs.getBool(_dotEnabledKey) ?? dotEnabled.value;

    dns1.addListener(() => prefs.setString(_dns1Key, dns1.value));
    dns2.addListener(() => prefs.setString(_dns2Key, dns2.value));
    tlsServerName
        .addListener(() => prefs.setString(_tlsNameKey, tlsServerName.value));
    dotEnabled
        .addListener(() => prefs.setBool(_dotEnabledKey, dotEnabled.value));
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
