import 'dart:io';

import 'package:fitness_tracker/data/database.dart';
import 'package:fitness_tracker/data/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v1 databases gain rir, nullable block time and round minutes', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('fitness-upgrade');
    final path = '${directory.path}/legacy.db';
    final legacy = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, type TEXT NOT NULL)',
        );
        await db.execute('''
          CREATE TABLE sets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            reps INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE session_blocks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            subtype TEXT NOT NULL,
            duration_min INTEGER NOT NULL,
            rpe INTEGER NOT NULL,
            load REAL NOT NULL
          )
        ''');
        await db.execute(
          'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        final sessionId = await db.insert('sessions', {
          'date': '2026-10-12',
          'type': 'muay_thai',
        });
        await db.insert('session_blocks', {
          'session_id': sessionId,
          'subtype': 'pads',
          'duration_min': 20,
          'rpe': 7,
          'load': 140,
        });
      },
    );
    await legacy.close();

    final upgraded = await openFitnessDatabase(path: path);
    final columns = await upgraded.rawQuery('PRAGMA table_info(sets)');
    expect(columns.any((column) => column['name'] == 'rir'), isTrue);
    await upgraded.insert('sets', {'session_id': 1, 'reps': 8, 'rir': 2});
    final set = await upgraded.query('sets');
    expect(set.single['rir'], 2);

    final blockColumns = await upgraded.rawQuery(
      'PRAGMA table_info(session_blocks)',
    );
    final duration = blockColumns.firstWhere(
      (column) => column['name'] == 'duration_min',
    );
    expect(duration['notnull'], 0);
    await upgraded.insert('session_blocks', {
      'session_id': 1,
      'subtype': 'other',
      'duration_min': null,
      'rpe': 6,
      'load': 0,
      'label': 'Bagwork',
    });
    final blocks = await upgraded.query('session_blocks', orderBy: 'id');
    expect(blocks.first['duration_min'], 20);
    expect(blocks.last['duration_min'], isNull);
    expect(blocks.last['label'], 'Bagwork');

    final setting = await upgraded.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['round_minutes'],
    );
    expect(setting.single['value'], '3');

    await upgradeFitnessDatabase(upgraded, 1, 2);
    final rirColumns = await upgraded.rawQuery('PRAGMA table_info(sets)');
    expect(rirColumns.where((column) => column['name'] == 'rir'), hasLength(1));
    expect(await upgraded.query('session_blocks'), hasLength(2));
    final goals = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'goals'",
    );
    expect(goals, hasLength(1));
    await upgraded.close();
  });

  test('v2 databases gain a goals table and keep existing sets', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('fitness-goals');
    final path = '${directory.path}/v2.db';
    final legacy = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, type TEXT NOT NULL)',
        );
        await db.execute('''
          CREATE TABLE sets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            reps INTEGER,
            rir INTEGER
          )
        ''');
        await db.insert('sessions', {'date': '2026-10-05', 'type': 'gym'});
        await db.insert('sets', {'session_id': 1, 'reps': 8, 'rir': 2});
      },
    );
    await legacy.close();

    final upgraded = await openFitnessDatabase(path: path);
    final tables = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'goals'",
    );
    expect(tables, hasLength(1));
    await upgraded.insert('goals', {
      'kind': 'general',
      'general': 'strength',
      'created_on': '2026-10-05',
    });
    final set = await upgraded.query('sets');
    expect(set.single['reps'], 8);
    expect(set.single['rir'], 2);

    await upgradeFitnessDatabase(upgraded, 2, 3);
    final again = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'goals'",
    );
    expect(again, hasLength(1));
    expect(await upgraded.query('goals'), hasLength(1));
    expect((await upgraded.query('sets')).single['rir'], 2);
    await upgraded.close();
  });

  test('an older database gains air squat and pistol squat', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('fitness-seed');
    final path = '${directory.path}/seed.db';
    final created = await openFitnessDatabase(path: path);
    final removed = await created.delete(
      'exercises',
      where: 'name = ? OR name = ?',
      whereArgs: ['Air squat', 'Pistol squat'],
    );
    expect(removed, 2);
    await created.close();

    final store = Store(clock: () => DateTime(2026, 10, 12, 9));
    await store.init(path: path);
    final air = store.exerciseByName('Air squat');
    final pistol = store.exerciseByName('Pistol squat');
    expect(air, isNotNull);
    expect(air!.category, 'strength');
    expect(air.bodyweight, isTrue);
    expect(air.aliases, contains('air squats'));
    expect(pistol, isNotNull);
    expect(pistol!.bodyweight, isTrue);
    expect(pistol.aliases, contains('pistol squats'));
    expect(store.exerciseByName('Bench press'), isNotNull);
  });

  test(
    'v3 databases keep sessions and gain routines and voice notes',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp('fitness-v3');
      final path = '${directory.path}/v3.db';
      final legacy = await openDatabase(
        path,
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE exercises (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            muscle_groups TEXT NOT NULL,
            aliases TEXT NOT NULL,
            default_load_factor REAL NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            start_time TEXT,
            type TEXT NOT NULL,
            duration_min INTEGER,
            rpe INTEGER,
            notes TEXT,
            raw_transcript TEXT
          )
        ''');
          await db.execute('''
          CREATE TABLE sets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            exercise_id INTEGER,
            set_count INTEGER,
            reps INTEGER,
            weight_kg REAL,
            distance_km REAL,
            duration_s INTEGER,
            rpe INTEGER,
            bodyweight INTEGER NOT NULL DEFAULT 0,
            rir INTEGER
          )
        ''');
          await db.execute('''
          CREATE TABLE session_blocks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            subtype TEXT NOT NULL,
            duration_min INTEGER,
            rpe INTEGER NOT NULL,
            load REAL NOT NULL,
            label TEXT
          )
        ''');
          await db.execute('''
          CREATE TABLE plan_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            type TEXT NOT NULL,
            muscle_groups TEXT NOT NULL,
            intensity TEXT,
            duration_min_est INTEGER,
            suggestion TEXT
          )
        ''');
          await db.execute('''
          CREATE TABLE checkins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            slot TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE warnings_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            rule TEXT NOT NULL,
            shown INTEGER NOT NULL,
            level TEXT NOT NULL,
            evidence_json TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            general TEXT,
            exercise_id INTEGER,
            target_kg REAL,
            distance_km REAL,
            target_pace_s INTEGER,
            created_on TEXT NOT NULL
          )
        ''');
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.insert('sessions', {
            'date': '2026-10-05',
            'start_time': '18:00',
            'type': 'gym',
          });
          await db.insert('sets', {
            'session_id': 1,
            'reps': 8,
            'weight_kg': 70,
            'rir': 2,
          });
          await db.insert('goals', {
            'kind': 'general',
            'general': 'strength',
            'created_on': '2026-10-05',
          });
        },
      );
      await legacy.close();

      final upgraded = await openFitnessDatabase(path: path);
      for (final name in [
        'routines',
        'routine_exercises',
        'routine_sets',
        'voice_notes',
      ]) {
        final tables = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [name],
        );
        expect(tables, hasLength(1), reason: name);
      }
      final set = await upgraded.query('sets');
      expect(set.single['reps'], 8);
      expect(set.single['rir'], 2);
      expect(set.single['weight_kg'], 70);
      final goal = await upgraded.query('goals');
      expect(goal.single['general'], 'strength');
      final session = await upgraded.query('sessions');
      expect(session.single['date'], '2026-10-05');
      expect(session.single['type'], 'gym');

      await upgraded.insert('routines', {
        'name': 'Push',
        'position': 0,
        'created_on': '2026-10-05',
      });
      await upgraded.insert('voice_notes', {
        'session_id': session.single['id'],
        'exercise_name': 'Bench press',
        'transcript': 'heavy',
        'created_at': '2026-10-05T18:10:00',
      });

      await upgradeFitnessDatabase(upgraded, 3, fitnessSchemaVersion);
      expect(await upgraded.query('routines'), hasLength(1));
      expect(
        (await upgraded.query('voice_notes')).single['transcript'],
        'heavy',
      );
      expect((await upgraded.query('sets')).single['reps'], 8);
      expect((await upgraded.query('sets')).single['rir'], 2);
      expect((await upgraded.query('goals')).single['general'], 'strength');
      expect((await upgraded.query('sessions')).single['date'], '2026-10-05');
      await upgraded.close();

      final store = Store(clock: () => DateTime(2026, 10, 5, 18));
      await store.init(path: path);
      expect(store.routines.single.name, 'Push');
      final day = await store.loadDay(DateTime(2026, 10, 5));
      expect(day.sessions.single.date, '2026-10-05');
      expect(day.sessions.single.sets.single.reps, 8);
      expect(day.sessions.single.sets.single.rir, 2);
      expect(day.sessions.single.voiceNotes.single.transcript, 'heavy');
      expect(day.sessions.single.voiceNotes.single.exerciseName, 'Bench press');
      expect(store.goals.single.general, 'strength');
    },
  );

  test('a newer file is not downgraded', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp(
      'fitness-downgrade',
    );
    final path = '${directory.path}/newer.db';
    final newer = await openDatabase(
      path,
      version: fitnessSchemaVersion + 1,
      onCreate: (db, version) async {},
    );
    await newer.close();
    expect(openFitnessDatabase(path: path), throwsA(isA<StateError>()));
  });
}
