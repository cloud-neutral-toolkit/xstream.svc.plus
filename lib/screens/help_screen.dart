import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _openManual() async {
    const url =
        'https://github.com/svc-design/Xstream/blob/main/docs/user-manual.md';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.get('help')),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _openManual,
          child: Text(context.l10n.get('openManual')),
        ),
      ),
    );
  }
}
