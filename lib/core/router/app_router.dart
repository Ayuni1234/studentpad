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
  Future<Map<String, dynamic>?>? _accountAccessFuture;
  String? _accountAccessUserId;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    if (isSupabaseConfigured) {
      _refreshAccountAccess();
      _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _passwordRecoveryRequired = true);
        } else if (state.event == AuthChangeEvent.signedOut) {
          setState(() {
            _passwordRecoveryRequired = false;
            _accountAccessFuture = null;
            _accountAccessUserId = null;
          });
        } else {
          // Signed-in and refreshed-session events must rebuild the gate,
          // including when an email-confirmation deep link returns in place.
          _refreshAccountAccess();
          setState(() {});
        }
      });
    }
  }

  void _refreshAccountAccess() {
    final userId = supabase.auth.currentUser?.id;
    _accountAccessUserId = userId;
    if (userId == null) {
      _accountAccessFuture = null;
      return;
    }
    _accountAccessFuture = _loadAccountAccess();
  }

  Future<Map<String, dynamic>?> _loadAccountAccess() async {
    final rows = await supabase.rpc('my_account_access_state') as List<dynamic>;
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
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

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const HomeShell(isGuest: true);
    final accessFuture = _accountAccessFuture;
    if (accessFuture == null || _accountAccessUserId != userId) {
      return const _AccountAccessLoading();
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AccountAccessLoading();
        }
        if (snapshot.hasError) {
          return _AccountAccessProblem(
            onRetry: () => setState(_refreshAccountAccess),
          );
        }
        final access = snapshot.data;
        final status = access?['account_status'];
        if (status == 'suspended' || status == 'banned') {
          return _AccountRestrictedScreen(
            status: status as String,
            note: access?['moderation_note'] as String?,
          );
        }
        return const HomeShell();
      },
    );
  }
}

class _AccountAccessLoading extends StatelessWidget {
  const _AccountAccessLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFFF9FBF9),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF134E3F)),
        ),
      );
}

class _AccountAccessProblem extends StatelessWidget {
  const _AccountAccessProblem({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF9FBF9),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.shield_outlined,
                  size: 42, color: Color(0xFF134E3F)),
              const SizedBox(height: 12),
              const Text('We could not confirm account access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF134E3F)),
                child: const Text('Try again'),
              ),
            ]),
          ),
        ),
      );
}

class _AccountRestrictedScreen extends StatelessWidget {
  const _AccountRestrictedScreen({required this.status, this.note});
  final String status;
  final String? note;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF9FBF9),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0EC),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 42, color: Color(0xFF134E3F)),
                const SizedBox(height: 12),
                Text(
                  status == 'banned'
                      ? 'Account access disabled'
                      : 'Account suspended',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  (note?.isNotEmpty == true)
                      ? note!
                      : 'Contact StudentPad support if you believe this is a mistake.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => supabase.auth.signOut(),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ]),
            ),
          ),
        ),
      );
}
