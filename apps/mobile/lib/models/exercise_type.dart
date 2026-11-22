enum ExerciseType {
  squat('squat', 'Squat', 'Build a stronger foundation', 'Lower body'),
  pushUp('push_up', 'Push-up', 'Own every controlled rep', 'Upper body'),
  jumpingJack('jumping_jack', 'Jumping Jack', 'Move your whole body', 'Full body'),
  plank('plank', 'Plank', 'Hold strong with control', 'Core');

  const ExerciseType(this.wireName, this.label, this.description, this.focus);

  final String wireName;
  final String label;
  final String description;
  final String focus;

  bool get isHold => this == plank;
  String get metric => isHold ? 'hold_ms' : 'reps';
  String get preparation => switch (this) {
    squat => 'Keep your hips, knees and ankles visible; choose a stable stance.',
    pushUp => 'Position the camera from the side to show the elbows, hips and feet.',
    jumpingJack => 'Face the camera with your hands and feet visible even when spread wide.',
    plank => 'Place the phone sideways, level with your body; show your shoulders, hips and ankles.',
  };
}
