import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import 'peer_reports_screen.dart';

const _adminForest = Color(0xFF134E3F);
const _adminSage = Color(0xFFE8F0EC);
const _adminCanvas = Color(0xFFF9FBF9);
const _verificationBucket = 'student-verification';

enum _AdminSection { overview, verification, listings, people, audit }

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _checkingAccess = true;
  bool _isAdmin = false;
  bool _loading = false;
  String? _error;
  _AdminSection _section = _AdminSection.overview;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _verifications = [];
  List<Map<String, dynamic>> _listings = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _audit = [];
  final _search = TextEditingController();
  String? _workingOn;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _checkAccess() async {
    setState(() {
      _checkingAccess = true;
      _error = null;
    });
    try {
      final allowed = await supabase.rpc('is_studentpad_admin') as bool;
      if (!mounted) return;
      setState(() {
        _isAdmin = allowed;
        _checkingAccess = false;
      });
      if (allowed) await _loadAll();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _checkingAccess = false;
        _error = 'Administrator access could not be confirmed.';
      });
    }
  }

  Future<void> _loadAll() async {
    if (!_isAdmin) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        supabase.rpc('admin_dashboard_summary'),
        supabase.rpc('admin_verification_queue'),
        supabase.rpc('admin_active_listings'),
        supabase.rpc('admin_user_directory', params: {
          'p_search': _search.text.trim().isEmpty ? null : _search.text.trim(),
        }),
        supabase.rpc('admin_audit_log', params: {'p_limit': 100}),
      ]);

      final reviewRows = _asRows(results[1]);
      for (final row in reviewRows) {
        final path = row['student_id_url'];
        if (path is String && path.isNotEmpty) {
          try {
            row['signed_image_url'] = await supabase.storage
                .from(_verificationBucket)
                .createSignedUrl(path, 20 * 60);
          } catch (_) {
            row['signed_image_url'] = null;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(results[0] as Map);
        _verifications = reviewRows;
        _listings = _asRows(results[2]);
        _users = _asRows(results[3]);
        _audit = _asRows(results[4]);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is PostgrestException
            ? error.message
            : 'Could not load the admin dashboard. Check the connection and retry.';
      });
    }
  }

  List<Map<String, dynamic>> _asRows(dynamic value) => (value as List<dynamic>)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  Future<void> _reviewVerification(
      Map<String, dynamic> item, bool approve) async {
    final note = approve
        ? null
        : await _askForNote(
            title: 'Reject student verification',
            prompt: 'Add a short reason so the student knows what to fix.',
            requiredNote: true,
          );
    if (!approve && note == null) return;
    await _perform('verification:${item['user_id']}', () async {
      await supabase.rpc('admin_review_verification', params: {
        'p_student_user_id': item['user_id'],
        'p_approved': approve,
        'p_note': note,
      });
      _message(approve ? 'Student verified.' : 'Verification rejected.');
      await _loadAll();
    });
  }

  Future<void> _deactivateListing(Map<String, dynamic> item) async {
    final note = await _askForNote(
      title: 'Remove listing from Explore?',
      prompt: 'Add a brief moderation reason for the audit record.',
      requiredNote: true,
    );
    if (note == null) return;
    await _perform('listing:${item['id']}', () async {
      await supabase.rpc('admin_set_listing_active', params: {
        'p_listing_id': item['id'],
        'p_is_active': false,
        'p_note': note,
      });
      _message('Listing deactivated.');
      await _loadAll();
    });
  }

  Future<void> _setAccountStatus(
      Map<String, dynamic> item, String status) async {
    final displayName = item['full_name'] as String? ?? 'this student';
    final note = status == 'active'
        ? ''
        : await _askForNote(
            title: status == 'banned' ? 'Ban account' : 'Suspend account',
            prompt: 'Add a reason for restricting $displayName.',
            requiredNote: true,
          );
    if (note == null) return;
    await _perform('user:${item['user_id']}', () async {
      await supabase.rpc('admin_set_account_status', params: {
        'p_student_user_id': item['user_id'],
        'p_status': status,
        'p_note': note,
      });
      _message(
          status == 'active' ? 'Account access restored.' : 'Account $status.');
      await _loadAll();
    });
  }

  Future<String?> _askForNote({
    required String title,
    required String prompt,
    required bool requiredNote,
  }) async {
    final controller = TextEditingController();
    String? validation;
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prompt),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 500,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Reason',
                    errorText: validation,
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _adminForest),
                onPressed: () {
                  final value = controller.text.trim();
                  if (requiredNote && value.isEmpty) {
                    setDialogState(() => validation = 'A reason is required.');
                    return;
                  }
                  Navigator.pop(dialogContext, value);
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _perform(String key, Future<void> Function() action) async {
    if (_workingOn != null) return;
    setState(() => _workingOn = key);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      _message(error is PostgrestException
          ? error.message
          : 'Action failed. $error');
    } finally {
      if (mounted) setState(() => _workingOn = null);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _adminCanvas,
        appBar: AppBar(
          backgroundColor: _adminCanvas,
          title: const Text('Admin dashboard',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: _loading ? null : _loadAll,
              icon: const Icon(Icons.refresh_rounded, color: _adminForest),
            ),
          ],
        ),
        body: _checkingAccess
            ? const Center(
                child: CircularProgressIndicator(color: _adminForest))
            : !_isAdmin
                ? _accessDenied()
                : _error != null
                    ? _stateMessage(
                        icon: Icons.cloud_off_outlined,
                        title: 'Dashboard unavailable',
                        message: _error!,
                        button: TextButton(
                            onPressed: _loadAll, child: const Text('Retry')),
                      )
                    : Column(
                        children: [
                          if (_loading)
                            const LinearProgressIndicator(
                                color: _adminForest,
                                backgroundColor: _adminSage),
                          SizedBox(
                            height: 54,
                            child: ListView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              scrollDirection: Axis.horizontal,
                              children: [
                                _sectionChip(_AdminSection.overview, 'Overview',
                                    Icons.dashboard_outlined),
                                _sectionChip(
                                    _AdminSection.verification,
                                    'Verification',
                                    Icons.verified_user_outlined),
                                _sectionChip(_AdminSection.listings, 'Listings',
                                    Icons.home_work_outlined),
                                _sectionChip(_AdminSection.people, 'Students',
                                    Icons.people_outline_rounded),
                                _sectionChip(_AdminSection.audit, 'Audit log',
                                    Icons.receipt_long_outlined),
                              ],
                            ),
                          ),
                          Expanded(child: _sectionBody()),
                        ],
                      ),
      );

  Widget _sectionChip(_AdminSection section, String label, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: _section == section,
          label: Text(label),
          avatar: Icon(icon, size: 18),
          selectedColor: _adminSage,
          onSelected: (_) => setState(() => _section = section),
        ),
      );

  Widget _sectionBody() => switch (_section) {
        _AdminSection.overview => _overview(),
        _AdminSection.verification => _verificationQueue(),
        _AdminSection.listings => _listingQueue(),
        _AdminSection.people => _userDirectory(),
        _AdminSection.audit => _auditLog(),
      };

  Widget _overview() => RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('StudentPadGH operations',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'Review student access, housing content, and account safety.'),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metric('Pending IDs', _summary['pending_verifications'],
                    Icons.badge_outlined),
                _metric('Active listings', _summary['active_listings'],
                    Icons.home_work_outlined),
                _metric('Registered students', _summary['registered_users'],
                    Icons.people_outline_rounded),
                _metric('Restricted accounts', _summary['restricted_accounts'],
                    Icons.shield_outlined),
              ],
            ),
            const SizedBox(height: 20),
            _overviewAction(
                'Review student IDs',
                'Approve or reject pending submissions.',
                Icons.verified_user_outlined,
                _AdminSection.verification),
            _overviewAction(
                'Moderate listings',
                'Remove spam or unsafe housing posts.',
                Icons.home_work_outlined,
                _AdminSection.listings),
            _overviewAction(
                'Manage student accounts',
                'Search, suspend, ban, or restore access.',
                Icons.manage_accounts_outlined,
                _AdminSection.people),
            _overviewAction(
                'Review peer reports',
                'Respond to safety reports from student chats.',
                Icons.flag_outlined,
                _AdminSection.overview,
                onTap: _openPeerReports),
            _overviewAction(
                'View audit history',
                'See who made changes and when.',
                Icons.receipt_long_outlined,
                _AdminSection.audit),
          ],
        ),
      );

  Widget _metric(String label, dynamic value, IconData icon) => Container(
        width: (MediaQuery.sizeOf(context).width - 54) / 2,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _adminSage,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
                color: Color(0x100B372C), blurRadius: 9, offset: Offset(0, 3))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _adminForest),
          const SizedBox(height: 12),
          Text('${value ?? 0}',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );

  Future<void> _openPeerReports() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const PeerReportsScreen()),
    );
    if (mounted) await _loadAll();
  }

  Widget _overviewAction(
          String title, String subtitle, IconData icon, _AdminSection section,
          {VoidCallback? onTap}) =>
      Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _adminSage)),
        child: ListTile(
          leading: CircleAvatar(
              backgroundColor: _adminSage,
              child: Icon(icon, color: _adminForest)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap ?? () => setState(() => _section = section),
        ),
      );

  Widget _verificationQueue() => _verifications.isEmpty
      ? _stateMessage(
          icon: Icons.inbox_outlined,
          title: 'No pending IDs',
          message: 'New student submissions will appear here.')
      : RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _verifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = _verifications[index];
              final id = item['user_id'] as String;
              final imageUrl = item['signed_image_url'] as String?;
              return _card(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['full_name'] as String? ?? 'Student',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 17)),
                      if ((item['university'] as String?)?.isNotEmpty == true)
                        Text(item['university'] as String),
                      const SizedBox(height: 10),
                      if (imageUrl != null)
                        ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(imageUrl,
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    _imageUnavailable()))
                      else
                        _imageUnavailable(),
                      const SizedBox(height: 8),
                      Text('Submitted ${_date(item['submitted_at'])}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: _workingOn == null
                                    ? () => _reviewVerification(item, false)
                                    : null,
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Reject'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: FilledButton.icon(
                                onPressed: _workingOn == null
                                    ? () => _reviewVerification(item, true)
                                    : null,
                                style: FilledButton.styleFrom(
                                    backgroundColor: _adminForest),
                                icon: const Icon(Icons.verified_rounded),
                                label: const Text('Approve'))),
                      ]),
                      if (_workingOn == 'verification:$id')
                        const LinearProgressIndicator(color: _adminForest),
                    ]),
              );
            },
          ),
        );

  Widget _listingQueue() => _listings.isEmpty
      ? _stateMessage(
          icon: Icons.home_work_outlined,
          title: 'No active listings',
          message: 'Active room posts will appear here for moderation.')
      : RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _listings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = _listings[index];
              return _card(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item['title'] as String? ?? 'Untitled listing',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(
                        '${item['location'] ?? 'Location unavailable'} · ${item['listing_type'] == 'needs_space' ? 'Needs a room' : 'Room available'}'),
                    Text('GHS ${item['monthly_rent_ghs'] ?? '—'} / month'),
                    Text(
                        'Owner: ${item['owner_name'] ?? 'Student'} · ${_date(item['created_at'])}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            onPressed: _workingOn == null
                                ? () => _deactivateListing(item)
                                : null,
                            icon: const Icon(Icons.visibility_off_outlined),
                            label: const Text('Deactivate'))),
                    if (_workingOn == 'listing:${item['id']}')
                      const LinearProgressIndicator(color: _adminForest),
                  ]));
            },
          ),
        );

  Widget _userDirectory() => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadAll(),
            decoration: InputDecoration(
              hintText: 'Search name, email, or university',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                  onPressed: _loadAll,
                  icon: const Icon(Icons.arrow_forward_rounded)),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _users.isEmpty
              ? _stateMessage(
                  icon: Icons.people_outline_rounded,
                  title: 'No students found',
                  message: 'Try a different search.')
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _users[index];
                      final isAdmin = item['is_admin'] == true;
                      final status =
                          item['account_status'] as String? ?? 'active';
                      return _card(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(
                                      item['full_name'] as String? ?? 'Student',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16))),
                              _statusPill(status),
                            ]),
                            if (item['email'] != null)
                              Text(item['email'] as String),
                            Text(item['university'] as String? ??
                                'University not provided'),
                            Text(
                                'Verification: ${item['verification_status'] ?? 'unknown'}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                            if ((item['moderation_note'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              Text('Note: ${item['moderation_note']}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                            if (!isAdmin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: PopupMenuButton<String>(
                                  tooltip: 'Account actions',
                                  onSelected: _workingOn == null
                                      ? (value) =>
                                          _setAccountStatus(item, value)
                                      : null,
                                  itemBuilder: (_) => [
                                    if (status != 'active')
                                      const PopupMenuItem(
                                          value: 'active',
                                          child: Text('Restore access')),
                                    if (status != 'suspended')
                                      const PopupMenuItem(
                                          value: 'suspended',
                                          child: Text('Suspend account')),
                                    if (status != 'banned')
                                      const PopupMenuItem(
                                          value: 'banned',
                                          child: Text('Ban account')),
                                  ],
                                  child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.more_horiz_rounded,
                                          color: _adminForest)),
                                ),
                              ),
                            if (_workingOn == 'user:${item['user_id']}')
                              const LinearProgressIndicator(
                                  color: _adminForest),
                          ]));
                    },
                  ),
                ),
        ),
      ]);

  Widget _auditLog() => _audit.isEmpty
      ? _stateMessage(
          icon: Icons.receipt_long_outlined,
          title: 'No admin actions yet',
          message: 'Administrative decisions will be recorded here.')
      : RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _audit.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _audit[index];
              final details = item['details'] is Map
                  ? Map<String, dynamic>.from(item['details'] as Map)
                  : <String, dynamic>{};
              return _card(
                  child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                    backgroundColor: _adminSage,
                    child: Icon(Icons.history_rounded, color: _adminForest)),
                title: Text(
                    _prettyAction(item['action'] as String? ?? 'admin action'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${item['actor_name'] ?? 'Admin'} · ${item['target_type'] ?? ''} · ${_date(item['created_at'])}${details['note'] == null ? '' : '\n${details['note']}'}'),
                isThreeLine: details['note'] != null,
              ));
            },
          ),
        );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: _adminSage,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x100B372C), blurRadius: 9, offset: Offset(0, 3))
            ]),
        child: child,
      );

  Widget _imageUnavailable() => Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child:
            const Center(child: Text('Private student ID image unavailable')),
      );

  Widget _statusPill(String status) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: isActive ? const Color(0xFFDDF2E6) : const Color(0xFFFFE4DB),
          borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive ? _adminForest : const Color(0xFF8A321D))),
    );
  }

  Widget _accessDenied() => _stateMessage(
        icon: Icons.lock_outline_rounded,
        title: 'Administrator access required',
        message: _error ??
            'This account is not authorized to use StudentPad administration.',
        button: TextButton(
            onPressed: _checkAccess, child: const Text('Check access again')),
      );

  Widget _stateMessage(
          {required IconData icon,
          required String title,
          required String message,
          Widget? button}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: _adminSage, borderRadius: BorderRadius.circular(20)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 32, color: _adminForest),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.4)),
              if (button != null) button,
            ]),
          ),
        ),
      );

  String _date(dynamic value) {
    if (value is! String) return 'Date unavailable';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return 'Date unavailable';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _prettyAction(String action) => action
      .replaceAll('_', ' ')
      .split(' ')
      .map((word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
