import 'dart:convert';
import 'dart:io';

import 'package:fitness_tracker/data/store.dart';
import 'package:fitness_tracker/models/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late String _dir;

Future<Store> _open() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _dir = (await Directory.systemTemp.createTemp('active_workout')).path;
  final store = Store(clock: () => DateTime(2026, 10, 12, 9, 3, 7));
  await store.init(path: '$_dir/fitness.db');
  return store;
}

Future<Store> _relaunch(Store store) async {
  await store.settled;
  await store.db.close();
  final again = Store(clock: () => DateTime(2026, 10, 12, 10));
  await again.init(path: '$_dir/fitness.db');
  return again;
}

Future<Store> _pushOpen() async {
  final store = await _open();
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
        const RoutineExercise(
          name: 'Barbell row',
          sets: [RoutineSet(reps: 10, weightKg: 40)],
        ),
      ],
    ),
  );
  store.startWorkout(from: store.routines.single);
  return store;
}

String _shape(ActiveWorkout? workout) {
  if (workout == null) {
    return 'none';
  }
  return jsonEncode({
    'routine': workout.routineId,
    'name': workout.name,
    'started': workout.startedAt.toIso8601String(),
    'index': workout.exerciseIndex,
    'rest': workout.restSeconds,
    'exercises': [
      for (final exercise in workout.exercises)
        [
          exercise.exerciseId,
          exercise.name,
          [for (final set in exercise.sets) [set.reps, set.weightKg, set.done]],
        ],
    ],
    'notes': [
      for (final note in workout.notes)
        [note.exerciseId, note.exerciseName, note.transcript, note.audioPath],
    ],
  });
}

void main() {
  final changes = <String, void Function(Store)>{
    'start': (store) {},
    'tick': (store) => store.toggleActiveSet(0),
    'reps and kg': (store) =>
        store.updateActiveSet(1, reps: 5, weightKg: 72.5, editWeight: true),
    'add set': (store) => store.addActiveSet(),
    'add exercise': (store) => store.addActiveExercise('Dip'),
    'next exercise': (store) => store.stepExercise(1),
    'rest length': (store) => store.setRestSeconds(120),
    'note added': (store) =>
        store.addActiveNote(transcript: 'knee', audioPath: '$_dir/n.m4a'),
    'note deleted': (store) {
      store.addActiveNote(transcript: 'x');
      store.deleteActiveNote(0);
    },
  };
  for (final entry in changes.entries) {
    test('a kill after ${entry.key} restores the same workout', () async {
      final store = await _pushOpen();
      await store.settled;
      entry.value(store);
      final before = _shape(store.activeWorkout);
      final again = await _relaunch(store);
      expect(_shape(again.activeWorkout), before);
    });
  }

  test('discard is not restored after a restart', () async {
    final store = await _pushOpen();
    store.toggleActiveSet(0);
    await store.discardWorkout();
    final again = await _relaunch(store);
    expect(again.activeWorkout, isNull);
  });

  test('an unreadable saved workout does not stop the app opening', () async {
    for (final raw in ['{', '[]', '{"startedAt":"x"}', '{"startedAt":5}', '{"exercises":7}']) {
      final store = await _open();
      await store.db.insert('settings', {
        'key': 'active_workout',
        'value': raw,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final again = await _relaunch(store);
      expect(again.activeWorkout, isNull, reason: raw);
      expect(again.exercises, isNotEmpty);
    }
  });

  test('finish with nothing ticked keeps nothing; a note alone is kept', () async {
    final store = await _pushOpen();
    store.updateActiveSet(0, reps: 3);
    expect(await store.finishWorkout(), isNull);
    expect((await store.loadDay(DateTime(2026, 10, 12))).sessions, isEmpty);
    expect(store.activeWorkout, isNull);

    store.startWorkout(from: store.routines.single);
    store.addActiveNote(transcript: 'shoulder');
    expect(await store.finishWorkout(), isNotNull);
    await Future<void>.delayed(Duration.zero);
    final day = await store.loadDay(DateTime(2026, 10, 12));
    expect(day.sessions.single.voiceNotes.single.transcript, 'shoulder');
  });

  test('two finishes at once save one session', () async {
    final store = await _pushOpen();
    store.toggleActiveSet(0);
    await Future.wait([store.finishWorkout(), store.finishWorkout()]);
    await Future<void>.delayed(Duration.zero);
    expect((await store.loadDay(DateTime(2026, 10, 12))).sessions, hasLength(1));
  });
}
