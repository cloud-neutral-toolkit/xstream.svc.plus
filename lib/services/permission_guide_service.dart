import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/global_config.dart' show GlobalState;
import '../utils/native_bridge.dart';

class PermissionCheckItem {
  final String id;
  final bool passed;
  final String detail;
  final String suggestion;

  const PermissionCheckItem({
    required this.id,
    required this.passed,
    required this.detail,
    required this.suggestion,
  });
}

class PermissionGuideReport {
  final List<PermissionCheckItem> items;

  const PermissionGuideReport(this.items);

  bool get allPassed => items.every((item) => item.passed);
}

class PermissionGuideService {
  static const _prefsKey = 'permissionGuideDone';

  static bool looksLikePacketTunnelPermissionDenied(String? message) {
    final normalized = (message ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('permission denied') ||
        normalized.contains('vpn_permission_required') ||
        normalized.contains('vpn_permission_requested') ||
        normalized.contains('vpn_permission_denied') ||
        normalized.contains('authorization denied') ||
        normalized.contains('not authorized');
  }

  static Future<bool> shouldPromptForPacketTunnelAuthorization({
    String? failureMessage,
  }) async {
    if (!Platform.isMacOS && !Platform.isAndroid) {
      return false;
    }
    if (looksLikePacketTunnelPermissionDenied(failureMessage)) {
      return true;
    }
    try {
      final status = await NativeBridge.getPacketTunnelStatus();
      if (status.status == 'not_configured') {
        return true;
      }
      return looksLikePacketTunnelPermissionDenied(status.lastError);
    } catch (_) {
      return false;
    }
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_prefsKey) ?? false;
    GlobalState.permissionGuideDone.value = done;
    GlobalState.permissionGuideDone.addListener(() {
      prefs.setBool(_prefsKey, GlobalState.permissionGuideDone.value);
    });
  }

  static Future<PermissionGuideReport> inspectSystemPermissions() async {
    final items = <PermissionCheckItem>[];
    items.add(await _checkAppSupportWritable());
    items.add(await _checkPacketTunnelPermission());
    items.add(await _checkLaunchAgentReadiness());
    items.add(await _checkNetworkQueryCapability());
    return PermissionGuideReport(items);
  }

  static Future<PermissionCheckItem> _checkAppSupportWritable() async {
    try {
      final dir = await Directory.systemTemp.createTemp('xstream-perm-check-');
      final file = File('${dir.path}/rw-check.txt');
      await file.writeAsString('ok');
      final readBack = await file.readAsString();
      await dir.delete(recursive: true);
      if (readBack == 'ok') {
        return const PermissionCheckItem(
          id: 'app_support_rw',
          passed: true,
          detail: 'Application Support read/write is available.',
          suggestion: '',
        );
      }
    } catch (e) {
      return PermissionCheckItem(
        id: 'app_support_rw',
        passed: false,
        detail: 'Application Support read/write failed: $e',
        suggestion:
            'Grant app file access in Privacy & Security if prompted, then retry.',
      );
    }
    return const PermissionCheckItem(
      id: 'app_support_rw',
      passed: false,
      detail: 'Application Support read/write validation failed.',
      suggestion: 'Check file permission and retry.',
    );
  }

  static Future<PermissionCheckItem> _checkPacketTunnelPermission() async {
    if (!Platform.isMacOS && !Platform.isIOS && !Platform.isAndroid) {
      return const PermissionCheckItem(
        id: 'packet_tunnel',
        passed: true,
        detail: 'Packet Tunnel check skipped on current platform.',
        suggestion: '',
      );
    }

    try {
      final status = await NativeBridge.getPacketTunnelStatus();
      final lastError = status.lastError?.trim();
      if (status.status == 'not_configured') {
        return PermissionCheckItem(
          id: 'packet_tunnel',
          passed: false,
          detail: Platform.isAndroid
              ? 'Android VPN service is not configured yet.'
              : 'Packet Tunnel manager is not configured.',
          suggestion: Platform.isAndroid
              ? 'Enable Tunnel Mode once to trigger the Android VPN permission prompt.'
              : 'Enable system VPN once in app to trigger NetworkExtension permission prompt.',
        );
      }
      if (status.status == 'unsupported') {
        return PermissionCheckItem(
          id: 'packet_tunnel',
          passed: false,
          detail: Platform.isAndroid
              ? 'Android VPN tunnel is unsupported in current runtime.'
              : 'Packet Tunnel is unsupported in current runtime.',
          suggestion: Platform.isAndroid
              ? 'Check VpnService manifest wiring, native bridge registration, and tunnel service packaging.'
              : 'Check NetworkExtension capability, PacketTunnel target embedding, and signing entitlement.',
        );
      }
      if (lastError != null &&
          lastError.isNotEmpty &&
          status.status != 'connected') {
        final permissionDenied = looksLikePacketTunnelPermissionDenied(
          lastError,
        );
        return PermissionCheckItem(
          id: 'packet_tunnel',
          passed: false,
          detail: 'Packet Tunnel last error: $lastError',
          suggestion: permissionDenied
              ? (Platform.isAndroid
                    ? 'Approve the Android VPN permission for Xstream, or reopen VPN settings and retry.'
                    : 'Open Privacy & Security, approve System VPN permission for Xstream, then retry.')
              : 'Review the Packet Tunnel error details, then retry after fixing authorization or configuration.',
        );
      }
      final utunDetail = status.utunInterfaces.isEmpty
          ? 'no active utun interface'
          : 'utun=${status.utunInterfaces.join(",")}';
      return PermissionCheckItem(
        id: 'packet_tunnel',
        passed: true,
        detail: 'Packet Tunnel status: ${status.status} ($utunDetail)',
        suggestion: '',
      );
    } catch (e) {
      return PermissionCheckItem(
        id: 'packet_tunnel',
        passed: false,
        detail: 'Packet Tunnel status query failed: $e',
        suggestion:
            'Allow VPN permission for this app in System Settings, then retry.',
      );
    }
  }

  static Future<PermissionCheckItem> _checkLaunchAgentReadiness() async {
    if (!Platform.isMacOS) {
      return const PermissionCheckItem(
        id: 'launch_agent',
        passed: true,
        detail: 'LaunchAgent check skipped on current platform.',
        suggestion: '',
      );
    }

    try {
      final uidResult = await Process.run('id', ['-u']);
      final uid = (uidResult.stdout as String).trim();
      final printResult = await Process.run('launchctl', ['print', 'gui/$uid']);
      final launchAgentsDir =
          '${Platform.environment['HOME'] ?? ''}/Library/LaunchAgents';
      final dir = Directory(launchAgentsDir);
      await dir.create(recursive: true);
      final probe = File('${dir.path}/.xstream_perm_probe');
      await probe.writeAsString('probe');
      await probe.delete();

      if (printResult.exitCode == 0) {
        return const PermissionCheckItem(
          id: 'launch_agent',
          passed: true,
          detail: 'LaunchAgent bootstrap context is available.',
          suggestion: '',
        );
      }
      return PermissionCheckItem(
        id: 'launch_agent',
        passed: false,
        detail: 'launchctl print gui/<uid> failed: ${printResult.stderr}',
        suggestion:
            'Re-login to desktop session and run app as normal user (not root shell).',
      );
    } catch (e) {
      return PermissionCheckItem(
        id: 'launch_agent',
        passed: false,
        detail: 'LaunchAgent readiness check failed: $e',
        suggestion:
            'If you hit "Bootstrap failed: 5", verify LaunchAgents permission and user session context.',
      );
    }
  }

  static Future<PermissionCheckItem> _checkNetworkQueryCapability() async {
    if (!Platform.isMacOS) {
      return const PermissionCheckItem(
        id: 'network_query',
        passed: true,
        detail: 'Network query check skipped on current platform.',
        suggestion: '',
      );
    }

    try {
      final a = await Process.run('scutil', ['--nc', 'list']);
      final b = await Process.run('networksetup', ['-listallnetworkservices']);
      final ok = a.exitCode == 0 && b.exitCode == 0;
      return PermissionCheckItem(
        id: 'network_query',
        passed: ok,
        detail: ok
            ? 'System network query commands are available.'
            : 'Network query failed: scutil=${a.exitCode}, networksetup=${b.exitCode}',
        suggestion: ok
            ? ''
            : 'Check terminal/system permission policy, then retry.',
      );
    } catch (e) {
      return PermissionCheckItem(
        id: 'network_query',
        passed: false,
        detail: 'Network query check failed: $e',
        suggestion: 'Ensure system network tools are available and retry.',
      );
    }
  }
}
