// lib/widgets/lock_button.dart
import 'package:flutter/material.dart';
import '../utils/global_config.dart';
import '../l10n/app_localizations.dart';

class LockButton extends StatefulWidget {
  final Function(String)? onUnlock;
  final Function()? onLock;

  const LockButton({super.key, this.onUnlock, this.onLock});

  @override
  State<LockButton> createState() => _LockButtonState();
}

class _LockButtonState extends State<LockButton> {
  bool get _isLocked => !GlobalState.isUnlocked.value;

  Future<void> _promptForPassword() async {
    String? password = await showDialog<String>(
      context: context,
      builder: (context) {
        TextEditingController passwordController = TextEditingController();
        return AlertDialog(
          title: Text(context.l10n.get('unlockPrompt')),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.get('password'),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.get('cancel')),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(passwordController.text),
              child: Text(context.l10n.get('confirm')),
            ),
          ],
        );
      },
    );

    if (password != null) {
      _attemptUnlock(password);
    }
  }

  void _attemptUnlock(String password) {
    GlobalState.isUnlocked.value = true;
    GlobalState.sudoPassword.value = password;
    widget.onUnlock?.call(password);
  }

  void _toggleLock() async {
    if (_isLocked) {
      await _promptForPassword();
    } else {
      GlobalState.isUnlocked.value = false;
      GlobalState.sudoPassword.value = '';
      widget.onLock?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.isUnlocked,
      builder: (context, isUnlocked, _) {
        return IconButton(
          icon: Icon(isUnlocked ? Icons.lock_open : Icons.lock),
          onPressed: _toggleLock,
        );
      },
    );
  }
}
