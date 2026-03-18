import 'package:flutter_test/flutter_test.dart';
import 'package:xstream/services/desktop/desktop_platform_capabilities.dart';

void main() {
  group('DesktopPlatformCapabilities', () {
    test('resolves macOS desktop parity capabilities', () {
      final capabilities =
          DesktopPlatformCapabilities.resolveForOperatingSystem('macos');

      expect(capabilities.supportsNativeTrayMenu, isTrue);
      expect(capabilities.supportsRuntimeMcp, isTrue);
      expect(capabilities.supportsUnifiedTunnelStatus, isTrue);
      expect(capabilities.supportsRuntimeMetrics, isTrue);
      expect(capabilities.usesLocalProxyLatencyProbe, isTrue);
    });

    test('resolves Windows core parity capabilities', () {
      final capabilities =
          DesktopPlatformCapabilities.resolveForOperatingSystem('windows');

      expect(capabilities.supportsNativeTrayMenu, isTrue);
      expect(capabilities.supportsRuntimeMcp, isFalse);
      expect(capabilities.supportsUnifiedTunnelStatus, isTrue);
      expect(capabilities.supportsRuntimeMetrics, isTrue);
      expect(capabilities.usesLocalProxyLatencyProbe, isFalse);
    });

    test('falls back to disabled capabilities for unsupported platforms', () {
      final capabilities =
          DesktopPlatformCapabilities.resolveForOperatingSystem('ios');

      expect(capabilities.supportsNativeTrayMenu, isFalse);
      expect(capabilities.supportsRuntimeMcp, isFalse);
      expect(capabilities.supportsUnifiedTunnelStatus, isFalse);
      expect(capabilities.supportsRuntimeMetrics, isFalse);
      expect(capabilities.usesLocalProxyLatencyProbe, isFalse);
    });
  });
}
