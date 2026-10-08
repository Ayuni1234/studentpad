import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../data/roommate_repository.dart';
import '../../auth/presentation/verification_screen.dart';

const _roommateForest = Color(0xFF134E3F);
const _roommateCanvas = Color(0xFFF9FBF9);
const _locationChoices = [
  'Legon',
  'Madina',
  'East Legon',
  'Adenta',
  'Achimota',
  'Dansoman',
  'Osu',
  'Cantonments',
  'Tema',
  'Kumasi',
  'Cape Coast',
  'Other',
];

class RoommateProfileScreen extends StatefulWidget {
  const RoommateProfileScreen({super.key});

  @override
  State<RoommateProfileScreen> createState() => _RoommateProfileScreenState();
}

class _RoommateProfileScreenState extends State<RoommateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bio = TextEditingController();
  final _major = TextEditingController();
  final _graduationYear = TextEditingController();
  final _budgetMin = TextEditingController();
  final _budgetMax = TextEditingController();
  final _customLocation = TextEditingController();
  final _picker = ImagePicker();
  final _repository = const RoommateRepository();
  final Set<String> _locations = {};
  bool _loading = true;
  bool _saving = false;
  bool _verified = false;
  bool _pickingAvatar = false;
  String? _loadError;
  String _gender = 'Prefer not to say';
  String _housingType = 'Off-campus';
  String? _avatarPath;
  String? _avatarUrl;
  Uint8List? _avatarPreview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bio.dispose();
    _major.dispose();
    _graduationYear.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    _customLocation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final verified = await _repository.currentStudentIsVerified();
      if (!verified) {
        if (mounted) {
          setState(() {
            _verified = false;
            _loading = false;
            _loadError = null;
          });
        }
        return;
      }
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw const AuthException('Sign in to continue.');
      final row = await supabase
          .from('roommate_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      final avatarPath = row?['avatar_url'] as String?;
      final avatarUrl = avatarPath == null
          ? null
          : await supabase.storage
              .from(roommateProfilePhotoBucket)
              .createSignedUrl(avatarPath, 60 * 60);
      if (!mounted) return;
      setState(() {
        _verified = true;
        _loading = false;
        _loadError = null;
        if (row != null) {
          _bio.text = row['bio'] as String? ?? '';
          _major.text = row['major'] as String? ?? '';
          _graduationYear.text =
              (row['graduation_year'] as num?)?.toInt().toString() ?? '';
          _budgetMin.text =
              (row['budget_min_ghs'] as num?)?.toStringAsFixed(0) ?? '';
          _budgetMax.text =
              (row['budget_max_ghs'] as num?)?.toStringAsFixed(0) ?? '';
          _gender = row['gender'] as String? ?? _gender;
          _housingType =
              row['housing_type_preference'] as String? ?? _housingType;
          final locations = row['preferred_locations'];
          if (locations is List) {
            _locations.addAll(locations.map((item) => item.toString()));
          }
          _avatarPath = avatarPath;
          _avatarUrl = avatarUrl;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Could not load your roommate profile. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _pickAvatar() async {
    if (_pickingAvatar || _saving) return;
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1200,
    );
    if (image == null || !mounted) return;
    final extension = image.name.split('.').last.toLowerCase();
    const contentTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    if (!contentTypes.containsKey(extension)) {
      _showMessage('Choose a JPG, PNG, or WebP profile photo.');
      return;
    }
    setState(() => _pickingAvatar = true);
    try {
      final bytes = await image.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _showMessage('Choose an image smaller than 5 MB.');
        return;
      }
      setState(() => _avatarPreview = bytes);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw const AuthException('Sign in to continue.');
      final path =
          '$userId/roommate-${DateTime.now().microsecondsSinceEpoch}.$extension';
      await supabase.storage.from(roommateProfilePhotoBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentTypes[extension]),
          );
      final signedUrl = await supabase.storage
          .from(roommateProfilePhotoBucket)
          .createSignedUrl(path, 60 * 60);
      if (!mounted) return;
      setState(() {
        _avatarPath = path;
        _avatarUrl = signedUrl;
        _avatarPreview = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _avatarPreview = null);
        _showMessage('Could not upload the photo. $error');
      }
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_locations.isEmpty || _locations.length > 20) {
      _showMessage(
        _locations.isEmpty
            ? 'Choose at least one target location.'
            : 'Choose no more than 20 locations.',
      );
      return;
    }
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showMessage('Sign in before saving your roommate profile.');
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('roommate_profiles').upsert({
        'user_id': userId,
        'bio': _bio.text.trim(),
        'major': _major.text.trim(),
        'graduation_year': int.parse(_graduationYear.text.trim()),
        'gender': _gender,
        'housing_type_preference': _housingType,
        'preferred_locations': _locations.toList()..sort(),
        'budget_min_ghs': double.parse(_budgetMin.text.trim()),
        'budget_max_ghs': double.parse(_budgetMax.text.trim()),
        'avatar_url': _avatarPath,
      }, onConflict: 'user_id');
      if (mounted) {
        _showMessage('Roommate profile saved.');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) _showMessage('Could not save your profile. $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addLocation() {
    final location = _customLocation.text.trim();
    if (location.isEmpty) return;
    if (location.length > 120) {
      _showMessage('Keep each location under 120 characters.');
      return;
    }
    if (_locations.length >= 20 &&
        !_locations
            .any((value) => value.toLowerCase() == location.toLowerCase())) {
      _showMessage('Choose no more than 20 locations.');
      return;
    }
    setState(() {
      if (!_locations
          .any((value) => value.toLowerCase() == location.toLowerCase())) {
        _locations.add(location);
      }
      _customLocation.clear();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _roommateCanvas,
        appBar: AppBar(
          backgroundColor: _roommateCanvas,
          title: const Text(
            'Roommate profile',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _roommateForest))
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined,
                              size: 42, color: _roommateForest),
                          const SizedBox(height: 12),
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : !_verified
                    ? _verificationRequired()
                    : Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          children: [
                            const Text(
                              'Help your next roommate get to know you.',
                              style: TextStyle(
                                  fontSize: 23, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: InkWell(
                                onTap: _pickingAvatar ? null : _pickAvatar,
                                borderRadius: BorderRadius.circular(52),
                                child: CircleAvatar(
                                  radius: 48,
                                  backgroundColor: const Color(0xFFE8F0EC),
                                  backgroundImage: _avatarPreview != null
                                      ? MemoryImage(_avatarPreview!)
                                      : _avatarUrl == null
                                          ? null
                                          : NetworkImage(_avatarUrl!),
                                  child: _avatarUrl == null &&
                                          _avatarPreview == null
                                      ? const Icon(
                                          Icons.add_a_photo_outlined,
                                          size: 28,
                                          color: _roommateForest,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text('Add a profile photo (optional)'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _bio,
                              maxLength: 1200,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'About you',
                                hintText:
                                    'Share what you are like as a roommate',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _major,
                              maxLength: 160,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Major / course of study',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value == null ||
                                      value.trim().isEmpty ||
                                      value.trim().length > 160
                                  ? 'Enter your major (up to 160 characters).'
                                  : null,
                            ),
                            TextFormField(
                              controller: _graduationYear,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Expected graduation year',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final year = int.tryParse(value ?? '');
                                return year == null ||
                                        year < 2000 ||
                                        year > 2200
                                    ? 'Enter a valid graduation year.'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _gender,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                'Woman',
                                'Man',
                                'Non-binary',
                                'Prefer not to say'
                              ]
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _gender = value);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              initialValue: _housingType,
                              decoration: const InputDecoration(
                                labelText: 'Housing preference',
                                border: OutlineInputBorder(),
                              ),
                              items: const ['On-campus', 'Off-campus', 'Either']
                                  .map(
                                    (value) => DropdownMenuItem(
                                        value: value, child: Text(value)),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _housingType = value);
                                }
                              },
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Preferred rental locations',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final location in _locationChoices)
                                  FilterChip(
                                    label: Text(location),
                                    selected: _locations.contains(location),
                                    onSelected: (selected) => setState(() {
                                      if (selected) {
                                        _locations.add(location);
                                      } else {
                                        _locations.remove(location);
                                      }
                                    }),
                                  ),
                                for (final location in _locations
                                    .where((item) =>
                                        !_locationChoices.contains(item))
                                    .toList())
                                  InputChip(
                                    label: Text(location),
                                    onDeleted: () => setState(
                                        () => _locations.remove(location)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _customLocation,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                      labelText: 'Add another area or campus',
                                      border: OutlineInputBorder(),
                                    ),
                                    onSubmitted: (_) => _addLocation(),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Add location',
                                  onPressed: _addLocation,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Monthly budget for your share (GH₵)',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _budgetMin,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: 'Minimum',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: _validateBudget,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _budgetMax,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: 'Maximum',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      final error = _validateBudget(value);
                                      if (error != null) return error;
                                      final minimum = double.tryParse(
                                        _budgetMin.text.trim(),
                                      );
                                      final maximum =
                                          double.tryParse(value!.trim());
                                      return minimum != null &&
                                              maximum != null &&
                                              maximum < minimum
                                          ? 'Must be at least the minimum.'
                                          : null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            AppButton(
                              label:
                                  _saving ? 'Saving profile…' : 'Save profile',
                              icon: Icons.check_rounded,
                              onPressed: _saving ? null : _save,
                            ),
                          ],
                        ),
                      ),
      );

  Widget _verificationRequired() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 44,
                color: _roommateForest,
              ),
              const SizedBox(height: 12),
              const Text(
                'Student verification required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Only approved students can create a roommate profile.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StudentVerificationScreen(),
                  ),
                ).then((_) => _load()),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Verify student status'),
              ),
            ],
          ),
        ),
      );

  String? _validateBudget(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    return amount == null || !amount.isFinite || amount < 0 || amount > 1000000
        ? 'Enter a valid amount.'
        : null;
  }
}
