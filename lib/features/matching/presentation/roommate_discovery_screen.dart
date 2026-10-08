import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../auth/presentation/verification_screen.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/chat_screens.dart';
import '../data/roommate_repository.dart';
import 'roommate_profile_screen.dart';

const _discoveryForest = Color(0xFF134E3F);
const _discoverySage = Color(0xFFE8F0EC);
const _discoveryCanvas = Color(0xFFF9FBF9);

class RoommateDiscoveryScreen extends StatefulWidget {
  const RoommateDiscoveryScreen({super.key});

  @override
  State<RoommateDiscoveryScreen> createState() =>
      _RoommateDiscoveryScreenState();
}

class _RoommateDiscoveryScreenState extends State<RoommateDiscoveryScreen> {
  final _repository = const RoommateRepository();
  final _budgetFilter = TextEditingController();
  List<RoommateProfile> _profiles = const [];
  bool _loading = true;
  bool _verified = false;
  String? _error;
  String _housingFilter = 'Any';
  String? _locationFilter;

  List<RoommateProfile> get _filteredProfiles {
    final budgetText = _budgetFilter.text.trim();
    final budget = double.tryParse(budgetText);
    return _profiles.where((profile) {
      final locationMatches = _locationFilter == null ||
          profile.preferredLocations.any(
            (location) =>
                location.toLowerCase() == _locationFilter!.toLowerCase(),
          );
      final housingMatches = _housingFilter == 'Any' ||
          profile.housingTypePreference == 'Either' ||
          profile.housingTypePreference == _housingFilter;
      final budgetMatches =
          budgetText.isEmpty || (budget != null && profile.budgetMin <= budget);
      return locationMatches && housingMatches && budgetMatches;
    }).toList(growable: false);
  }

  List<String> get _availableLocations =>
      _profiles.expand((profile) => profile.preferredLocations).toSet().toList()
        ..sort();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _budgetFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    if (supabase.auth.currentUser == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _verified = false;
          _error = 'Sign in to find a roommate.';
        });
      }
      return;
    }
    try {
      final verified = await _repository.currentStudentIsVerified();
      if (!verified) {
        if (mounted) {
          setState(() {
            _verified = false;
            _profiles = const [];
            _loading = false;
          });
        }
        return;
      }
      final profiles = await _repository.discover();
      if (!mounted) return;
      setState(() {
        _verified = true;
        _profiles = profiles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is PostgrestException
            ? error.message
            : 'Could not load roommate profiles. Check your connection and try again.';
      });
    }
  }

  Future<void> _editProfile() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RoommateProfileScreen()),
    );
    if (saved == true) await _load();
  }

  Future<void> _connect(RoommateProfile profile) async {
    try {
      final chatId = await getOrCreateConversation(profile.userId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: chatId,
            name: profile.fullName,
            initials: _initials(profile.fullName),
            isVerified: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open chat. $error')));
    }
  }

  void _showProfile(RoommateProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _discoveryCanvas,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: _discoverySage,
                    backgroundImage: profile.avatarUrl == null
                        ? null
                        : NetworkImage(profile.avatarUrl!),
                    child: profile.avatarUrl == null
                        ? Text(
                            _initials(profile.fullName),
                            style: const TextStyle(
                              color: _discoveryForest,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    profile.fullName,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    '${profile.major} · Class of ${profile.graduationYear}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 18),
                _detailRow(
                  Icons.school_outlined,
                  profile.university ?? 'University not listed',
                ),
                _detailRow(
                  Icons.home_work_outlined,
                  '${profile.housingTypePreference} preferred',
                ),
                _detailRow(
                  Icons.payments_outlined,
                  'GH₵${_amount(profile.budgetMin)}–${_amount(profile.budgetMax)} / month',
                ),
                _detailRow(
                  Icons.place_outlined,
                  profile.preferredLocations.join(', '),
                ),
                _detailRow(Icons.person_outline, 'Gender: ${profile.gender}'),
                if (profile.bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'About',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    profile.bio,
                    style: const TextStyle(height: 1.45, color: Colors.black87),
                  ),
                ],
                const SizedBox(height: 18),
                AppButton(
                  label: 'Connect / message',
                  icon: Icons.chat_bubble_outline,
                  onPressed: () {
                    Navigator.pop(context);
                    _connect(profile);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: _discoveryForest),
            const SizedBox(width: 9),
            Expanded(child: Text(text)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _discoveryCanvas,
        appBar: AppBar(
          backgroundColor: _discoveryCanvas,
          title: const Text(
            'Find roommates',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'Edit roommate profile',
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined, color: _discoveryForest),
            ),
            IconButton(
              tooltip: 'Refresh roommate profiles',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, color: _discoveryForest),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: _discoveryForest,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const Text(
                'Find someone to make a place feel like home.',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'Browse verified students looking to team up and share rent.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _editProfile,
                icon: const Icon(Icons.person_outline),
                label: const Text('Create or edit my roommate profile'),
              ),
              if (_verified && !_loading) ...[
                const SizedBox(height: 12),
                _filters(),
              ],
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 54),
                  child: Center(
                    child: CircularProgressIndicator(color: _discoveryForest),
                  ),
                )
              else if (_error != null)
                _notice(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load roommates',
                  message: _error!,
                  action: TextButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                )
              else if (!_verified)
                _notice(
                  icon: Icons.lock_outline_rounded,
                  title: 'Verify to find roommates',
                  message:
                      'Roommate profiles and conversations are available to approved students only.',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StudentVerificationScreen(),
                      ),
                    ).then((_) => _load()),
                    style: FilledButton.styleFrom(
                      backgroundColor: _discoveryForest,
                    ),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Verify student status'),
                  ),
                )
              else if (_profiles.isEmpty)
                _notice(
                  icon: Icons.people_outline_rounded,
                  title: 'No roommate profiles yet',
                  message:
                      'Create your profile to let other verified students find you. Check back as more students join.',
                  action: TextButton.icon(
                    onPressed: _editProfile,
                    icon: const Icon(Icons.add),
                    label: const Text('Set up your profile'),
                  ),
                )
              else if (_filteredProfiles.isEmpty)
                _notice(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No profiles match those filters',
                  message: 'Try a different location, budget, or housing type.',
                  action: TextButton(
                    onPressed: () => setState(() {
                      _locationFilter = null;
                      _housingFilter = 'Any';
                      _budgetFilter.clear();
                    }),
                    child: const Text('Clear filters'),
                  ),
                )
              else
                ..._filteredProfiles.map(
                  (profile) => _RoommateCard(
                    profile: profile,
                    onViewProfile: () => _showProfile(profile),
                    onConnect: () => _connect(profile),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _filters() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _discoverySage,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter roommates',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _locationFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Target location',
                filled: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Any location'),
                ),
                ..._availableLocations.map(
                  (location) => DropdownMenuItem<String?>(
                    value: location,
                    child: Text(location),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _locationFilter = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _housingFilter,
              decoration: const InputDecoration(
                labelText: 'Housing type',
                filled: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const ['Any', 'On-campus', 'Off-campus']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _housingFilter = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _budgetFilter,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Your maximum monthly share (GH₵)',
                filled: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      );

  Widget _notice({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) =>
      Container(
        margin: const EdgeInsets.symmetric(vertical: 18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _discoverySage,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, size: 34, color: _discoveryForest),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      );
}

class _RoommateCard extends StatelessWidget {
  const _RoommateCard({
    required this.profile,
    required this.onViewProfile,
    required this.onConnect,
  });

  final RoommateProfile profile;
  final VoidCallback onViewProfile;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Card(
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
                    radius: 28,
                    backgroundColor: _discoverySage,
                    backgroundImage: profile.avatarUrl == null
                        ? null
                        : NetworkImage(profile.avatarUrl!),
                    child: profile.avatarUrl == null
                        ? Text(
                            _initials(profile.fullName),
                            style: const TextStyle(
                              color: _discoveryForest,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${profile.major} · Class of ${profile.graduationYear}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.verified_rounded,
                    size: 19,
                    color: _discoveryForest,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _badge(profile.housingTypePreference),
                  _badge(
                    'GH₵${_amount(profile.budgetMin)}–${_amount(profile.budgetMax)}',
                  ),
                  for (final location in profile.preferredLocations.take(3))
                    _badge(location, icon: Icons.place_outlined),
                  if (profile.preferredLocations.length > 3)
                    _badge('+${profile.preferredLocations.length - 3} more'),
                ],
              ),
              if (profile.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 11),
                Text(
                  profile.bio.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF56645C),
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onViewProfile,
                      child: const Text('View profile'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: 'Connect',
                      icon: Icons.chat_bubble_outline,
                      onPressed: onConnect,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _badge(String text, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: _discoverySage,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: _discoveryForest),
              const SizedBox(width: 3),
            ],
            Text(
              text,
              style: const TextStyle(
                color: _discoveryForest,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
}

String _amount(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
  return initials.isEmpty ? 'SP' : initials;
}
