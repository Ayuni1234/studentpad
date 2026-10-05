import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../data/listing_photos.dart';

const _editForest = Color(0xFF134E3F);
const _editSage = Color(0xFFE8F0EC);
const _editCanvas = Color(0xFFF9FBF9);
const _maxListingPhotoBytes = 5 * 1024 * 1024;

class EditListingScreen extends StatefulWidget {
  const EditListingScreen({super.key, required this.listing});

  final Map<String, dynamic> listing;

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _rent;
  late final TextEditingController _description;
  final _imagePicker = ImagePicker();
  late List<String> _existingImagePaths;
  final Set<String> _removedExistingPaths = {};
  final Map<String, String> _existingImageUrls = {};
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImageBytes = [];
  bool _pickingImage = false;
  late String _listingType;
  String? _saveStatus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final row = widget.listing;
    _title = TextEditingController(text: row['title'] as String? ?? '');
    _location = TextEditingController(text: row['location'] as String? ?? '');
    _rent = TextEditingController(
        text: (row['monthly_rent_ghs'] as num?)?.toString() ?? '');
    _description =
        TextEditingController(text: row['description'] as String? ?? '');
    _listingType = row['listing_type'] as String? ?? 'has_space';
    _existingImagePaths = listingPhotoPaths(row);
    unawaited(_loadExistingImageUrls());
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _rent.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showMessage('Sign in before editing a listing.');
      return;
    }
    setState(() => _saving = true);
    final listingId = widget.listing['id'] as String;
    final pathsToKeep = _existingImagePaths
        .where((path) => !_removedExistingPaths.contains(path))
        .toList(growable: false);
    final pathsToRemove = _removedExistingPaths.toList(growable: false);
    final uploadedPaths = <String>[];
    try {
      if (mounted) setState(() => _saveStatus = 'Saving your changes…');
      final updates = <String, dynamic>{
        'title': _title.text.trim(),
        'listing_type': _listingType,
        'location': _location.text.trim(),
        'monthly_rent_ghs': double.parse(_rent.text.trim()),
        'description': _description.text.trim(),
        'images': pathsToKeep,
        'image_path': pathsToKeep.isEmpty ? null : pathsToKeep.first,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final updatedRow = await supabase
          .from('listings')
          .update(updates)
          .eq('id', listingId)
          .eq('owner_id', userId)
          .select('id')
          .maybeSingle();
      if (updatedRow == null) {
        throw StateError('This listing could not be found or updated.');
      }
      _existingImagePaths = pathsToKeep;
      if (pathsToRemove.isNotEmpty) {
        await supabase.storage.from(listingPhotoBucket).remove(pathsToRemove);
        _removedExistingPaths.clear();
        for (final path in pathsToRemove) {
          _existingImageUrls.remove(path);
        }
      }
      for (var index = 0; index < _selectedImages.length; index++) {
        if (mounted) {
          setState(() => _saveStatus =
              'Uploading photo ${index + 1} of ${_selectedImages.length}…');
        }
        final image = _selectedImages[index];
        final path =
            '$userId/$listingId/${DateTime.now().microsecondsSinceEpoch}_${index + 1}.${_imageExtension(image.name)}';
        await supabase.storage.from(listingPhotoBucket).uploadBinary(
              path,
              _selectedImageBytes[index],
              fileOptions: FileOptions(
                contentType: _imageContentType(image.name)!,
                upsert: false,
              ),
            );
        uploadedPaths.add(path);
      }
      if (mounted) setState(() => _saveStatus = 'Saving your photos…');
      final finalPaths = [...pathsToKeep, ...uploadedPaths];
      await supabase
          .from('listings')
          .update({
            'images': finalPaths,
            'image_path': finalPaths.isEmpty ? null : finalPaths.first,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', listingId)
          .eq('owner_id', userId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (uploadedPaths.isNotEmpty) {
        try {
          await supabase.storage.from(listingPhotoBucket).remove(uploadedPaths);
        } catch (_) {
          // Keep the row update error visible.
        }
      }
      if (mounted) _showMessage('Could not save listing. ${error.message}');
    } catch (_) {
      if (uploadedPaths.isNotEmpty) {
        try {
          await supabase.storage.from(listingPhotoBucket).remove(uploadedPaths);
        } catch (_) {
          // Keep the row update error visible.
        }
      }
      if (mounted) {
        _showMessage(
            'Could not save listing. Check your connection and try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveStatus = null;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    if (_saving || _pickingImage) return;
    final retainedCount = _existingImagePaths
        .where((path) => !_removedExistingPaths.contains(path))
        .length;
    final remaining = maxListingPhotos - retainedCount - _selectedImages.length;
    if (remaining <= 0) {
      _showMessage(
          'Remove a photo before adding another. Up to 6 photos are allowed.');
      return;
    }
    setState(() => _pickingImage = true);
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
        if (bytes.length > _maxListingPhotoBytes) {
          _showMessage('Each photo must be smaller than 5 MB.');
          continue;
        }
        accepted.add(image);
        acceptedBytes.add(bytes);
      }
      if (images.length > remaining) {
        _showMessage('You can add up to 6 photos.');
      }
      if (!mounted) return;
      setState(() {
        _selectedImages.addAll(accepted);
        _selectedImageBytes.addAll(acceptedBytes);
      });
    } catch (_) {
      _showMessage('Could not open the photo library. Please try again.');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _loadExistingImageUrls() async {
    for (final path in _existingImagePaths) {
      try {
        final url = await supabase.storage
            .from(listingPhotoBucket)
            .createSignedUrl(path, 60 * 60);
        if (mounted) setState(() => _existingImageUrls[path] = url);
      } catch (_) {
        // Keep an unavailable photo removable from the listing.
      }
    }
  }

  void _removeExistingPhoto(String path) {
    setState(() => _removedExistingPaths.add(path));
  }

  void _removeSelectedPhoto(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _selectedImageBytes.removeAt(index);
    });
  }

  String? _validateTitle(String? value) {
    final title = value?.trim() ?? '';
    if (title.length < 5) return 'Use at least 5 characters.';
    if (title.length > 160) return 'Keep the title under 160 characters.';
    return null;
  }

  String? _validateLocation(String? value) {
    final location = value?.trim() ?? '';
    if (location.isEmpty) return 'Add a neighbourhood or campus area.';
    if (location.length > 240) return 'Keep the location under 240 characters.';
    return null;
  }

  String? _validateRent(String? value) {
    final rent = double.tryParse(value?.trim() ?? '');
    if (rent == null || !rent.isFinite || rent < 0) {
      return 'Enter a valid GHS amount of 0 or more.';
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _editCanvas,
        appBar: AppBar(
          backgroundColor: _editCanvas,
          title: const Text('Edit listing',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const Text(
                'Keep the details current so students know what to expect.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 20),
              const Text('This listing is for',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'has_space',
                    icon: Icon(Icons.key_outlined),
                    label: Text('I have space'),
                  ),
                  ButtonSegment(
                    value: 'needs_space',
                    icon: Icon(Icons.search_rounded),
                    label: Text('I need space'),
                  ),
                ],
                selected: {_listingType},
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(() => _listingType = value.first),
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Colors.white
                        : _editForest,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? _editForest
                        : _editSage,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Title',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              TextFormField(
                controller: _title,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 160,
                validator: _validateTitle,
                decoration: const InputDecoration(
                  hintText: 'Bright room in a shared apartment',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Location',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              TextFormField(
                controller: _location,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                maxLength: 240,
                validator: _validateLocation,
                decoration: const InputDecoration(
                  hintText: 'Legon, Accra',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Monthly rent or budget',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              TextFormField(
                controller: _rent,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  TextInputFormatter.withFunction((oldValue, newValue) =>
                      RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
                          ? newValue
                          : oldValue),
                ],
                validator: _validateRent,
                decoration: const InputDecoration(
                  hintText: '1200.00',
                  prefixText: 'GHS  ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Photos (up to 6)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              _photoEditor(),
              const SizedBox(height: 18),
              const Text('Description (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              TextFormField(
                controller: _description,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 5000,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText:
                      'Describe the room, household, or what you’re looking for.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: _saving
                    ? (_saveStatus ?? 'Saving changes…')
                    : 'Save changes',
                icon: Icons.check_rounded,
                onPressed: _saving ? null : _save,
              ),
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  color: _editForest,
                  backgroundColor: _editSage,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _photoEditor() {
    final retainedPaths = _existingImagePaths
        .where((path) => !_removedExistingPaths.contains(path))
        .toList(growable: false);
    final photoCount = retainedPaths.length + _selectedImages.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _editSage,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('$photoCount of $maxListingPhotos photos selected',
                style: const TextStyle(
                    color: Color(0xFF56645C), fontWeight: FontWeight.w700)),
          ),
          OutlinedButton.icon(
            onPressed:
                _saving || _pickingImage || photoCount >= maxListingPhotos
                    ? null
                    : _pickImage,
            icon: Icon(_pickingImage
                ? Icons.hourglass_top_rounded
                : Icons.add_photo_alternate_outlined),
            label: Text(_pickingImage ? 'Opening…' : 'Add photos'),
          ),
        ]),
        if (photoCount > 0) ...[
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: photoCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final existingCount = retainedPaths.length;
              final isExisting = index < existingCount;
              final image = isExisting
                  ? null
                  : _selectedImageBytes[index - existingCount];
              final existingPath = isExisting ? retainedPaths[index] : null;
              final url = existingPath == null
                  ? null
                  : _existingImageUrls[existingPath];
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  if (image != null)
                    Image.memory(image, fit: BoxFit.cover)
                  else if (url != null)
                    Image.network(url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _photoPlaceholder())
                  else
                    _photoPlaceholder(),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      tooltip: 'Remove photo ${index + 1}',
                      visualDensity: VisualDensity.compact,
                      onPressed: _saving
                          ? null
                          : isExisting
                              ? () => _removeExistingPhoto(existingPath!)
                              : () =>
                                  _removeSelectedPhoto(index - existingCount),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ]),
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        const Text('JPG, PNG, or WebP · up to 5 MB each',
            style: TextStyle(color: Color(0xFF56645C), fontSize: 12)),
      ]),
    );
  }

  Widget _photoPlaceholder() => Container(
        color: const Color(0xFFDCE9E0),
        alignment: Alignment.center,
        child: const Icon(Icons.apartment_rounded, color: Color(0xFF709581)),
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
