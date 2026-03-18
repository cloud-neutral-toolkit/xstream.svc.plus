import 'package:flutter_test/flutter_test.dart';
import 'package:xstream/utils/native_bridge.dart';

void main() {
  group('DesktopRuntimeSnapshot', () {
    test('parses desktop runtime snapshot JSON payload', () {
      final snapshot = DesktopRuntimeSnapshot.fromJsonString('''
      {
        "running": true,
        "downloadBytesPerSecond": 1234,
        "uploadBytesPerSecond": 567,
        "memoryBytes": 2048,
        "cpuPercent": 18.5,
        "updatedAt": 1742097600000
      }
      ''');

      expect(snapshot.running, isTrue);
      expect(snapshot.downloadBytesPerSecond, 1234);
      expect(snapshot.uploadBytesPerSecond, 567);
      expect(snapshot.memoryBytes, 2048);
      expect(snapshot.cpuPercent, 18.5);
      expect(snapshot.updatedAt, 1742097600000);
    });

    test('returns fallback snapshot for invalid payload', () {
      final snapshot = DesktopRuntimeSnapshot.fromJsonString(
        'not-a-json-payload',
      );

      expect(snapshot.running, isFalse);
      expect(snapshot.downloadBytesPerSecond, isNull);
      expect(snapshot.uploadBytesPerSecond, isNull);
      expect(snapshot.memoryBytes, isNull);
      expect(snapshot.cpuPercent, isNull);
      expect(snapshot.updatedAt, isNull);
    });
  });
}
