import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/password_recovery_screen.dart';
import '../../features/matching/presentation/student_setup_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/listings/presentation/home_shell.dart';
import '../services/supabase_service.dart';

/// Keeps the private app shell behind a live Supabase session check.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _passwordRecoveryRequired = false;
  String? _setupCheckUserId;
  Future<bool>? _studentSetupCheck;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    if (isSupabaseConfigured) {
      _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _passwordRecoveryRequired = true);
        } else if (state.event == AuthChangeEvent.signedOut) {
          setState(() {
            _passwordRecoveryRequired = false;
            _setupCheckUserId = null;
            _studentSetupCheck = null;
          });
        } else {
          // Signed-in and refreshed-session events must rebuild the gate,
          // including when an email-confirmation deep link returns in place.
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    if (isSupabaseConfigured) _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isSupabaseConfigured) return const WelcomeScreen();

    if (supabase.auth.currentSession == null) return const WelcomeScreen();
    if (_passwordRecoveryRequired) {
      return PasswordRecoveryScreen(
        onPasswordUpdated: () {
          if (mounted) setState(() => _passwordRecoveryRequired = false);
        },
      );
    }

    final userId = supabase.auth.currentUser!.id;
    if (_setupCheckUserId != userId) {
      _setupCheckUserId = userId;
      _studentSetupCheck = _accountNeedsSetup(userId);
    }
    return FutureBuilder<bool>(
      future: _studentSetupCheck,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined,
                        size: 42, color: Color(0xFF134E3F)),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not check your student setup.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _setupCheckUserId = null;
                        _studentSetupCheck = null;
                      }),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return snapshot.data == true
            ? const StudentSetupScreen(isRequired: true)
            : const HomeShell();
      },
    );
  }

  Future<bool> _accountNeedsSetup(String userId) async {
    final account = await supabase
        .from('users')
        .select('university')
        .eq('user_id', userId)
        .maybeSingle();
    final profile = await supabase
        .from('profiles')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    final university = account?['university'] as String?;
    return profile == null || university == null || university.trim().isEmpty;
  }
}
