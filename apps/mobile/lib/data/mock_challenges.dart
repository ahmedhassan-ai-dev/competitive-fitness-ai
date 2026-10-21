import '../models/exercise_type.dart';

enum ChallengeStatus { waiting, active, completed }

// Presentation fixtures, not wire DTOs. No serialization or score mutation.
class ChallengeParticipant {
  const ChallengeParticipant(this.displayName, this.acceptedReps);
  final String displayName;
  final int acceptedReps;
}

class Challenge {
  const Challenge({
    required this.title,
    required this.exercise,
    required this.status,
    required this.participants,
  });
  final String title;
  final ExerciseType exercise;
  final ChallengeStatus status;
  final List<ChallengeParticipant> participants;
}

const mockChallenges = [
  Challenge(
    title: 'The squat showdown',
    exercise: ExerciseType.squat,
    status: ChallengeStatus.active,
    participants: [
      ChallengeParticipant('You', 12),
      ChallengeParticipant('Alex', 10),
    ],
  ),
  Challenge(
    title: 'Push your limits',
    exercise: ExerciseType.pushUp,
    status: ChallengeStatus.waiting,
    participants: [ChallengeParticipant('You', 0)],
  ),
  Challenge(
    title: 'Stronger together',
    exercise: ExerciseType.squat,
    status: ChallengeStatus.completed,
    participants: [
      ChallengeParticipant('You', 20),
      ChallengeParticipant('Sam', 20),
    ],
  ),
];
