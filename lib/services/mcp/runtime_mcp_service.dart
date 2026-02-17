import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import '../../widgets/log_console.dart' show LogLevel;

class RuntimeMcpService {
  RuntimeMcpService._();

  static final RuntimeMcpService instance = RuntimeMcpService._();

  final ValueNotifier<bool> running = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> available = ValueNotifier<bool>(false);
  final ValueNotifier<String?> launcherPath = ValueNotifier<String?>(null);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  Process? _process;

  Future<void> init() async {
    if (!Platform.isMacOS) {
      available.value = false;
      launcherPath.value = null;
      return;
    }

    final launcher = await _resolveLauncherPath();
    launcherPath.value = launcher;
    available.value = launcher != null;
  }

  Future<bool> start() async {
    if (running.value) return true;
    loading.value = true;
    lastError.value = null;

    try {
      final launcher = launcherPath.value ?? await _resolveLauncherPath();
      launcherPath.value = launcher;
      if (launcher == null) {
        available.value = false;
        lastError.value = 'Runtime MCP launcher not found';
        return false;
      }

      available.value = true;
      final proc = await Process.start(launcher, <String>[]);
      _process = proc;
      running.value = true;
      addAppLog('[runtime mcp] started: $launcher');

      proc.stdout.transform(const SystemEncoding().decoder).listen((line) {
        if (line.trim().isNotEmpty) {
          addAppLog('[runtime mcp] $line');
        }
      });
      proc.stderr.transform(const SystemEncoding().decoder).listen((line) {
        if (line.trim().isNotEmpty) {
          addAppLog('[runtime mcp] $line', level: LogLevel.warning);
        }
      });

      proc.exitCode.then((code) {
        if (_process == proc) {
          _process = null;
          running.value = false;
          if (code != 0) {
            lastError.value = 'Runtime MCP exited with code $code';
            addAppLog('[runtime mcp] exited with code $code',
                level: LogLevel.warning);
          } else {
            addAppLog('[runtime mcp] stopped');
          }
        }
      });

      return true;
    } catch (e) {
      lastError.value = 'Start runtime MCP failed: $e';
      addAppLog('[runtime mcp] start failed: $e', level: LogLevel.error);
      return false;
    } finally {
      loading.value = false;
    }
  }

  Future<bool> stop() async {
    loading.value = true;
    try {
      final proc = _process;
      if (proc == null) {
        running.value = false;
        return true;
      }
      final killed = proc.kill(ProcessSignal.sigterm);
      if (!killed) {
        lastError.value = 'Failed to stop runtime MCP process';
        addAppLog('[runtime mcp] stop failed', level: LogLevel.warning);
        return false;
      }
      _process = null;
      running.value = false;
      addAppLog('[runtime mcp] stop requested');
      return true;
    } catch (e) {
      lastError.value = 'Stop runtime MCP failed: $e';
      addAppLog('[runtime mcp] stop failed: $e', level: LogLevel.error);
      return false;
    } finally {
      loading.value = false;
    }
  }

  Future<String?> _resolveLauncherPath() async {
    if (!Platform.isMacOS) return null;

    final execPath = Platform.resolvedExecutable;
    final currentAppLauncher = _buildLauncherFromExecutable(execPath);
    if (currentAppLauncher != null && await File(currentAppLauncher).exists()) {
      return currentAppLauncher;
    }

    const defaultInstalled =
        '/Applications/xstream.app/Contents/Resources/runtime-tools/xstream-mcp/start-xstream-mcp-server.sh';
    if (await File(defaultInstalled).exists()) {
      return defaultInstalled;
    }

    return null;
  }

  String? _buildLauncherFromExecutable(String executablePath) {
    final macosDir = Directory(executablePath).parent.path;
    final contentsDir = Directory(macosDir).parent.path;
    if (!contentsDir.endsWith('/Contents')) {
      return null;
    }
    return '$contentsDir/Resources/runtime-tools/xstream-mcp/start-xstream-mcp-server.sh';
  }
}
