import 'dart:io';

import 'package:fitness_tracker/data/store.dart';
import 'package:fitness_tracker/models/workout.dart';
import 'package:fitness_tracker/services/voice_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<(Store, String)> _open() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await Directory.systemTemp.createTemp('voice_cleanup');
  final store = Store(clock: () => DateTime(2026, 10, 12, 9));
  await store.init(path: '${dir.path}/fitness.db');
  return (store, dir.path);
}

Future<String> _clip(String dir, String name) async {
  final file = File('$dir/voice_notes/$name.m4a');
  await file.create(recursive: true);
  await file.writeAsString('aac');
  return file.path;
}

Future<int> _finishWithNote(Store store, String path) async {
  store.startWorkout();
  store.addActiveNote(transcript: 'note', audioPath: path);
  final id = await store.finishWorkout();
  await Future<void>.delayed(Duration.zero);
  return id!;
}

void main() {
  test('deleting an active note removes only its file', () async {
    final (store, dir) = await _open();
    final a = await _clip(dir, '1');
    final b = await _clip(dir, '10');
    store.startWorkout();
    store.addActiveNote(transcript: 'a', audioPath: a);
    store.addActiveNote(transcript: 'b', audioPath: b);
    store.deleteActiveNote(0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(File(a).existsSync(), isFalse);
    expect(File(b).existsSync(), isTrue);
  });

  test('discard removes every recording from the session', () async {
    final (store, dir) = await _open();
    final a = await _clip(dir, '2');
    final b = await _clip(dir, '3');
    store.startWorkout();
    store.addActiveNote(transcript: 'a', audioPath: a);
    store.addActiveNote(transcript: 'b', audioPath: b);
    await store.discardWorkout();
    expect(File(a).existsSync(), isFalse);
    expect(File(b).existsSync(), isFalse);
  });

  test(
    'deleting a saved note removes its file and keeps the session',
    () async {
      final (store, dir) = await _open();
      final a = await _clip(dir, '4');
      final keep = await _clip(dir, '40');
      await _finishWithNote(store, a);
      final note = (await store.loadDay(DateTime(2026, 10, 12)))
          .sessions
          .single
          .voiceNotes
          .single;
      await store.deleteVoiceNote(note.id);
      expect(File(a).existsSync(), isFalse);
      expect(File(keep).existsSync(), isTrue);
      expect(
        (await store.loadDay(DateTime(2026, 10, 12))).sessions,
        hasLength(1),
      );
    },
  );

  test('deleting a session removes its recordings', () async {
    final (store, dir) = await _open();
    final a = await _clip(dir, '5');
    final id = await _finishWithNote(store, a);
    await store.deleteSession(id);
    expect(await store.db.query('voice_notes'), isEmpty);
    expect(File(a).existsSync(), isFalse);
  });

  test('re-logging a session as nothing removes its recordings', () async {
    final (store, dir) = await _open();
    final a = await _clip(dir, '6');
    final id = await _finishWithNote(store, a);
    await store.replaceSession(
      id,
      const ParseResult(normalised: '', plans: [], sessions: []),
    );
    expect(File(a).existsSync(), isFalse);
  });

  test('an open workout survives the app being killed', () async {
    final (store, dir) = await _open();
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
    store.updateActiveSet(0, reps: 6, weightKg: 72.5, editWeight: true);
    store.toggleActiveSet(0);
    final a = await _clip(dir, '7');
    store.addActiveNote(
      transcript: 'knee',
      audioPath: a,
      exerciseId: bench.id,
      exerciseName: bench.name,
    );
    await store.settled; // or whatever write-through future the fix exposes
    await store.db.close(); // process death

    final again = Store(clock: () => DateTime(2026, 10, 12, 10));
    await again.init(path: '$dir/fitness.db');
    final restored = again.activeWorkout;
    expect(restored, isNotNull);
    expect(restored!.name, 'Push');
    expect(restored.startedAt, DateTime(2026, 10, 12, 9));
    expect(restored.exercises.single.sets.first.done, isTrue);
    expect(restored.exercises.single.sets.first.reps, 6);
    expect(restored.exercises.single.sets.first.weightKg, 72.5);
    expect(restored.notes.single.audioPath, a);
    await again.finishWorkout();
    await Future<void>.delayed(Duration.zero);
    final day = await again.loadDay(DateTime(2026, 10, 12));
    expect(day.sessions.single.sets.single.reps, 6);
    expect(day.sessions.single.voiceNotes.single.transcript, 'knee');
    expect(again.activeWorkout, isNull);
    final third = Store(clock: () => DateTime(2026, 10, 12, 11));
    await again.db.close();
    await third.init(path: '$dir/fitness.db');
    expect(
      third.activeWorkout,
      isNull,
      reason: 'finished workout must not come back',
    );
  });
}
