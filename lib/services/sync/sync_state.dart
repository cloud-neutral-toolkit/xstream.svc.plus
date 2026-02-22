import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncSummary {
  final int configVersion;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final String? subscriptionMetadata;

  const SyncSummary({
    required this.configVersion,
    required this.lastSuccessAt,
    required this.lastError,
    required this.subscriptionMetadata,
  });

  SyncSummary copyWith({
    int? configVersion,
    DateTime? lastSuccessAt,
    String? lastError,
    String? subscriptionMetadata,
  }) {
    return SyncSummary(
      configVersion: configVersion ?? this.configVersion,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastError: lastError,
      subscriptionMetadata: subscriptionMetadata ?? this.subscriptionMetadata,
    );
  }
}

class SyncStateStore {
  SyncStateStore._();

  static final SyncStateStore instance = SyncStateStore._();

  static const _configVersionKey = 'sync.configVersion';
  static const _lastSuccessKey = 'sync.lastSuccessAt';
  static const _lastErrorKey = 'sync.lastError';
  static const _metadataKey = 'sync.subscriptionMetadata';

  final ValueNotifier<SyncSummary> summary = ValueNotifier<SyncSummary>(
    const SyncSummary(
      configVersion: 0,
      lastSuccessAt: null,
      lastError: null,
      subscriptionMetadata: null,
    ),
  );

  int get lastConfigVersion => summary.value.configVersion;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final configVersion = prefs.getInt(_configVersionKey) ?? 0;
    final lastSuccessMillis = prefs.getInt(_lastSuccessKey);
    final lastError = prefs.getString(_lastErrorKey);
    final metadata = prefs.getString(_metadataKey);

    summary.value = SyncSummary(
      configVersion: configVersion,
      lastSuccessAt: lastSuccessMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastSuccessMillis)
          : null,
      lastError: lastError,
      subscriptionMetadata: metadata,
    );
  }

  Future<void> recordSuccess({
    required int configVersion,
    String? metadata,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setInt(_configVersionKey, configVersion);
    await prefs.setInt(_lastSuccessKey, now.millisecondsSinceEpoch);
    if (metadata != null) {
      await prefs.setString(_metadataKey, metadata);
    }
    await prefs.remove(_lastErrorKey);

    summary.value = SyncSummary(
      configVersion: configVersion,
      lastSuccessAt: now,
      lastError: null,
      subscriptionMetadata: metadata ?? summary.value.subscriptionMetadata,
    );
  }

  Future<void> recordError(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastErrorKey, message);
    summary.value = summary.value.copyWith(lastError: message);
  }
}
