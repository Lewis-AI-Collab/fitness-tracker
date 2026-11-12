import 'package:fitness_tracker/data/store.dart';
import 'package:fitness_tracker/models/workout.dart';
import 'package:fitness_tracker/screens/today_screen.dart';
import 'package:fitness_tracker/screens/workout_screen.dart';
import 'package:fitness_tracker/services/speech_capture.dart';
import 'package:fitness_tracker/services/workout_recorder.dart';
import 'package:fitness_tracker/theme/app_theme.dart';
import 'package:fitness_tracker/widgets/rest_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

class FakeWorkoutRecorder implements WorkoutRecorder {
  FakeWorkoutRecorder({
    this.transcript = 'left knee tight',
    this.audioPath = 'note.m4a',
    this.deny = false,
  });

  final String transcript;
  final String? audioPath;
  final bool deny;
  var starts = 0;
  var plays = 0;
  String? lastPath;
  String? lastTranscript;

  @override
  Future<void> start() async {
    starts++;
    if (deny) {
      throw const MicPermissionDenied();
    }
  }

  @override
  Future<VoiceCapture> stop() async {
    if (deny) {
      return const VoiceCapture(denied: true);
    }
    return VoiceCapture(transcript: transcript, audioPath: audioPath);
  }

  @override
  Future<void> play({String? audioPath, String? transcript}) async {
    plays++;
    lastPath = audioPath;
    lastTranscript = transcript;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rest counts down one second at a time and stops at zero', () {
    expect(restSecondsLeft(90), 89);
    expect(restSecondsLeft(2), 1);
    expect(restSecondsLeft(1), 0);
    expect(restSecondsLeft(0), 0);
  });

  testWidgets('today points at routines and hides the rest timer', (
    tester,
  ) async {
    final store = (await tester.runAsync(openStore))!;
    await _mount(tester, store, FakeWorkoutRecorder());

    expect(find.text('No routines yet'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Create routine'), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-pill')), findsNothing);
    expect(find.byTooltip('Rest'), findsNothing);
    expect(find.text('Rest'), findsNothing);
  });

  testWidgets('a routine can be built, reordered, edited and deleted', (
    tester,
  ) async {
    final store = (await tester.runAsync(openStore))!;
    await _mount(tester, store, FakeWorkoutRecorder());

    await tester.tap(find.byKey(const ValueKey('create-routine')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('routine-name')),
      'Week 1 Push',
    );
    await tester.enterText(
      find.byKey(const ValueKey('exercise-name-0')),
      'Bench press',
    );
    await _choose(tester, const ValueKey('set-reps-0-0'), '9');
    await _choose(tester, const ValueKey('set-kg-0-0'), '10');
    await tester.tap(find.byKey(const ValueKey('add-set-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-set-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-set-0-2')));
    await tester.pumpAndSettle();
    await _choose(tester, const ValueKey('set-reps-0-1'), '10');
    await tester.tap(find.byKey(const ValueKey('move-set-up-0-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-exercise')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('exercise-name-1')),
      'Barbell row',
    );
    await tester.tap(find.byKey(const ValueKey('move-exercise-up-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-routine')));
    await _until(
      tester,
      () =>
          store.routines.any((routine) => routine.name == 'Week 1 Push') &&
          find.byKey(const ValueKey('save-routine')).evaluate().isEmpty,
    );

    final saved = store.routines.single;
    expect(saved.exercises.map((exercise) => exercise.name), [
      'Barbell row',
      'Bench press',
    ]);
    expect(saved.exercises[1].sets.map((set) => set.reps), [10, 9]);
    expect(saved.exercises[1].sets.first.weightKg, 10);
    expect(find.text('Week 1 Push'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('edit-routine-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('routine-name')),
      'Week 1 Pull',
    );
    await tester.tap(find.byKey(const ValueKey('save-routine')));
    await _until(tester, () => store.routines.single.name == 'Week 1 Pull');
    expect(store.routines.single.exercises, hasLength(2));

    await tester.tap(find.byKey(ValueKey('delete-routine-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Week 1 Pull'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('delete-routine-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Confirm'));
    await _until(tester, () => store.routines.isEmpty);
    expect(find.text('No routines yet'), findsOneWidget);
  });

  testWidgets(
    'the rest timer is only in a session and finish saves ticked sets',
    (tester) async {
      final store = (await tester.runAsync(() async {
        final store = await openStore();
        final bench = store.exerciseByName('Bench press')!;
        await store.saveRoutine(
          Routine(
            name: 'Push',
            exercises: [
              RoutineExercise(
                exerciseId: bench.id,
                name: bench.name,
                sets: const [
                  RoutineSet(reps: 8, weightKg: 70),
                  RoutineSet(reps: 8, weightKg: 70),
                ],
              ),
            ],
          ),
        );
        store.startWorkout(from: store.routines.single);
        return store;
      }))!;
      await _pumpWorkout(tester, store, FakeWorkoutRecorder());

      expect(find.byKey(const ValueKey('workout-screen')), findsOneWidget);
      expect(find.byKey(const ValueKey('rest-pill')), findsOneWidget);
      expect(find.text('Rest'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('Bench press'), findsOneWidget);
      expect(find.byKey(const ValueKey('elapsed')), findsOneWidget);
      expect(find.byKey(const ValueKey('rest-idle')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rest-more')));
      await tester.pump();
      expect(find.text('1:45'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('active-reps-0')));
      await tester.pump();
      await _tapPick(tester, '9');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('set-tick-0')));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byKey(const ValueKey('rest-running')), findsOneWidget);

      _press(tester, const ValueKey('finish-workout'));
      await tester.pump();
      expect(find.byTooltip('Confirm'), findsOneWidget);
      _pressTooltip(tester, 'Confirm');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

      final day = (await tester.runAsync(
        () => store.loadDay(DateTime(2026, 10, 12)),
      ))!;
      expect(day.sessions, hasLength(1));
      expect(day.sessions.single.sets, hasLength(1));
      expect(day.sessions.single.sets.single.reps, 9);
      expect(day.sessions.single.sets.single.weightKg, 70);
      expect(day.sessions.single.notes, 'Push');
    },
  );

  testWidgets('discard asks before dropping the session', (tester) async {
    final store = (await tester.runAsync(openStore))!;
    store.startWorkout();
    await _pumpWorkout(tester, store, FakeWorkoutRecorder());

    await tester.enterText(find.byKey(const ValueKey('session-exercise')), 'Dip');
    await tester.tap(find.byKey(const ValueKey('add-session-exercise')));
    await tester.pump();
    expect(find.text('Dip'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('set-tick-0')));
    await tester.pump();

    _press(tester, const ValueKey('discard-workout'));
    await tester.pump();
    _pressTooltip(tester, 'Cancel');
    await tester.pump();
    expect(find.byKey(const ValueKey('finish-workout')), findsOneWidget);
    expect(store.activeWorkout, isNotNull);

    _press(tester, const ValueKey('discard-workout'));
    await tester.pump();
    _pressTooltip(tester, 'Confirm');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(store.activeWorkout, isNull);
    final day = (await tester.runAsync(
      () => store.loadDay(DateTime(2026, 10, 12)),
    ))!;
    expect(day.sessions, isEmpty);
  });

  testWidgets(
    'voice notes attach, play and delete, and a denied mic stays quiet',
    (tester) async {
      final store = (await tester.runAsync(() async {
        final store = await openStore();
        final bench = store.exerciseByName('Bench press')!;
        await store.saveRoutine(
          Routine(
            name: 'Push',
            exercises: [
              RoutineExercise(
                exerciseId: bench.id,
                name: bench.name,
                sets: const [RoutineSet(reps: 8, weightKg: 70)],
              ),
            ],
          ),
        );
        store.startWorkout(from: store.routines.single);
        return store;
      }))!;
      final recorder = FakeWorkoutRecorder();
      await _pumpWorkout(tester, store, recorder);

      await tester.tap(find.byKey(const ValueKey('voice-record')));
      await tester.pump();
      expect(find.text('Stop'), findsOneWidget);
      expect(recorder.starts, 1);

      await tester.tap(find.byKey(const ValueKey('voice-record')));
      await tester.pump();
      expect(find.text('Bench press · left knee tight'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('play-note-0')));
      await tester.pump();
      expect(recorder.plays, 1);
      expect(recorder.lastPath, 'note.m4a');
      expect(recorder.lastTranscript, 'left knee tight');

      await tester.tap(find.byKey(const ValueKey('delete-note-0')));
      await tester.pump();
      expect(find.textContaining('left knee tight'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('voice-record')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-record')));
      await tester.pump();
      expect(find.textContaining('left knee tight'), findsOneWidget);

      _press(tester, const ValueKey('finish-workout'));
      await tester.pump();
      _pressTooltip(tester, 'Confirm');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

      var day = (await tester.runAsync(
        () => store.loadDay(DateTime(2026, 10, 12)),
      ))!;
      final note = day.sessions.single.voiceNotes.single;
      expect(note.transcript, 'left knee tight');
      expect(note.exerciseName, 'Bench press');
      expect(note.audioPath, 'note.m4a');

      await tester.runAsync(() => store.deleteVoiceNote(note.id));
      day = (await tester.runAsync(
        () => store.loadDay(DateTime(2026, 10, 12)),
      ))!;
      expect(day.sessions.single.voiceNotes, isEmpty);

      final denied = FakeWorkoutRecorder(deny: true);
      store.startWorkout();
      await _pumpWorkout(tester, store, denied);
      _press(tester, const ValueKey('voice-record'));
      await tester.pump();
      expect(find.text('Microphone is off'), findsOneWidget);
      expect(find.textContaining('left knee tight'), findsNothing);
      expect(denied.starts, 1);
      _press(tester, const ValueKey('discard-workout'));
      await tester.pump();
      _pressTooltip(tester, 'Confirm');
      await tester.pump();
      expect(store.activeWorkout, isNull);
    },
  );
}

Future<void> _pumpWorkout(
  WidgetTester tester,
  Store store,
  WorkoutRecorder recorder,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: WorkoutScreen(store: store, recorder: recorder),
    ),
  );
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  Store store,
  WorkoutRecorder recorder,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: TodayScreen(
        store: store,
        speech: SpeechCapture(),
        recorder: recorder,
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() => store.settled);
}

void _press(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(key));
  button.onPressed!.call();
}

void _pressTooltip(WidgetTester tester, String message) {
  final button = find.descendant(
    of: find.byTooltip(message),
    matching: find.byType(IconButton),
  );
  tester.widget<IconButton>(button).onPressed!.call();
}

Future<void> _choose(WidgetTester tester, Key field, String choice) async {
  await tester.ensureVisible(find.byKey(field));
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await _tapPick(tester, choice);
  await tester.pumpAndSettle();
}

Future<void> _tapPick(WidgetTester tester, String choice) async {
  final item = find.byKey(ValueKey('pick-$choice'));
  final list = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(Scrollable),
  );
  final dialog = tester.getRect(find.byType(Dialog));
  for (var i = 0; i < 40; i++) {
    if (item.evaluate().isNotEmpty) {
      final rect = tester.getRect(item);
      if (rect.center.dy > dialog.top + 48 &&
          rect.center.dy < dialog.bottom - 48) {
        break;
      }
      final dy = rect.center.dy >= dialog.center.dy ? -140.0 : 140.0;
      await tester.drag(list, Offset(0, dy));
    } else {
      await tester.drag(list, const Offset(0, -180));
    }
    await tester.pump();
  }
  await tester.tap(item);
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
  fail('Timed out waiting for the screen');
}
