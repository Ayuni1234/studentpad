import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';
import '../../chat/presentation/chat_screens.dart';

const _forest = Color(0xFF134E3F);
const _sage = Color(0xFFE8F0EC);
const _canvas = Color(0xFFF9FBF9);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final String? _userId;
  late final Stream<List<Map<String, dynamic>>>? _notifications;
  final Set<String> _opening = {};

  @override
  void initState() {
    super.initState();
    _userId = supabase.auth.currentUser?.id;
    _notifications = _userId == null
        ? null
        : supabase
            .from('notifications')
            .stream(primaryKey: const ['id']).eq('user_id', _userId);
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    final id = notification['id'] as String;
    if (!_opening.add(id)) return;
    final userId = _userId;
    if (userId == null) return;

    try {
      if (notification['read_at'] == null) {
        await supabase
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', id)
            .eq('user_id', userId);
      }
      if (!mounted) return;

      final chatId = notification['chat_id'] as String?;
      if (chatId != null) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              name: 'Conversation',
              initials: 'C',
              chatId: chatId,
              isVerified: true,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this notification.')),
        );
      }
    } finally {
      _opening.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: _canvas,
          title: const Text('Notifications',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: _notifications == null
            ? const _EmptyNotifications(
                title: 'Sign in to view updates',
                message: 'Your messages and account updates will appear here.',
              )
            : StreamBuilder<List<Map<String, dynamic>>>(
                stream: _notifications,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _EmptyNotifications(
                      title: 'Could not load notifications',
                      message: 'Check your connection and try again.',
                      action: TextButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(color: _forest));
                  }
                  final rows = [...snapshot.data!]..sort((a, b) =>
                      DateTime.tryParse(b['created_at']?.toString() ?? '')
                          ?.compareTo(DateTime.tryParse(
                                  a['created_at']?.toString() ?? '') ??
                              DateTime.fromMillisecondsSinceEpoch(0)) ??
                      0);
                  if (rows.isEmpty) {
                    return const _EmptyNotifications(
                      title: 'You’re all caught up',
                      message:
                          'New messages and verification updates will appear here.',
                    );
                  }
                  return RefreshIndicator(
                    color: _forest,
                    onRefresh: () async => setState(() {}),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final unread = row['read_at'] == null;
                        final type = row['notification_type'] as String? ?? '';
                        final icon = switch (type) {
                          'message' => Icons.chat_bubble_outline_rounded,
                          'verification_approved' => Icons.verified_rounded,
                          'verification_rejected' => Icons.info_outline_rounded,
                          _ => Icons.notifications_none_rounded,
                        };
                        final createdAt = DateTime.tryParse(
                          row['created_at']?.toString() ?? '',
                        );
                        return Material(
                          color: unread ? _sage : Colors.white,
                          borderRadius: BorderRadius.circular(17),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17)),
                            leading: CircleAvatar(
                              backgroundColor: Colors.white,
                              foregroundColor: _forest,
                              child: Icon(icon),
                            ),
                            title: Text(
                              row['title'] as String? ?? 'StudentPad update',
                              style: TextStyle(
                                fontWeight:
                                    unread ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${row['body'] ?? ''}\n${_formatTime(createdAt)}',
                                style: const TextStyle(height: 1.4),
                              ),
                            ),
                            isThreeLine: true,
                            trailing: unread
                                ? const Icon(Icons.circle,
                                    size: 10, color: _forest)
                                : null,
                            onTap: _opening.contains(row['id'])
                                ? null
                                : () => _openNotification(row),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      );

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final difference = DateTime.now().toUtc().difference(value.toUtc());
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${value.day}/${value.month}/${value.year}';
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.notifications_none_rounded,
                size: 48, color: Color(0xFF709581)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
            if (action != null) action!,
          ]),
        ),
      );
}
