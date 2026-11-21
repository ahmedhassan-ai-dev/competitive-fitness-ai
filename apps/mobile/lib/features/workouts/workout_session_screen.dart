import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/exercise_type.dart';
import '../../shared/ui.dart';
import 'pose_rep_counter.dart';
import 'workout_screens.dart';

class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key, required this.exercise});
  final ExerciseType exercise;

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

  Timer? _timer;
  late final PoseRepCounter _repCounter;
  StreamSubscription<dynamic>? _poseSubscription;
  bool _cameraEnabled = false;
  bool _requestingCamera = false;
  String _cameraMessage = 'Camera is off. Enable it when you are ready.';
  String? _trackingFeedback;
  int _displayedRepCount = 0;
  int _seconds = 0;
  bool _paused = false;
  bool _allowExit = false;
  bool _confirmingExit = false;

  @override
  void initState() {
    super.initState();
    _repCounter = PoseRepCounter(widget.exercise);
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  void _togglePause() {
    final pause = !_paused;
    setState(() {
      _paused = pause;
      if (pause) {
        _cameraEnabled = false;
        _cameraMessage = 'Camera stopped while practice is paused.';
      }
    });
    if (_paused) {
      _timer?.cancel();
      _poseSubscription?.cancel();
      _poseSubscription = null;
    } else {
      _startTimer();
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameraEnabled) {
      setState(() {
        _cameraEnabled = false;
        _cameraMessage = 'Camera stopped.';
        _trackingFeedback = null;
      });
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
      if (!mounted) return;
      setState(() {
        _cameraEnabled = granted;
        _cameraMessage = granted
            ? 'Loading the on-device pose model…'
            : 'Camera permission was not granted.';
        _trackingFeedback = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _cameraMessage =
            error.message ?? 'Could not request camera permission.',
      );
    } on MissingPluginException {
      if (!mounted) return;
      setState(
        () => _cameraMessage = 'Camera tracking is available on Android only.',
      );
    } finally {
      if (mounted) setState(() => _requestingCamera = false);
    }
  }

  void _onPoseViewCreated(int viewId) {
    _poseSubscription?.cancel();
    _poseSubscription = EventChannel('$_poseChannelPrefix/$viewId')
        .receiveBroadcastStream()
        .listen(
          _onPoseEvent,
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _cameraMessage = 'Pose tracking stopped: $error';
              _cameraEnabled = false;
            });
            _poseSubscription?.cancel();
            _poseSubscription = null;
          },
        );
  }

  void _onPoseEvent(dynamic event) {
    if (event is! Map) return;
    if (event['type'] == 'status') {
      final status = event['status'];
      if (status is String && mounted) {
        setState(() {
          _cameraMessage = switch (status) {
            'downloading_model' => 'Downloading the pose model for first use…',
            'ready' => 'Pose model ready.',
            'tracking' => 'On-device pose tracking is active.',
            _ => status,
          };
        });
      }
      return;
    }
    if (event['type'] != 'pose' ||
        event['timestampMs'] is! int ||
        event['landmarks'] is! Map) {
      return;
    }
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

    final update = _repCounter.process(event['timestampMs'] as int, landmarks);
    if (!mounted) return;
    if (_trackingFeedback == update.feedback &&
        _displayedRepCount == update.reps) {
      return;
    }
    setState(() {
      _trackingFeedback = update.feedback;
      _displayedRepCount = update.reps;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_paused) _togglePause();
  }

  @override
  void dispose() {
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
          'Your detected reps will be discarded. The session is paused.',
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
    _timer?.cancel();
    _poseSubscription?.cancel();
    _poseSubscription = null;
    setState(() => _cameraEnabled = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WorkoutSummaryScreen(
          exercise: widget.exercise,
          reps: _repCounter.reps,
          elapsed: Duration(seconds: _seconds),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _confirmExit();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.exercise.label} session'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _confirmExit,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: PageBody(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const Chip(
                avatar: Icon(Icons.science_outlined, size: 18),
                label: Text('On-device tracking'),
              ),
              Chip(label: Text(_paused ? 'Paused' : 'In progress')),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 240,
              child: _cameraEnabled
                  ? AndroidView(
                      viewType: _viewType,
                      onPlatformViewCreated: _onPoseViewCreated,
                    )
                  : ColoredBox(
                      color: const Color(0xFF123D30),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.accessibility_new,
                              size: 48,
                              color: Color(0xFFD2EF89),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Text(
                                _cameraMessage,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          AdaptivePair(
            first: MetricCard(
              value: '${_repCounter.reps}',
              label: 'Detected reps',
            ),
            second: MetricCard(
              value: formatElapsed(Duration(seconds: _seconds)),
              label: 'Elapsed time',
            ),
          ),
          InfoCard(
            icon: Icons.tips_and_updates_outlined,
            title: 'Tracking guidance',
            message: _trackingFeedback ?? 'Face the camera side-on and keep the required joints visible. Rep counts are local and do not assess form quality.',
          ),
          OutlinedButton.icon(
            onPressed: _paused || _requestingCamera ? null : _toggleCamera,
            icon: Icon(_cameraEnabled ? Icons.videocam_off : Icons.videocam),
            label: Text(
              _requestingCamera
                  ? 'Requesting permission…'
                  : _cameraEnabled
                  ? 'Stop camera'
                  : 'Enable camera',
            ),
          ),
          OutlinedButton.icon(
            onPressed: _togglePause,
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            label: Text(_paused ? 'Resume' : 'Pause'),
          ),
          TextButton(onPressed: _finish, child: const Text('Finish workout')),
        ],
      ),
    ),
  );
}
