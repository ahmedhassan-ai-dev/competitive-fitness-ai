import 'package:flutter/material.dart';

import '../../models/exercise_type.dart';
import 'pose_rep_counter.dart';

/// Pre-workout placement guide. This is drawn in Flutter, not a stock image,
/// so it ships offline and remains crisp on small screens.
class WorkoutSetupGuide extends StatelessWidget {
  const WorkoutSetupGuide({
    super.key,
    required this.exercise,
    required this.onBegin,
    this.squatStyle = SquatStyle.standard,
    this.onSquatStyleChanged,
  });

  final ExerciseType exercise;
  final VoidCallback onBegin;
  final SquatStyle squatStyle;
  final ValueChanged<SquatStyle>? onSquatStyleChanged;

  bool get _isSquat => exercise == ExerciseType.squat;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0D1716);
    const surface = Color(0xFF1B2D28);
    const accent = Color(0xFFC8F38C);
    const muted = Color(0xFFADC1B5);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('BEFORE YOU START',
                    style: TextStyle(color: accent, fontSize: 12,
                        fontWeight: FontWeight.w700, letterSpacing: 1.6)),
                const SizedBox(height: 10),
                Text('Set up your ${exercise.label.toLowerCase()}',
                    style: const TextStyle(color: Colors.white, fontSize: 27,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('A clear view helps the app detect full movements.',
                    style: TextStyle(color: muted, fontSize: 14, height: 1.5)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: surface, borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF34483D))),
                  child: Column(children: [
                    AspectRatio(
                      aspectRatio: 1.75,
                      child: CustomPaint(
                        key: const Key('placement-illustration'),
                        painter: _PlacementPainter(exercise: exercise),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(switch (exercise) {
                        ExerciseType.squat => 'Recommended: front or slight diagonal view',
                        ExerciseType.pushUp => 'Recommended: side or slight diagonal view',
                        ExerciseType.jumpingJack => 'Recommended: full-body front view',
                        ExerciseType.plank => 'Recommended: side view at body height',
                      },
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: accent,
                          fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 20),
                if (_isSquat) ...[
                  const Text('SQUAT STYLE', style: TextStyle(
                    color: muted, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final style in SquatStyle.values)
                      ChoiceChip(
                        key: Key('squat-style-${style.name}'),
                        label: Text(style.label),
                        selected: squatStyle == style,
                        onSelected: onSquatStyleChanged == null
                            ? null
                            : (_) => onSquatStyleChanged!(style),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Choose your planned stance. Counting profiles '
                      'are experimental; unsupported variations may need '
                      'a different exercise profile.',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 18),
                ],
                _Instruction(icon: Icons.fullscreen,
                    text: 'Keep your entire body inside the frame.'),
                const SizedBox(height: 10),
                _Instruction(icon: Icons.phone_android,
                    text: switch (exercise) {
                      ExerciseType.squat => 'Place the phone in front of you, far enough to show hips, knees and ankles.',
                      ExerciseType.pushUp => 'Place the phone at body height to show arms, hips and feet.',
                      ExerciseType.jumpingJack => 'Stand back with space for fully raised arms and wide feet.',
                      ExerciseType.plank => 'Place the phone sideways at body height; include shoulders, hips and ankles.',
                    },),
                const SizedBox(height: 10),
                const _Instruction(icon: Icons.light_mode_outlined,
                    text: 'Use even lighting and avoid blocking your joints.'),
                const SizedBox(height: 20),
                const Text('Counting may be less reliable if joints are hidden '
                    'or your movement is too fast for the camera.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onBegin,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Begin tracking'),
                  style: FilledButton.styleFrom(
                      backgroundColor: accent, foregroundColor: background,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                ),
                const SizedBox(height: 8),
                const Text('Rear camera opens first. You can switch cameras '
                    'during the workout.', textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 21, color: const Color(0xFFC8F38C)),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: const TextStyle(
          color: Colors.white, height: 1.45))),
    ],
  );
}

class _PlacementPainter extends CustomPainter {
  const _PlacementPainter({required this.exercise});
  final ExerciseType exercise;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 320;
    final sy = size.height / 180;
    canvas.save();
    canvas.scale(sx, sy);
    final grid = Paint()..color = const Color(0xFF3A554A)
      ..strokeWidth = 0.75;
    for (var x = 20.0; x < 320; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, 180), grid);
    }
    for (var y = 20.0; y < 180; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(320, y), grid);
    }
    final joints = Paint()..color = const Color(0xFFC8F38C)
      ..strokeWidth = 5..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final point = Paint()..color = const Color(0xFFC8F38C);
    void line(double ax, double ay, double bx, double by) {
      canvas.drawLine(Offset(ax, ay), Offset(bx, by), joints);
      canvas.drawCircle(Offset(ax, ay), 4, point);
      canvas.drawCircle(Offset(bx, by), 4, point);
    }
    final phone = Paint()..color = const Color(0xFFE7F1E9)
      ..strokeWidth = 2..style = PaintingStyle.stroke;
    if (exercise == ExerciseType.plank) {
      // Straight side-on forearm plank, not a push-up bend.
      canvas.drawLine(const Offset(28, 158), const Offset(290, 158), grid);
      canvas.drawCircle(const Offset(70, 81), 13, joints);
      line(83, 91, 115, 100);
      line(115, 100, 183, 104);
      line(183, 104, 255, 112);
      line(115, 100, 108, 133);
      line(108, 133, 143, 151);
      line(255, 112, 273, 157);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 114, 18, 36), const Radius.circular(3)), phone);
    } else if (exercise == ExerciseType.pushUp) {
      // Side-on push-up, ground plane and a small camera/phone.
      canvas.drawLine(const Offset(28, 158), const Offset(290, 158), grid);
      canvas.drawCircle(const Offset(65, 80), 14, joints);
      line(80, 91, 140, 102);
      line(140, 102, 220, 108);
      line(220, 108, 270, 150);
      line(115, 98, 109, 129);
      line(109, 129, 102, 154);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 114, 18, 36), const Radius.circular(3)), phone);
      canvas.drawCircle(const Offset(27, 144), 1.5, point);
    } else if (exercise == ExerciseType.jumpingJack) {
      canvas.drawCircle(const Offset(155, 27), 12, joints);
      line(155, 40, 155, 95);
      line(155, 55, 112, 30);
      line(112, 30, 91, 10);
      line(155, 55, 198, 30);
      line(198, 30, 219, 10);
      line(155, 95, 124, 133);
      line(124, 133, 92, 158);
      line(155, 95, 186, 133);
      line(186, 133, 218, 158);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(260, 116, 18, 36), const Radius.circular(3)), phone);
    } else {
      // A squat from a frontal view with hips/knees/ankles in frame.
      canvas.drawCircle(const Offset(155, 34), 13, joints);
      line(155, 49, 155, 98);
      line(155, 60, 117, 86);
      line(117, 86, 99, 104);
      line(155, 60, 193, 86);
      line(193, 86, 211, 104);
      line(155, 98, 133, 130);
      line(133, 130, 118, 160);
      line(155, 98, 177, 130);
      line(177, 130, 192, 160);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(244, 126, 20, 37), const Radius.circular(3)), phone);
      canvas.drawCircle(const Offset(254, 157), 1.5, point);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlacementPainter oldDelegate) =>
      oldDelegate.exercise != exercise;
}
