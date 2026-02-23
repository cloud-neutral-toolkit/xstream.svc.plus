import 'package:flutter/material.dart';
import '../services/session/session_manager.dart';
import '../l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SessionManager _sessionManager = SessionManager.instance;
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

  Future<void> _handleEmailLogin() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<SessionStatus>(
              valueListenable: _sessionManager.status,
              builder: (context, status, _) {
                final isMfaRequired = status == SessionStatus.mfaRequired;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.get('accountLogin'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF222222),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _baseUrlController,
                      decoration: InputDecoration(
                        labelText: context.l10n.get('serverAddress'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      enabled: !isMfaRequired,
                      decoration: InputDecoration(
                        labelText: context.l10n.get('accountOrEmail'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      enabled: !isMfaRequired,
                      decoration: InputDecoration(
                        labelText: context.l10n.get('password'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (isMfaRequired) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _mfaCodeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.get('mfaCode'),
                          helperText: context.l10n.get('mfaRequiredHint'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ValueListenableBuilder<bool>(
                      valueListenable: _sessionManager.loading,
                      builder: (context, loading, _) {
                        return ElevatedButton(
                          onPressed: loading
                              ? null
                              : () async {
                                  if (isMfaRequired) {
                                    final result = await _sessionManager
                                        .verifyMfaCode(_mfaCodeController.text);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(result.message)));
                                      if (result.success) Navigator.pop(context);
                                    }
                                  } else {
                                    await _sessionManager
                                        .setBaseUrl(_baseUrlController.text);
                                    final result = await _sessionManager.login(
                                      identifier: _usernameController.text,
                                      password: _passwordController.text,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(result.message)));
                                      if (result.success && !result.mfaRequired) {
                                        Navigator.pop(context);
                                      }
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF222222),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
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
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSocialBtn(String iconName, String label, Color bgColor,
      Color textColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Placeholder for actual icon assets
            Icon(Icons.login, color: textColor, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SessionStatus>(
      valueListenable: _sessionManager.status,
      builder: (context, status, _) {
        final isLoggedIn = status == SessionStatus.loggedIn;

        if (isLoggedIn) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person, size: 80, color: Color(0xFF4A6572)),
                const SizedBox(height: 24),
                Text(
                  _sessionManager.currentUser.value ?? '',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _sessionManager.baseUrl.value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () async {
                    await _sessionManager.logout();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.get('logoutSuccess'))),
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(context.l10n.get('logout')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Text(
                  'Welcome to',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    color: Color(0xFF666666),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cloud Neutral',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF222222),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                _buildSocialBtn(
                  'email',
                  'Continue with Email',
                  const Color(0xFF222222),
                  Colors.white,
                  _handleEmailLogin,
                ),
                const SizedBox(height: 16),
                _buildSocialBtn(
                  'google',
                  'Continue with Google',
                  Colors.white,
                  const Color(0xFF222222),
                  () {}, // Mock
                ),
                const SizedBox(height: 16),
                _buildSocialBtn(
                  'apple',
                  'Continue with Apple',
                  Colors.black,
                  Colors.white,
                  () {}, // Mock
                ),
                const SizedBox(height: 16),
                _buildSocialBtn(
                  'microsoft',
                  'Continue with Microsoft',
                  Colors.white,
                  const Color(0xFF222222),
                  () {}, // Mock
                ),
                const Spacer(flex: 2),
                const Text(
                  'By continuing, you agree to our Terms of Service and Privacy Policy.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
