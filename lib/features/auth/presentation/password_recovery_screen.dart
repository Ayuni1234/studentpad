import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_button.dart';

const _recoveryForest = Color(0xFF134E3F);
const _recoverySage = Color(0xFFE8F0EC);
const _recoveryCanvas = Color(0xFFF9FBF9);

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key, required this.onPasswordUpdated});

  final VoidCallback onPasswordUpdated;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been updated.')),
      );
      widget.onPasswordUpdated();
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage(
            'Could not update your password. Request a new reset link and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _recoveryCanvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 36),
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _recoverySage,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.lock_reset_rounded,
                        color: _recoveryForest, size: 30),
                  ),
                  const SizedBox(height: 22),
                  Text('Choose a new password',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  const Text(
                    'Set a new password for your StudentPad account to continue.',
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('New password',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _password,
                          enabled: !_saving,
                          obscureText: _hidePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (value) {
                            if ((value ?? '').length < 8) {
                              return 'Use at least 8 characters.';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'At least 8 characters',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(_hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Confirm new password',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _confirmPassword,
                          enabled: !_saving,
                          obscureText: _hideConfirmation,
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (value) {
                            if (value != _password.text) {
                              return 'The passwords do not match.';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Enter the same password again',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _hideConfirmation
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                  () => _hideConfirmation = !_hideConfirmation),
                              icon: Icon(_hideConfirmation
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        AppButton(
                          label:
                              _saving ? 'Updating password…' : 'Save password',
                          icon: Icons.check_rounded,
                          onPressed: _saving ? null : _savePassword,
                        ),
                        if (_saving) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(
                            color: _recoveryForest,
                            backgroundColor: _recoverySage,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
