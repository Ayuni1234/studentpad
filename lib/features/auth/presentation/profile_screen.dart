import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../listings/presentation/my_listings_screen.dart';
import 'safety_screen.dart';
import 'verification_screen.dart';
import 'welcome_screen.dart';

const _forest = Color(0xFF134E3F);
const _sage = Color(0xFFE8F0EC);
const _canvas = Color(0xFFF9FBF9);
const _profilePhotoBucket = 'profile-photos';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _minimumBudget = TextEditingController();
  final _maximumBudget = TextEditingController();
  final _bio = TextEditingController();
  final _otherUniversity = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _whatsappNumber = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _fullName;
  String? _university;
  String _universityOption = 'Other';
  bool _isVerified = false;
  bool _whatsappUsesPhone = false;
  bool _changingPhoto = false;
  bool _deletingAccount = false;
  String? _avatarPath;
  String? _avatarUrl;
  Uint8List? _avatarPreview;
  double _cleanlinessScore = 3;
  String _sleepSchedule = 'Night owl';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _minimumBudget.dispose();
    _maximumBudget.dispose();
    _bio.dispose();
    _otherUniversity.dispose();
    _phoneNumber.dispose();
    _whatsappNumber.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Sign in to view and edit your profile.';
      });
      return;
    }

    try {
      final account = await supabase
          .from('users')
          .select('full_name, university, is_verified')
          .eq('user_id', user.id)
          .maybeSingle();
      final profile = await supabase
          .from('profiles')
          .select(
              'budget_min_ghs, budget_max_ghs, cleanliness_score, sleep_schedule, bio, avatar_path')
          .eq('user_id', user.id)
          .maybeSingle();
      final avatarPath = profile?['avatar_path'] as String?;
      final avatarUrl = avatarPath == null
          ? null
          : await supabase.storage
              .from(_profilePhotoBucket)
              .createSignedUrl(avatarPath, 60 * 60);
      final contactRows =
          await supabase.rpc('my_contact_details') as List<dynamic>;
      final contact = contactRows.isEmpty
          ? null
          : Map<String, dynamic>.from(contactRows.first as Map);

      if (!mounted) return;
      final university = account?['university'] as String?;
      final knownUniversity = university != null &&
              AppConstants.ghanaianUniversities.contains(university)
          ? university
          : null;
      setState(() {
        _fullName = account?['full_name'] as String? ??
            user.userMetadata?['full_name'] as String?;
        _university = university;
        _universityOption = knownUniversity ?? 'Other';
        _otherUniversity.text = knownUniversity == null ? university ?? '' : '';
        _isVerified = account?['is_verified'] == true;
        _minimumBudget.text = _displayBudget(profile?['budget_min_ghs']);
        _maximumBudget.text = _displayBudget(profile?['budget_max_ghs']);
        _bio.text = profile?['bio'] as String? ?? '';
        _cleanlinessScore =
            (profile?['cleanliness_score'] as num?)?.toDouble() ?? 3;
        final sleep = profile?['sleep_schedule'] as String?;
        _sleepSchedule =
            const ['Early bird', 'Night owl', 'It varies'].contains(sleep)
                ? sleep!
                : 'Night owl';
        _phoneNumber.text = contact?['phone_number'] as String? ?? '';
        _whatsappNumber.text = contact?['whatsapp_number'] as String? ?? '';
        _whatsappUsesPhone = contact?['whatsapp_uses_phone'] == true;
        _avatarPath = avatarPath;
        _avatarUrl = avatarUrl;
        _avatarPreview = null;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendlyError(error);
      });
    }
  }

  Future<void> _changeProfilePhoto() async {
    if (_changingPhoto) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Sign in before changing your profile photo.');
      return;
    }

    final image = await ImagePicker().pickImage(
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
    final contentType = contentTypes[extension];
    if (contentType == null) {
      _showMessage('Choose a JPG, PNG, or WebP profile photo.');
      return;
    }

    setState(() => _changingPhoto = true);
    String? uploadedPath;
    try {
      final bytes = await image.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _showMessage('Choose an image smaller than 5 MB.');
        return;
      }
      setState(() => _avatarPreview = bytes);
      uploadedPath =
          '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await supabase.storage.from(_profilePhotoBucket).uploadBinary(
            uploadedPath,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
      await supabase.from('profiles').upsert(
        {'user_id': user.id, 'avatar_path': uploadedPath},
        onConflict: 'user_id',
      );
      final signedUrl = await supabase.storage
          .from(_profilePhotoBucket)
          .createSignedUrl(uploadedPath, 60 * 60);
      final previousPath = _avatarPath;
      if (!mounted) return;
      setState(() {
        _avatarPath = uploadedPath;
        _avatarUrl = signedUrl;
        _avatarPreview = null;
      });
      if (previousPath != null && previousPath != uploadedPath) {
        try {
          await supabase.storage
              .from(_profilePhotoBucket)
              .remove([previousPath]);
        } catch (_) {
          // Keep the newly saved photo even if removing the old file fails.
        }
      }
      _showMessage('Profile photo updated.');
    } catch (error) {
      if (uploadedPath != null) {
        try {
          await supabase.storage
              .from(_profilePhotoBucket)
              .remove([uploadedPath]);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _avatarPreview = null);
        _showMessage('Could not update your photo. ${_friendlyError(error)}');
      }
    } finally {
      if (mounted) setState(() => _changingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Sign in before saving your preferences.');
      return;
    }
    final university = _universityOption == 'Other'
        ? _otherUniversity.text.trim()
        : _universityOption;
    if (university.isEmpty || university.length > 160) {
      _showMessage(university.isEmpty
          ? 'Add your university to help us find compatible students.'
          : 'Keep the university name under 160 characters.');
      return;
    }

    setState(() => _saving = true);
    try {
      final contactFields = <String, dynamic>{
        'phone_number': _normalizeContactNumber(_phoneNumber.text),
        'whatsapp_number': _whatsappUsesPhone
            ? null
            : _normalizeContactNumber(_whatsappNumber.text),
        'whatsapp_uses_phone': _whatsappUsesPhone,
      };
      // profiles.user_id references public.users, which may not exist for a
      // newly registered Auth user yet.
      final account = await supabase
          .from('users')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (account == null) {
        final metadataName = user.userMetadata?['full_name'] as String?;
        try {
          await supabase.from('users').insert({
            'user_id': user.id,
            'full_name': metadataName,
            'university': university,
            ...contactFields,
          });
        } on PostgrestException catch (error) {
          // If another request created the account row at the same time,
          // continue and save the preferences against that row.
          if (error.code != '23505') rethrow;
          await supabase
              .from('users')
              .update({'university': university, ...contactFields}).eq(
                  'user_id', user.id);
        }
      } else {
        await supabase
            .from('users')
            .update({'university': university, ...contactFields}).eq(
                'user_id', user.id);
      }

      final minValue = _minimumBudget.text.trim().isEmpty
          ? null
          : double.parse(_minimumBudget.text.trim());
      final maxValue = _maximumBudget.text.trim().isEmpty
          ? null
          : double.parse(_maximumBudget.text.trim());

      await supabase.from('profiles').upsert(
        {
          'user_id': user.id,
          'budget_min_ghs': minValue,
          'budget_max_ghs': maxValue,
          'cleanliness_score': _cleanlinessScore.round(),
          'sleep_schedule': _sleepSchedule,
          'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        },
        onConflict: 'user_id',
      );

      if (!mounted) return;
      setState(() {
        _loadError = null;
        _university = university;
        _universityOption =
            AppConstants.ghanaianUniversities.contains(university)
                ? university
                : 'Other';
        _otherUniversity.text = _universityOption == 'Other' ? university : '';
      });
      _showMessage('Your profile and lifestyle preferences are saved.');
    } catch (error) {
      if (mounted) {
        _showMessage('Could not save preferences. ${_friendlyError(error)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateMinimum(String? rawValue) {
    final value = rawValue?.trim() ?? '';
    final maximum = _maximumBudget.text.trim();
    if (value.isEmpty) {
      return maximum.isEmpty ? null : 'Enter a minimum budget.';
    }
    final minimum = double.tryParse(value);
    if (minimum == null || !minimum.isFinite || minimum < 0) {
      return 'Enter a valid amount of GHS 0 or more.';
    }
    final maximumValue = double.tryParse(maximum);
    if (maximum.isNotEmpty && maximumValue != null && minimum > maximumValue) {
      return 'Minimum must be below the maximum.';
    }
    return null;
  }

  String? _validateMaximum(String? rawValue) {
    final value = rawValue?.trim() ?? '';
    final minimum = _minimumBudget.text.trim();
    if (value.isEmpty) {
      return minimum.isEmpty ? null : 'Enter a maximum budget.';
    }
    final maximum = double.tryParse(value);
    if (maximum == null || !maximum.isFinite || maximum < 0) {
      return 'Enter a valid amount of GHS 0 or more.';
    }
    final minimumValue = double.tryParse(minimum);
    if (minimum.isNotEmpty && minimumValue != null && minimumValue > maximum) {
      return 'Maximum must be above the minimum.';
    }
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (_whatsappUsesPhone && (value?.trim().isEmpty ?? true)) {
      return 'Add a phone number to use it for WhatsApp.';
    }
    return _validateContactNumber(value);
  }

  String? _validateContactNumber(String? value) {
    if (value?.trim().isEmpty ?? true) return null;
    return _normalizeContactNumber(value) == null
        ? 'Enter a Ghanaian number or an international number with country code.'
        : null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    final confirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'This permanently removes your profile, listings, chats, and uploaded photos. This cannot be undone.'),
              const SizedBox(height: 14),
              TextField(
                  controller: confirmation,
                  decoration: const InputDecoration(
                      labelText: 'Type DELETE to confirm')),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(
                  dialogContext, confirmation.text.trim() == 'DELETE'),
              child: const Text('Delete account')),
        ],
      ),
    );
    confirmation.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _deletingAccount = true);
    try {
      final result = await supabase.functions.invoke('delete-account');
      if (result.status < 200 ||
          result.status >= 300 ||
          (result.data is Map && result.data['deleted'] != true)) {
        throw StateError('Account deletion was not confirmed.');
      }
      await supabase.auth.signOut(scope: SignOutScope.local);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil<void>(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (_) => false);
    } catch (_) {
      if (mounted) {
        _showMessage('Could not delete your account. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          title: const Text('Your profile',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _canvas,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _forest))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  _profileHeader(),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Lifestyle preferences',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reload profile',
                        onPressed: _saving ? null : () => _loadProfile(),
                        icon: const Icon(Icons.refresh_rounded, color: _forest),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Help us find roommates whose routines and budget fit yours.',
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                  if (_loadError != null) ...[
                    const SizedBox(height: 14),
                    _errorCard(_loadError!),
                  ],
                  const SizedBox(height: 18),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(Icons.school_outlined, 'University'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _universityOption,
                          isExpanded: true,
                          items: [
                            ...AppConstants.ghanaianUniversities.map(
                              (university) => DropdownMenuItem(
                                value: university,
                                child: Text(university,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            const DropdownMenuItem(
                                value: 'Other',
                                child: Text('Other university')),
                          ],
                          onChanged: _loadError != null || _saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => _universityOption = value);
                                  _formKey.currentState?.validate();
                                },
                        ),
                        if (_universityOption == 'Other') ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _otherUniversity,
                            enabled: _loadError == null && !_saving,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 160,
                            validator: (value) {
                              if (_universityOption != 'Other') return null;
                              final name = value?.trim() ?? '';
                              if (name.isEmpty) return 'Enter your university.';
                              if (name.length > 160) {
                                return 'Keep the name under 160 characters.';
                              }
                              return null;
                            },
                            onChanged: (_) => _formKey.currentState?.validate(),
                            decoration: const InputDecoration(
                              labelText: 'University name',
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _sectionTitle(Icons.waving_hand_outlined,
                            'Roommate introduction'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _bio,
                          enabled: _loadError == null && !_saving,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          maxLines: 4,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            hintText:
                                'Share a little about your routines, interests, or what you’re looking for in a roommate.',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _sectionTitle(Icons.contact_phone_outlined,
                            'Contact details for listings'),
                        const SizedBox(height: 4),
                        const Text(
                          'Your contact details are shared only with approved students viewing one of your active listings.',
                          style: TextStyle(
                              color: Colors.black54, height: 1.4, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _phoneNumber,
                          enabled: _loadError == null && !_saving,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          validator: _validatePhoneNumber,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            hintText: '024 000 0000 or +233 24 000 0000',
                            prefixIcon: Icon(Icons.call_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Use this number for WhatsApp'),
                          value: _whatsappUsesPhone,
                          onChanged: _loadError != null || _saving
                              ? null
                              : (value) {
                                  if (value == true &&
                                      _phoneNumber.text.trim().isEmpty) {
                                    _showMessage(
                                        'Add your phone number first.');
                                    return;
                                  }
                                  setState(() =>
                                      _whatsappUsesPhone = value ?? false);
                                },
                        ),
                        if (!_whatsappUsesPhone) ...[
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _whatsappNumber,
                            enabled: _loadError == null && !_saving,
                            keyboardType: TextInputType.phone,
                            validator: _validateContactNumber,
                            decoration: const InputDecoration(
                              labelText: 'WhatsApp number',
                              hintText: '024 000 0000 or +233 24 000 0000',
                              prefixIcon: Icon(Icons.chat_outlined),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const SizedBox(height: 12),
                        _sectionTitle(
                            Icons.payments_outlined, 'Monthly budget (GHS)'),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _minimumBudget,
                                enabled: _loadError == null && !_saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [_budgetInputFormatter()],
                                validator: _validateMinimum,
                                onChanged: (_) =>
                                    _formKey.currentState?.validate(),
                                decoration: const InputDecoration(
                                  labelText: 'Minimum',
                                  prefixText: 'GHS ',
                                  hintText: '800',
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 20),
                              child: Text('to',
                                  style: TextStyle(color: Colors.black54)),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _maximumBudget,
                                enabled: _loadError == null && !_saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [_budgetInputFormatter()],
                                validator: _validateMaximum,
                                onChanged: (_) =>
                                    _formKey.currentState?.validate(),
                                decoration: const InputDecoration(
                                  labelText: 'Maximum',
                                  prefixText: 'GHS ',
                                  hintText: '2500',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Text(
                            'Leave both blank if you do not have a set range.',
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _sectionTitle(Icons.cleaning_services_outlined,
                            'Cleanliness preference'),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
                          decoration: BoxDecoration(
                            color: _sage,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              const Row(
                                children: [
                                  Text('1 · Relaxed',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.black54)),
                                  Spacer(),
                                  Text('5 · Very tidy',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.black54)),
                                ],
                              ),
                              Slider(
                                value: _cleanlinessScore,
                                min: 1,
                                max: 5,
                                divisions: 4,
                                label:
                                    '${_cleanlinessScore.round()} · ${_cleanlinessLabel(_cleanlinessScore.round())}',
                                activeColor: _forest,
                                onChanged: _loadError != null || _saving
                                    ? null
                                    : (value) => setState(
                                        () => _cleanlinessScore = value),
                              ),
                              Text(
                                'Your preference: ${_cleanlinessLabel(_cleanlinessScore.round())}',
                                style: const TextStyle(
                                    color: _forest,
                                    fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _sectionTitle(
                            Icons.nightlight_outlined, 'Sleep schedule'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _sleepSchedule,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.schedule_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'Early bird', child: Text('Early bird')),
                            DropdownMenuItem(
                                value: 'Night owl', child: Text('Night owl')),
                            DropdownMenuItem(
                                value: 'It varies', child: Text('It varies')),
                          ],
                          onChanged: _loadError != null || _saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _sleepSchedule = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 22),
                        AppButton(
                          label:
                              _saving ? 'Saving preferences…' : 'Save changes',
                          icon: Icons.check_rounded,
                          onPressed: _loadError != null || _saving
                              ? null
                              : () => _saveProfile(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('Account',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('Student verification'),
                    subtitle:
                        Text(_isVerified ? 'Verified student' : 'Pending'),
                    trailing: Icon(
                      _isVerified
                          ? Icons.verified_rounded
                          : Icons.chevron_right,
                      color: _isVerified ? _forest : null,
                    ),
                    onTap: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentVerificationScreen(),
                        ),
                      );
                      if (mounted) await _loadProfile();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('Safety & privacy'),
                    subtitle: const Text('Stay safe while finding a room'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SafetyScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home_work_outlined),
                    title: const Text('My listings'),
                    subtitle: const Text('Review, pause, or reactivate posts'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MyListingsScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _signOut,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_forever_outlined,
                        color: Colors.red.shade700),
                    title: Text('Delete account',
                        style: TextStyle(color: Colors.red.shade700)),
                    subtitle:
                        const Text('Permanently remove your account and data'),
                    trailing: _deletingAccount
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _deletingAccount ? null : _deleteAccount,
                  ),
                ],
              ),
      );

  Widget _profileHeader() {
    final displayName = _fullName?.trim().isNotEmpty == true
        ? _fullName!.trim()
        : 'Your StudentPad profile';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _sage,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: Colors.white,
                backgroundImage: _avatarPreview != null
                    ? MemoryImage(_avatarPreview!)
                    : (_avatarUrl == null ? null : NetworkImage(_avatarUrl!)),
                child: _avatarPreview == null && _avatarUrl == null
                    ? Text(
                        _initials(displayName),
                        style: const TextStyle(
                            color: _forest,
                            fontSize: 22,
                            fontWeight: FontWeight.w800),
                      )
                    : null,
              ),
              Material(
                color: _forest,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _changingPhoto ? null : _changeProfilePhoto,
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: _changingPhoto
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.camera_alt_outlined,
                            size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _changingPhoto ? null : _changeProfilePhoto,
            icon: const Icon(Icons.photo_camera_outlined, size: 17),
            label: Text(_changingPhoto ? 'Uploading photo…' : 'Change photo'),
            style: TextButton.styleFrom(foregroundColor: _forest),
          ),
          const SizedBox(height: 2),
          Text(
            displayName,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (_university?.isNotEmpty == true) ...[
            const SizedBox(height: 3),
            Text(_university!, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isVerified
                      ? Icons.verified_rounded
                      : Icons.verified_outlined,
                  color: _forest,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Text(
                  _isVerified ? 'Verified student' : 'Verification pending',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 19, color: _forest),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      );

  Widget _errorCard(String message) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF2E8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF8A4D18)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(onPressed: _loadProfile, child: const Text('Retry')),
          ],
        ),
      );
}

TextInputFormatter _budgetInputFormatter() =>
    TextInputFormatter.withFunction((oldValue, newValue) {
      return RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
          ? newValue
          : oldValue;
    });

String? _normalizeContactNumber(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final cleaned = raw.replaceAll(RegExp(r'[\s().-]'), '');
  if (RegExp(r'^0\d{9}$').hasMatch(cleaned)) {
    return '+233${cleaned.substring(1)}';
  }
  if (RegExp(r'^233\d{9}$').hasMatch(cleaned)) return '+$cleaned';
  if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)) return cleaned;
  return null;
}

String _displayBudget(Object? value) {
  if (value is! num) return '';
  return value.toStringAsFixed(value.toDouble() == value.toInt() ? 0 : 2);
}

String _cleanlinessLabel(int score) => switch (score) {
      1 => 'Relaxed',
      2 => 'Somewhat relaxed',
      3 => 'Balanced',
      4 => 'Tidy',
      _ => 'Very tidy',
    };

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final result = parts.take(2).map((part) => part[0].toUpperCase()).join();
  return result.isEmpty ? 'SP' : result;
}

String _friendlyError(Object error) => error is PostgrestException
    ? error.message
    : 'Check your connection and try again.';
