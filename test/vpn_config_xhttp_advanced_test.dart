import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xstream/services/vpn_config_service.dart';
import 'package:xstream/utils/global_config.dart';

Map<String, dynamic> _proxyStreamSettingsFromConfig(String jsonText) {
  final obj = jsonDecode(jsonText) as Map<String, dynamic>;
  final outbounds = (obj['outbounds'] as List<dynamic>);
  final proxy = outbounds.cast<Map>().firstWhere(
        (item) => item['tag'] == 'proxy',
      );
  return Map<String, dynamic>.from(
    proxy['streamSettings'] as Map<dynamic, dynamic>,
  );
}

void main() {
  group('xhttp advanced config', () {
    test('defaults to auto and includes h3/h2/http1.1', () async {
      XhttpAdvancedConfig.setMode(XhttpAdvancedConfig.modeAuto);
      XhttpAdvancedConfig.setAlpn(<String>[
        XhttpAdvancedConfig.alpnH3,
        XhttpAdvancedConfig.alpnH2,
        XhttpAdvancedConfig.alpnHttp11,
      ]);

      final jsonText = await VpnConfig.tryGenerateXrayJsonFromVlessUri(
        'vless://11111111-1111-1111-1111-111111111111@example.com:443'
        '?type=xhttp&security=tls&mode=stream-up&alpn=h2#example',
      );
      expect(jsonText, isNotNull);

      final streamSettings = _proxyStreamSettingsFromConfig(jsonText!);
      final xhttpSettings = Map<String, dynamic>.from(
        streamSettings['xhttpSettings'] as Map<dynamic, dynamic>,
      );
      final tlsSettings = Map<String, dynamic>.from(
        streamSettings['tlsSettings'] as Map<dynamic, dynamic>,
      );
      final alpn = List<String>.from(tlsSettings['alpn'] as List<dynamic>);

      expect(xhttpSettings['mode'], XhttpAdvancedConfig.modeAuto);
      expect(alpn, <String>['h3', 'h2', 'http/1.1']);
    });

    test('allows stream-up and removing h3 from advanced config', () async {
      XhttpAdvancedConfig.setMode(XhttpAdvancedConfig.modeStreamUp);
      XhttpAdvancedConfig.setAlpn(<String>[
        XhttpAdvancedConfig.alpnH2,
        XhttpAdvancedConfig.alpnHttp11,
      ]);

      final jsonText = await VpnConfig.tryGenerateXrayJsonFromVlessUri(
        'vless://22222222-2222-2222-2222-222222222222@example.com:443'
        '?type=xhttp&security=tls#example',
      );
      expect(jsonText, isNotNull);

      final streamSettings = _proxyStreamSettingsFromConfig(jsonText!);
      final xhttpSettings = Map<String, dynamic>.from(
        streamSettings['xhttpSettings'] as Map<dynamic, dynamic>,
      );
      final tlsSettings = Map<String, dynamic>.from(
        streamSettings['tlsSettings'] as Map<dynamic, dynamic>,
      );
      final alpn = List<String>.from(tlsSettings['alpn'] as List<dynamic>);

      expect(xhttpSettings['mode'], XhttpAdvancedConfig.modeStreamUp);
      expect(alpn, <String>['h2', 'http/1.1']);
    });
  });
}
