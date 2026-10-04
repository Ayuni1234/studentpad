import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../auth/presentation/verification_screen.dart';

const _forest = Color(0xFF134E3F);
const _sage = Color(0xFFE8F0EC);
const _canvas = Color(0xFFF9FBF9);

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<_ChatThread> _threads = const [];
  RealtimeChannel? _channel;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _viewerVerified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThreads());
    _subscribeToInbox();
  }

  void _subscribeToInbox() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _channel = supabase
        .channel('inbox:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => unawaited(_loadThreads()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chats',
          callback: (payload) {
            final chat = payload.newRecord;
            if (chat['participant_one_id'] == userId ||
                chat['participant_two_id'] == userId) {
              unawaited(_loadThreads());
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadThreads() async {
    final generation = ++_loadGeneration;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _threads = const [];
        _loading = false;
        _error = 'Sign in to see your conversations.';
      });
      return;
    }

    try {
      final account = await supabase
          .from('users')
          .select('is_verified')
          .eq('user_id', userId)
          .maybeSingle();
      if (account?['is_verified'] != true) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _threads = const [];
          _viewerVerified = false;
          _loading = false;
          _error = null;
        });
        return;
      }

      final chatResponse = await supabase
          .from('chats')
          .select('id, participant_one_id, participant_two_id, created_at')
          .or('participant_one_id.eq.$userId,participant_two_id.eq.$userId');
      final chatRows = List<Map<String, dynamic>>.from(chatResponse);
      if (chatRows.isEmpty) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _threads = const [];
          _viewerVerified = true;
          _loading = false;
          _error = null;
        });
        return;
      }

      final chatIds = chatRows.map((chat) => chat['id'] as String).toList();
      final peerIds = chatRows
          .map((chat) => chat['participant_one_id'] == userId
              ? chat['participant_two_id'] as String
              : chat['participant_one_id'] as String)
          .toSet()
          .toList();

      final results = await Future.wait([
        supabase
            .from('users')
            .select('user_id, full_name, university, is_verified')
            .inFilter('user_id', peerIds),
        supabase
            .from('messages')
            .select('id, chat_id, sender_id, body, created_at')
            .inFilter('chat_id', chatIds)
            .order('created_at', ascending: false),
        supabase
            .from('user_blocks')
            .select('blocked_user_id')
            .eq('blocker_id', userId)
            .inFilter('blocked_user_id', peerIds),
      ]);

      final userRows = List<Map<String, dynamic>>.from(results[0]);
      final messageRows = List<Map<String, dynamic>>.from(results[1]);
      final blockedIds = List<Map<String, dynamic>>.from(results[2])
          .map((row) => row['blocked_user_id'] as String)
          .toSet();
      final usersById = {
        for (final user in userRows) user['user_id'] as String: user,
      };
      final latestMessageByChat = <String, Map<String, dynamic>>{};
      for (final message in messageRows) {
        latestMessageByChat.putIfAbsent(
            message['chat_id'] as String, () => message);
      }

      final threads = chatRows.map((chat) {
        final chatId = chat['id'] as String;
        final peerId = chat['participant_one_id'] == userId
            ? chat['participant_two_id'] as String
            : chat['participant_one_id'] as String;
        final peer = usersById[peerId];
        final fullName = (peer?['full_name'] as String?)?.trim();
        final name =
            fullName == null || fullName.isEmpty ? 'Student' : fullName;
        final latest = latestMessageByChat[chatId];
        final university = peer?['university'] as String?;
        return _ChatThread(
          id: chatId,
          name: name,
          initials: _initials(name),
          isVerified: peer?['is_verified'] == true,
          isBlocked: blockedIds.contains(peerId),
          preview: blockedIds.contains(peerId)
              ? 'You blocked this student'
              : latest?['body'] as String? ??
                  (university == null || university.isEmpty
                      ? 'Start a conversation'
                      : university),
          activityAt: DateTime.tryParse(
                (latest?['created_at'] ?? chat['created_at']).toString(),
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0),
        );
      }).toList()
        ..sort((a, b) => b.activityAt.compareTo(a.activityAt));

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _threads = threads;
        _viewerVerified = true;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    final channel = _channel;
    if (channel != null) unawaited(supabase.removeChannel(channel));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          title: const Text('Inbox',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _canvas,
          actions: [
            IconButton(
              tooltip: 'Refresh conversations',
              onPressed: () => unawaited(_loadThreads()),
              icon: const Icon(Icons.refresh_rounded, color: _forest),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: _forest,
          onRefresh: _loadThreads,
          child: _loading
              ? ListView(
                  physics: AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 220),
                    Center(child: CircularProgressIndicator(color: _forest)),
                  ],
                )
              : _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 130),
                        const Icon(Icons.lock_outline,
                            size: 42, color: _forest),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () => unawaited(_loadThreads()),
                            child: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                  : !_viewerVerified
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 95),
                            const Icon(Icons.lock_outline_rounded,
                                size: 46, color: _forest),
                            const SizedBox(height: 14),
                            const Text(
                              'Verify to use StudentPad chat',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'In-app conversations are available to verified students.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: FilledButton.icon(
                                onPressed: () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const StudentVerificationScreen(),
                                  ),
                                ).then((_) => _loadThreads()),
                                style: FilledButton.styleFrom(
                                    backgroundColor: _forest),
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Verify student status'),
                              ),
                            ),
                          ],
                        )
                      : _threads.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(24),
                              children: const [
                                SizedBox(height: 115),
                                Icon(Icons.forum_outlined,
                                    size: 48, color: _forest),
                                SizedBox(height: 14),
                                Text(
                                  'Your conversations will show up here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 7),
                                Text(
                                  'Say hello to a verified student to get started.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                              itemCount: _threads.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 9),
                              itemBuilder: (context, index) =>
                                  _ConversationTile(
                                thread: _threads[index],
                                onChanged: () => unawaited(_loadThreads()),
                              ),
                            ),
        ),
      );
}

class _ChatThread {
  const _ChatThread({
    required this.id,
    required this.name,
    required this.initials,
    required this.isVerified,
    required this.isBlocked,
    required this.preview,
    required this.activityAt,
  });

  final String id;
  final String name;
  final String initials;
  final bool isVerified;
  final bool isBlocked;
  final String preview;
  final DateTime activityAt;
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.thread, required this.onChanged});

  final _ChatThread thread;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Material(
        color: _sage,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatRoomScreen(
                  chatId: thread.id,
                  name: thread.name,
                  initials: thread.initials,
                  isVerified: thread.isVerified,
                ),
              ),
            );
            onChanged();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.white,
                  child: Text(
                    thread.initials,
                    style: const TextStyle(
                      color: _forest,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              thread.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (thread.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded,
                                size: 16, color: _forest),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        thread.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(thread.activityAt),
                  style: const TextStyle(color: Colors.black45, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );
}

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.name,
    required this.initials,
    this.chatId,
    this.isVerified = false,
  });

  final String name;
  final String initials;
  final String? chatId;
  final bool isVerified;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final Map<String, _ChatMessage> _messagesById = {};
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  bool _blockedByMe = false;
  bool _blockBusy = false;
  bool _reporting = false;
  String? _peerUserId;
  String? _error;

  List<_ChatMessage> get _messages => _messagesById.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  void initState() {
    super.initState();
    if (widget.chatId != null && supabase.auth.currentUser != null) {
      unawaited(_startConversation());
    } else {
      _loading = false;
      _error =
          'Open an existing conversation from your inbox to send a message.';
    }
  }

  Future<void> _startConversation() async {
    final chatId = widget.chatId!;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final previousChannel = _channel;
      _channel = null;
      if (previousChannel != null) {
        await supabase.removeChannel(previousChannel);
      }
      final conversation = await supabase
          .from('chats')
          .select('id, participant_one_id, participant_two_id')
          .eq('id', chatId)
          .maybeSingle();
      if (!mounted) return;
      if (conversation == null) {
        setState(() {
          _loading = false;
          _error =
              'This conversation is available only to its verified participants.';
        });
        return;
      }

      final userId = supabase.auth.currentUser!.id;
      final peerId = conversation['participant_one_id'] == userId
          ? conversation['participant_two_id'] as String
          : conversation['participant_one_id'] as String;
      final block = await supabase
          .from('user_blocks')
          .select('blocked_user_id')
          .eq('blocker_id', userId)
          .eq('blocked_user_id', peerId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _peerUserId = peerId;
        _blockedByMe = block != null;
      });

      _channel = supabase
          .channel('chat:$chatId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chat_id',
              value: chatId,
            ),
            callback: (payload) => _addMessage(payload.newRecord),
          )
          .subscribe();
      await _loadMessages();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _loadMessages() async {
    try {
      final rows = await supabase
          .from('messages')
          .select('id, chat_id, sender_id, body, created_at')
          .eq('chat_id', widget.chatId!)
          .order('created_at');
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        _addMessage(row, scroll: false);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _addMessage(Map<String, dynamic> row, {bool scroll = true}) {
    final id = row['id'] as String?;
    final currentUserId = supabase.auth.currentUser?.id;
    if (id == null || currentUserId == null || !mounted) return;
    final message = _ChatMessage(
      text: row['body'] as String? ?? '',
      mine: row['sender_id'] == currentUserId,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
    if (_messagesById.containsKey(id)) return;
    setState(() => _messagesById[id] = message);
    if (scroll) _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    final userId = supabase.auth.currentUser?.id;
    final chatId = widget.chatId;
    if (body.isEmpty ||
        userId == null ||
        chatId == null ||
        _sending ||
        _blockedByMe) {
      return;
    }

    setState(() => _sending = true);
    _controller.clear();
    try {
      final row = await supabase
          .from('messages')
          .insert({'chat_id': chatId, 'sender_id': userId, 'body': body})
          .select('id, chat_id, sender_id, body, created_at')
          .single();
      _addMessage(Map<String, dynamic>.from(row));
    } catch (error) {
      if (!mounted) return;
      _controller.text = body;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Message could not be sent. ${_friendlyError(error)}')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleBlock() async {
    final currentUserId = supabase.auth.currentUser?.id;
    final peerUserId = _peerUserId;
    if (_blockBusy || currentUserId == null || peerUserId == null) return;

    if (!_blockedByMe) {
      final shouldBlock = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Block this student?'),
          content: const Text(
            'They will not be able to start a new chat with you or send more messages in this conversation. You can unblock them later from here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: _forest),
              child: const Text('Block student'),
            ),
          ],
        ),
      );
      if (shouldBlock != true || !mounted) return;
    }

    setState(() => _blockBusy = true);
    try {
      if (_blockedByMe) {
        await supabase
            .from('user_blocks')
            .delete()
            .eq('blocker_id', currentUserId)
            .eq('blocked_user_id', peerUserId);
      } else {
        await supabase.from('user_blocks').insert({
          'blocker_id': currentUserId,
          'blocked_user_id': peerUserId,
        });
      }
      if (!mounted) return;
      setState(() => _blockedByMe = !_blockedByMe);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_blockedByMe
              ? 'Student blocked. You can still review this chat and unblock them here.'
              : 'Student unblocked.'),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update block. ${error.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update block. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  Future<void> _reportPeer() async {
    final currentUserId = supabase.auth.currentUser?.id;
    final peerUserId = _peerUserId;
    final chatId = widget.chatId;
    if (_reporting ||
        currentUserId == null ||
        peerUserId == null ||
        chatId == null ||
        !widget.isVerified) {
      return;
    }

    final draft = await _showPeerReportDialog();
    if (draft == null || !mounted) return;
    setState(() => _reporting = true);
    try {
      await supabase.from('conversation_reports').insert({
        'reporter_id': currentUserId,
        'reported_user_id': peerUserId,
        'chat_id': chatId,
        'reason': draft.reason,
        'details': draft.details,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Your report was sent privately to the review team.')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send your report. ${error.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send your report. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  Future<_PeerReportDraft?> _showPeerReportDialog() async {
    final details = TextEditingController();
    var reason = 'scam_or_fraud';
    try {
      return await showDialog<_PeerReportDraft>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Report this conversation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose the concern. Your report is visible to the StudentPad review team.',
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: const [
                      DropdownMenuItem(
                          value: 'scam_or_fraud', child: Text('Scam or fraud')),
                      DropdownMenuItem(
                          value: 'harassment_or_abuse',
                          child: Text('Harassment or abuse')),
                      DropdownMenuItem(
                          value: 'unsafe_housing',
                          child: Text('Unsafe housing information')),
                      DropdownMenuItem(
                          value: 'impersonation', child: Text('Impersonation')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => reason = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: details,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Additional details (optional)',
                      hintText: 'Share only what is relevant to review.',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _PeerReportDraft(reason, details.text.trim()),
                ),
                style: FilledButton.styleFrom(backgroundColor: _forest),
                child: const Text('Send report'),
              ),
            ],
          ),
        ),
      );
    } finally {
      details.dispose();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    final channel = _channel;
    if (channel != null) unawaited(supabase.removeChannel(channel));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.chatId != null &&
        supabase.auth.currentUser != null &&
        !_loading &&
        _error == null &&
        !_blockedByMe;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        titleSpacing: 0,
        actions: [
          if (_peerUserId != null && widget.isVerified && _error == null)
            IconButton(
              tooltip: 'Report conversation',
              onPressed: _reporting ? null : () => _reportPeer(),
              icon: _reporting
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _forest),
                    )
                  : const Icon(Icons.flag_outlined, color: _forest),
            ),
          if (_peerUserId != null && _error == null)
            IconButton(
              tooltip: _blockedByMe ? 'Unblock student' : 'Block student',
              onPressed: _blockBusy ? null : () => _toggleBlock(),
              icon: _blockBusy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _forest),
                    )
                  : Icon(
                      _blockedByMe
                          ? Icons.person_add_alt_1_outlined
                          : Icons.block_rounded,
                      color: _forest,
                    ),
            ),
        ],
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: _sage,
              child: Text(
                widget.initials,
                style: const TextStyle(
                  color: _forest,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(
                    widget.isVerified
                        ? 'Verified student'
                        : 'StudentPad member',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: _sage,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _blockedByMe ? Icons.block_rounded : Icons.lock_outline,
                  size: 14,
                  color: _forest,
                ),
                SizedBox(width: 6),
                Text(
                  _blockedByMe
                      ? 'This student is blocked. Messages are paused.'
                      : 'Chat safely in StudentPad',
                  style: TextStyle(fontSize: 12, color: Color(0xFF315C4B)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _forest))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              if (widget.chatId != null) ...[
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: () =>
                                      unawaited(_startConversation()),
                                  child: const Text('Try again'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? const Center(
                            child: Text(
                              'Start the conversation with a friendly hello.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) =>
                                _MessageBubble(message: _messages[index]),
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: canSend && !_sending,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4000,
                      onSubmitted: (_) => unawaited(_send()),
                      decoration: InputDecoration(
                        hintText: _blockedByMe
                            ? 'Unblock this student to reply'
                            : canSend
                                ? 'Write a message…'
                                : 'Open a conversation to reply',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 17, vertical: 12),
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: _sage),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: _sage),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: _forest),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed:
                        canSend && !_sending ? () => unawaited(_send()) : null,
                    style: IconButton.styleFrom(
                      backgroundColor: _forest,
                      disabledBackgroundColor: _sage,
                      foregroundColor: Colors.white,
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.mine,
    required this.createdAt,
  });

  final String text;
  final bool mine;
  final DateTime createdAt;
}

class _PeerReportDraft {
  const _PeerReportDraft(this.reason, this.details);

  final String reason;
  final String details;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) => Align(
        alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
          decoration: BoxDecoration(
            color: message.mine ? _forest : _sage,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(message.mine ? 18 : 5),
              bottomRight: Radius.circular(message.mine ? 5 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: TextStyle(
                    color: message.mine ? Colors.white : Colors.black87,
                    height: 1.35),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                    color: message.mine ? Colors.white70 : Colors.black45,
                    fontSize: 10),
              ),
            ],
          ),
        ),
      );
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

String _formatTime(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }
  return '${local.day}/${local.month}/${local.year}';
}

String _friendlyError(Object error) {
  if (error is PostgrestException) {
    return error.message;
  }
  return 'Check your connection and try again.';
}
