import 'package:flutter_test/flutter_test.dart';
import 'package:xstream/utils/native_bridge.dart';

void main() {
  test('LinuxDesktopIntegrationStatus parses bridge payload', () {
    final status = LinuxDesktopIntegrationStatus.fromMap(<String, dynamic>{
      'desktopEnvironment': 'gnome',
      'autostartEnabled': true,
      'privilegeReady': true,
      'message': 'ok',
    });

    expect(status.desktopEnvironment, 'gnome');
    expect(status.autostartEnabled, isTrue);
    expect(status.privilegeReady, isTrue);
    expect(status.message, 'ok');
  });
}
