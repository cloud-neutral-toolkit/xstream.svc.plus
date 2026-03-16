import 'package:flutter_test/flutter_test.dart';
import 'package:xstream/services/permission_guide_service.dart';

void main() {
  group('PermissionGuideService.looksLikePacketTunnelPermissionDenied', () {
    test('matches Android VPN permission lifecycle markers', () {
      expect(
        PermissionGuideService.looksLikePacketTunnelPermissionDenied(
          'vpn_permission_requested',
        ),
        isTrue,
      );
      expect(
        PermissionGuideService.looksLikePacketTunnelPermissionDenied(
          'vpn_permission_denied',
        ),
        isTrue,
      );
      expect(
        PermissionGuideService.looksLikePacketTunnelPermissionDenied(
          'vpn_permission_required',
        ),
        isTrue,
      );
    });

    test('ignores unrelated failures', () {
      expect(
        PermissionGuideService.looksLikePacketTunnelPermissionDenied(
          'xray_start_failed',
        ),
        isFalse,
      );
    });
  });
}
