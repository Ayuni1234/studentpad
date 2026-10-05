import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_button.dart';
import 'admin_dashboard_screen.dart';

const _forest = Color(0xFF134E3F);
const _sage = Color(0xFFE8F0EC);
const _canvas = Color(0xFFF9FBF9);
const _bucket = 'student-verification';
const _maxStudentIdBytes = 8 * 1024 * 1024;

enum _SubmissionStage { uploading, saving }

class StudentVerificationScreen extends StatefulWidget {
  const StudentVerificationScreen({super.key});

  @override
  State<StudentVerificationScreen> createState() =>
      _StudentVerificationScreenState();
}

class _StudentVerificationScreenState extends State<StudentVerificationScreen> {
  final _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _imageBytes;
  String? _storedImagePath;
  bool _verified = false;
  bool _isAdmin = false;
  String _verificationStatus = 'not_submitted';
  bool _loading = true;
  String? _loadError;
  _SubmissionStage? _submissionStage;

  bool get _busy => _submissionStage != null;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Sign in to submit a student ID for verification.';
      });
      return;
    }

    try {
      final rows =
          await supabase.rpc('my_student_verification_state') as List<dynamic>;
      final row =
          rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
      final isAdmin = await supabase.rpc('is_studentpad_admin') as bool;
      if (!mounted) return;
      setState(() {
        _storedImagePath = row?['student_id_path'] as String?;
        _verified = row?['is_verified'] == true;
        _verificationStatus =
            row?['verification_status'] as String? ?? 'not_submitted';
        _isAdmin = isAdmin;
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

  Future<void> _chooseImage() async {
    if (_busy || _verified) return;
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (image == null) return;

      final contentType = _imageContentType(image.name);
      if (contentType == null) {
        _showMessage('Choose a JPG, PNG, or WebP image.');
        return;
      }

      final bytes = await image.readAsBytes();
      if (bytes.length > _maxStudentIdBytes) {
        _showMessage('Choose an image smaller than 8 MB.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _imageBytes = bytes;
      });
    } catch (_) {
      _showMessage('Could not open the photo library. Please try again.');
    }
  }

  Future<void> _submitForReview() async {
    if (_busy || _verified || _selectedImage == null || _imageBytes == null) {
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Sign in to submit a student ID for verification.');
      return;
    }

    final image = _selectedImage!;
    final extension = _imageExtension(image.name);
    final newPath =
        '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final previousPath = _storedImagePath;
    var uploaded = false;
    setState(() => _submissionStage = _SubmissionStage.uploading);

    try {
      await _ensureUserRow(user);
      await supabase.storage.from(_bucket).uploadBinary(
            newPath,
            _imageBytes!,
            fileOptions: FileOptions(
              contentType: _imageContentType(image.name)!,
              upsert: false,
            ),
          );
      uploaded = true;

      if (mounted) {
        setState(() => _submissionStage = _SubmissionStage.saving);
      }
      await supabase.rpc('submit_student_verification', params: {
        'p_student_id_path': newPath,
      });

      // Deliberately leave is_verified unchanged. Uploading a document submits
      // it for review; only an authorized reviewer may mark it verified.
      if (previousPath != null && previousPath.isNotEmpty) {
        try {
          await supabase.storage.from(_bucket).remove([previousPath]);
        } catch (_) {
          // Keep the successful submission if an old file cannot be removed.
        }
      }

      if (!mounted) return;
      setState(() {
        _storedImagePath = newPath;
        _verificationStatus = 'pending';
        _selectedImage = null;
        _imageBytes = null;
      });
      _showMessage(
          'Student ID submitted. Your verification is pending review.');
    } catch (error) {
      if (uploaded) {
        try {
          await supabase.storage.from(_bucket).remove([newPath]);
        } catch (_) {
          // Preserve the original submission error.
        }
      }
      if (mounted) {
        _showMessage('Could not submit your ID. ${_friendlyError(error)}');
      }
    } finally {
      if (mounted) setState(() => _submissionStage = null);
    }
  }

  Future<void> _ensureUserRow(User user) async {
    final row = await supabase
        .from('users')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row != null) return;

    try {
      await supabase.from('users').insert({
        'user_id': user.id,
        'full_name': user.userMetadata?['full_name'] as String?,
      });
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          title: const Text('Student verification',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _canvas,
          actions: [
            if (_isAdmin)
              IconButton(
                tooltip: 'Admin dashboard',
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminDashboardScreen(),
                          ),
                        );
                        if (mounted) await _loadStatus();
                      },
                icon: const Icon(Icons.fact_check_outlined, color: _forest),
              ),
            IconButton(
              tooltip: 'Refresh verification status',
              onPressed: _loading || _busy ? null : () => _loadStatus(),
              icon: const Icon(Icons.refresh_rounded, color: _forest),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _forest))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: _sage,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline_rounded, color: _forest),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Upload a clear photo of your current student ID. It is kept in private storage for verification review.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_loadError != null) ...[
                    _statusCard(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not load verification status',
                      message: _loadError!,
                      color: const Color(0xFFFFF2E8),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _loadStatus,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ] else if (_verified) ...[
                    _statusCard(
                      icon: Icons.verified_rounded,
                      title: 'You’re verified',
                      message:
                          'Your student status has been reviewed and approved.',
                      color: _sage,
                    ),
                  ] else ...[
                    if (_verificationStatus == 'rejected') ...[
                      _statusCard(
                        icon: Icons.info_outline_rounded,
                        title: 'A clearer ID is needed',
                        message:
                            'Your previous submission was not approved. Upload a clear, current student ID to request another review.',
                        color: const Color(0xFFFFF2E8),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_verificationStatus == 'pending' &&
                        _storedImagePath != null &&
                        _storedImagePath!.isNotEmpty &&
                        _imageBytes == null) ...[
                      _statusCard(
                        icon: Icons.hourglass_top_rounded,
                        title: 'Submitted for review',
                        message:
                            'Your student ID is on file. We’ll update your verification status after review.',
                        color: _sage,
                      ),
                      const SizedBox(height: 18),
                    ],
                    _photoPickerCard(),
                    const SizedBox(height: 16),
                    if (_submissionStage != null) ...[
                      LinearProgressIndicator(
                        color: _forest,
                        backgroundColor: _sage,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        _submissionStage == _SubmissionStage.uploading
                            ? 'Uploading your ID securely…'
                            : 'Saving your submission…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _forest, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                    ],
                    AppButton(
                      label: _busy
                          ? 'Submitting…'
                          : _storedImagePath == null
                              ? 'Submit for review'
                              : 'Replace submitted ID',
                      icon: Icons.upload_rounded,
                      onPressed: _busy || _imageBytes == null
                          ? null
                          : () => _submitForReview(),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Uploading an ID submits it for review; it does not automatically verify your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ],
              ),
      );

  Widget _photoPickerCard() => Material(
        color: _sage,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _busy ? null : _chooseImage,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 200),
            padding: const EdgeInsets.all(12),
            child: _imageBytes == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_outlined,
                          size: 38, color: _forest),
                      const SizedBox(height: 10),
                      const Text('Choose student ID image',
                          style: TextStyle(
                              color: _forest, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('JPG, PNG, or WebP · Up to 8 MB',
                          style:
                              TextStyle(fontSize: 12, color: Colors.black54)),
                      if (_storedImagePath != null && !_verified) ...[
                        const SizedBox(height: 8),
                        const Text(
                            'Choose a new image to replace the one on file.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Image.memory(
                          _imageBytes!,
                          width: double.infinity,
                          height: 280,
                          fit: BoxFit.contain,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                tooltip: 'Choose a different image',
                                onPressed: _busy ? null : _chooseImage,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              const SizedBox(width: 4),
                              IconButton.filledTonal(
                                tooltip: 'Remove selected image',
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _selectedImage = null;
                                          _imageBytes = null;
                                        }),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );

  Widget _statusCard({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _forest),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _forest, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(message, style: const TextStyle(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
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

String _friendlyError(Object error) => error is PostgrestException
    ? error.message
    : error is StorageException
        ? error.message
        : 'Check your connection and try again.';
