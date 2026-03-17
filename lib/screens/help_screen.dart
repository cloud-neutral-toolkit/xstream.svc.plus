import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../utils/global_config.dart';
import '../widgets/app_breadcrumb.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, this.breadcrumbItems});

  final List<String>? breadcrumbItems;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  late final Future<_HelpPaths> _pathsFuture = _loadPaths();

  Future<void> _openManual() async {
    const url =
        'https://github.com/svc-design/Xstream/blob/main/docs/user-manual.md';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSupportDocs() async {
    const url =
        'https://github.com/svc-design/Xstream/blob/main/Runbook/Tunnel-Mode-Site-Diff-From-Proxy-Mode.md';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openDirectory(String path) async {
    final uri = Uri.directory(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<_HelpPaths> _loadPaths() async {
    final nodesPath = await GlobalApplicationConfig.getLocalConfigPath();
    final configsPath = await GlobalApplicationConfig.getConfigsPath();
    final logsPath = await GlobalApplicationConfig.getLogsPath();
    return _HelpPaths(
      nodesPath: nodesPath,
      runtimeConfigPath: '$configsPath/node-*-config.json',
      logsPath: '$logsPath/xray-runtime.log',
      configsDir: configsPath,
      logsDir: logsPath,
    );
  }

  Widget _buildBody(BuildContext context) {
    return FutureBuilder<_HelpPaths>(
      future: _pathsFuture,
      builder: (context, snapshot) {
        final paths = snapshot.data;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionCard(
              context,
              title: context.l10n.get('helpQuickStartTitle'),
              children: [
                Text(context.l10n.get('helpQuickStartIntro')),
                const SizedBox(height: 12),
                Text(context.l10n.get('helpQuickStartNote')),
              ],
            ),
            _buildSectionCard(
              context,
              title: context.l10n.get('helpSupportTitle'),
              children: [
                Text(context.l10n.get('helpSupportIntro')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton(
                      onPressed: _openManual,
                      child: Text(context.l10n.get('openManual')),
                    ),
                    OutlinedButton(
                      onPressed: _openSupportDocs,
                      child: Text(context.l10n.get('helpOpenRunbook')),
                    ),
                  ],
                ),
              ],
            ),
            _buildSectionCard(
              context,
              title: context.l10n.get('helpQuickCheckTitle'),
              children: [
                _buildBullet(context.l10n.get('helpQuickCheckItem1')),
                _buildBullet(context.l10n.get('helpQuickCheckItem2')),
                _buildBullet(context.l10n.get('helpQuickCheckItem3')),
                _buildBullet(context.l10n.get('helpQuickCheckItem4')),
              ],
            ),
            _buildSectionCard(
              context,
              title: context.l10n.get('helpModeDiffTitle'),
              children: [
                Text(context.l10n.get('helpModeDiffIntro')),
                const SizedBox(height: 8),
                _buildBullet(context.l10n.get('helpModeDiffItem1')),
                _buildBullet(context.l10n.get('helpModeDiffItem2')),
                _buildBullet(context.l10n.get('helpModeDiffItem3')),
              ],
            ),
            _buildSectionCard(
              context,
              title: context.l10n.get('helpDnsTlsTitle'),
              children: [
                Text(context.l10n.get('helpDnsTlsIntro')),
                const SizedBox(height: 8),
                _buildBullet(context.l10n.get('helpDnsTlsItem1')),
                _buildBullet(context.l10n.get('helpDnsTlsItem2')),
                _buildBullet(context.l10n.get('helpDnsTlsItem3')),
              ],
            ),
            _buildSectionCard(
              context,
              title: context.l10n.get('helpPathsTitle'),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: paths == null
                          ? null
                          : () => _openDirectory(paths.configsDir),
                      child: Text(context.l10n.get('helpOpenConfigDir')),
                    ),
                    OutlinedButton(
                      onPressed: paths == null
                          ? null
                          : () => _openDirectory(paths.logsDir),
                      child: Text(context.l10n.get('helpOpenLogsDir')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPathRow(
                  context,
                  context.l10n.get('helpNodesPathLabel'),
                  paths?.nodesPath ?? context.l10n.get('helpLoading'),
                ),
                const SizedBox(height: 12),
                _buildPathRow(
                  context,
                  context.l10n.get('helpRuntimeConfigLabel'),
                  paths?.runtimeConfigPath ?? context.l10n.get('helpLoading'),
                ),
                const SizedBox(height: 12),
                _buildPathRow(
                  context,
                  context.l10n.get('helpRuntimeLogLabel'),
                  paths?.logsPath ?? context.l10n.get('helpLoading'),
                ),
              ],
            ),
            _buildSectionCard(
              context,
              title: context.l10n.get('helpCommandsTitle'),
              children: [
                Text(context.l10n.get('helpCommandsIntro')),
                const SizedBox(height: 12),
                SelectableText(
                  context.l10n.get('helpCommandsBlock'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // When breadcrumbItems is provided, this screen is pushed standalone
    // and needs its own AppBar.
    // When null, it is embedded in MainPage which already has a top AppBar.
    if (widget.breadcrumbItems != null) {
      return Scaffold(
        appBar: AppBar(
          title: AppBreadcrumb(items: widget.breadcrumbItems!),
        ),
        body: _buildBody(context),
      );
    }
    return _buildBody(context);
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildPathRow(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _HelpPaths {
  final String nodesPath;
  final String runtimeConfigPath;
  final String logsPath;
  final String configsDir;
  final String logsDir;

  const _HelpPaths({
    required this.nodesPath,
    required this.runtimeConfigPath,
    required this.logsPath,
    required this.configsDir,
    required this.logsDir,
  });
}
