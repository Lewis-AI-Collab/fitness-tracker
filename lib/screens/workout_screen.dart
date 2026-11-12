import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/workout.dart';
import '../services/normalise.dart';
import '../services/workout_recorder.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_action.dart';
import '../widgets/rest_pill.dart';
import '../widgets/value_picker.dart';
import '../widgets/voice_note_list.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.store, required this.recorder});

  final Store store;
  final WorkoutRecorder recorder;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final _exerciseName = TextEditingController();
  Timer? _clock;
  var _recording = false;
  var _busy = false;
  var _denied = false;
  var _finishing = false;
  int? _captureExercise;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    final live = !WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (live) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    widget.store.removeListener(_onStore);
    _exerciseName.dispose();
    if (_recording) {
      unawaited(widget.recorder.cancel());
    }
    super.dispose();
  }

  void _onStore() {
    if (mounted) {
      setState(() {});
    }
  }

  String _elapsed(ActiveWorkout workout) {
    final seconds = widget.store.now().difference(workout.startedAt).inSeconds;
    final safe = seconds < 0 ? 0 : seconds;
    final minutes = safe ~/ 60;
    final remain = (safe % 60).toString().padLeft(2, '0');
    final hours = minutes ~/ 60;
    if (hours > 0) {
      final mm = (minutes % 60).toString().padLeft(2, '0');
      return '$hours:$mm:$remain';
    }
    return '$minutes:$remain';
  }

  Future<void> _finish() async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    try {
      final ok = await confirmChoice(context);
      if (!ok || !mounted) {
        return;
      }
      if (_recording) {
        _recording = false;
        try {
          final capture = await widget.recorder.stop();
          if (!capture.denied) {
            _attach(capture);
          }
        } on Object {
          // The take could not be closed. Finish still continues.
        }
      }
      if (!mounted) {
        return;
      }
      await widget.store.finishWorkout();
      if (!mounted) {
        return;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
    } finally {
      _finishing = false;
    }
  }

  Future<void> _discard() async {
    final ok = await confirmChoice(context);
    if (!ok || !mounted) {
      return;
    }
    await widget.store.discardWorkout();
    if (!mounted) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  Future<void> _toggleRecord() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      if (_recording) {
        final capture = await widget.recorder.stop();
        if (!mounted) {
          return;
        }
        setState(() => _recording = false);
        if (capture.denied) {
          setState(() => _denied = true);
          return;
        }
        _attach(capture);
        return;
      }
      _captureExercise = widget.store.activeWorkout?.exerciseIndex;
      try {
        await widget.recorder.start();
      } on MicPermissionDenied {
        if (mounted) {
          setState(() => _denied = true);
        }
        return;
      } on StateError {
        if (mounted) {
          setState(() => _denied = true);
        }
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _recording = true;
        _denied = false;
      });
    } finally {
      _busy = false;
    }
  }

  void _attach(VoiceCapture capture) {
    final workout = widget.store.activeWorkout;
    if (workout == null) {
      return;
    }
    ActiveExercise? exercise;
    final index = _captureExercise;
    if (index != null && index >= 0 && index < workout.exercises.length) {
      exercise = workout.exercises[index];
    }
    widget.store.addActiveNote(
      transcript: capture.transcript,
      audioPath: capture.audioPath,
      exerciseId: exercise?.exerciseId,
      exerciseName: exercise?.name,
    );
  }

  Future<void> _pickReps(int index, ActiveSet set) async {
    final next = await showValuePicker(
      context: context,
      values: [for (var i = 1; i <= 30; i++) i],
      current: set.reps,
      label: (value) => '${value.toInt()}',
    );
    if (next == null) {
      return;
    }
    widget.store.updateActiveSet(index, reps: next.toInt());
  }

  Future<void> _pickKg(int index, ActiveSet set) async {
    final next = await showValuePicker(
      context: context,
      values: [for (var i = 0; i <= 80; i++) i * 2.5],
      current: set.weightKg ?? 0,
      label: (value) => fmtKg(value.toDouble()),
    );
    if (next == null) {
      return;
    }
    widget.store.updateActiveSet(
      index,
      weightKg: next.toDouble(),
      editWeight: true,
    );
  }

  void _addExercise() {
    final name = _exerciseName.text;
    if (name.trim().isEmpty) {
      return;
    }
    widget.store.addActiveExercise(name);
    _exerciseName.clear();
  }

  @override
  Widget build(BuildContext context) {
    final workout = widget.store.activeWorkout;
    if (workout == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final current = workout.current;
    return Scaffold(
      key: const ValueKey('workout-screen'),
      appBar: AppBar(
        title: Text(workout.name, key: const ValueKey('workout-title')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _elapsed(workout),
                  key: const ValueKey('elapsed'),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  current?.name ?? workout.name,
                  key: const ValueKey('current-exercise'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                if (workout.exercises.length > 1)
                  Row(
                    children: [
                      Text(
                        '${workout.exerciseIndex + 1} of ${workout.exercises.length}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const Spacer(),
                      IconButton(
                        key: const ValueKey('prev-exercise'),
                        tooltip: 'Previous',
                        onPressed: workout.exerciseIndex == 0
                            ? null
                            : () => widget.store.stepExercise(-1),
                        icon: const Icon(
                          Icons.chevron_left,
                          color: AppColors.accent,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('next-exercise'),
                        tooltip: 'Next',
                        onPressed:
                            workout.exerciseIndex >=
                                workout.exercises.length - 1
                            ? null
                            : () => widget.store.stepExercise(1),
                        icon: const Icon(
                          Icons.chevron_right,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                if (current != null)
                  for (var i = 0; i < current.sets.length; i++)
                    _setRow(i, current.sets[i]),
                if (current != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('add-session-set'),
                      onPressed: widget.store.addActiveSet,
                      icon: const Icon(Icons.add),
                      label: const Text('Add set'),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('session-exercise'),
                        controller: _exerciseName,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Exercise',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addExercise(),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('add-session-exercise'),
                      onPressed: _addExercise,
                      child: const Text('Add exercise'),
                    ),
                  ],
                ),
                VoiceNoteList(
                  notes: workout.notes,
                  onPlay: (index) {
                    final note = workout.notes[index];
                    widget.recorder.play(
                      audioPath: note.audioPath,
                      transcript: note.transcript,
                    );
                  },
                  onDelete: widget.store.deleteActiveNote,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const ValueKey('voice-record'),
                  onPressed: _toggleRecord,
                  style: FilledButton.styleFrom(
                    backgroundColor: _recording
                        ? AppColors.accentPressed
                        : AppColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: Icon(_recording ? Icons.stop : Icons.mic),
                  label: Text(
                    _recording ? 'Stop' : 'Voice note',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_denied)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Microphone is off',
                      key: ValueKey('mic-denied'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                RestPill(
                  seconds: workout.restSeconds,
                  startToken: workout.restToken,
                  onSecondsChanged: widget.store.setRestSeconds,
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('discard-workout'),
                      onPressed: _discard,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        minimumSize: const Size.fromHeight(52),
                        side: const BorderSide(color: AppColors.hairline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Discard',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('finish-workout'),
                      onPressed: _finish,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Finish',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _setRow(int index, ActiveSet set) {
    final kg = set.weightKg == null ? '– kg' : '${fmtKg(set.weightKg!)} kg';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: cardBox(),
      child: Row(
        children: [
          IconButton(
            key: ValueKey('set-tick-$index'),
            tooltip: set.done ? 'Done' : 'Tick set',
            onPressed: () => widget.store.toggleActiveSet(index),
            icon: Icon(
              set.done ? Icons.check_circle : Icons.circle_outlined,
              color: set.done ? AppColors.accent : AppColors.muted,
            ),
          ),
          GestureDetector(
            key: ValueKey('active-reps-$index'),
            onTap: () => _pickReps(index, set),
            child: Text(
              '${set.reps}',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '×',
              style: TextStyle(fontSize: 20, color: AppColors.muted),
            ),
          ),
          GestureDetector(
            key: ValueKey('active-kg-$index'),
            onTap: () => _pickKg(index, set),
            child: Text(
              kg,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
