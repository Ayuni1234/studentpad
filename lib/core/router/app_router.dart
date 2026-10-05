import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/password_recovery_screen.dart';
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

    if (supabase.auth.currentSession == null) {
      return const HomeShell(isGuest: true);
    }
    if (_passwordRecoveryRequired) {
      return PasswordRecoveryScreen(
        onPasswordUpdated: () {
          if (mounted) setState(() => _passwordRecoveryRequired = false);
        },
      );
    }

    return const HomeShell();
  }
}
