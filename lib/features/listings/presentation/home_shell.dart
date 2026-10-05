import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/services/supabase_service.dart';
import 'premium_explore_screen.dart';
import '../../chat/presentation/chat_screens.dart';
import '../../matching/presentation/matches_screen.dart';
import '../../auth/presentation/profile_screen.dart';
import '../../auth/presentation/welcome_screen.dart';
import '../data/listing_photos.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.isGuest = false});
  final bool isGuest;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selected = 0;
  List<Widget> get _pages => widget.isGuest
      ? [
          PremiumExploreScreen(
            onCreateListing: _openCreateListing,
          ),
        ]
      : [
          PremiumExploreScreen(onCreateListing: _openCreateListing),
          const MatchesScreen(),
          const ChatsScreen(),
          const ProfileScreen(),
        ];

  Future<bool> _openCreateListing() async =>
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const CreateListingScreen()),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF9FBF9),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktopPreview = constraints.maxWidth > 700;
            final frameWidth = isDesktopPreview ? 460.0 : constraints.maxWidth;
            return Center(
              child: SizedBox(
                width: frameWidth,
                height: constraints.maxHeight,
                child: Container(
                  clipBehavior: isDesktopPreview ? Clip.antiAlias : Clip.none,
                  decoration: isDesktopPreview
                      ? BoxDecoration(
                          color: const Color(0xFFF9FBF9),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x180B372C),
                                blurRadius: 38,
                                offset: Offset(0, 16))
                          ],
                        )
                      : const BoxDecoration(color: Color(0xFFF9FBF9)),
                  child: Column(
                    children: [
                      Expanded(
                        child: IndexedStack(index: _selected, children: _pages),
                      ),
                      NavigationBar(
                        selectedIndex: _selected,
                        onDestinationSelected: (index) {
                          if (widget.isGuest) {
                            Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => const WelcomeScreen(),
                                ));
                          } else {
                            setState(() => _selected = index);
                          }
                        },
                        destinations: widget.isGuest
                            ? const [
                                NavigationDestination(
                                    icon: Icon(Icons.search_rounded),
                                    selectedIcon: Icon(Icons.search),
                                    label: 'Explore'),
                                NavigationDestination(
                                    icon: Icon(Icons.login_rounded),
                                    label: 'Sign in'),
                              ]
                            : const [
                                NavigationDestination(
                                    icon: Icon(Icons.search_rounded),
                                    selectedIcon: Icon(Icons.search),
                                    label: 'Explore'),
                                NavigationDestination(
                                    icon: Icon(Icons.favorite_border_rounded),
                                    selectedIcon: Icon(Icons.favorite),
                                    label: 'Matches'),
                                NavigationDestination(
                                    icon:
                                        Icon(Icons.chat_bubble_outline_rounded),
                                    selectedIcon: Icon(Icons.chat_bubble),
                                    label: 'Inbox'),
                                NavigationDestination(
                                    icon: Icon(Icons.person_outline_rounded),
                                    selectedIcon: Icon(Icons.person),
                                    label: 'Profile'),
                              ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  static const _forest = Color(0xFF134E3F);
  static const _sage = Color(0xFFE8F0EC);
  static const _maxImageBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _title = TextEditingController();
  final _rent = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  String _listingType = 'has_space';
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _imageBytes = [];
  bool _isPickingImage = false;
  bool _isSubmitting = false;
  String? _submissionStatus;

  @override
  void dispose() {
    _title.dispose();
    _rent.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isPickingImage || _isSubmitting) return;
    final remaining = maxListingPhotos - _selectedImages.length;
    if (remaining <= 0) {
      _showMessage('You can add up to $maxListingPhotos photos.');
      return;
    }
    setState(() => _isPickingImage = true);
    try {
      final images = await _imagePicker.pickMultiImage(
        imageQuality: 82,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (images.isEmpty) return;
      final accepted = <XFile>[];
      final acceptedBytes = <Uint8List>[];
      for (final image in images.take(remaining)) {
        if (_imageContentType(image.name) == null) {
          _showMessage('Choose JPG, PNG, or WebP images only.');
          continue;
        }
        final bytes = await image.readAsBytes();
        if (bytes.length > _maxImageBytes) {
          _showMessage('Each photo must be smaller than 5 MB.');
          continue;
        }
        accepted.add(image);
        acceptedBytes.add(bytes);
      }
      if (images.length > remaining) {
        _showMessage('You can add up to $maxListingPhotos photos.');
      }
      if (!mounted) return;
      setState(() {
        _selectedImages.addAll(accepted);
        _imageBytes.addAll(acceptedBytes);
      });
    } catch (_) {
      _showMessage('Could not open the photo library. Please try again.');
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _publishListing() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Sign in before publishing a listing.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submissionStatus = 'Publishing your listing…';
    });
    final uploadedPaths = <String>[];
    String? listingId;
    try {
      final rent = double.parse(_rent.text.trim());
      final listing = await supabase
          .from('listings')
          .insert({
            'owner_id': user.id,
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'listing_type': _listingType,
            'location': _location.text.trim(),
            'monthly_rent_ghs': rent,
            'image_path': null,
            'images': <String>[],
          })
          .select('id')
          .single();
      listingId = listing['id'] as String;

      for (var index = 0; index < _selectedImages.length; index++) {
        if (mounted) {
          setState(() => _submissionStatus =
              'Uploading photo ${index + 1} of ${_selectedImages.length}…');
        }
        final image = _selectedImages[index];
        final path =
            '${user.id}/$listingId/${DateTime.now().microsecondsSinceEpoch}_${index + 1}.${_imageExtension(image.name)}';
        await supabase.storage.from(listingPhotoBucket).uploadBinary(
              path,
              _imageBytes[index],
              fileOptions: FileOptions(
                contentType: _imageContentType(image.name)!,
                upsert: false,
              ),
            );
        uploadedPaths.add(path);
      }

      if (uploadedPaths.isNotEmpty) {
        if (mounted) setState(() => _submissionStatus = 'Saving your photos…');
        await supabase
            .from('listings')
            .update({
              'images': uploadedPaths,
              'image_path': uploadedPaths.first,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', listingId)
            .eq('owner_id', user.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your listing has been published.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (uploadedPaths.isNotEmpty) {
        try {
          await supabase.storage.from(listingPhotoBucket).remove(uploadedPaths);
        } catch (_) {
          // Keep the original publish error visible if cleanup also fails.
        }
      }
      if (listingId != null) {
        try {
          await supabase
              .from('listings')
              .delete()
              .eq('id', listingId)
              .eq('owner_id', user.id);
        } catch (_) {
          // Keep the original publish error visible if row cleanup also fails.
        }
      }
      if (mounted) {
        final message = error is PostgrestException
            ? error.message
            : 'Check your connection and student verification, then try again.';
        _showMessage('Could not publish listing. $message');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submissionStatus = null;
        });
      }
    }
  }

  String? _validateTitle(String? value) {
    final title = value?.trim() ?? '';
    if (title.isEmpty) return 'Add a title for your listing.';
    if (title.length < 5) return 'Use at least 5 characters.';
    if (title.length > 160) return 'Keep the title under 160 characters.';
    return null;
  }

  String? _validateLocation(String? value) {
    final location = value?.trim() ?? '';
    if (location.isEmpty) return 'Add a neighbourhood or area.';
    if (location.length > 240) return 'Keep the location under 240 characters.';
    return null;
  }

  String? _validateRent(String? value) {
    final rent = double.tryParse(value?.trim() ?? '');
    if (rent == null || !rent.isFinite) return 'Enter a valid rent amount.';
    if (rent <= 0) return 'Rent must be greater than GHS 0.';
    if (rent > 9999999999.99) return 'Rent is above the supported amount.';
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_isSubmitting,
        child: Scaffold(
          backgroundColor: const Color(0xFFF9FBF9),
          appBar: AppBar(
            title: const Text('Create a listing',
                style: TextStyle(fontWeight: FontWeight.w800)),
            backgroundColor: const Color(0xFFF9FBF9),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text(
                  'Share what you need',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text('Connect with verified students around your campus.',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'has_space',
                      label: Text('I have space'),
                      icon: Icon(Icons.key_outlined),
                    ),
                    ButtonSegment(
                      value: 'needs_space',
                      label: Text('I need space'),
                      icon: Icon(Icons.search_rounded),
                    ),
                  ],
                  selected: {_listingType},
                  onSelectionChanged: _isSubmitting
                      ? null
                      : (values) => setState(() => _listingType = values.first),
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? _forest
                          : null,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected) ? _sage : null,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _fieldLabel('Listing title'),
                const SizedBox(height: 7),
                TextFormField(
                  controller: _title,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 160,
                  validator: _validateTitle,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Bright room in a shared apartment',
                    prefixIcon: Icon(Icons.home_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('Location'),
                const SizedBox(height: 7),
                TextFormField(
                  controller: _location,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 240,
                  validator: _validateLocation,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Legon, Accra',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('Monthly rent'),
                const SizedBox(height: 7),
                TextFormField(
                  controller: _rent,
                  enabled: !_isSubmitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      return RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
                          ? newValue
                          : oldValue;
                    }),
                  ],
                  validator: _validateRent,
                  maxLength: 13,
                  decoration: const InputDecoration(
                    hintText: '1200.00',
                    prefixText: 'GHS  ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('About this listing (optional)'),
                const SizedBox(height: 7),
                TextFormField(
                  controller: _description,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 5000,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText:
                        'Describe the space, household, or what you’re looking for…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                _fieldLabel('Photos (up to 6, optional)'),
                const SizedBox(height: 7),
                _imagePickerCard(),
                const SizedBox(height: 24),
                AppButton(
                  label: _isSubmitting
                      ? (_submissionStatus ?? 'Publishing…')
                      : _listingType == 'has_space'
                          ? 'Publish space'
                          : 'Publish request',
                  icon: Icons.publish_rounded,
                  onPressed: _isSubmitting || _isPickingImage
                      ? null
                      : () => _publishListing(),
                ),
                if (_isSubmitting) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(
                    color: _forest,
                    backgroundColor: _sage,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Listings are visible to verified students only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _imagePickerCard() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _sage,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            onPressed: _isSubmitting ||
                    _isPickingImage ||
                    _selectedImages.length >= maxListingPhotos
                ? null
                : _pickImage,
            icon: Icon(_isPickingImage
                ? Icons.hourglass_top_rounded
                : Icons.add_photo_alternate_outlined),
            label: Text(_isPickingImage
                ? 'Opening photos…'
                : 'Choose photos (${_selectedImages.length}/$maxListingPhotos)'),
          ),
          if (_selectedImages.isNotEmpty) ...[
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedImages.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(_imageBytes[index], fit: BoxFit.cover),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      tooltip: 'Remove photo ${index + 1}',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSubmitting
                          ? null
                          : () => setState(() {
                                _selectedImages.removeAt(index);
                                _imageBytes.removeAt(index);
                              }),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 5),
          const Text('JPG, PNG, or WebP · up to 5 MB each',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
        ]),
      );

  Widget _fieldLabel(String label) => Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
}

String? _imageContentType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}

String _imageExtension(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.webp')) return 'webp';
  return 'jpg';
}
