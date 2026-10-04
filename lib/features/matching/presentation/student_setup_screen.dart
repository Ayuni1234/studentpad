import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/presentation/verification_screen.dart';
import '../../listings/presentation/home_shell.dart';

class StudentSetupScreen extends StatefulWidget {
  const StudentSetupScreen({super.key, this.isRequired = false});

  /// True when the auth gate requires setup before allowing the main app.
  final bool isRequired;

  @override
  State<StudentSetupScreen> createState() => _StudentSetupScreenState();
}

class _StudentSetupScreenState extends State<StudentSetupScreen> {
  final _page = PageController();
  final _otherUniversity = TextEditingController();
  int _step = 0;
  bool _saving = false;
  String _university = 'University of Ghana';
  RangeValues _budget = const RangeValues(800, 2500);
  String _cleanliness = 'Balanced';
  String _sleep = 'Night owl';

  @override
  void dispose() {
    _page.dispose();
    _otherUniversity.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_step < 2) {
      setState(() => _step++);
      _page.animateToPage(_step,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      await _saveSetup();
    }
  }

  Future<void> _back() async {
    if (_step > 0) {
      setState(() => _step--);
      _page.animateToPage(_step,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      return;
    }
    if (widget.isRequired) {
      try {
        await supabase.auth.signOut();
      } on AuthException catch (error) {
        _showMessage(error.message);
      }
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _saveSetup() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Sign in again to save your setup.');
      return;
    }
    final university =
        _university == 'Other' ? _otherUniversity.text.trim() : _university;
    if (university.isEmpty || university == 'Other') {
      _showMessage('Enter the name of your university.');
      return;
    }
    if (university.length > 160) {
      _showMessage('Keep the university name under 160 characters.');
      return;
    }

    setState(() => _saving = true);
    try {
      final account = await supabase
          .from('users')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (account == null) {
        try {
          await supabase.from('users').insert({
            'user_id': user.id,
            'full_name': user.userMetadata?['full_name'] as String?,
            'university': university,
          });
        } on PostgrestException catch (error) {
          if (error.code != '23505') rethrow;
          await supabase
              .from('users')
              .update({'university': university}).eq('user_id', user.id);
        }
      } else {
        await supabase
            .from('users')
            .update({'university': university}).eq('user_id', user.id);
      }

      await supabase.from('profiles').upsert({
        'user_id': user.id,
        'budget_min_ghs': _budget.start,
        'budget_max_ghs': _budget.end,
        'cleanliness_score': switch (_cleanliness) {
          'Very tidy' => 5,
          'Relaxed' => 1,
          _ => 3,
        },
        'sleep_schedule': _sleep,
      }, onConflict: 'user_id');

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
    } catch (error) {
      if (mounted) {
        _showMessage('Could not save your setup. ${_errorText(error)}');
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

  void _choice(String key, String value) => setState(() {
        switch (key) {
          case 'university':
            _university = value;
            break;
          case 'cleanliness':
            _cleanliness = value;
            break;
          case 'sleep':
            _sleep = value;
            break;
        }
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: IconButton(
                tooltip:
                    _step == 0 && widget.isRequired ? 'Sign out' : 'Go back',
                icon: Icon(_step == 0 && widget.isRequired
                    ? Icons.logout_rounded
                    : Icons.arrow_back),
                onPressed: _saving ? null : () => _back()),
            title: const Text('Set up your profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Step ${_step + 1} of 3',
                        style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 9),
                    LinearProgressIndicator(
                        value: (_step + 1) / 3,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(8)),
                  ])),
          Expanded(
              child: PageView(
                  controller: _page,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                _universityStep(),
                _lifestyleStep(),
                _verificationStep(),
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: AppButton(
                  label: _saving
                      ? 'Saving setup…'
                      : (_step == 2 ? 'Finish setup' : 'Continue'),
                  icon: Icons.arrow_forward,
                  onPressed: _saving ? null : _next)),
        ])),
      );

  Widget _universityStep() => _stepBody('Tell us where you study',
          'We’ll use your campus to find homes and people nearby.', [
        _label('University'),
        DropdownButtonFormField<String>(
            initialValue: _university,
            isExpanded: true,
            items: [
              ...AppConstants.ghanaianUniversities.map(
                (university) => DropdownMenuItem(
                  value: university,
                  child: Text(university,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
              const DropdownMenuItem(
                  value: 'Other', child: Text('Other university')),
            ],
            onChanged: (value) {
              if (value != null) _choice('university', value);
            }),
        if (_university == 'Other') ...[
          const SizedBox(height: 14),
          TextField(
            controller: _otherUniversity,
            textCapitalization: TextCapitalization.words,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'University name',
              hintText: 'Enter the name used by your university',
            ),
          ),
        ],
        const SizedBox(height: 20),
        _label('Monthly budget for your share'),
        Row(children: [
          const Text('GH₵'),
          Expanded(
              child: RangeSlider(
                  values: _budget,
                  min: 300,
                  max: 5000,
                  divisions: 47,
                  labels: RangeLabels(_budget.start.round().toString(),
                      _budget.end.round().toString()),
                  onChanged: (v) => setState(() => _budget = v)))
        ]),
        Text('GH₵${_budget.start.round()} – GH₵${_budget.end.round()} / month',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);

  Widget _lifestyleStep() => _stepBody('Find a compatible roommate',
          'A few everyday preferences help make a better match.', [
        _label('How tidy do you like your space?'),
        _chips(
            ['Very tidy', 'Balanced', 'Relaxed'], _cleanliness, 'cleanliness'),
        const SizedBox(height: 20),
        _label('When are you usually most active?'),
        _chips(['Early bird', 'Night owl', 'It varies'], _sleep, 'sleep'),
      ]);

  Widget _verificationStep() => _stepBody(
          'Verify your student status',
          'Submit a student ID image for private review by the StudentPad team.',
          [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFE8F0EC),
                  borderRadius: BorderRadius.circular(18)),
              child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: Color(0xFF134E3F)),
                    SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            'Student verification helps keep the housing community focused on students.',
                            style: TextStyle(height: 1.4))),
                  ]),
            ),
            const SizedBox(height: 22),
            _label('Student ID card'),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const StudentVerificationScreen()),
                ),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Open secure ID upload'),
              ),
            ),
            const SizedBox(height: 14),
            Center(
                child: TextButton(
                    onPressed: _next, child: const Text('I’ll do this later'))),
          ]);

  Widget _stepBody(String title, String subtitle, List<Widget> content) =>
      SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text(subtitle,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
            const SizedBox(height: 25),
            ...content,
          ]));
  Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)));
  Widget _chips(List<String> options, String selected, String key) => Wrap(
      spacing: 8,
      runSpacing: 4,
      children: options
          .map((v) => ChoiceChip(
              label: Text(v),
              selected: selected == v,
              onSelected: (_) => _choice(key, v)))
          .toList());
}

String _errorText(Object error) => error is PostgrestException
    ? error.message
    : 'Check your connection and try again.';
