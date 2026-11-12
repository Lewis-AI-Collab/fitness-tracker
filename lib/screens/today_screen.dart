import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/training.dart';
import '../models/workout.dart';
import '../services/dates.dart';
import '../services/speech_capture.dart';
import '../services/voice_audio.dart';
import '../services/voice_log_flow.dart';
import '../services/voice_parser.dart';
import '../services/workout_recorder.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_action.dart';
import '../widgets/confirm_card.dart';
import '../widgets/set_log.dart';
import '../widgets/share_deck.dart';
import 'checkin_screen.dart';
import 'routine_editor_screen.dart';
import 'workout_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.store,
    required this.speech,
    this.recorder,
  });

  final Store store;
  final SpeechCapture speech;
  final WorkoutRecorder? recorder;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DayBundle? _day;
  var _listening = false;
  VoiceLogFlow? _flow;
  late final WorkoutRecorder _recorder =
      widget.recorder ??
      SpeechWorkoutRecorder(widget.speech, audio: RecordVoiceAudio());

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) {
      setState(() {});
    }
    _load();
  }

  Future<void> _load() async {
    final day = await widget.store.loadDay(widget.store.now());
    if (mounted) {
      setState(() => _day = day);
    }
  }

  Future<void> _holdStart() async {
    final last = await widget.store.lastExercise();
    _flow = VoiceLogFlow(
      onStop: () {
        widget.speech.stop();
      },
      onConfirm: (text) => _confirm(text, last),
    );
    setState(() => _listening = true);
    try {
      await widget.speech.start(
        onText: (words, isFinal) => _flow?.onSpeech(words, isFinal: isFinal),
      );
    } on Object {
      if (mounted) {
        setState(() => _listening = false);
      }
    }
  }

  void _holdEnd() {
    _flow?.onRelease(_flow?.latest ?? '');
    if (mounted) {
      setState(() => _listening = false);
    }
  }

  Future<void> _confirm(String text, Exercise? last) async {
    if (mounted) {
      setState(() => _listening = false);
    }
    final parser = VoiceParser(
      widget.store.exercises,
      roundMinutes: widget.store.roundMinutes,
    );
    final result = parser.parse(text, lastExercise: last);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => ConfirmCard(
        result: result,
        exercises: widget.store.exercises,
        onAlias: widget.store.addAlias,
        onSave: (draft) => widget.store.saveParse(draft),
      ),
    );
  }

  Future<void> _edit(Session session) async {
    final result = sessionToParseResult(session);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => ConfirmCard(
        result: result,
        exercises: widget.store.exercises,
        onAlias: widget.store.addAlias,
        onSave: (draft) => widget.store.replaceSession(session.id, draft),
        autoSaveAfter: null,
      ),
    );
  }

  Future<void> _delete(Session session) async {
    final ok = await confirmChoice(context);
    if (!ok) {
      return;
    }
    await widget.store.deleteSession(session.id);
  }

  Future<void> _openWorkout({Routine? routine}) async {
    if (widget.store.activeWorkout == null) {
      widget.store.startWorkout(from: routine);
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            WorkoutScreen(store: widget.store, recorder: _recorder),
      ),
    );
  }

  Future<void> _editRoutine([Routine? routine]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            RoutineEditorScreen(store: widget.store, routine: routine),
      ),
    );
  }

  Future<void> _deleteRoutine(Routine routine) async {
    final ok = await confirmChoice(context);
    if (!ok) {
      return;
    }
    await widget.store.deleteRoutine(routine.id);
  }

  void _openCheckIn(String slot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CheckInScreen(
          store: widget.store,
          slot: slot,
          speech: widget.speech,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    final today = widget.store.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          Tooltip(
            message: 'Log',
            child: GestureDetector(
              key: const ValueKey('mic'),
              onLongPressStart: (_) => _holdStart(),
              onLongPressEnd: (_) => _holdEnd(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.mic,
                  color: _listening
                      ? AppColors.accentPressed
                      : AppColors.accent,
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('share'),
            tooltip: 'Share',
            onPressed: () => showShareDeck(context, widget.store),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            fmtWeekdayDate(today),
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('start-workout'),
            onPressed: () => _openWorkout(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              widget.store.activeWorkout == null
                  ? 'Start workout'
                  : 'Resume workout',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.store.routines.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No routines yet',
                key: ValueKey('no-routines'),
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            for (final routine in widget.store.routines) _routine(routine),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('create-routine'),
              onPressed: () => _editRoutine(),
              child: const Text('Create routine'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _status(
                key: const ValueKey('morning-status'),
                icon: day?.morning == null
                    ? Icons.wb_sunny_outlined
                    : Icons.wb_sunny,
                message: 'Morning',
                done: day?.morning != null,
                onTap: () => _openCheckIn('morning'),
              ),
              _status(
                key: const ValueKey('evening-status'),
                icon: day?.evening == null
                    ? Icons.nightlight_outlined
                    : Icons.nightlight,
                message: 'Evening',
                done: day?.evening != null,
                onTap: () => _openCheckIn('evening'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (day != null)
            for (final plan in day.plans)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  planLine(plan),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          if (day != null)
            for (final session in day.sessions)
              SetLog(
                session: session,
                goals: widget.store.goals,
                store: widget.store,
                onEdit: () => _edit(session),
                onDelete: () => _delete(session),
                onPlayNote: (note) => _recorder.play(
                  audioPath: note.audioPath,
                  transcript: note.transcript,
                ),
                onDeleteNote: (note) => widget.store.deleteVoiceNote(note.id),
              ),
        ],
      ),
    );
  }

  Widget _routine(Routine routine) {
    final names = routine.exercises.map((exercise) => exercise.name).join(', ');
    return Container(
      key: ValueKey('routine-${routine.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      decoration: cardBox(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routine.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (names.isNotEmpty)
                  Text(
                    names,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted),
                  ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('start-routine-${routine.id}'),
            onPressed: () => _openWorkout(routine: routine),
            child: const Text('Start'),
          ),
          IconButton(
            key: ValueKey('edit-routine-${routine.id}'),
            tooltip: 'Edit',
            onPressed: () => _editRoutine(routine),
            icon: const Icon(Icons.edit_outlined, color: AppColors.accent),
          ),
          IconButton(
            key: ValueKey('delete-routine-${routine.id}'),
            tooltip: 'Delete',
            onPressed: () => _deleteRoutine(routine),
            icon: const Icon(Icons.delete_outline, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  Widget _status({
    required Key key,
    required IconData icon,
    required String message,
    required bool done,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: message,
      child: IconButton(
        key: key,
        onPressed: onTap,
        icon: Icon(
          icon,
          color: done ? AppColors.accent : AppColors.muted,
          size: 28,
        ),
      ),
    );
  }
}
