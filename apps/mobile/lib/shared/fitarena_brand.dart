import 'package:flutter/material.dart';

/// FitArena visual identity shared by the welcome, authentication and home screens.
class FitArenaMark extends StatelessWidget {
  const FitArenaMark({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/fitarena_mark.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
  );
}

class FitArenaBrandHeader extends StatelessWidget {
  const FitArenaBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FitArenaMark(size: compact ? 28 : 36),
        SizedBox(width: compact ? 6 : 8),
        Flexible(
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: const Text(
              'FitArena',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Color(0xFF113B38),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
