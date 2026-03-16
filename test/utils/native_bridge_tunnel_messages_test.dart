import 'package:flutter_test/flutter_test.dart';
import 'package:xstream/utils/native_bridge.dart';

void main() {
  group('NativeBridge.isTunnelStartAcceptedMessage', () {
    test('accepts Android pending and submitted messages', () {
      expect(
        NativeBridge.isTunnelStartAcceptedMessage('vpn_permission_requested'),
        isTrue,
      );
      expect(
        NativeBridge.isTunnelStartAcceptedMessage('start_submitted'),
        isTrue,
      );
    });

    test('rejects explicit failures', () {
      expect(
        NativeBridge.isTunnelStartAcceptedMessage(
          '启动失败: vpn_permission_denied',
        ),
        isFalse,
      );
      expect(
        NativeBridge.isTunnelStartAcceptedMessage('xray_start_failed'),
        isFalse,
      );
    });
  });
}
