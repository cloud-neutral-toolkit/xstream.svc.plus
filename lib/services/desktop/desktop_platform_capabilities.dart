import 'dart:io';

class DesktopPlatformCapabilities {
  const DesktopPlatformCapabilities({
    required this.supportsNativeTrayMenu,
    required this.supportsRuntimeMcp,
    required this.supportsUnifiedTunnelStatus,
    required this.supportsRuntimeMetrics,
    required this.usesLocalProxyLatencyProbe,
  });

  final bool supportsNativeTrayMenu;
  final bool supportsRuntimeMcp;
  final bool supportsUnifiedTunnelStatus;
  final bool supportsRuntimeMetrics;
  final bool usesLocalProxyLatencyProbe;

  static DesktopPlatformCapabilities get current =>
      resolveForOperatingSystem(Platform.operatingSystem);

  static DesktopPlatformCapabilities resolveForOperatingSystem(
    String operatingSystem,
  ) {
    switch (operatingSystem) {
      case 'macos':
        return const DesktopPlatformCapabilities(
          supportsNativeTrayMenu: true,
          supportsRuntimeMcp: true,
          supportsUnifiedTunnelStatus: true,
          supportsRuntimeMetrics: true,
          usesLocalProxyLatencyProbe: true,
        );
      case 'windows':
        return const DesktopPlatformCapabilities(
          supportsNativeTrayMenu: true,
          supportsRuntimeMcp: false,
          supportsUnifiedTunnelStatus: true,
          supportsRuntimeMetrics: true,
          usesLocalProxyLatencyProbe: false,
        );
      case 'linux':
        return const DesktopPlatformCapabilities(
          supportsNativeTrayMenu: false,
          supportsRuntimeMcp: false,
          supportsUnifiedTunnelStatus: true,
          supportsRuntimeMetrics: true,
          usesLocalProxyLatencyProbe: false,
        );
      default:
        return const DesktopPlatformCapabilities(
          supportsNativeTrayMenu: false,
          supportsRuntimeMcp: false,
          supportsUnifiedTunnelStatus: false,
          supportsRuntimeMetrics: false,
          usesLocalProxyLatencyProbe: false,
        );
    }
  }
}
