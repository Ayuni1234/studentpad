import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Returns the existing peer conversation or creates one under the chat RLS
/// rules, which require both participants to be verified students.
Future<String> getOrCreateConversation(String peerUserId) async {
  final currentUserId = supabase.auth.currentUser?.id;
  if (currentUserId == null) {
    throw const AuthException('Sign in to message another student.');
  }
  if (currentUserId == peerUserId) {
    throw const AuthException('You cannot start a conversation with yourself.');
  }

  Future<String?> findExisting() async {
    final rows = await supabase
        .from('chats')
        .select('id, participant_one_id, participant_two_id')
        .or('participant_one_id.eq.$currentUserId,participant_two_id.eq.$currentUserId');
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final first = row['participant_one_id'];
      final second = row['participant_two_id'];
      if ((first == currentUserId && second == peerUserId) ||
          (first == peerUserId && second == currentUserId)) {
        return row['id'] as String;
      }
    }
    return null;
  }

  final existing = await findExisting();
  if (existing != null) return existing;

  try {
    final row = await supabase
        .from('chats')
        .insert({
          'participant_one_id': currentUserId,
          'participant_two_id': peerUserId,
          'created_by': currentUserId,
        })
        .select('id')
        .single();
    return row['id'] as String;
  } on PostgrestException catch (error) {
    // Another tap/device may have created the unique participant pair first.
    if (error.code != '23505') rethrow;
    final racedConversation = await findExisting();
    if (racedConversation != null) return racedConversation;
    rethrow;
  }
}
