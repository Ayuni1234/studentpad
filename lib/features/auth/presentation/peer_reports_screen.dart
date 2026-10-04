import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

const _reportsForest = Color(0xFF134E3F);
const _reportsSage = Color(0xFFE8F0EC);
const _reportsCanvas = Color(0xFFF9FBF9);

class PeerReportsScreen extends StatefulWidget {
  const PeerReportsScreen({super.key});

  @override
  State<PeerReportsScreen> createState() => _PeerReportsScreenState();
}

class _PeerReportsScreenState extends State<PeerReportsScreen> {
  List<Map<String, dynamic>> _reports = const [];
  bool _loading = true;
  String? _error;
  String? _actingOn;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await supabase.rpc('pending_conversation_reports') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _reports =
            rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is PostgrestException
            ? error.message
            : 'Could not load peer reports. Check your connection and try again.';
      });
    }
  }

  Future<String?> _askReviewerNote(String decision) async {
    final note = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title:
              Text(decision == 'resolve' ? 'Resolve report' : 'Dismiss report'),
          content: TextField(
            controller: note,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Optional reviewer note',
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, note.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: _reportsForest),
              child: Text(decision == 'resolve' ? 'Resolve' : 'Dismiss'),
            ),
          ],
        ),
      );
    } finally {
      note.dispose();
    }
  }

  Future<void> _review(Map<String, dynamic> report, String decision) async {
    if (_actingOn != null || report['status'] != 'open') return;
    final note = await _askReviewerNote(decision);
    if (note == null || !mounted) return;
    final reportId = report['id'] as String;
    setState(() => _actingOn = reportId);
    try {
      await supabase.rpc('review_conversation_report', params: {
        'p_report_id': reportId,
        'p_decision': decision,
        'p_reviewer_note': note.isEmpty ? null : note,
      });
      if (!mounted) return;
      await _loadReports();
      if (mounted) {
        _showMessage(decision == 'resolve'
            ? 'Report marked as resolved.'
            : 'Report dismissed.');
      }
    } catch (error) {
      if (mounted) _showMessage('Could not review this report. $error');
    } finally {
      if (mounted) setState(() => _actingOn = null);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _reportsCanvas,
        appBar: AppBar(
          backgroundColor: _reportsCanvas,
          title: const Text('Peer reports',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Refresh reports',
              onPressed: _loading || _actingOn != null ? null : _loadReports,
              icon: const Icon(Icons.refresh_rounded, color: _reportsForest),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _reportsForest))
            : _error != null
                ? _notice(
                    icon: Icons.lock_outline_rounded,
                    title: 'Reviewer access required',
                    message: _error!,
                    action: TextButton(
                        onPressed: _loadReports,
                        child: const Text('Try again')),
                  )
                : _reports.isEmpty
                    ? _notice(
                        icon: Icons.inbox_outlined,
                        title: 'No peer reports',
                        message:
                            'Reports submitted from student conversations will appear here.',
                      )
                    : RefreshIndicator(
                        color: _reportsForest,
                        onRefresh: _loadReports,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          itemCount: _reports.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) =>
                              _reportCard(_reports[index]),
                        ),
                      ),
      );

  Widget _reportCard(Map<String, dynamic> report) {
    final status = report['status'] as String? ?? 'open';
    final busy = _actingOn == report['id'];
    final createdAt = DateTime.tryParse(report['created_at'].toString());
    final reporterName = _name(report['reporter_name'] as String?);
    final reportedName = _name(report['reported_user_name'] as String?);
    final reporterUniversity =
        (report['reporter_university'] as String?)?.trim();
    final reportedUniversity =
        (report['reported_user_university'] as String?)?.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _reportsSage,
        borderRadius: BorderRadius.circular(19),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D173D30), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.flag_outlined, color: _reportsForest, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_reasonLabel(report['reason'] as String? ?? 'other'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          _statusPill(status),
        ]),
        const SizedBox(height: 11),
        Text(
            'Reported by $reporterName${reporterUniversity?.isNotEmpty == true ? ' · $reporterUniversity' : ''}\nAbout $reportedName${reportedUniversity?.isNotEmpty == true ? ' · $reportedUniversity' : ''}',
            style: const TextStyle(color: Color(0xFF56645C))),
        if (createdAt != null) ...[
          const SizedBox(height: 3),
          Text(_formatDate(createdAt),
              style: const TextStyle(color: Colors.black45, fontSize: 12)),
        ],
        const SizedBox(height: 11),
        Text(
            (report['details'] as String?)?.trim().isNotEmpty == true
                ? (report['details'] as String).trim()
                : 'No additional details provided.',
            style: const TextStyle(height: 1.4)),
        if ((report['reviewer_note'] as String?)?.trim().isNotEmpty ==
            true) ...[
          const SizedBox(height: 9),
          Text('Reviewer note: ${(report['reviewer_note'] as String).trim()}',
              style: const TextStyle(
                  color: Color(0xFF56645C), fontStyle: FontStyle.italic)),
        ],
        if (status == 'open') ...[
          const SizedBox(height: 14),
          if (busy)
            const LinearProgressIndicator(color: _reportsForest)
          else
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _actingOn == null
                      ? () => _review(report, 'dismiss')
                      : null,
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _actingOn == null
                      ? () => _review(report, 'resolve')
                      : null,
                  style:
                      FilledButton.styleFrom(backgroundColor: _reportsForest),
                  child: const Text('Resolve'),
                ),
              ),
            ]),
        ],
      ]),
    );
  }

  Widget _statusPill(String status) {
    final label = switch (status) {
      'resolved' => 'Resolved',
      'dismissed' => 'Dismissed',
      _ => 'Open',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: status == 'open' ? const Color(0xFFFFE8C2) : Colors.white,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label,
          style: const TextStyle(
              color: _reportsForest,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
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

String _reasonLabel(String reason) => switch (reason) {
      'scam_or_fraud' => 'Scam or fraud',
      'harassment_or_abuse' => 'Harassment or abuse',
      'unsafe_housing' => 'Unsafe housing information',
      'impersonation' => 'Impersonation',
      _ => 'Other concern',
    };

String _name(String? value) =>
    value?.trim().isNotEmpty == true ? value!.trim() : 'Student';

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} at $hour:$minute';
}
