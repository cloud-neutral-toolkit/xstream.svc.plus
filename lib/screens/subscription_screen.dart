import 'package:flutter/material.dart';
import '../../utils/global_config.dart';
import '../../widgets/log_console.dart';
import '../../utils/app_logger.dart';
import '../../services/vpn_config_service.dart';
import '../l10n/app_localizations.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.initialVlessUri});

  final String? initialVlessUri;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _vlessUriController = TextEditingController();
  final _nodeNameController = TextEditingController();
  final _domainController = TextEditingController();
  final _portController = TextEditingController(text: '443');
  final _uuidController = TextEditingController();
  String _message = '';
  String? _bundleId; // Start with null and load it asynchronously
  bool _autoFlowRunning = false;

  @override
  void initState() {
    super.initState();
    // Directly load bundleId when the state is initialized
    GlobalApplicationConfig.getBundleId().then((bundleId) {
      setState(() {
        _bundleId = bundleId;
      });
    }).catchError((_) {
      setState(() {
        _bundleId = 'com.xstream'; // Fallback value if error occurs
      });
    });

    final initialUri = widget.initialVlessUri?.trim() ?? '';
    if (initialUri.isNotEmpty) {
      _vlessUriController.text = initialUri;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _onParseVlessUri(autoComplete: true);
      });
    }
  }

  @override
  void dispose() {
    _vlessUriController.dispose();
    _nodeNameController.dispose();
    _domainController.dispose();
    _portController.dispose();
    _uuidController.dispose();
    super.dispose();
  }

  Future<void> _onParseVlessUri({bool autoComplete = true}) async {
    final rawUri = _vlessUriController.text.trim();
    if (rawUri.isEmpty) {
      setState(() {
        _message = context.l10n.get('vlessUriEmpty');
      });
      return;
    }

    try {
      final parsed = VpnConfig.parseVlessUri(
        rawUri,
        fallbackNodeName: _nodeNameController.text.trim(),
      );
      setState(() {
        _nodeNameController.text = parsed.name;
        _domainController.text = parsed.domain;
        _portController.text = parsed.port;
        _uuidController.text = parsed.uuid;
        _message =
            '${context.l10n.get('vlessUriParsed')}: ${parsed.protocol}/${parsed.network}/${parsed.security}';
      });
      addAppLog(
        '已解析 VLESS 链接: ${parsed.name}, ${parsed.protocol}/${parsed.network}/${parsed.security}',
      );
      if (autoComplete) {
        await _generateAndSyncFromVless(
          rawUri: rawUri,
          fallbackNodeName: parsed.name,
          autoFlow: true,
        );
      }
    } catch (e) {
      setState(() {
        _message = '${context.l10n.get('vlessUriInvalid')}: $e';
      });
      addAppLog('VLESS 链接解析失败: $e', level: LogLevel.error);
    }
  }

  Future<void> _onCreateConfig() async {
    final rawUri = _vlessUriController.text.trim();

    if (_bundleId == null || _bundleId!.isEmpty) {
      setState(() {
        _message = context.l10n.get('bundleIdMissing');
      });
      addAppLog('缺少 Bundle ID', level: LogLevel.error);
      return;
    }

    if (rawUri.isNotEmpty) {
      await _generateAndSyncFromVless(
        rawUri: rawUri,
        fallbackNodeName: _nodeNameController.text.trim(),
        autoFlow: false,
      );
      return;
    }

    final unlocked = GlobalState.isUnlocked.value;
    final password = GlobalState.sudoPassword.value;
    if (!unlocked) {
      setState(() {
        _message = context.l10n.get('unlockFirst');
      });
      addAppLog('请先解锁后再创建配置', level: LogLevel.warning);
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _message = context.l10n.get('sudoMissing');
      });
      addAppLog('无法获取 sudo 密码', level: LogLevel.error);
      return;
    }

    if (_nodeNameController.text.trim().isEmpty ||
        _domainController.text.trim().isEmpty ||
        _uuidController.text.trim().isEmpty) {
      setState(() {
        _message = context.l10n.get('requiredFieldsMissing');
      });
      addAppLog('缺少必填项', level: LogLevel.error);
      return;
    }

    await VpnConfig.generateContent(
      nodeName: _nodeNameController.text.trim(),
      domain: _domainController.text.trim(),
      port: _portController.text.trim(),
      uuid: _uuidController.text.trim(),
      password: password,
      bundleId: _bundleId!,
      setMessage: (msg) {
        setState(() {
          _message = msg;
        });
      },
      logMessage: (msg) {
        addAppLog(msg);
      },
    );
    await _syncHomeAfterImport(_nodeNameController.text.trim());
  }

  Future<void> _generateAndSyncFromVless({
    required String rawUri,
    required String fallbackNodeName,
    required bool autoFlow,
  }) async {
    if (_autoFlowRunning) return;
    final unlocked = GlobalState.isUnlocked.value;
    final password = GlobalState.sudoPassword.value;
    if (!unlocked) {
      setState(() {
        _message = context.l10n.get('unlockFirst');
      });
      addAppLog('请先解锁后再创建配置', level: LogLevel.warning);
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _message = context.l10n.get('sudoMissing');
      });
      addAppLog('无法获取 sudo 密码', level: LogLevel.error);
      return;
    }

    try {
      _autoFlowRunning = true;
      if (autoFlow) {
        setState(() {
          _message = context.l10n.get('autoImportInProgress');
        });
      }
      final parsed = VpnConfig.parseVlessUri(
        rawUri,
        fallbackNodeName: fallbackNodeName,
      );
      await VpnConfig.generateFromVlessUri(
        vlessUri: rawUri,
        fallbackNodeName: fallbackNodeName,
        password: password,
        bundleId: _bundleId!,
        setMessage: (msg) {
          setState(() {
            _message = msg;
          });
        },
        logMessage: (msg) {
          addAppLog(msg);
        },
      );
      await _syncHomeAfterImport(parsed.name);
    } catch (e) {
      setState(() {
        _message = '${context.l10n.get('vlessUriInvalid')}: $e';
      });
      addAppLog('VLESS 链接创建失败: $e', level: LogLevel.error);
    } finally {
      _autoFlowRunning = false;
    }
  }

  Future<void> _syncHomeAfterImport(String preferredName) async {
    await VpnConfig.load();
    final targetName = preferredName.trim().isNotEmpty
        ? preferredName.trim()
        : (VpnConfig.nodes.isNotEmpty ? VpnConfig.nodes.last.name : '');
    if (targetName.isEmpty) return;
    GlobalState.lastImportedNodeName.value = targetName;
    GlobalState.nodeListRevision.value++;
    GlobalState.activeNodeName.value = '';
    addAppLog('✅ 导入节点已同步到首页: $targetName');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.get('addNodeConfig')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _vlessUriController,
              decoration:
                  InputDecoration(labelText: context.l10n.get('vlessUri')),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _onParseVlessUri(autoComplete: true),
                child: Text(context.l10n.get('parseVlessUri')),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nodeNameController,
              decoration: InputDecoration(
                labelText: context.l10n.get('nodeName'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _domainController,
              decoration: InputDecoration(
                labelText: context.l10n.get('serverDomain'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              decoration: InputDecoration(labelText: context.l10n.get('port')),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _uuidController,
              decoration: InputDecoration(labelText: context.l10n.get('uuid')),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _onCreateConfig,
              child: Text(context.l10n.get('generateSave')),
            ),
            const SizedBox(height: 16),
            Text(_message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
