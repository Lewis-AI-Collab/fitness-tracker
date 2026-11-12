import 'package:fitness_tracker/models/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('routines can be created, edited, reordered and deleted', () async {
    final store = await openStore();
    final bench = store.exerciseByName('Bench press')!;
    final row = store.exerciseByName('Barbell row')!;

    await store.saveRoutine(
      Routine(
        name: 'Week 1 Push',
        exercises: [
          RoutineExercise(
            exerciseId: bench.id,
            name: bench.name,
            sets: const [
              RoutineSet(reps: 8, weightKg: 60),
              RoutineSet(reps: 8, weightKg: 60),
            ],
          ),
          RoutineExercise(
            exerciseId: row.id,
            name: row.name,
            sets: const [RoutineSet(reps: 10, weightKg: 40)],
          ),
        ],
      ),
    );

    expect(store.routines, hasLength(1));
    final saved = store.routines.single;
    expect(saved.name, 'Week 1 Push');
    expect(saved.exercises.map((exercise) => exercise.name), [
      'Bench press',
      'Barbell row',
    ]);
    expect(saved.exercises.first.exerciseId, bench.id);
    expect(saved.exercises.first.sets, hasLength(2));
    expect(saved.exercises.first.sets.first.weightKg, 60);
    expect(saved.exercises.first.sets.first.reps, 8);

    await store.saveRoutine(
      Routine(
        id: saved.id,
        name: 'Week 1 Pull',
        exercises: [
          saved.exercises[1],
          RoutineExercise(
            exerciseId: bench.id,
            name: bench.name,
            sets: const [RoutineSet(reps: 5, weightKg: 80)],
          ),
        ],
      ),
    );

    final edited = store.routines.single;
    expect(edited.id, saved.id);
    expect(edited.name, 'Week 1 Pull');
    expect(edited.exercises.map((exercise) => exercise.name), [
      'Barbell row',
      'Bench press',
    ]);
    expect(edited.exercises[1].sets, hasLength(1));
    expect(edited.exercises[1].sets.single.reps, 5);
    expect(edited.exercises[1].sets.single.weightKg, 80);
    expect(
      Sqflite.firstIntValue(
        await store.db.rawQuery('SELECT COUNT(*) FROM routine_sets'),
      ),
      2,
    );

    await store.saveRoutine(
      const Routine(
        name: 'Alias',
        exercises: [
          RoutineExercise(
            name: 'bench',
            sets: [RoutineSet(reps: 8, weightKg: 20)],
          ),
        ],
      ),
    );
    expect(store.routines, hasLength(2));
    expect(store.routines.last.exercises.single.exerciseId, bench.id);
    expect(store.routines.last.exercises.single.name, 'Bench press');

    await store.deleteRoutine(edited.id);
    expect(store.routines, hasLength(1));
    expect(store.routines.single.name, 'Alias');
    expect(
      Sqflite.firstIntValue(
        await store.db.rawQuery('SELECT COUNT(*) FROM routine_exercises'),
      ),
      1,
    );
  });

  test('finish keeps ticked sets and discard keeps nothing', () async {
    final store = await openStore();
    final bench = store.exerciseByName('Bench press')!;
    final row = store.exerciseByName('Barbell row')!;
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
          RoutineExercise(
            exerciseId: row.id,
            name: row.name,
            sets: const [RoutineSet(reps: 10, weightKg: 40)],
          ),
        ],
      ),
    );

    store.startWorkout(from: store.routines.single);
    store.updateActiveSet(0, reps: 6, weightKg: 72.5, editWeight: true);
    store.toggleActiveSet(0);
    store.stepExercise(1);
    store.toggleActiveSet(0);
    final id = await store.finishWorkout();
    expect(id, isNotNull);
    expect(store.activeWorkout, isNull);

    final day = await store.loadDay(DateTime(2026, 10, 12));
    final session = day.sessions.single;
    expect(session.notes, 'Push');
    expect(session.type, 'gym');
    expect(session.sets, hasLength(2));
    expect(session.sets[0].exerciseName, 'Bench press');
    expect(session.sets[0].reps, 6);
    expect(session.sets[0].weightKg, 72.5);
    expect(session.sets[0].setCount, 1);
    expect(session.sets[1].exerciseName, 'Barbell row');
    expect(session.sets[1].reps, 10);
    expect(session.sets[1].weightKg, 40);

    store.startWorkout(from: store.routines.single);
    store.toggleActiveSet(0);
    store.addActiveNote(transcript: '   ');
    expect(store.activeWorkout!.notes, isEmpty);
    await store.discardWorkout();
    expect(store.activeWorkout, isNull);
    final after = await store.loadDay(DateTime(2026, 10, 12));
    expect(after.sessions, hasLength(1));
  });

  test(
    'voice notes attach to the session and the exercise, then delete',
    () async {
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
      store.addActiveNote(
        transcript: 'left knee tight',
        audioPath: 'note.m4a',
        exerciseId: bench.id,
        exerciseName: 'Bench press',
      );
      await store.finishWorkout();

      var day = await store.loadDay(DateTime(2026, 10, 12));
      final note = day.sessions.single.voiceNotes.single;
      expect(note.transcript, 'left knee tight');
      expect(note.exerciseName, 'Bench press');
      expect(note.exerciseId, bench.id);
      expect(note.audioPath, 'note.m4a');

      await store.deleteVoiceNote(note.id);
      day = await store.loadDay(DateTime(2026, 10, 12));
      expect(day.sessions.single.voiceNotes, isEmpty);
    },
  );
}
