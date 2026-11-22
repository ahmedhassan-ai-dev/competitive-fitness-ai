import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/exercise_type.dart';
import '../../shared/ui.dart';
import 'pose_rep_counter.dart';
import 'additional_exercise_tracker.dart';
import 'pose_diagnostics.dart';
import 'workout_setup_guide.dart';
import 'session_active_clock.dart';
import 'workout_screens.dart';

// FEATURE-001A: presentation and camera selection only.
// Counting thresholds and the exercise wire contract remain unchanged.
class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key, required this.exercise, this.roomId});

  final ExerciseType exercise;
  final String? roomId;

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen>
    with WidgetsBindingObserver {
  static const _permissionChannel = MethodChannel(
    'competitive_fitness/camera_permission',
  );
  static const _viewType = 'competitive_fitness/pose_camera';
  static const _poseChannelPrefix = 'competitive_fitness/pose';
  static const _controlChannelPrefix =
      'competitive_fitness/pose_camera_control';

  static const _background = Color(0xFF0D1716);
  static const _panel = Color(0xFF1B2D28);
  static const _lime = Color(0xFFC8F38C);
  static const _muted = Color(0xFFA8BAB1);

  Timer? _timer;
  final SessionActiveClock _sessionClock = SessionActiveClock();
  final Stopwatch _poseHeartbeat = Stopwatch()..start();
  int? _lastPoseFrameMs;
  static const _maxFrameSilenceMs = 1500;
  late PoseRepCounter _repCounter;
  AdditionalExerciseTracker? _additionalTracker;
  int _displayedHoldMs = 0;
  SquatStyle _squatStyle = SquatStyle.standard;
  StreamSubscription<dynamic>? _poseSubscription;
  int? _activeViewId;
  bool _cameraEnabled = false;
  bool _requestingCamera = false;
  bool _switchingCamera = false;
  bool _trackingActive = false;
  bool _poseVisible = false;
  String _cameraLens = 'back';
  String _cameraMessage = 'Enable camera when you are ready.';
  String? _trackingFeedback;
  int _displayedRepCount = 0;
  int _seconds = 0;
  bool _paused = false;
  bool _restartCameraAfterPause = false;
  bool _allowExit = false;
  bool _confirmingExit = false;
  bool _showDiagnostics = false;
  bool _setupAcknowledged = false;
  PoseDiagnostics? _diagnostics;

  @override
  void initState() {
    super.initState();
    _repCounter = PoseRepCounter(
      widget.exercise == ExerciseType.squat ? ExerciseType.squat : ExerciseType.pushUp,
    );
    if (widget.exercise == ExerciseType.jumpingJack) {
      _additionalTracker = JumpingJackTracker();
    } else if (widget.exercise == ExerciseType.plank) {
      _additionalTracker = PlankTracker();
    }
    WidgetsBinding.instance.addObserver(this);
    // Do not open the camera until the user has seen exercise-specific
    // placement guidance. Active time stays at zero during setup.
  }

  bool get _hasRecentPoseFrame =>
      _lastPoseFrameMs != null &&
      _poseHeartbeat.elapsedMilliseconds - _lastPoseFrameMs! <=
          _maxFrameSilenceMs;

  // Only live camera frames count as workout time. A stalled preview,
  // loading model, camera switch, backgrounded app or paused session stops
  // the monotonic stopwatch. The periodic Timer ONLY refreshes the display.
  void _syncSessionClock() {
    final shouldRun = mounted && !_paused && _cameraEnabled &&
        _trackingActive && !_switchingCamera && _hasRecentPoseFrame;
    _sessionClock.setActive(shouldRun);
    if (shouldRun) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) _syncSessionClock();
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    final elapsedSeconds = _sessionClock.elapsed.inSeconds;
    if (mounted && elapsedSeconds != _seconds) {
      setState(() => _seconds = elapsedSeconds);
    }
  }

  void _togglePause() {
    final pause = !_paused;
    if (pause) _restartCameraAfterPause = _cameraEnabled;
    if (pause) _additionalTracker?.interrupt();
    setState(() {
      _paused = pause;
      if (pause) {
        _cameraEnabled = false;
        _trackingActive = false;
        _poseVisible = false;
        _lastPoseFrameMs = null;
        _activeViewId = null;
        _trackingFeedback = null;
        _diagnostics = null;
        _cameraMessage = 'Camera stopped while practice is paused.';
      }
    });
    _syncSessionClock();
    if (pause) {
      _poseSubscription?.cancel();
      _poseSubscription = null;
    } else if (_restartCameraAfterPause) {
      // Resume opens the camera again, but the session clock stays frozen
      // until actual frames arrive from the new native platform view.
      _restartCameraAfterPause = false;
      _toggleCamera();
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameraEnabled) {
      _additionalTracker?.interrupt();
      setState(() {
        _cameraEnabled = false;
        _activeViewId = null;
        _trackingActive = false;
        _poseVisible = false;
        _lastPoseFrameMs = null;
        _trackingFeedback = null;
        _diagnostics = null;
        _cameraMessage = 'Camera stopped.';
      });
      _syncSessionClock();
      await _poseSubscription?.cancel();
      _poseSubscription = null;
      return;
    }

    setState(() => _requestingCamera = true);
    try {
      final granted =
          await _permissionChannel.invokeMethod<bool>(
            'requestCameraPermission',
          ) ??
          false;
      if (!mounted || _paused) return;
      setState(() {
        _cameraEnabled = granted;
        _cameraLens = 'back';
        _trackingActive = false;
        _poseVisible = false;
        _lastPoseFrameMs = null;
        _cameraMessage = granted
            ? 'Loading the on-device pose model…'
            : 'Camera permission was not granted.';
        _trackingFeedback = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _cameraMessage =
          error.message ?? 'Could not request camera permission.');
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _cameraMessage =
          'Camera tracking is available on Android only.');
    } finally {
      if (mounted) {
        setState(() => _requestingCamera = false);
        _syncSessionClock();
      }
    }
  }

  Future<void> _switchCamera() async {
    final viewId = _activeViewId;
    if (viewId == null || !_cameraEnabled || !_trackingActive ||
        _paused || _switchingCamera) {
      return;
    }
    _additionalTracker?.interrupt();
    setState(() {
      _switchingCamera = true;
      _trackingActive = false;
      _poseVisible = false;
      _lastPoseFrameMs = null;
      _trackingFeedback = null;
      _diagnostics = null;
      _cameraMessage = 'Switching camera…';
    });
    _syncSessionClock();
    try {
      final facing = await MethodChannel('$_controlChannelPrefix/$viewId')
          .invokeMethod<String>('switchCamera');
      if (!mounted || !_cameraEnabled || _activeViewId != viewId) return;
      setState(() {
        if (facing == 'front' || facing == 'back') _cameraLens = facing!;
        _cameraMessage = 'Camera ready. Keep your body in frame.';
      });
    } on PlatformException catch (error) {
      if (!mounted || !_cameraEnabled) return;
      setState(() {
        _cameraMessage = error.message ?? 'Could not switch camera.';
        _trackingFeedback = _cameraMessage;
        // An unavailable lens leaves the previous stream running; a failed
        // rebind requires a camera restart instead of showing a false green state.
        _trackingActive = error.code == 'camera_unavailable';
      });
    } on MissingPluginException {
      if (!mounted || !_cameraEnabled) return;
      setState(() {
        _cameraMessage = 'Camera switching requires the updated Android app.';
        _trackingFeedback = _cameraMessage;
        _trackingActive = false;
      });
    } finally {
      if (mounted) {
        setState(() => _switchingCamera = false);
        _syncSessionClock();
      }
    }
  }

  void _onPoseViewCreated(int viewId) {
    if (!mounted || !_cameraEnabled || _paused) return;
    _poseSubscription?.cancel();
    _activeViewId = viewId;
    _poseSubscription = EventChannel('$_poseChannelPrefix/$viewId')
        .receiveBroadcastStream()
        .listen(
          _onPoseEvent,
          onError: (Object error) {
            if (!mounted || _activeViewId != viewId) return;
            setState(() {
              _cameraMessage = 'Pose tracking stopped: $error';
              _cameraEnabled = false;
              _activeViewId = null;
              _trackingActive = false;
              _poseVisible = false;
              _lastPoseFrameMs = null;
            });
            _syncSessionClock();
            _poseSubscription?.cancel();
            _poseSubscription = null;
          },
        );
  }

  void _onPoseEvent(dynamic event) {
    if (!mounted || !_cameraEnabled || _paused || event is! Map) return;
    if (event['type'] == 'diagnostics') {
      final metrics = PoseDiagnostics.fromEvent(event);
      if (metrics != null) setState(() => _diagnostics = metrics);
      return;
    }
    if (event['type'] == 'lens') {
      final facing = event['facing'];
      if (facing == 'front' || facing == 'back') {
        setState(() => _cameraLens = facing as String);
      }
      return;
    }
    if (event['type'] == 'status') {
      final status = event['status'];
      if (status is String) {
        setState(() {
          _trackingActive = status == 'tracking';
          if (!_trackingActive) _lastPoseFrameMs = null;
          _cameraMessage = switch (status) {
            'downloading_model' => 'Preparing the on-device pose model…',
            'ready' => 'Pose model ready. Starting camera…',
            'waiting_for_preview' => 'Waiting for camera preview…',
            'tracking' => 'Tracking is active. Keep your body in view.',
            _ => status,
          };
        });
        _syncSessionClock();
      }
      return;
    }
    if (event['type'] != 'pose' ||
        event['timestampMs'] is! int ||
        event['landmarks'] is! Map) {
      return;
    }
    _lastPoseFrameMs = _poseHeartbeat.elapsedMilliseconds;
    _syncSessionClock();
    final landmarks = <String, PosePoint>{};
    for (final entry in (event['landmarks'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String || value is! Map) continue;
      final x = value['x'];
      final y = value['y'];
      final confidence = value['confidence'];
      if (x is num && y is num && confidence is num) {
        landmarks[entry.key as String] = PosePoint(
          x: x.toDouble(),
          y: y.toDouble(),
          confidence: confidence.toDouble(),
        );
      }
    }

    PoseRepUpdate update;
    if (_additionalTracker != null) {
      final result = _additionalTracker!.process(
        event['timestampMs'] as int, landmarks,
      );
      update = PoseRepUpdate(reps: result.reps, feedback: result.feedback);
    } else {
      update = _repCounter.process(event['timestampMs'] as int, landmarks);
    }
    final holdMs = _additionalTracker?.holdMs ?? 0;
    final visible = landmarks.isNotEmpty;
    if (_poseVisible == visible &&
        _trackingFeedback == update.feedback &&
        _displayedRepCount == update.reps &&
        (_displayedHoldMs ~/ 1000) == (holdMs ~/ 1000)) {
      return;
    }
    setState(() {
      _poseVisible = visible;
      _trackingFeedback = update.feedback;
      _displayedRepCount = update.reps;
      _displayedHoldMs = holdMs;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_paused) _togglePause();
  }

  @override
  void dispose() {
    _sessionClock.setActive(false);
    _timer?.cancel();
    _poseSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _confirmExit() async {
    if (_confirmingExit) return;
    _confirmingExit = true;
    if (!_paused) _togglePause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this practice?'),
        content: const Text(
          'Your detected workout result will be discarded. The session is paused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep practicing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave practice'),
          ),
        ],
      ),
    );
    _confirmingExit = false;
    if (leave == true && mounted) {
      setState(() => _allowExit = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _finish() {
    _sessionClock.setActive(false);
    _seconds = _sessionClock.elapsed.inSeconds;
    _timer?.cancel();
    _poseSubscription?.cancel();
    _poseSubscription = null;
    setState(() => _cameraEnabled = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WorkoutSummaryScreen(
          exercise: widget.exercise,
          roomId: widget.roomId,
          reps: _additionalTracker?.reps ?? _repCounter.reps,
          holdSeconds: (_additionalTracker?.holdMs ?? 0) ~/ 1000,
          elapsed: Duration(seconds: _seconds),
        ),
      ),
    );
  }

  String get _trackingLabel {
    if (_paused) return 'Paused';
    if (!_cameraEnabled) return 'Camera off';
    if (!_trackingActive) return 'Connecting';
    if (!_hasRecentPoseFrame) return 'Waiting for frames';
    if (_poseVisible && _trackingFeedback == null) return 'Pose detected';
    if (_poseVisible) return 'Adjust position';
    return 'Find your position';
  }

  String get _guidance {
    if (_cameraEnabled && !_trackingActive) return _cameraMessage;
    if (_trackingFeedback != null) return _trackingFeedback!;
    return switch (widget.exercise) {
      ExerciseType.squat => 'Keep your hips, knees and ankles visible.',
      ExerciseType.pushUp => 'Keep your shoulders, elbows and wrists visible.',
      ExerciseType.jumpingJack => 'Face the camera with arms and feet fully in frame.',
      ExerciseType.plank => 'Turn sideways and keep your body in a straight line.',
    };
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _confirmExit();
    },
    child: Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.exercise.label} session',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _confirmExit,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: _showDiagnostics ? 'Hide diagnostics' : 'Show diagnostics',
            onPressed: () => setState(() => _showDiagnostics = !_showDiagnostics),
            icon: Icon(_showDiagnostics ? Icons.speed : Icons.speed_outlined),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _cameraEnabled && _trackingActive &&
                    !_switchingCamera && !_paused
                ? _switchCamera
                : null,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_setupAcknowledged
          ? WorkoutSetupGuide(
              squatStyle: _squatStyle,
              onSquatStyleChanged: (style) {
                setState(() {
                  _squatStyle = style;
                  if (widget.exercise == ExerciseType.squat) {
                    _repCounter = PoseRepCounter(widget.exercise, squatStyle: style);
                  }
                });
              },
              exercise: widget.exercise,
              onBegin: () {
                setState(() => _setupAcknowledged = true);
                _toggleCamera();
              },
            )
          : SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'LIVE PRACTICE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: _muted,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TrackingPill(
                          label: _trackingLabel,
                          active: _poseVisible && _trackingActive &&
                              _trackingFeedback == null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_cameraEnabled)
                              AndroidView(
                                viewType: _viewType,
                                onPlatformViewCreated: _onPoseViewCreated,
                              )
                            else
                              ColoredBox(
                                color: _panel,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.accessibility_new_outlined,
                                          size: 64,
                                          color: _lime,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _cameraMessage,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            // Place metrics above the native skeleton overlay
                            // without intercepting touches to the camera.
                            IgnorePointer(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    16, 45, 16, 16),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Color(0xDD06130F),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          widget.exercise.isHold
                      ? '${_displayedHoldMs ~/ 1000}'
                      : '$_displayedRepCount',
                                          style: const TextStyle(
                                            fontSize: 80,
                                            height: 1,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        widget.exercise.isHold ? 'HOLD SECONDS' : 'REPS',
                                        style: TextStyle(
                                          fontSize: 11,
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.w700,
                                          color: _lime,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 14,
                              left: 14,
                              child: _CameraLabel(
                                label: _cameraLens == 'front'
                                    ? 'Front camera'
                                    : 'Back camera',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showDiagnostics) ...[
                      const SizedBox(height: 10),
                      Semantics(
                        label: 'Pose performance diagnostics',
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _diagnostics == null
                                ? 'Diagnostics: waiting for 2+ tracked frames…'
                                : 'Processed: ${_diagnostics!.processedFps.toStringAsFixed(1)} FPS  ·  '
                                    'Pre: ${_diagnostics!.preprocessMs.toStringAsFixed(1)} ms  ·  '
                                    'AI: ${_diagnostics!.inferenceMs.toStringAsFixed(1)} ms\n'
                                    'Pipeline P95: ${_diagnostics!.pipelineP95Ms.toStringAsFixed(1)} ms  ·  '
                                    'Pose: ${_diagnostics!.poseRatePercent.toStringAsFixed(0)}% '
                                    '(n=${_diagnostics!.sampleCount})',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: _lime,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CAMERA ACTIVE TIME',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                    color: _muted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatElapsed(Duration(seconds: _seconds)),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.shield_outlined,
                            size: 22,
                            color: _muted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.center_focus_strong,
                            color: _lime,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'POSITION GUIDE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _lime,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _paused ? 'Resume to keep tracking.' : _guidance,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: _paused || _requestingCamera ||
                              _switchingCamera
                          ? null
                          : _toggleCamera,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF587269)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_cameraEnabled
                              ? Icons.videocam_off_outlined
                              : Icons.videocam_outlined),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _requestingCamera
                                  ? 'Requesting permission…'
                                  : _cameraEnabled
                                      ? 'Stop camera'
                                      : 'Enable camera',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, limits) {
                        final stacked = limits.maxWidth < 430 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3;
                        final pauseButton = OutlinedButton(
                          onPressed: _togglePause,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF587269)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_paused
                                  ? Icons.play_arrow
                                  : Icons.pause_outlined),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _paused ? 'Resume' : 'Pause',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                        final finishButton = FilledButton(
                          onPressed: _finish,
                          style: FilledButton.styleFrom(
                            backgroundColor: _lime,
                            foregroundColor: _background,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Finish workout',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                        if (stacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              pauseButton,
                              const SizedBox(height: 8),
                              finishButton,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: pauseButton),
                            const SizedBox(width: 10),
                            Expanded(child: finishButton),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Counts are estimated on this device. Form quality and '
                      'challenge scores are not verified.',
                      style: TextStyle(color: _muted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ),
    ),
  );
}

class _TrackingPill extends StatelessWidget {
  const _TrackingPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF22372F),
      borderRadius: BorderRadius.circular(40),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: active ? const Color(0xFFC8F38C) : const Color(0xFF8EAAA0),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}

class _CameraLabel extends StatelessWidget {
  const _CameraLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xD611231D),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}
