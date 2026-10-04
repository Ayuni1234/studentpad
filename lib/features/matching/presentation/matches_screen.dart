import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../auth/presentation/verification_screen.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/chat_screens.dart';
import '../data/compatibility_repository.dart';

const _forest = Color(0xFF134E3F);
const _sage = Color(0xFFE8F0EC);
const _canvas = Color(0xFFF9FBF9);

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final _repository = const CompatibilityRepository();
  List<CompatibilityScore> _matches = const [];
  final Set<String> _hiddenIds = {};
  bool _loading = true;
  bool _viewerVerified = false;
  String? _error;

  List<CompatibilityScore> get _visibleMatches => _matches
      .where((match) => !_hiddenIds.contains(match.candidateUserId))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _viewerVerified = false;
        _error = 'Sign in to see roommate matches.';
      });
      return;
    }

    try {
      final account = await supabase
          .from('users')
          .select('is_verified')
          .eq('user_id', userId)
          .maybeSingle();
      final verified = account?['is_verified'] == true;
      if (!verified) {
        if (!mounted) return;
        setState(() {
          _matches = const [];
          _viewerVerified = false;
          _loading = false;
          _error = null;
        });
        return;
      }

      final matches = await _repository.fetchForCurrentUser();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _viewerVerified = true;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is PostgrestException
            ? error.message
            : 'Could not load matches. Check your connection and try again.';
      });
    }
  }

  Future<void> _sayHello(CompatibilityScore match) async {
    final name = _displayName(match.fullName);
    try {
      final chatId = await getOrCreateConversation(match.candidateUserId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: chatId,
            name: name,
            initials: _initials(name),
            isVerified: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat. $error')),
      );
    }
  }

  void _hideMatch(CompatibilityScore match) {
    setState(() => _hiddenIds.add(match.candidateUserId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Match hidden for now.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: _canvas,
          title: const Text('Roommate matches',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Refresh matches',
              onPressed: _loading ? null : () => _loadMatches(),
              icon: const Icon(Icons.refresh_rounded, color: _forest),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: _forest,
          onRefresh: _loadMatches,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text('People who could feel like home.',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text(
                  'Verified students ranked by university, GHS budget, and lifestyle fit.',
                  style: TextStyle(color: Colors.black54, height: 1.4)),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 54),
                  child:
                      Center(child: CircularProgressIndicator(color: _forest)),
                )
              else if (_error != null)
                _notice(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load matches',
                  message: _error!,
                  action: TextButton(
                    onPressed: _loadMatches,
                    child: const Text('Try again'),
                  ),
                )
              else if (!_viewerVerified)
                _notice(
                  icon: Icons.lock_outline_rounded,
                  title: 'Verify to see roommate matches',
                  message:
                      'Matches include verified students only. Submit your student ID for review to unlock compatibility results.',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StudentVerificationScreen()),
                    ).then((_) => _loadMatches()),
                    style: FilledButton.styleFrom(backgroundColor: _forest),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Verify student status'),
                  ),
                )
              else if (_matches.isEmpty)
                _notice(
                  icon: Icons.people_outline_rounded,
                  title: 'No matches yet',
                  message:
                      'Complete your university and lifestyle preferences, then check again when more verified students join.',
                )
              else if (_visibleMatches.isEmpty)
                _notice(
                  icon: Icons.visibility_off_outlined,
                  title: 'All shown matches are hidden',
                  message: 'Bring them back if you want to reconsider.',
                  action: TextButton(
                    onPressed: () => setState(_hiddenIds.clear),
                    child: const Text('Show hidden matches'),
                  ),
                )
              else
                ..._visibleMatches.indexed.map((entry) => _MatchCard(
                      match: entry.$2,
                      color: _avatarColors[entry.$1 % _avatarColors.length],
                      onHide: () => _hideMatch(entry.$2),
                      onSayHello: () => _sayHello(entry.$2),
                    )),
            ],
          ),
        ),
      );

  Widget _notice({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) =>
      Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _sage,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, size: 34, color: _forest),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      );
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.color,
    required this.onHide,
    required this.onSayHello,
  });

  final CompatibilityScore match;
  final Color color;
  final VoidCallback onHide;
  final VoidCallback onSayHello;

  @override
  Widget build(BuildContext context) {
    final name = _displayName(match.fullName);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE9ECE9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: color,
                  child: Text(_initials(name),
                      style: const TextStyle(
                          color: _forest, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(
                        match.university?.trim().isNotEmpty == true
                            ? match.university!.trim()
                            : 'University not listed',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                      color: _sage, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${match.compatibilityScore!.round()}% fit',
                    style: const TextStyle(
                        color: _forest,
                        fontWeight: FontWeight.w800,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_rounded, size: 16, color: _forest),
                const SizedBox(width: 5),
                const Text('Verified student',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            if (match.bio?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                match.bio!.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF56645C), height: 1.4, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, size: 17, color: _forest),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _matchSummary(match),
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: onHide, child: const Text('Not now')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Say hello',
                    icon: Icons.chat_bubble_outline,
                    onPressed: onSayHello,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _avatarColors = [
  Color(0xFFF1DECC),
  Color(0xFFDDE9E3),
  Color(0xFFE5E3F2),
];

String _matchSummary(CompatibilityScore match) {
  final reasons = <String>[];
  if (match.universityScore == 100) reasons.add('Same university');
  if ((match.budgetOverlapScore ?? 0) >= 50) {
    reasons.add('Overlapping GHS budgets');
  }
  if ((match.cleanlinessScore ?? 0) >= 75) {
    reasons.add('Similar cleanliness preferences');
  }
  if (match.sleepScheduleScore == 100) reasons.add('Similar sleep schedules');
  if (reasons.isEmpty) return 'Compared by budget and lifestyle preferences.';
  return reasons.take(2).join(' · ');
}

String _displayName(String? value) {
  final name = value?.trim() ?? '';
  return name.isEmpty ? 'Student' : name;
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
  return initials.isEmpty ? 'SP' : initials;
}
