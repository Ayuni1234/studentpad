import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../matching/presentation/student_setup_screen.dart';
import '../../listings/presentation/home_shell.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.createAccount = false});
  final bool createAccount;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _creating = widget.createAccount;
  bool _hidePassword = true;
  bool _submitting = false;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_email.text.trim().isEmpty ||
        _password.text.isEmpty ||
        (_creating && _name.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in the required fields.')));
      return;
    }

    if (!isSupabaseConfigured) {
      _showMessage(
          'Add your Supabase URL and publishable key to enable sign-in.');
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_creating) {
        final response = await supabase.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'full_name': _name.text.trim()},
        );

        if (!mounted) return;
        if (response.session == null) {
          _showMessage(
              'Check your email to confirm your account, then sign in.');
          setState(() => _creating = false);
          return;
        }
        _openSignedInApp(const StudentSetupScreen());
      } else {
        final response = await supabase.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        final userId = response.user?.id;
        final account = userId == null
            ? null
            : await supabase
                .from('users')
                .select('university')
                .eq('user_id', userId)
                .maybeSingle();
        final profile = userId == null
            ? null
            : await supabase
                .from('profiles')
                .select('user_id')
                .eq('user_id', userId)
                .maybeSingle();
        final university = account?['university'] as String?;
        final needsSetup =
            profile == null || university == null || university.trim().isEmpty;
        if (!mounted) return;
        _openSignedInApp(
            needsSetup ? const StudentSetupScreen() : const HomeShell());
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage('Could not connect. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openSignedInApp(Widget screen) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetPassword() async {
    if (!isSupabaseConfigured) {
      _showMessage(
          'Add your Supabase URL and publishable key to enable password reset.');
      return;
    }
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email address first.');
      return;
    }
    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (mounted) {
        _showMessage('If an account exists, a reset link is on its way.');
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
                        shrinkWrap: true,
                        children: [
                          if (!isSupabaseConfigured)
                            Container(
                              margin: const EdgeInsets.only(bottom: 18),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4DC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Supabase is not configured yet. Add the project URL and publishable key to enable authentication.',
                              ),
                            ),
                          Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE8F0EC),
                                  borderRadius: BorderRadius.circular(17)),
                              child: const Icon(Icons.home_work_rounded,
                                  color: Color(0xFF134E3F), size: 29)),
                          const SizedBox(height: 22),
                          Text(
                              _creating
                                  ? 'Join your student community'
                                  : 'Welcome back',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 7),
                          Text(
                              _creating
                                  ? 'Create an account to find a place and people that fit.'
                                  : 'Sign in to pick up where you left off.',
                              style: const TextStyle(
                                  color: Colors.black54, height: 1.4)),
                          const SizedBox(height: 24),
                          if (_creating) ...[
                            const Text('Full name',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            TextField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                    hintText: 'Your name',
                                    prefixIcon: Icon(Icons.person_outline))),
                            const SizedBox(height: 16),
                          ],
                          const Text('Email address',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                  hintText: 'you@example.com',
                                  prefixIcon: Icon(Icons.mail_outline))),
                          const SizedBox(height: 16),
                          const Text('Password',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          TextField(
                              controller: _password,
                              obscureText: _hidePassword,
                              decoration: InputDecoration(
                                  hintText: 'At least 8 characters',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                      onPressed: () => setState(
                                          () => _hidePassword = !_hidePassword),
                                      icon: Icon(_hidePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined)))),
                          if (!_creating)
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                    onPressed: _resetPassword,
                                    child: const Text('Forgot password?'))),
                          const SizedBox(height: 14),
                          AppButton(
                              label: _creating ? 'Create account' : 'Sign in',
                              onPressed: _submitting ? null : _continue),
                          const SizedBox(height: 18),
                          Center(
                              child: Wrap(
                                  alignment: WrapAlignment.center,
                                  children: [
                                Text(_creating
                                    ? 'Already have an account? '
                                    : 'New to StudentPad? '),
                                TextButton(
                                    onPressed: () =>
                                        setState(() => _creating = !_creating),
                                    child: Text(_creating
                                        ? 'Sign in'
                                        : 'Create account'))
                              ])),
                          const SizedBox(height: 6),
                          const Center(
                              child: Text(
                                  'By continuing, you agree to our Terms and Privacy Policy.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.black45, fontSize: 12))),
                        ])))),
      );
}
