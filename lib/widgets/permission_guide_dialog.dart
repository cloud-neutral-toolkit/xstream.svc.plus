import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/permission_guide_service.dart';
import '../utils/global_config.dart' show GlobalState;
import '../utils/app_theme.dart';

Future<void> showPermissionGuideDialog(
  BuildContext context, {
  String? failureMessage,
}) async {
  final report = await PermissionGuideService.inspectSystemPermissions();
  if (!context.mounted) return;

  final normalizedFailure = failureMessage?.trim();
  final showFailureContext =
      normalizedFailure != null && normalizedFailure.isNotEmpty;

  if (!showFailureContext &&
      GlobalState.permissionGuideDone.value &&
      report.allPassed) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.get('permissionGuide')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.get('permissionFinished')),
            const SizedBox(height: 8),
            Text(context.l10n.get('permissionGuideAllPassed')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.get('close')),
          ),
        ],
      ),
    );
    return;
  }

  if (!report.allPassed && GlobalState.permissionGuideDone.value) {
    GlobalState.permissionGuideDone.value = false;
  }

  final steps = context.l10n.get('permissionGuideSteps');

  String titleForCheck(String id) {
    switch (id) {
      case 'app_support_rw':
        return context.l10n.get('permissionCheckAppSupport');
      case 'packet_tunnel':
        return context.l10n.get('permissionCheckPacketTunnel');
      case 'launch_agent':
        return context.l10n.get('permissionCheckLaunchAgent');
      case 'network_query':
        return context.l10n.get('permissionCheckNetworkQuery');
      default:
        return id;
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final cs = Theme.of(dialogContext).colorScheme;
      final xc = dialogContext.xColors;

      return AlertDialog(
        title: Text(
          showFailureContext
              ? context.l10n.get('permissionGuideFailureTitle')
              : context.l10n.get('permissionGuide'),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showFailureContext) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: xc.warningBannerBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: xc.warningBannerBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.get('permissionGuideFailureIntro'),
                        style: TextStyle(
                          fontSize: 13,
                          color: xc.warningBannerText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.get('permissionGuideLastError'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: xc.warningBannerText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        normalizedFailure,
                        style: TextStyle(
                          fontSize: 12,
                          color: xc.warningBannerText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                context.l10n.get('permissionGuideIntro'),
                style: TextStyle(color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              SelectableText(
                steps,
                style: TextStyle(color: cs.onSurface),
              ),
              const SizedBox(height: 12),
              ...report.items.map((item) {
                final statusText = item.passed
                    ? context.l10n.get('permissionStatusPass')
                    : context.l10n.get('permissionStatusFail');
                final statusColor =
                    item.passed ? xc.success : cs.error;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${titleForCheck(item.id)}: $statusText',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                      if (!item.passed) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.suggestion,
                          style: TextStyle(
                            fontSize: 12,
                            color: xc.warning,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              if (!report.allPassed) ...[
                Text(
                  context.l10n.get('permissionBootstrapHint'),
                  style: TextStyle(fontSize: 12, color: xc.warning),
                ),
                const SizedBox(height: 4),
              ],
              if (showFailureContext &&
                  PermissionGuideService.looksLikePacketTunnelPermissionDenied(
                    normalizedFailure,
                  ))
                Text(
                  context.l10n.get('permissionGuideTunnelDeniedHint'),
                  style: TextStyle(fontSize: 12, color: xc.warning),
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _openSecurityPage,
                child: Text(context.l10n.get('openPrivacy')),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  showPermissionGuideDialog(
                    context,
                    failureMessage: failureMessage,
                  );
                },
                child: Text(context.l10n.get('permissionRecheck')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              GlobalState.permissionGuideDone.value = report.allPassed;
              if (!report.allPassed) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(context.l10n.get('permissionGuideNeedsFix')),
                  ),
                );
              }
              Navigator.pop(dialogContext);
            },
            child: Text(context.l10n.get('confirm')),
          ),
        ],
      );
    },
  );
}

void _openSecurityPage() {
  if (Platform.isMacOS) {
    Process.run(
      'open',
      ['x-apple.systempreferences:com.apple.preference.security'],
    );
  } else if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', 'ms-settings:privacy']);
  } else if (Platform.isLinux) {
    Process.run('xdg-open', ['settings://privacy']);
  }
}
