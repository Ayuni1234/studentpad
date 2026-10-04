import '../../../core/services/supabase_service.dart';

/// Loads the signed-in student's compatibility scores from the protected RPC.
class CompatibilityRepository {
  const CompatibilityRepository();

  Future<List<CompatibilityScore>> fetchForCurrentUser() async {
    final response = await supabase.rpc('get_compatibility_scores');
    if (response is! List) {
      throw const FormatException(
        'Unexpected response from get_compatibility_scores.',
      );
    }

    final scores = response
        .map(
          (row) => CompatibilityScore.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .where((score) => score.compatibilityScore != null)
        .toList(growable: false);
    if (scores.isEmpty) return const [];

    final candidates = await supabase
        .from('users')
        .select('user_id, full_name, university, is_verified')
        .inFilter(
          'user_id',
          scores.map((score) => score.candidateUserId).toList(),
        )
        .eq('is_verified', true);
    final profiles =
        await supabase.from('profiles').select('user_id, bio').inFilter(
              'user_id',
              scores.map((score) => score.candidateUserId).toList(),
            );
    final candidatesById = {
      for (final row in List<Map<String, dynamic>>.from(candidates))
        row['user_id'] as String: row,
    };
    final biosById = {
      for (final row in List<Map<String, dynamic>>.from(profiles))
        row['user_id'] as String: row['bio'] as String?,
    };

    return scores
        .where((score) => candidatesById.containsKey(score.candidateUserId))
        .map((score) {
      final candidate = candidatesById[score.candidateUserId]!;
      return score.withStudent(
        fullName: candidate['full_name'] as String?,
        university: candidate['university'] as String?,
        bio: biosById[score.candidateUserId],
      );
    }).toList(growable: false);
  }
}

class CompatibilityScore {
  const CompatibilityScore({
    required this.candidateUserId,
    required this.compatibilityScore,
    required this.universityScore,
    required this.budgetOverlapScore,
    required this.cleanlinessScore,
    required this.sleepScheduleScore,
    this.fullName,
    this.university,
    this.bio,
  });

  final String candidateUserId;
  final double? compatibilityScore;
  final double? universityScore;
  final double? budgetOverlapScore;
  final double? cleanlinessScore;
  final double? sleepScheduleScore;
  final String? fullName;
  final String? university;
  final String? bio;

  CompatibilityScore withStudent({
    String? fullName,
    String? university,
    String? bio,
  }) =>
      CompatibilityScore(
        candidateUserId: candidateUserId,
        compatibilityScore: compatibilityScore,
        universityScore: universityScore,
        budgetOverlapScore: budgetOverlapScore,
        cleanlinessScore: cleanlinessScore,
        sleepScheduleScore: sleepScheduleScore,
        fullName: fullName,
        university: university,
        bio: bio,
      );

  factory CompatibilityScore.fromJson(Map<String, dynamic> json) {
    return CompatibilityScore(
      candidateUserId: json['candidate_user_id'] as String,
      compatibilityScore: _score(json['compatibility_score']),
      universityScore: _score(json['university_score']),
      budgetOverlapScore: _score(json['budget_overlap_score']),
      cleanlinessScore: _score(json['cleanliness_score']),
      sleepScheduleScore: _score(json['sleep_schedule_score']),
    );
  }

  static double? _score(Object? value) =>
      value is num ? value.toDouble() : null;
}
