import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../data/listing_photos.dart';
import 'edit_listing_screen.dart';

const _myListingsForest = Color(0xFF134E3F);
const _myListingsSage = Color(0xFFE8F0EC);
const _myListingsCanvas = Color(0xFFF9FBF9);

/// Lets a student review, edit, pause, or reactivate listings they own.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  List<Map<String, dynamic>> _listings = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _updating = {};

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign in to view your listings.';
      });
      return;
    }

    try {
      final rows = await supabase
          .from('listings')
          .select(
              'id, title, description, image_path, images, listing_type, location, monthly_rent_ghs, is_active, created_at')
          .eq('owner_id', userId)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _listings = rows.map((row) => Map<String, dynamic>.from(row)).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is PostgrestException
            ? error.message
            : 'Could not load your listings. Check your connection and try again.';
      });
    }
  }

  Future<void> _setActive(Map<String, dynamic> listing, bool active) async {
    final id = listing['id'] as String;
    if (!_updating.add(id)) return;
    setState(() {});
    try {
      await supabase.from('listings').update({
        'is_active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (!mounted) return;
      setState(() => listing['is_active'] = active);
      _showMessage(active ? 'Listing is visible again.' : 'Listing paused.');
    } catch (error) {
      if (!mounted) return;
      final details = error is PostgrestException ? ' ${error.message}' : '';
      _showMessage('Could not update this listing.$details');
    } finally {
      _updating.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editListing(Map<String, dynamic> listing) async {
    if (_updating.contains(listing['id'])) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditListingScreen(listing: listing),
      ),
    );
    if (saved == true && mounted) await _loadListings();
  }

  Future<void> _deleteListing(Map<String, dynamic> listing) async {
    final id = listing['id'] as String;
    if (_updating.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: Text(
          '“${listing['title']}” will be removed from StudentPad permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep listing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _myListingsForest),
            child: const Text('Delete listing'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_updating.add(id)) return;
    setState(() {});

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _updating.remove(id);
      setState(() {});
      _showMessage('Sign in again to delete this listing.');
      return;
    }

    try {
      final deleted = await supabase
          .from('listings')
          .delete()
          .eq('id', id)
          .eq('owner_id', userId)
          .select('id')
          .maybeSingle();
      if (deleted == null) {
        throw StateError('This listing could not be found or deleted.');
      }
      final imagePaths = listingPhotoPaths(listing);
      if (imagePaths.isNotEmpty) {
        try {
          await supabase.storage.from(listingPhotoBucket).remove(imagePaths);
        } catch (_) {
          // The listing is deleted; a cleanup failure leaves only a private orphan.
        }
      }
      if (!mounted) return;
      setState(() => _listings.removeWhere((item) => item['id'] == id));
      _showMessage('Listing deleted.');
    } catch (error) {
      if (!mounted) return;
      final details = error is PostgrestException ? ' ${error.message}' : '';
      _showMessage('Could not delete this listing.$details');
    } finally {
      _updating.remove(id);
      if (mounted) setState(() {});
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _myListingsCanvas,
        appBar: AppBar(
          backgroundColor: _myListingsCanvas,
          title: const Text('My listings',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Refresh listings',
              onPressed: _loading ? null : _loadListings,
              icon: const Icon(Icons.refresh_rounded, color: _myListingsForest),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _myListingsForest))
            : _error != null
                ? _notice(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load listings',
                    message: _error!,
                    action: TextButton(
                        onPressed: _loadListings,
                        child: const Text('Try again')),
                  )
                : _listings.isEmpty
                    ? _notice(
                        icon: Icons.home_work_outlined,
                        title: 'No listings yet',
                        message:
                            'Rooms and roommate requests you publish will appear here. You can pause a listing when it is no longer available.',
                      )
                    : RefreshIndicator(
                        color: _myListingsForest,
                        onRefresh: _loadListings,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                          children: [
                            const Text(
                              'Manage your room offers and roommate requests.',
                              style:
                                  TextStyle(color: Colors.black54, height: 1.4),
                            ),
                            const SizedBox(height: 14),
                            ..._listings.map(_listingCard),
                          ],
                        ),
                      ),
      );

  Widget _listingCard(Map<String, dynamic> listing) {
    final active = listing['is_active'] == true;
    final updating = _updating.contains(listing['id']);
    final kind = listing['listing_type'] == 'needs_space'
        ? 'Looking for a room'
        : 'Room available';
    final rent = (listing['monthly_rent_ghs'] as num).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 12),
      decoration: BoxDecoration(
        color: _myListingsSage,
        borderRadius: BorderRadius.circular(19),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D173D30), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kind,
                  style: const TextStyle(
                      color: _myListingsForest,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(listing['title'] as String,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFD7E9DE) : Colors.white,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(active ? 'Live' : 'Paused',
                style: const TextStyle(
                    color: _myListingsForest,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 9),
        Text(
            '${listing['location']}  ·  GHS ${rent.toStringAsFixed(0)} / month',
            style: const TextStyle(color: Colors.black54)),
        const Divider(height: 22),
        Row(children: [
          Icon(
              active
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
              color: _myListingsForest),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                active ? 'Visible to verified students' : 'Hidden from Explore',
                style: const TextStyle(fontSize: 13)),
          ),
          if (updating)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _myListingsForest),
            )
          else
            Switch.adaptive(
              value: active,
              activeTrackColor: _myListingsForest,
              onChanged: (value) => _setActive(listing, value),
            ),
          PopupMenuButton<String>(
            tooltip: 'Listing actions',
            enabled: !updating,
            onSelected: (action) {
              if (action == 'edit') {
                _editListing(listing);
              } else if (action == 'delete') {
                _deleteListing(listing);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit listing'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete listing'),
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert_rounded, color: _myListingsForest),
          ),
        ]),
      ]),
    );
  }

  Widget _notice({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: const Color(0xFF709581)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 10), action],
          ]),
        ),
      );
}
