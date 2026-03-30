import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/deadline_reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/responsive_layout.dart';
import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  final AppState appState;

  const LoginPage({super.key, required this.appState});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _isAuthenticating = false;
  String? _errorMessage;

  Future<void> _login() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(
        () => _errorMessage = 'Please enter your username and password.',
      );
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final isValid = await widget.appState.validateCredentialsFresh(
      username: _username.text,
      password: _password.text,
    );
    if (!mounted) {
      return;
    }

    if (!isValid) {
      setState(() {
        _isAuthenticating = false;
        _errorMessage = 'Invalid username or password.';
      });
      return;
    }

    setState(() {
      _isAuthenticating = false;
      _errorMessage = null;
    });
    widget.appState.startSession(username: widget.appState.loginUsername);
    DeadlineReminderService.instance.checkNow(force: true);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardPage(appState: widget.appState),
      ),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = ResponsiveLayout.pagePaddingForWidth(
            constraints.maxWidth,
            compactVertical: 24,
            mediumVertical: 32,
            wideVertical: 40,
          );
          final compact = ResponsiveLayout.isCompactWidth(
            constraints.maxWidth,
            breakpoint: 520,
          );

          return SafeArea(
            child: SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - padding.vertical).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 24 : 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BrandMark(
                              size: compact ? 117 : 132,
                              image: const AssetImage('assets/images/logo.png'),
                            ),
                            SizedBox(height: compact ? 18 : 22),
                            const Text(
                              'PMIS-SGOD',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Personnel Management Information System',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            SizedBox(height: compact ? 24 : 32),
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.tint(AppColors.danger, 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.tint(
                                      AppColors.danger,
                                      0.28,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextField(
                              controller: _username,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                hintText: 'e.g. j.smith',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              onSubmitted: (_) => _login(),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _password,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                hintText: 'Enter your password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _login(),
                            ),
                            const SizedBox(height: 28),
                            Tooltip(
                              message: 'Log in',
                              child: SizedBox(
                                height: 46,
                                child: ElevatedButton(
                                  onPressed: _isAuthenticating ? null : _login,
                                  child: Text(
                                    _isAuthenticating
                                        ? 'Logging in...'
                                        : 'Login',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
