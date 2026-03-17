import 'package:flutter_test/flutter_test.dart';
import 'package:xstream/services/sync/desktop_sync_service.dart';

void main() {
  group('DesktopSyncService.shouldApplySyncPayload', () {
    test('applies when changed and config version is newer', () {
      final shouldApply = DesktopSyncService.shouldApplySyncPayload(
        changed: true,
        configVersion: 11,
        lastConfigVersion: 10,
        manual: false,
        hasRenderablePayload: false,
      );

      expect(shouldApply, isTrue);
    });

    test('skips when changed but config version is not newer in auto mode', () {
      final shouldApply = DesktopSyncService.shouldApplySyncPayload(
        changed: true,
        configVersion: 10,
        lastConfigVersion: 10,
        manual: false,
        hasRenderablePayload: true,
      );

      expect(shouldApply, isFalse);
    });

    test('applies manual sync when same version but payload is present', () {
      final shouldApply = DesktopSyncService.shouldApplySyncPayload(
        changed: true,
        configVersion: 10,
        lastConfigVersion: 10,
        manual: true,
        hasRenderablePayload: true,
      );

      expect(shouldApply, isTrue);
    });

    test('skips manual sync when payload is absent', () {
      final shouldApply = DesktopSyncService.shouldApplySyncPayload(
        changed: true,
        configVersion: 10,
        lastConfigVersion: 10,
        manual: true,
        hasRenderablePayload: false,
      );

      expect(shouldApply, isFalse);
    });

    test('always skips when server says not changed', () {
      final shouldApply = DesktopSyncService.shouldApplySyncPayload(
        changed: false,
        configVersion: 99,
        lastConfigVersion: 1,
        manual: true,
        hasRenderablePayload: true,
      );

      expect(shouldApply, isFalse);
    });
  });

  group('DesktopSyncService.isRenderableXrayConfig', () {
    test('returns false for empty config object', () {
      expect(DesktopSyncService.isRenderableXrayConfig('{}'), isFalse);
    });

    test('returns false when outbounds are missing', () {
      const json = '{"inbounds":[{"protocol":"tun"}]}';
      expect(DesktopSyncService.isRenderableXrayConfig(json), isFalse);
    });

    test('returns true for config with proxy outbound', () {
      const json = '''
{
  "outbounds": [
    {"tag":"proxy","protocol":"vless"},
    {"tag":"direct","protocol":"freedom"}
  ]
}
''';
      expect(DesktopSyncService.isRenderableXrayConfig(json), isTrue);
    });
  });

  group('DesktopSyncService.pickSyncedNodeName', () {
    test('prefers server-provided node name over vless host', () {
      final name = DesktopSyncService.pickSyncedNodeName(
        serverName: 'Japan Node',
        vlessUri:
            'vless://uuid@jp-xhttp.svc.plus:443?security=tls#jp-xhttp.svc.plus',
        id: 'jp-xhttp.svc.plus',
      );

      expect(name, 'Japan Node');
    });

    test('falls back to vless fragment then host when server name is absent', () {
      final fromFragment = DesktopSyncService.pickSyncedNodeName(
        vlessUri: 'vless://uuid@jp-xhttp.svc.plus:443?security=tls#Tokyo',
        id: 'node-1',
      );
      final fromHost = DesktopSyncService.pickSyncedNodeName(
        vlessUri: 'vless://uuid@jp-xhttp.svc.plus:443?security=tls',
        id: 'node-2',
      );

      expect(fromFragment, 'Tokyo');
      expect(fromHost, 'jp-xhttp.svc.plus');
    });
  });
}
