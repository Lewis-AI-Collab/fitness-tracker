import 'dart:convert';
import 'dart:io';

import 'package:fitness_tracker/data/store.dart';
import 'package:fitness_tracker/screens/routine_editor_screen.dart';
import 'package:fitness_tracker/screens/workout_screen.dart';
import 'package:fitness_tracker/services/workout_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

class _Recorder implements WorkoutRecorder {
  @override
  Future<void> start() async {}

  @override
  Future<VoiceCapture> stop() async => const VoiceCapture();

  @override
  Future<void> play({String? audioPath, String? transcript}) async {}

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('an unknown active workout version is ignored', () async {
    final store = await openStore();
    await store.db.insert('settings', {
      'key': 'active_workout',
      'value': jsonEncode({
        'v': 2,
        'name': 'Later',
        'startedAt': '2026-10-12T09:00:00.000',
        'exercises': [],
        'notes': [],
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final path = store.db.path;
    await store.db.close();
    final again = Store(clock: () => DateTime(2026, 10, 12, 10));
    await again.init(path: path);
    expect(again.activeWorkout, isNull);
    expect(again.exercises, isNotEmpty);
  });

  test('startup deletes voice files nothing references', () async {
    final root = await Directory.systemTemp.createTemp('voice-sweep');
    final notes = Directory('${root.path}/voice_notes');
    final dbDir = await Directory.systemTemp.createTemp('voice-sweep-db');
    final path = '${dbDir.path}/fitness.db';
    final store = Store(
      clock: () => DateTime(2026, 10, 12, 9),
      voiceNotesDir: notes,
    );
    await store.init(path: path);
    await notes.create();
    final orphan = File('${notes.path}/orphan.m4a');
    final keep = File('${notes.path}/keep.m4a');
    await orphan.writeAsString('orphan');
    await keep.writeAsString('keep');
    store.startWorkout();
    store.addActiveNote(transcript: 'keep', audioPath: keep.path);
    await store.settled;
    await store.db.close();

    final again = Store(
      clock: () => DateTime(2026, 10, 12, 10),
      voiceNotesDir: notes,
    );
    await again.init(path: path);
    expect(orphan.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
    expect(again.activeWorkout!.notes.single.audioPath, keep.path);
  });

  testWidgets('focusing the routine name does not ask to drop edits', (
    tester,
  ) async {
    final store = (await tester.runAsync(openStore))!;
    await _openEditor(tester, store);
    await tester.tap(find.byKey(const ValueKey('routine-name')));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Confirm'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('system back after typing a routine name asks first', (
    tester,
  ) async {
    final store = (await tester.runAsync(openStore))!;
    await _openEditor(tester, store);
    await tester.enterText(find.byKey(const ValueKey('routine-name')), 'Push');
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    await navigator.maybePop();
    await tester.pump();
    expect(find.byTooltip('Confirm'), findsOneWidget);
    expect(find.byKey(const ValueKey('routine-name')), findsOneWidget);
    expect(find.text('Push'), findsWidgets);
  });

  testWidgets('finish with nothing kept uses a discard confirm', (
    tester,
  ) async {
    final store = (await tester.runAsync(openStore))!;
    store.startWorkout();
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutScreen(store: store, recorder: _Recorder()),
      ),
    );
    await tester.pump();
    tester
        .widget<ButtonStyleButton>(find.byKey(const ValueKey('finish-workout')))
        .onPressed!
        .call();
    await tester.pump();
    expect(find.byKey(const ValueKey('finish-discard')), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byTooltip('Discard'), findsOneWidget);
    expect(find.byTooltip('Confirm'), findsNothing);

    tester
        .widget<IconButton>(
          find.descendant(
            of: find.byTooltip('Cancel'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!
        .call();
    await tester.pump();

    store.addActiveExercise('Bench press');
    store.toggleActiveSet(0);
    await tester.pump();
    tester
        .widget<ButtonStyleButton>(find.byKey(const ValueKey('finish-workout')))
        .onPressed!
        .call();
    await tester.pump();
    expect(find.byTooltip('Confirm'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}

Future<void> _openEditor(WidgetTester tester, Store store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => RoutineEditorScreen(store: store),
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
