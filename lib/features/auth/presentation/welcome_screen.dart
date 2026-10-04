import 'package:flutter/material.dart';

import '../../../core/constants/photo_urls.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth > 650;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: wide
                      ? Row(children: [
                          Expanded(child: _illustration()),
                          const SizedBox(width: 50),
                          Expanded(child: _welcomeActions(context))
                        ])
                      : Column(children: [
                          Expanded(child: _illustration()),
                          _welcomeActions(context)
                        ]),
                ),
              ),
            );
          }),
        ),
      );

  Widget _illustration() => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 260),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDDF0E6), Color(0xFFB8D9C6)]),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: Image.network(PhotoUrls.students,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFF567B68), Color(0xFF134E3F)])),
                    child: const Icon(Icons.people_alt_rounded,
                        size: 150, color: Colors.white54))),
          ),
          const Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                Color(0x35134E3F),
                Color(0x00134E3F),
                Color(0xB8134E3F)
              ])))),
          Positioned(
              top: 24,
              left: 24,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .94),
                      borderRadius: BorderRadius.circular(16)),
                  child: const _Brand())),
          Positioned(
              bottom: 28,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(18)),
                child: const Row(children: [
                  Icon(Icons.verified_user_outlined, color: Color(0xFF134E3F)),
                  SizedBox(width: 8),
                  Text('A community built for students',
                      style: TextStyle(fontWeight: FontWeight.w700))
                ]),
              )),
        ]),
      );

  Widget _welcomeActions(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Find your place.\nFind your people.',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800, height: 1.12)),
              const SizedBox(height: 12),
              Text(
                  'Discover off-campus rooms and meet roommates who fit your student life.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.black54, height: 1.45)),
              const SizedBox(height: 26),
              AppButton(
                  label: 'Create an account',
                  icon: Icons.arrow_forward,
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AuthScreen(createAccount: true)))),
              const SizedBox(height: 10),
              SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AuthScreen())),
                      child: const Text('I already have an account'))),
              const SizedBox(height: 14),
              const Text(
                  'By continuing, you agree to our Terms and Privacy Policy.',
                  style: TextStyle(color: Colors.black45, fontSize: 12)),
            ]),
      );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(children: [
        Icon(Icons.home_work_rounded, color: Color(0xFF134E3F)),
        SizedBox(width: 8),
        Text('StudentPad',
            style: TextStyle(
                color: Color(0xFF134E3F),
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ]);
}
