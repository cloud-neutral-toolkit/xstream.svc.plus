import 'dart:convert';
import 'dart:typed_data';

class SyncRequest {
  final int version;
  final Uint8List deviceFingerprint;
  final String clientVersion;
  final Uint8List nonce;
  final int timestamp;
  final int lastConfigVersion;

  SyncRequest({
    required this.version,
    required this.deviceFingerprint,
    required this.clientVersion,
    required this.nonce,
    required this.timestamp,
    required this.lastConfigVersion,
  })  : assert(deviceFingerprint.length == 32,
            'deviceFingerprint must be 32 bytes'),
        assert(nonce.length == 24, 'nonce must be 24 bytes');

  Uint8List toBytes() {
    final builder = BytesBuilder();
    builder.add([version & 0xFF]);
    builder.add(deviceFingerprint);

    final clientVersionBytes = utf8.encode(clientVersion);
    if (clientVersionBytes.length > 255) {
      throw ArgumentError('clientVersion length must be <= 255 bytes');
    }
    builder.add([clientVersionBytes.length]);
    builder.add(clientVersionBytes);

    builder.add(nonce);

    final timeBuffer = ByteData(8)..setInt64(0, timestamp, Endian.big);
    builder.add(timeBuffer.buffer.asUint8List());

    final versionBuffer = ByteData(4)
      ..setInt32(0, lastConfigVersion, Endian.big);
    builder.add(versionBuffer.buffer.asUint8List());

    return builder.toBytes();
  }
}

enum SyncResponseStatus { ok, noPrivilege, error }

class SyncResponse {
  final int version;
  final SyncResponseStatus status;
  final int configVersion;
  final Uint8List xrayConfigGzip;
  final String? subscriptionMetadata;

  const SyncResponse({
    required this.version,
    required this.status,
    required this.configVersion,
    required this.xrayConfigGzip,
    this.subscriptionMetadata,
  });
}

SyncResponse parseSyncResponse(Uint8List bytes) {
  if (bytes.length < 6) {
    throw StateError('sync response too short');
  }
  var offset = 0;
  final version = bytes[offset];
  offset += 1;
  final statusByte = bytes[offset];
  offset += 1;

  final status = switch (statusByte) {
    0 => SyncResponseStatus.ok,
    1 => SyncResponseStatus.noPrivilege,
    _ => SyncResponseStatus.error,
  };

  final versionBuffer = ByteData.sublistView(bytes, offset, offset + 4);
  final configVersion = versionBuffer.getInt32(0, Endian.big);
  offset += 4;

  if (bytes.length < offset + 4) {
    throw StateError('invalid sync payload length');
  }
  final lengthBuffer = ByteData.sublistView(bytes, offset, offset + 4);
  final configLength = lengthBuffer.getUint32(0, Endian.big);
  offset += 4;

  if (bytes.length < offset + configLength) {
    throw StateError('xray config truncated');
  }
  final xrayConfig =
      Uint8List.sublistView(bytes, offset, offset + configLength);
  offset += configLength;

  String? metadata;
  if (bytes.length >= offset + 2) {
    final metadataLength = ByteData.sublistView(bytes, offset, offset + 2)
        .getUint16(0, Endian.big);
    offset += 2;
    if (metadataLength > 0) {
      if (bytes.length < offset + metadataLength) {
        throw StateError('subscription metadata truncated');
      }
      metadata = utf8.decode(
        bytes.sublist(offset, offset + metadataLength),
      );
    }
  }

  return SyncResponse(
    version: version,
    status: status,
    configVersion: configVersion,
    xrayConfigGzip: xrayConfig,
    subscriptionMetadata: metadata,
  );
}
