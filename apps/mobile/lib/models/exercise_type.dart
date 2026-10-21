enum ExerciseType {
  squat('squat', 'Squat', 'Build a stronger foundation', 'Lower body'),
  pushUp('push_up', 'Push-up', 'Own every controlled rep', 'Upper body');

  const ExerciseType(this.wireName, this.label, this.description, this.focus);

  final String wireName;
  final String label;
  final String description;
  final String focus;

  String get preparation => switch (this) {
    squat => 'Stand side-on with your full body in view. Keep your feet stable and move at a controlled pace.',
    pushUp => 'Place your hands beneath your shoulders. Keep your full body in view from the side.',
  };
}
