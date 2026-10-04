import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import 'peer_reports_screen.dart';

const _reviewForest = Color(0xFF134E3F);
const _reviewSage = Color(0xFFE8F0EC);
const _reviewCanvas = Color(0xFFF9FBF9);
const _reviewBucket = 'student-verification';

class VerificationReviewScreen extends StatefulWidget {
  const VerificationReviewScreen({super.key});

  @override
  State<VerificationReviewScreen> createState() =>
      _VerificationReviewScreenState();
}

class _VerificationReviewScreenState extends State<VerificationReviewScreen> {
  List<_VerificationSubmission> _submissions = [];
  bool _loading = true;
  String? _error;
  String? _actingOn;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows =
          await supabase.rpc('pending_student_verifications') as List<dynamic>;
      final submissions = <_VerificationSubmission>[];
      for (final row in rows) {
        final submission = _VerificationSubmission.fromMap(
            Map<String, dynamic>.from(row as Map));
        final signedUrl = await supabase.storage
            .from(_reviewBucket)
            .createSignedUrl(submission.imagePath, 20 * 60);
        submissions.add(submission.withSignedImage(signedUrl));
      }
      if (!mounted) return;
      setState(() {
        _submissions = submissions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _review(
      _VerificationSubmission submission, bool approved) async {
    final decision = approved ? 'approve' : 'reject';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${approved ? 'Approve' : 'Reject'} student ID?'),
        content: Text(
            'This will ${approved ? 'verify' : 'decline'} ${submission.fullName ?? 'this student'}’s submission.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _reviewForest),
            child: Text(approved ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || _actingOn != null) return;

    setState(() => _actingOn = submission.userId);
    try {
      await supabase.rpc('review_student_verification', params: {
        'p_student_user_id': submission.userId,
        'p_approved': approved,
      });
      if (!mounted) return;
      setState(() =>
          _submissions.removeWhere((item) => item.userId == submission.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Student ID $decision${approved ? 'd' : 'ed'}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not $decision this ID. $error')),
      );
    } finally {
      if (mounted) setState(() => _actingOn = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _reviewCanvas,
        appBar: AppBar(
          backgroundColor: _reviewCanvas,
          title: const Text('Student ID reviews',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Peer reports',
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const PeerReportsScreen(),
                ),
              ),
              icon: const Icon(Icons.flag_outlined, color: _reviewForest),
            ),
            IconButton(
              tooltip: 'Refresh submissions',
              onPressed: _loading || _actingOn != null
                  ? null
                  : () => _loadSubmissions(),
              icon: const Icon(Icons.refresh_rounded, color: _reviewForest),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _reviewForest))
            : _error != null
                ? _messageCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Reviewer access required',
                    message: _error!,
                    action: TextButton(
                      onPressed: _loadSubmissions,
                      child: const Text('Try again'),
                    ),
                  )
                : _submissions.isEmpty
                    ? _messageCard(
                        icon: Icons.inbox_outlined,
                        title: 'No pending submissions',
                        message:
                            'New student ID submissions will appear here for review.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                        itemCount: _submissions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final submission = _submissions[index];
                          final busy = _actingOn == submission.userId;
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _reviewSage,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  submission.fullName ?? 'Student',
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800),
                                ),
                                if (submission.university?.isNotEmpty == true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(submission.university!),
                                  ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.network(
                                    submission.signedImageUrl!,
                                    width: double.infinity,
                                    height: 230,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child,
                                            progress) =>
                                        progress == null
                                            ? child
                                            : const SizedBox(
                                                height: 230,
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                          color: _reviewForest),
                                                ),
                                              ),
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(
                                      height: 150,
                                      child: Center(
                                        child: Text(
                                            'Could not load the private ID image.'),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Submitted ${_formatDate(submission.submittedAt)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                                if (busy) ...[
                                  const SizedBox(height: 14),
                                  const LinearProgressIndicator(
                                      color: _reviewForest),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _actingOn == null
                                            ? () => _review(submission, false)
                                            : null,
                                        icon: const Icon(Icons.close_rounded),
                                        label: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _actingOn == null
                                            ? () => _review(submission, true)
                                            : null,
                                        style: FilledButton.styleFrom(
                                            backgroundColor: _reviewForest),
                                        icon:
                                            const Icon(Icons.verified_rounded),
                                        label: const Text('Approve'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      );

  Widget _messageCard({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _reviewSage,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 32, color: _reviewForest),
                const SizedBox(height: 10),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.4)),
                if (action != null) action,
              ],
            ),
          ),
        ),
      );
}

class _VerificationSubmission {
  const _VerificationSubmission({
    required this.userId,
    required this.fullName,
    required this.university,
    required this.imagePath,
    required this.submittedAt,
    this.signedImageUrl,
  });

  final String userId;
  final String? fullName;
  final String? university;
  final String imagePath;
  final DateTime submittedAt;
  final String? signedImageUrl;

  factory _VerificationSubmission.fromMap(Map<String, dynamic> row) =>
      _VerificationSubmission(
        userId: row['user_id'] as String,
        fullName: row['full_name'] as String?,
        university: row['university'] as String?,
        imagePath: row['student_id_url'] as String,
        submittedAt: DateTime.parse(row['submitted_at'] as String),
      );

  _VerificationSubmission withSignedImage(String url) =>
      _VerificationSubmission(
        userId: userId,
        fullName: fullName,
        university: university,
        imagePath: imagePath,
        submittedAt: submittedAt,
        signedImageUrl: url,
      );
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}
