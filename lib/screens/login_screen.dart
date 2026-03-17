import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/session/session_manager.dart';
import '../services/sync/desktop_sync_service.dart';
import '../services/sync/sync_state.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SessionManager _sessionManager = SessionManager.instance;
  final DesktopSyncService _syncService = DesktopSyncService.instance;
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mfaCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = _sessionManager.baseUrl.value;
    _usernameController.text = _sessionManager.currentUser.value ?? '';
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final isMfaRequired = _sessionManager.isMfaRequired;
    if (isMfaRequired) {
      final result =
          await _sessionManager.verifyMfaCode(_mfaCodeController.text);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } else {
      await _sessionManager.setBaseUrl(_baseUrlController.text);
      final result = await _sessionManager.login(
        identifier: _usernameController.text,
        password: _passwordController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    }
  }

  Future<void> _handleLogout() async {
    await _sessionManager.logout();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.get('logoutSuccess'))),
      );
    }
  }

  Future<void> _handleSyncNow() async {
    final result = await _syncService.syncNow(manual: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}:${_pad(local.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SessionStatus>(
      valueListenable: _sessionManager.status,
      builder: (context, status, _) {
        final isLoggedIn = status == SessionStatus.loggedIn;
        final isMfaRequired = status == SessionStatus.mfaRequired;

        if (isLoggedIn) {
          return _buildLoggedInView(context);
        }
        return _buildLoginForm(context, isMfaRequired);
      },
    );
  }

  Widget _buildLoggedInView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final xc = context.xColors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.account_circle, size: 80, color: xc.brand),
              const SizedBox(height: 16),
              Text(
                _sessionManager.currentUser.value ?? '',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _sessionManager.baseUrl.value,
                style: TextStyle(fontSize: 13, color: xc.mutedText),
              ),
              const SizedBox(height: 24),

              // Sync status card
              _buildSyncStatusCard(context),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _syncService.syncing,
                    builder: (context, syncing, _) {
                      return ElevatedButton.icon(
                        onPressed: syncing ? null : _handleSyncNow,
                        icon: syncing
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: Text(syncing
                            ? context.l10n.get('syncInProgress')
                            : context.l10n.get('syncNow')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: xc.brand,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(Icons.logout),
                    label: Text(context.l10n.get('logout')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final xc = context.xColors;

    return ValueListenableBuilder<SyncSummary>(
      valueListenable: SyncStateStore.instance.summary,
      builder: (context, summary, _) {
        final lastSync = summary.lastSuccessAt != null
            ? _formatDateTime(summary.lastSuccessAt!)
            : context.l10n.get('never');
        final metadata = summary.subscriptionMetadata;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: xc.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: xc.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync, size: 18, color: xc.brand),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.get('desktopSync'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _infoRow(context, context.l10n.get('lastSyncTime'), lastSync),
              const SizedBox(height: 4),
              _infoRow(context, context.l10n.get('configVersion'),
                  '${summary.configVersion}'),
              if (metadata != null && metadata.isNotEmpty) ...[
                const SizedBox(height: 4),
                _infoRow(context,
                    context.l10n.get('subscriptionMetadata'), metadata),
              ],
              if (summary.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  summary.lastError!,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final xc = context.xColors;
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: xc.mutedText),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context, bool isMfaRequired) {
    final cs = Theme.of(context).colorScheme;
    final xc = context.xColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_outlined,
                          size: 64, color: xc.brand),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.get('accountLogin'),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.get('syncNotLoggedIn'),
                        style: TextStyle(
                            fontSize: 14, color: xc.mutedText),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Server address
                      TextField(
                        controller: _baseUrlController,
                        decoration: InputDecoration(
                          labelText: context.l10n.get('serverAddress'),
                          prefixIcon: const Icon(Icons.dns_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) =>
                            _sessionManager.setBaseUrl(_baseUrlController.text),
                      ),
                      const SizedBox(height: 16),

                      // Username / email
                      TextField(
                        controller: _usernameController,
                        enabled: !isMfaRequired,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        decoration: InputDecoration(
                          labelText: context.l10n.get('accountOrEmail'),
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        enabled: !isMfaRequired,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: context.l10n.get('password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => _handleLogin(),
                      ),

                      // MFA code field
                      if (isMfaRequired) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _mfaCodeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: InputDecoration(
                            labelText: context.l10n.get('mfaCode'),
                            helperText: context.l10n.get('mfaRequiredHint'),
                            prefixIcon:
                                const Icon(Icons.verified_user_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onSubmitted: (_) => _handleLogin(),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Login button
                      ValueListenableBuilder<bool>(
                        valueListenable: _sessionManager.loading,
                        builder: (context, loading, _) {
                          return ElevatedButton(
                            onPressed: loading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: xc.brand,
                              foregroundColor: cs.onPrimary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: loading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onPrimary,
                                    ),
                                  )
                                : Text(
                                    context.l10n.get(
                                        isMfaRequired ? 'verifyMfa' : 'login'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          );
                        },
                      ),

                      // Error message
                      ValueListenableBuilder<String?>(
                        valueListenable: _sessionManager.lastError,
                        builder: (context, error, _) {
                          if (error == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error,
                              style: TextStyle(
                                color: cs.error,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
