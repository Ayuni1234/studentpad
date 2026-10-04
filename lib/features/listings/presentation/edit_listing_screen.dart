import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';

const _editForest = Color(0xFF134E3F);
const _editSage = Color(0xFFE8F0EC);
const _editCanvas = Color(0xFFF9FBF9);
const _listingPhotoBucket = 'listing-photos';
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
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _removeExistingImage = false;
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
    String? uploadedPath;
    var listingUpdated = false;
    final oldImagePath = widget.listing['image_path'] as String?;
    try {
      final selectedImage = _selectedImage;
      final imageBytes = _selectedImageBytes;
      if (selectedImage != null && imageBytes != null) {
        setState(() => _saveStatus = 'Uploading your new photo…');
        final extension = _imageExtension(selectedImage.name);
        uploadedPath =
            '$userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
        await supabase.storage.from(_listingPhotoBucket).uploadBinary(
              uploadedPath,
              imageBytes,
              fileOptions: FileOptions(
                contentType: _imageContentType(selectedImage.name)!,
                upsert: false,
              ),
            );
      }
      if (mounted) setState(() => _saveStatus = 'Saving your changes…');
      final updates = <String, dynamic>{
        'title': _title.text.trim(),
        'listing_type': _listingType,
        'location': _location.text.trim(),
        'monthly_rent_ghs': double.parse(_rent.text.trim()),
        'description': _description.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (uploadedPath != null) {
        updates['image_path'] = uploadedPath;
      } else if (_removeExistingImage) {
        updates['image_path'] = null;
      }
      final updatedRow = await supabase
          .from('listings')
          .update(updates)
          .eq('id', widget.listing['id'])
          .eq('owner_id', userId)
          .select('id')
          .maybeSingle();
      if (updatedRow == null) {
        throw StateError('This listing could not be found or updated.');
      }
      listingUpdated = true;
      if (oldImagePath != null &&
          (uploadedPath != null || _removeExistingImage)) {
        try {
          await supabase.storage
              .from(_listingPhotoBucket)
              .remove([oldImagePath]);
        } catch (_) {
          // The row now points to the new photo or has no photo.
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (!listingUpdated && uploadedPath != null) {
        try {
          await supabase.storage
              .from(_listingPhotoBucket)
              .remove([uploadedPath]);
        } catch (_) {
          // Keep the row update error visible.
        }
      }
      if (mounted) _showMessage('Could not save listing. ${error.message}');
    } catch (_) {
      if (!listingUpdated && uploadedPath != null) {
        try {
          await supabase.storage
              .from(_listingPhotoBucket)
              .remove([uploadedPath]);
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
    setState(() => _pickingImage = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (image == null) return;
      if (_imageContentType(image.name) == null) {
        _showMessage('Choose a JPG, PNG, or WebP image.');
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.length > _maxListingPhotoBytes) {
        _showMessage('Choose an image smaller than 5 MB.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
        _removeExistingImage = false;
      });
    } catch (_) {
      _showMessage('Could not open the photo library. Please try again.');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _removePhoto() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
      _removeExistingImage = true;
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
              const Text('Listing photo (optional)',
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
    final bytes = _selectedImageBytes;
    final hasCurrentPhoto =
        (widget.listing['image_path'] as String?)?.isNotEmpty == true &&
            !_removeExistingImage;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _editSage,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes,
                height: 190, width: double.infinity, fit: BoxFit.cover),
          )
        else
          Row(children: [
            Icon(
              hasCurrentPhoto
                  ? Icons.image_outlined
                  : Icons.add_photo_alternate_outlined,
              color: _editForest,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                hasCurrentPhoto
                    ? 'A photo is attached. It stays unless you replace or remove it.'
                    : _removeExistingImage
                        ? 'The current photo will be removed when you save.'
                        : 'Choose a JPG, PNG, or WebP photo up to 5 MB.',
                style: const TextStyle(color: Color(0xFF56645C), height: 1.35),
              ),
            ),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _saving || _pickingImage ? null : _pickImage,
            icon: Icon(_pickingImage
                ? Icons.hourglass_top_rounded
                : Icons.photo_library_outlined),
            label: Text(_pickingImage
                ? 'Opening photos…'
                : hasCurrentPhoto || bytes != null
                    ? 'Replace photo'
                    : 'Choose photo'),
          ),
          if (hasCurrentPhoto || bytes != null)
            TextButton.icon(
              onPressed: _saving ? null : _removePhoto,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove'),
            ),
        ]),
      ]),
    );
  }
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
