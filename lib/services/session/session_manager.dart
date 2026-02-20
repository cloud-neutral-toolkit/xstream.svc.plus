import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Session lifecycle states for account authentication.
enum SessionStatus { unknown, loggedOut, mfaRequired, loggedIn }

class LoginResult {
  final bool success;
  final bool mfaRequired;
  final String message;

  const LoginResult({
    required this.success,
    required this.message,
    this.mfaRequired = false,
  });
}

/// Handles xc_session cookie and bearer token persistence.
class SessionManager {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  static const _prefsBaseUrlKey = 'session.baseUrl';
  static const _prefsCookieKey = 'session.cookie';
  static const _prefsTokenKey = 'session.token';
  static const _prefsUserKey = 'session.username';

  final ValueNotifier<SessionStatus> status =
      ValueNotifier<SessionStatus>(SessionStatus.unknown);
  final ValueNotifier<String?> currentUser = ValueNotifier<String?>(null);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<String> baseUrl =
      ValueNotifier<String>('https://accounts.svc.plus');

  String? _cookie;
  String? _sessionToken;
  String? _mfaTicket;

  bool get isLoggedIn => status.value == SessionStatus.loggedIn;
  bool get isMfaRequired => status.value == SessionStatus.mfaRequired;
  String? get cookie => _cookie;
  String? get sessionToken => _sessionToken;
  String? get mfaTicket => _mfaTicket;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedBaseUrl = prefs.getString(_prefsBaseUrlKey);
    if (storedBaseUrl != null && storedBaseUrl.isNotEmpty) {
      baseUrl.value = storedBaseUrl;
    }

    _cookie = prefs.getString(_prefsCookieKey);
    _sessionToken = prefs.getString(_prefsTokenKey);
    currentUser.value = prefs.getString(_prefsUserKey);

    if ((_sessionToken ?? '').isNotEmpty || (_cookie ?? '').isNotEmpty) {
      status.value = SessionStatus.loggedIn;
    } else {
      status.value = SessionStatus.loggedOut;
    }
  }

  Future<void> setBaseUrl(String url) async {
    final normalized = _normalizeBaseUrl(url);
    baseUrl.value = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBaseUrlKey, normalized);
  }

  String _normalizeBaseUrl(String url) {
    var value = url.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    return value;
  }

  Uri buildEndpoint(String path) {
    final root = baseUrl.value;
    return Uri.parse('$root$path');
  }

  Future<LoginResult> login({
    required String identifier,
    required String password,
  }) async {
    loading.value = true;
    lastError.value = null;
    try {
      final response = await http.post(
        buildEndpoint('/api/auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identifier': identifier,
          'username': identifier,
          'email': identifier,
          'password': password,
        }),
      );

      if (response.statusCode >= 500) {
        lastError.value = '服务器错误 (${response.statusCode})';
        return LoginResult(success: false, message: lastError.value!);
      }
      if (response.statusCode == 404) {
        lastError.value = '登录接口未启用，请确认部署配置。';
        return LoginResult(success: false, message: lastError.value!);
      }

      final payload = _parseBody(response.body);
      if (_isMfaRequired(payload)) {
        final ticket = _extractMfaTicket(payload);
        if (ticket == null || ticket.isEmpty) {
          lastError.value = 'MFA 票据缺失';
          return LoginResult(success: false, message: lastError.value!);
        }
        _mfaTicket = ticket;
        currentUser.value = identifier;
        status.value = SessionStatus.mfaRequired;
        return const LoginResult(
          success: false,
          mfaRequired: true,
          message: '请输入 MFA 验证码',
        );
      }

      if (response.statusCode != 200) {
        final message = payload['message'] as String? ?? '账号或密码错误';
        lastError.value = message;
        return LoginResult(success: false, message: message);
      }

      return await _completeLogin(
        payload: payload,
        responseHeaders: response.headers,
        fallbackUsername: identifier,
      );
    } catch (e) {
      final message = '登录失败: $e';
      lastError.value = message;
      return LoginResult(success: false, message: message);
    } finally {
      loading.value = false;
    }
  }

  Future<LoginResult> verifyMfaCode(String code) async {
    final ticket = (_mfaTicket ?? '').trim();
    final normalizedCode = code.trim();
    if (ticket.isEmpty) {
      lastError.value = 'MFA 会话不存在，请重新登录';
      return LoginResult(success: false, message: lastError.value!);
    }
    if (normalizedCode.isEmpty) {
      lastError.value = '请输入 MFA 验证码';
      return LoginResult(success: false, message: lastError.value!);
    }

    loading.value = true;
    lastError.value = null;
    try {
      final response = await http.post(
        buildEndpoint('/api/auth/mfa/verify'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mfa_ticket': ticket,
          'code': normalizedCode,
          'method': 'totp',
        }),
      );

      final payload = _parseBody(response.body);
      if (response.statusCode != 200) {
        final message = payload['message'] as String? ?? 'MFA 验证失败';
        lastError.value = message;
        return LoginResult(success: false, message: message);
      }

      return await _completeLogin(
        payload: payload,
        responseHeaders: response.headers,
        fallbackUsername: currentUser.value ?? '',
      );
    } catch (e) {
      final message = 'MFA 验证失败: $e';
      lastError.value = message;
      return LoginResult(success: false, message: message);
    } finally {
      loading.value = false;
    }
  }

  Future<LoginResult> _completeLogin({
    required Map<String, dynamic> payload,
    required Map<String, String> responseHeaders,
    required String fallbackUsername,
  }) async {
    final token = _extractSessionToken(payload);
    final cookie = _extractSessionCookie(responseHeaders);
    if ((token ?? '').isEmpty && (cookie ?? '').isEmpty) {
      lastError.value = '未返回有效会话信息';
      return LoginResult(success: false, message: lastError.value!);
    }

    _sessionToken = token;
    _cookie = cookie ?? _cookie;
    _mfaTicket = null;
    final savedUser = _extractLoginIdentity(payload, fallbackUsername);
    currentUser.value = savedUser;
    status.value = SessionStatus.loggedIn;

    final prefs = await SharedPreferences.getInstance();
    if (_cookie != null && _cookie!.isNotEmpty) {
      await prefs.setString(_prefsCookieKey, _cookie!);
    } else {
      await prefs.remove(_prefsCookieKey);
    }
    if (_sessionToken != null && _sessionToken!.isNotEmpty) {
      await prefs.setString(_prefsTokenKey, _sessionToken!);
    } else {
      await prefs.remove(_prefsTokenKey);
    }
    await prefs.setString(_prefsUserKey, savedUser);

    return const LoginResult(success: true, message: '登录成功');
  }

  Future<void> logout() async {
    _cookie = null;
    _sessionToken = null;
    _mfaTicket = null;
    currentUser.value = null;
    status.value = SessionStatus.loggedOut;
    lastError.value = null;
    await _clearPrefs();
  }

  Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsCookieKey);
    await prefs.remove(_prefsTokenKey);
    await prefs.remove(_prefsUserKey);
  }

  Map<String, dynamic> _parseBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  bool _isMfaRequired(Map<String, dynamic> payload) {
    return payload['mfa_required'] == true || payload['mfaRequired'] == true;
  }

  String? _extractMfaTicket(Map<String, dynamic> payload) {
    final candidates = [
      payload['mfa_ticket'],
      payload['mfaTicket'],
      payload['mfaToken'],
    ];
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  String? _extractSessionToken(Map<String, dynamic> payload) {
    final candidates = [payload['token'], payload['access_token']];
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  String? _extractSessionCookie(Map<String, String> headers) {
    final setCookie = headers['set-cookie'];
    if (setCookie == null) return null;

    final match = RegExp(r'xc_session=([^;\s,]+)').firstMatch(setCookie);
    if (match != null) return 'xc_session=${match.group(1)}';
    return null;
  }

  String _extractLoginIdentity(
    Map<String, dynamic> payload,
    String fallbackUsername,
  ) {
    final user = payload['user'];
    if (user is Map) {
      final normalized = user.cast<Object?, Object?>();
      final candidates = [
        normalized['email'],
        normalized['username'],
        normalized['name'],
      ];
      for (final candidate in candidates) {
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    }
    return fallbackUsername;
  }
}
