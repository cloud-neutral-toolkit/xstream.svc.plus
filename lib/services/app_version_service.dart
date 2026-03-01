import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  const AppVersionInfo({
    this.appName = 'xstream',
    this.packageName = '',
    this.version = '0.0.0',
    this.buildNumber = '0',
  });

  String get shortLabel => '$version ($buildNumber)';
}

class AppVersionService {
  static final ValueNotifier<AppVersionInfo> info =
      ValueNotifier<AppVersionInfo>(const AppVersionInfo());

  static Future<void> init() async {
    try {
      final package = await PackageInfo.fromPlatform();
      info.value = AppVersionInfo(
        appName: package.appName.isEmpty ? 'xstream' : package.appName,
        packageName: package.packageName,
        version: package.version.isEmpty ? '0.0.0' : package.version,
        buildNumber: package.buildNumber.isEmpty ? '0' : package.buildNumber,
      );
    } catch (_) {}
  }

  static String get currentVersion => info.value.version;

  static String get buildNumber => info.value.buildNumber;

  static String get shortLabel => info.value.shortLabel;
}
