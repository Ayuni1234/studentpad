import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/photo_urls.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../auth/presentation/verification_screen.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/chat_screens.dart';

class PremiumExploreScreen extends StatefulWidget {
  const PremiumExploreScreen({super.key, required this.onCreateListing});
  final Future<bool> Function() onCreateListing;

  @override
  State<PremiumExploreScreen> createState() => _PremiumExploreScreenState();
}

class _PremiumExploreScreenState extends State<PremiumExploreScreen> {
  String _filter = 'All';
  final _search = TextEditingController();
  static const _photoBucket = 'listing-photos';
  List<_HomeListing> _homes = const [];
  bool _loading = true;
  bool _viewerVerified = false;
  String? _loadError;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _homes = const [];
        _viewerVerified = false;
        _loading = false;
        _loadError = 'Sign in to explore student listings.';
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
          _homes = const [];
          _viewerVerified = false;
          _loading = false;
          _loadError = null;
        });
        return;
      }

      final rows = await supabase
          .from('listings')
          .select(
              'id, owner_id, title, description, listing_type, location, monthly_rent_ghs, image_path, created_at, owner:users!listings_owner_id_fkey(full_name, is_verified)')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(50);

      final homes = <_HomeListing>[];
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final owner = row['owner'] is Map
            ? Map<String, dynamic>.from(row['owner'] as Map)
            : <String, dynamic>{};
        final imagePath = row['image_path'] as String?;
        String? imageUrl;
        if (imagePath != null && imagePath.isNotEmpty) {
          try {
            imageUrl = await supabase.storage
                .from(_photoBucket)
                .createSignedUrl(imagePath, 20 * 60);
          } on StorageException {
            // An unavailable photo should not hide an otherwise valid listing.
          }
        }
        homes.add(_HomeListing.fromRows(row, owner, imageUrl, userId));
      }
      if (!mounted) return;
      setState(() {
        _homes = homes;
        _viewerVerified = true;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _homes = const [];
        _loading = false;
        _loadError = error is PostgrestException
            ? error.message
            : 'Check your connection and try again.';
      });
    }
  }

  Future<void> _createListing() async {
    final published = await widget.onCreateListing();
    if (published) await _loadListings();
  }

  Future<void> _startChat(_HomeListing home) async {
    try {
      final chatId = await getOrCreateConversation(home.ownerId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: chatId,
            name: home.name,
            initials: home.initials,
            isVerified: home.isVerified,
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

  List<_HomeListing> get _visibleHomes {
    final search = _search.text.trim().toLowerCase();
    return _homes.where((home) {
      final typeMatches = _filter == 'All' ||
          _filter == 'Legon' ||
          _filter == 'East Legon' ||
          (_filter == 'Has a room' && home.listingType == 'has_space') ||
          (_filter == 'Looking for a room' &&
              home.listingType == 'needs_space');
      final areaMatches = (_filter != 'Legon' && _filter != 'East Legon') ||
          (_filter == 'Legon' && home.area.toLowerCase().startsWith('legon')) ||
          (_filter == 'East Legon' &&
              home.area.toLowerCase().startsWith('east legon'));
      final searchMatches = search.isEmpty ||
          '${home.title} ${home.area} ${home.listingLabel}'
              .toLowerCase()
              .contains(search);
      return typeMatches && areaMatches && searchMatches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 62,
          title: const _Brand(),
          actions: [
            IconButton(
              tooltip: _viewerVerified
                  ? 'Create a listing'
                  : 'Verify student status',
              onPressed: _loading
                  ? null
                  : _viewerVerified
                      ? _createListing
                      : () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const StudentVerificationScreen()),
                          ).then((_) => _loadListings()),
              icon: Icon(_viewerVerified
                  ? Icons.add_box_outlined
                  : Icons.verified_user_outlined),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: RefreshIndicator(
          color: const Color(0xFF134E3F),
          onRefresh: _loadListings,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                children: [
                  _hero(),
                  const SizedBox(height: 23),
                  Text('Find a place that feels like home',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: const Color(0xFF1D2923))),
                  const SizedBox(height: 5),
                  const Text('Rooms and roommates around your campus.',
                      style: TextStyle(color: Color(0xFF718078), fontSize: 13)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search Legon, East Legon…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Filters',
                        onPressed: _showFilters,
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        'All',
                        'Has a room',
                        'Looking for a room',
                        'Legon',
                        'East Legon',
                      ]
                          .map((value) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(value),
                                  selected: _filter == value,
                                  showCheckmark: false,
                                  selectedColor: const Color(0xFFE8F0EC),
                                  backgroundColor: Colors.white,
                                  side: BorderSide(
                                      color: _filter == value
                                          ? const Color(0xFFC7D9CE)
                                          : const Color(0xFFE7ECE8)),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: _filter == value
                                        ? const Color(0xFF134E3F)
                                        : const Color(0xFF58665E),
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _filter = value),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionLabel(
                    'Homes near your campus',
                    action: 'Refresh',
                    onAction: () => _loadListings(),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 38),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF134E3F))),
                    )
                  else if (_loadError != null)
                    _FeedNotice(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load listings',
                      message: _loadError!,
                      action: TextButton(
                          onPressed: _loadListings,
                          child: const Text('Try again')),
                    )
                  else if (!_viewerVerified)
                    _FeedNotice(
                      icon: Icons.lock_outline_rounded,
                      title: 'Verify to explore student listings',
                      message:
                          'Student listings and photos are available to verified students. Submit your ID for review to unlock the feed.',
                      action: FilledButton.icon(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const StudentVerificationScreen()),
                        ).then((_) => _loadListings()),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF134E3F)),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Verify student status'),
                      ),
                    )
                  else if (_visibleHomes.isEmpty)
                    _EmptySearch(noListings: _homes.isEmpty)
                  else
                    ..._visibleHomes.map((home) {
                      return _HomeCard(
                        home: home,
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => _HomeDetailScreen(
                              home: home,
                              onMessage: () => _startChat(home),
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: _viewerVerified ? _createListing : null,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Share a room or find roommates'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _hero() => Container(
        height: 206,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: const Color(0xFF134E3F),
            borderRadius: BorderRadius.circular(25)),
        child: Stack(fit: StackFit.expand, children: [
          Image.network(PhotoUrls.students,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                  color: const Color(0xFF547867),
                  child: const Icon(Icons.people_alt_rounded,
                      size: 96, color: Colors.white54))),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xE8134E3F),
                  Color(0xA6134E3F),
                  Color(0x18134E3F)
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('STUDENT LIVING, MADE EASIER',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          letterSpacing: 1.15,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 10),
                const Text('Find your place.\nFind your people.',
                    style: TextStyle(
                        color: Colors.white,
                        height: 1.08,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
                const SizedBox(height: 7),
                const Text('Good homes start with good company.',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ]),
      );

  Future<void> _showFilters() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter listings',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                'All',
                'Has a room',
                'Looking for a room',
                'Legon',
                'East Legon',
              ]
                  .map((value) => ChoiceChip(
                        label: Text(value),
                        selected: _filter == value,
                        onSelected: (_) => Navigator.pop(sheetContext, value),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _filter = selected);
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(children: [
        Icon(Icons.home_work_rounded, color: Color(0xFF134E3F), size: 22),
        SizedBox(width: 8),
        Text('StudentPad',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      ]);
}

class _HomeListing {
  const _HomeListing({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.area,
    required this.monthlyRent,
    required this.listingType,
    required this.name,
    required this.initials,
    required this.isVerified,
    required this.isCurrentUser,
    this.imageUrl,
  });

  final String id,
      ownerId,
      title,
      description,
      area,
      listingType,
      name,
      initials;
  final num monthlyRent;
  final bool isVerified, isCurrentUser;
  final String? imageUrl;

  String get rent => '${_formatGhs(monthlyRent)} / month';
  String get listingLabel =>
      listingType == 'has_space' ? 'Room available' : 'Looking for a room';

  factory _HomeListing.fromRows(Map<String, dynamic> row,
          Map<String, dynamic> owner, String? imageUrl, String viewerId) =>
      _HomeListing(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String,
        title: row['title'] as String,
        description: (row['description'] as String?)?.trim() ?? '',
        area: row['location'] as String,
        monthlyRent: row['monthly_rent_ghs'] as num,
        listingType: row['listing_type'] as String,
        name: (owner['full_name'] as String?)?.trim().isNotEmpty == true
            ? (owner['full_name'] as String).trim()
            : 'Student',
        initials: _initials(owner['full_name'] as String?),
        isVerified: owner['is_verified'] == true,
        isCurrentUser: row['owner_id'] == viewerId,
        imageUrl: imageUrl,
      );
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.home, required this.onTap});
  final _HomeListing home;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFE8F0EC),
        elevation: 2,
        shadowColor: const Color(0x24134E3F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFDCE8E0)),
        ),
        margin: const EdgeInsets.only(bottom: 15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 178,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (home.imageUrl != null)
                  Image.network(home.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          _listingPhotoPlaceholder())
                else
                  _listingPhotoPlaceholder(),
                Positioned(
                    left: 13,
                    top: 13,
                    child: _PhotoTag(
                        icon: home.isCurrentUser
                            ? Icons.person_outline_rounded
                            : Icons.verified_rounded,
                        text: home.isCurrentUser
                            ? 'Your listing'
                            : 'Student verified')),
                Positioned(
                    right: 13,
                    bottom: 13,
                    child: _PhotoTag(
                        icon: Icons.home_work_outlined,
                        text: home.listingLabel)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(home.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.2))),
                      const SizedBox(width: 8),
                      Text(home.rent,
                          style: const TextStyle(
                              color: Color(0xFF134E3F),
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                    ]),
                    const SizedBox(height: 7),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: Color(0xFF728078)),
                      const SizedBox(width: 3),
                      Text(home.area,
                          style: const TextStyle(
                              color: Color(0xFF728078), fontSize: 12)),
                      const Spacer(),
                      Text(home.listingLabel,
                          style: const TextStyle(
                              color: Color(0xFF557361),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFE8F0EC),
                          child: Text(home.initials,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF134E3F),
                                  fontWeight: FontWeight.w800))),
                      const SizedBox(width: 8),
                      Text(home.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      const Spacer(),
                      if (home.isVerified) ...[
                        const Icon(Icons.verified_rounded,
                            color: Color(0xFF39775E), size: 16),
                        const SizedBox(width: 4),
                        const Text('Verified student',
                            style: TextStyle(
                                color: Color(0xFF728078), fontSize: 11)),
                      ],
                    ]),
                  ]),
            ),
          ]),
        ),
      );
}

class _PhotoTag extends StatelessWidget {
  const _PhotoTag({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: const Color(0xFF134E3F), size: 14),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  color: Color(0xFF244C3D),
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}

Widget _listingPhotoPlaceholder() => Container(
      color: const Color(0xFFDCE9E0),
      alignment: Alignment.center,
      child: const Icon(Icons.apartment_rounded,
          size: 58, color: Color(0xFF709581)),
    );

class _FeedNotice extends StatelessWidget {
  const _FeedNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 22),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F0EC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF134E3F), size: 34),
            const SizedBox(height: 9),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF56645C), height: 1.4)),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      );
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.noListings});
  final bool noListings;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Column(children: [
          const Icon(Icons.search_off_rounded,
              size: 42, color: Color(0xFF709581)),
          const SizedBox(height: 10),
          Text(noListings ? 'No listings yet' : 'No homes found',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              noListings
                  ? 'Be the first to share a room or find a roommate.'
                  : 'Try a different neighbourhood or filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF718078))),
        ]),
      );
}

class _HomeDetailScreen extends StatelessWidget {
  const _HomeDetailScreen({required this.home, required this.onMessage});
  final _HomeListing home;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Home details'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: home.imageUrl == null
                        ? SizedBox(
                            height: 250, child: _listingPhotoPlaceholder())
                        : Image.network(home.imageUrl!,
                            height: 250,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => SizedBox(
                                height: 250,
                                child: _listingPhotoPlaceholder())),
                  ),
                  const SizedBox(height: 18),
                  Text(home.title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  Text('${home.area} · ${home.listingLabel}',
                      style: const TextStyle(color: Color(0xFF718078))),
                  const SizedBox(height: 10),
                  Text('${home.rent} / month',
                      style: const TextStyle(
                          color: Color(0xFF134E3F),
                          fontSize: 21,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 20),
                  const SectionLabel('About this listing'),
                  Text(
                      home.description.isEmpty
                          ? 'No additional details provided.'
                          : home.description,
                      style: const TextStyle(
                          height: 1.5, color: Color(0xFF56645C))),
                  const SizedBox(height: 18),
                  const Wrap(spacing: 8, children: [
                    Chip(
                        avatar: Icon(Icons.school_outlined, size: 17),
                        label: Text('Student home')),
                    Chip(
                        avatar:
                            Icon(Icons.cleaning_services_outlined, size: 17),
                        label: Text('Shared spaces')),
                  ]),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE8F0EC),
                        child: Text(home.initials,
                            style: const TextStyle(
                                color: Color(0xFF134E3F),
                                fontWeight: FontWeight.w800))),
                    title: Text(home.name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(home.isCurrentUser
                        ? 'Your listing'
                        : home.isVerified
                            ? 'Verified student'
                            : 'Student'),
                    trailing: home.isVerified
                        ? const Icon(Icons.verified_rounded,
                            color: Color(0xFF39775E))
                        : null,
                  ),
                  if (!home.isCurrentUser && home.isVerified) ...[
                    const SizedBox(height: 8),
                    AppButton(
                        label: 'Message ${home.name.split(' ').first}',
                        icon: Icons.chat_bubble_outline,
                        onPressed: onMessage),
                  ],
                ]),
          ),
        ),
      );
}

String _formatGhs(num amount) {
  final value = amount.toDouble();
  final whole = value.floor().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  final fraction = value - value.floor();
  final decimal = fraction == 0
      ? ''
      : value
          .toStringAsFixed(2)
          .substring(value.toStringAsFixed(2).indexOf('.'));
  return 'GHS $whole$decimal';
}

String _initials(String? fullName) {
  final name = fullName?.trim() ?? '';
  if (name.isEmpty) return 'SP';
  final parts = name.split(RegExp(r'\s+'));
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}
