/// Accumulates only intervals explicitly marked as active by the camera.
/// Uses a monotonic Stopwatch in production and accepts an injected clock
/// for deterministic unit tests. Does not depend on timer tick frequency.
class SessionActiveClock {
  SessionActiveClock({Duration Function()? monotonicNow}) {
    _timeline.start();
    _now = monotonicNow ?? () => _timeline.elapsed;
  }

  final Stopwatch _timeline = Stopwatch();
  late final Duration Function() _now;
  Duration _accumulated = Duration.zero;
  Duration? _startedAt;

  bool get isActive => _startedAt != null;

  Duration get elapsed {
    final currentStart = _startedAt;
    if (currentStart == null) return _accumulated;
    final delta = _now() - currentStart;
    return _accumulated + (delta.isNegative ? Duration.zero : delta);
  }

  void setActive(bool active) {
    if (active == isActive) return;
    if (active) {
      _startedAt = _now();
    } else {
      _accumulated = elapsed;
      _startedAt = null;
    }
  }
}
