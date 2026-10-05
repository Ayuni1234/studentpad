import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/photo_urls.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../auth/presentation/verification_screen.dart';
import '../../auth/presentation/welcome_screen.dart';
import '../../chat/presentation/chat_screens.dart';
import '../data/listing_photos.dart';
import '../data/listing_share.dart';
import 'listing_photo_carousel.dart';

const _forest = Color(0xFF134E3F);

class PremiumExploreScreen extends StatefulWidget {
  const PremiumExploreScreen({super.key, required this.onCreateListing});
  final Future<bool> Function() onCreateListing;

  @override
  State<PremiumExploreScreen> createState() => _PremiumExploreScreenState();
}

class _PremiumExploreScreenState extends State<PremiumExploreScreen> {
  String _filter = 'All';
  final _search = TextEditingController();
  List<_HomeListing> _homes = const [];
  bool _loading = true;
  bool _viewerVerified = false;
  bool _deepLinkHandled = false;
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
    try {
      var verified = false;
      if (supabase.auth.currentUser != null) {
        try {
          final verificationRows = await supabase
              .rpc('my_student_verification_state') as List<dynamic>;
          final verification = verificationRows.isEmpty
              ? null
              : Map<String, dynamic>.from(verificationRows.first as Map);
          verified = verification?['verification_status'] == 'approved';
        } catch (_) {
          // Verification status controls contact actions only. Feed access is
          // public, so a temporary status lookup failure never hides listings.
        }
      }

      final rows = await supabase
          .from('listings')
          .select(
              'id, title, description, listing_type, location, monthly_rent_ghs, image_path, images, created_at')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(50);

      final homes = List<Map<String, dynamic>>.from(rows).map((row) {
        final imagePaths = listingPhotoPaths(row);
        final imageUrl = imagePaths.isEmpty
            ? null
            : supabase.storage
                .from(listingPhotoBucket)
                .getPublicUrl(imagePaths.first);
        return _HomeListing.fromRow(row, imagePaths, imageUrl);
      }).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _homes = homes;
        _viewerVerified = verified;
        _loading = false;
        _loadError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openIncomingListingLink());
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

  void _showHomeDetails(_HomeListing home) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _HomeDetailScreen(
          home: home,
          onMessage: () => _startChat(home),
          ensureApproved: _ensureApprovedForContact,
        ),
      ),
    );
  }

  Future<void> _openIncomingListingLink() async {
    if (_deepLinkHandled) return;
    final segments = Uri.base.pathSegments;
    if (segments.length != 2 || segments.first != 'listing') return;
    _deepLinkHandled = true;
    final listingId = segments[1];
    final existing = _homes.where((home) => home.id == listingId);
    if (existing.isNotEmpty) {
      _showHomeDetails(existing.first);
      return;
    }

    try {
      final row = await supabase
          .from('listings')
          .select(
              'id, title, description, listing_type, location, monthly_rent_ghs, image_path, images, created_at')
          .eq('id', listingId)
          .eq('is_active', true)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This listing is no longer available.')),
        );
        return;
      }
      final imagePaths = listingPhotoPaths(row);
      final home = _HomeListing.fromRow(
        row,
        imagePaths,
        imagePaths.isEmpty
            ? null
            : supabase.storage
                .from(listingPhotoBucket)
                .getPublicUrl(imagePaths.first),
      );
      _showHomeDetails(home);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open this listing. Try again.')),
      );
    }
  }

  Future<void> _startChat(_HomeListing home) async {
    try {
      if (!await _ensureApprovedForContact()) return;
      final chatId = await supabase.rpc('start_listing_chat', params: {
        'p_listing_id': home.id,
      }) as String;
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: chatId,
            name: 'StudentPad student',
            initials: 'S',
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

  Future<bool> _ensureApprovedForContact() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final rows = await supabase.rpc('my_student_verification_state')
            as List<dynamic>;
        final row =
            rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
        if (row?['verification_status'] == 'approved') return true;
      } catch (_) {
        // Fail closed when the current server-side status cannot be checked.
      }
    }
    if (!mounted) return false;
    final signedIn = user != null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined, color: _forest),
        title: Text(
            signedIn ? 'Student verification required' : 'Sign in to contact'),
        content: Text(signedIn
            ? 'Browse listings freely. To message or contact another student, submit your student ID for review.'
            : 'You can browse listings and room details without an account. Sign in and get your student status approved to contact listing owners.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => signedIn
                      ? const StudentVerificationScreen()
                      : const WelcomeScreen(),
                ),
              ).then((_) => _loadListings());
            },
            style: FilledButton.styleFrom(backgroundColor: _forest),
            icon: Icon(
                signedIn ? Icons.upload_file_outlined : Icons.login_rounded),
            label: Text(signedIn ? 'Upload student ID' : 'Sign in'),
          ),
        ],
      ),
    );
    return false;
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
                  : 'Sign in and verify to list a room',
              onPressed: _loading
                  ? null
                  : _viewerVerified
                      ? _createListing
                      : () async {
                          await _ensureApprovedForContact();
                        },
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
                  else if (_visibleHomes.isEmpty)
                    _EmptySearch(noListings: _homes.isEmpty)
                  else
                    ..._visibleHomes.map((home) {
                      return _HomeCard(
                        home: home,
                        onTap: () => _showHomeDetails(home),
                      );
                    }),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: _viewerVerified
                          ? _createListing
                          : () async {
                              await _ensureApprovedForContact();
                            },
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
    required this.title,
    required this.description,
    required this.area,
    required this.monthlyRent,
    required this.listingType,
    required this.imagePaths,
    this.imageUrl,
  });

  final String id, title, description, area, listingType;
  final num monthlyRent;
  final List<String> imagePaths;
  final String? imageUrl;

  String get rent => '${_formatGhs(monthlyRent)} / month';
  String get listingLabel =>
      listingType == 'has_space' ? 'Room available' : 'Looking for a room';

  factory _HomeListing.fromRow(Map<String, dynamic> row,
          List<String> imagePaths, String? imageUrl) =>
      _HomeListing(
        id: row['id'] as String,
        title: row['title'] as String,
        description: (row['description'] as String?)?.trim() ?? '',
        area: row['location'] as String,
        monthlyRent: row['monthly_rent_ghs'] as num,
        listingType: row['listing_type'] as String,
        imagePaths: imagePaths,
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
                        icon: Icons.verified_rounded, text: 'Student listing')),
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
                      const CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(0xFFE8F0EC),
                          child: Icon(Icons.school_outlined,
                              size: 16, color: Color(0xFF134E3F))),
                      const SizedBox(width: 8),
                      const Text('StudentPad student',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      const Spacer(),
                      const Icon(Icons.verified_rounded,
                          color: Color(0xFF39775E), size: 16),
                      const SizedBox(width: 4),
                      const Text('Verified student',
                          style: TextStyle(
                              color: Color(0xFF728078), fontSize: 11)),
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

class _HomeDetailScreen extends StatefulWidget {
  const _HomeDetailScreen({
    required this.home,
    required this.onMessage,
    required this.ensureApproved,
  });
  final _HomeListing home;
  final Future<void> Function() onMessage;
  final Future<bool> Function() ensureApproved;

  @override
  State<_HomeDetailScreen> createState() => _HomeDetailScreenState();
}

class _HomeDetailScreenState extends State<_HomeDetailScreen> {
  late List<String> _photoUrls;

  Uri get _shareUri => listingShareUri(widget.home.id);

  String get _shareText =>
      'Check out this room on StudentPad: ${widget.home.title} - ${_formatGhs(widget.home.monthlyRent)}/month in ${widget.home.area}. ${_shareUri.toString()}';

  @override
  void initState() {
    super.initState();
    _photoUrls = widget.home.imageUrl == null ? [] : [widget.home.imageUrl!];
    unawaited(_loadPhotos());
  }

  Future<void> _loadPhotos() async {
    final urls = widget.home.imagePaths
        .map((path) =>
            supabase.storage.from(listingPhotoBucket).getPublicUrl(path))
        .toList(growable: false);
    if (mounted) setState(() => _photoUrls = urls);
  }

  void _showShareOptions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined, color: _forest),
              title: const Text('Share listing'),
              subtitle: const Text('Choose an app or social platform'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_shareListing());
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: Color(0xFF128C7E)),
              title: const Text('WhatsApp'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_openShareTarget(Uri.https(
                  'wa.me',
                  '/',
                  {'text': _shareText},
                )));
              },
            ),
            ListTile(
              leading: const Icon(Icons.sms_outlined, color: _forest),
              title: const Text('Text message'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_openShareTarget(Uri(
                  scheme: 'sms',
                  queryParameters: {'body': _shareText},
                )));
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded, color: _forest),
              title: const Text('Copy link'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_copyListingLink());
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _shareListing() async {
    try {
      final renderObject = context.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      await SharePlus.instance.share(
        ShareParams(
          title: widget.home.title,
          subject: 'StudentPad listing: ${widget.home.title}',
          text: _shareText,
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      _showMessage(
          'Could not open the share sheet. Copy the listing link instead.');
    }
  }

  Future<void> _openShareTarget(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _showMessage('No app is available for this sharing option.');
      }
    } catch (_) {
      if (mounted) _showMessage('Could not open this sharing option.');
    }
  }

  Future<void> _copyListingLink() async {
    try {
      await Clipboard.setData(ClipboardData(text: _shareUri.toString()));
      if (mounted) _showMessage('Link copied to clipboard!');
    } catch (_) {
      if (mounted) _showMessage('Could not copy the listing link.');
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _showMessage('No app is available to open this contact option.');
      }
    } catch (_) {
      if (mounted) _showMessage('Could not open this contact option.');
    }
  }

  Future<void> _openListingContact({required bool whatsapp}) async {
    if (!await widget.ensureApproved()) return;
    try {
      // Recheck approval, listing activity, and blocks at the moment the
      // student opens the dialer or WhatsApp, not only when the screen loads.
      final rows = await supabase.rpc('listing_owner_contact', params: {
        'p_listing_id': widget.home.id,
      }) as List<dynamic>;
      if (rows.isEmpty) {
        _showMessage('Direct contact is no longer available for this listing.');
        return;
      }
      final owner = Map<String, dynamic>.from(rows.first as Map);
      final uri = whatsapp
          ? _whatsAppUri(owner['whatsapp_number'] as String?, widget.home.title)
          : _phoneUri(owner['phone_number'] as String?);
      if (uri == null) {
        _showMessage(whatsapp
            ? 'The owner has not added a WhatsApp number.'
            : 'The owner has not added a phone number.');
        return;
      }
      await _openExternal(uri);
    } catch (_) {
      _showMessage('Could not confirm secure contact access. Try again.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _contactSection() => Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0EC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contact this student',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text(
            'Only students with approved verification can contact the listing owner.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _openListingContact(whatsapp: false),
                style: FilledButton.styleFrom(backgroundColor: _forest),
                icon: const Icon(Icons.call_rounded),
                label: const Text('Call'),
              ),
              FilledButton.icon(
                onPressed: () => _openListingContact(whatsapp: true),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF128C7E)),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('WhatsApp'),
              ),
            ],
          ),
        ],
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Home details'),
          actions: [
            IconButton(
              tooltip: 'Share listing',
              onPressed: _showShareOptions,
              icon: const Icon(Icons.ios_share_rounded, color: _forest),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: [
                  ListingPhotoCarousel(imageUrls: _photoUrls),
                  const SizedBox(height: 18),
                  Text(widget.home.title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  Text('${widget.home.area} · ${widget.home.listingLabel}',
                      style: const TextStyle(color: Color(0xFF718078))),
                  const SizedBox(height: 10),
                  Text('${widget.home.rent} / month',
                      style: const TextStyle(
                          color: Color(0xFF134E3F),
                          fontSize: 21,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 20),
                  const SectionLabel('About this listing'),
                  Text(
                      widget.home.description.isEmpty
                          ? 'No additional details provided.'
                          : widget.home.description,
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
                    leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8F0EC),
                        child: Icon(Icons.school_outlined,
                            color: Color(0xFF134E3F))),
                    title: const Text('StudentPad student',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Listing owner'),
                  ),
                  _contactSection(),
                  const SizedBox(height: 8),
                  AppButton(
                      label: 'Message listing owner',
                      icon: Icons.chat_bubble_outline,
                      onPressed: () => widget.onMessage()),
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

Uri? _phoneUri(String? phoneNumber) {
  final value = phoneNumber?.trim() ?? '';
  if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)) return null;
  return Uri(scheme: 'tel', path: value);
}

Uri? _whatsAppUri(String? phoneNumber, String listingTitle) {
  final digits = (phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 8 || digits.length > 15) return null;
  final message =
      "Hi, I saw your room listing '$listingTitle' on StudentPad and I'm interested!";
  return Uri.https('wa.me', '/$digits', {'text': message});
}
