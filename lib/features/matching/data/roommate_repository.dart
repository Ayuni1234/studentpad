import '../../../core/services/supabase_service.dart';

const roommateProfilePhotoBucket = 'profile-photos';

class RoommateRepository {
  const RoommateRepository();

  Future<RoommateContact?> fetchContact(String peerUserId) async {
    final response = await supabase.rpc(
      'roommate_profile_contact',
      params: {'p_peer_user_id': peerUserId},
    );
    if (response is! List) {
      throw const FormatException(
        'Unexpected response from roommate_profile_contact.',
      );
    }
    if (response.isEmpty) return null;
    final row = Map<String, dynamic>.from(response.first as Map);
    final phoneNumber = row['phone_number'] as String?;
    final whatsappNumber = row['whatsapp_number'] as String?;
    if (phoneNumber == null && whatsappNumber == null) return null;
    return RoommateContact(
      phoneNumber: phoneNumber,
      whatsappNumber: whatsappNumber,
    );
  }

  Future<bool> currentStudentIsVerified() async {
    final rows =
        await supabase.rpc('my_student_verification_state') as List<dynamic>;
    if (rows.isEmpty) return false;
    return Map<String, dynamic>.from(
          rows.first as Map,
        )['verification_status'] ==
        'approved';
  }

  Future<List<RoommateProfile>> discover() async {
    final response = await supabase
        .from('roommate_profiles')
        .select(
          'user_id, bio, major, graduation_year, gender, '
          'housing_type_preference, preferred_locations, budget_min_ghs, '
          'budget_max_ghs, avatar_url',
        )
        .order('updated_at', ascending: false);
    final currentUserId = supabase.auth.currentUser?.id;
    final profiles = List<Map<String, dynamic>>.from(response)
        .where((row) => row['user_id'] != currentUserId)
        .toList(growable: false);
    if (profiles.isEmpty) return const [];

    final ids = profiles.map((row) => row['user_id'] as String).toList();
    final userResponse = await supabase
        .from('users')
        .select('user_id, full_name, university, is_verified')
        .inFilter('user_id', ids)
        .eq('is_verified', true);
    final usersById = {
      for (final row in List<Map<String, dynamic>>.from(userResponse))
        row['user_id'] as String: row,
    };

    final results = <RoommateProfile>[];
    for (final row in profiles) {
      final userId = row['user_id'] as String;
      final user = usersById[userId];
      if (user == null) continue;
      final avatarPath = row['avatar_url'] as String?;
      final avatarUrl = avatarPath == null
          ? null
          : await supabase.storage
              .from(roommateProfilePhotoBucket)
              .createSignedUrl(avatarPath, 60 * 60);
      results.add(RoommateProfile.fromRows(row, user, avatarUrl));
    }
    return results;
  }
}

class RoommateContact {
  const RoommateContact({
    this.phoneNumber,
    this.whatsappNumber,
  });

  final String? phoneNumber;
  final String? whatsappNumber;
}

class RoommateProfile {
  const RoommateProfile({
    required this.userId,
    required this.fullName,
    required this.major,
    required this.graduationYear,
    required this.gender,
    required this.housingTypePreference,
    required this.preferredLocations,
    required this.budgetMin,
    required this.budgetMax,
    required this.bio,
    this.university,
    this.avatarUrl,
  });

  final String userId;
  final String fullName;
  final String major;
  final int graduationYear;
  final String gender;
  final String housingTypePreference;
  final List<String> preferredLocations;
  final double budgetMin;
  final double budgetMax;
  final String bio;
  final String? university;
  final String? avatarUrl;

  factory RoommateProfile.fromRows(
    Map<String, dynamic> profile,
    Map<String, dynamic> user,
    String? avatarUrl,
  ) {
    final rawLocations = profile['preferred_locations'];
    return RoommateProfile(
      userId: profile['user_id'] as String,
      fullName: (user['full_name'] as String?)?.trim().isNotEmpty == true
          ? (user['full_name'] as String).trim()
          : 'Student',
      major: profile['major'] as String,
      graduationYear: profile['graduation_year'] as int,
      gender: profile['gender'] as String,
      housingTypePreference: profile['housing_type_preference'] as String,
      preferredLocations: rawLocations is List
          ? rawLocations.map((value) => value.toString()).toList()
          : const [],
      budgetMin: (profile['budget_min_ghs'] as num).toDouble(),
      budgetMax: (profile['budget_max_ghs'] as num).toDouble(),
      bio: profile['bio'] as String? ?? '',
      university: user['university'] as String?,
      avatarUrl: avatarUrl,
    );
  }
}
