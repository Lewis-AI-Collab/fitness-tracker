import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'exercise_seed.dart';

const fitnessSchemaVersion = 4;

Future<Database> openFitnessDatabase({String? path}) async {
  final resolved = path ?? p.join(await getDatabasesPath(), 'fitness.db');
  return openDatabase(
    resolved,
    version: fitnessSchemaVersion,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
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
          rir INTEGER,
          FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
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
          label TEXT,
          FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
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
          slot TEXT NOT NULL,
          soreness INTEGER,
          energy INTEGER,
          sleep_quality INTEGER,
          sleep_hours REAL,
          mood INTEGER,
          stress INTEGER,
          session_feel INTEGER,
          ate_well INTEGER,
          raw_transcript TEXT,
          UNIQUE(date, slot)
        )
      ''');
      await db.execute('''
        CREATE TABLE pattern_samples (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pattern_key TEXT NOT NULL,
          outcome_date TEXT NOT NULL,
          readiness REAL NOT NULL,
          fatigue REAL NOT NULL,
          UNIQUE(pattern_key, outcome_date)
        )
      ''');
      await db.execute('''
        CREATE TABLE patterns (
          key TEXT PRIMARY KEY,
          n INTEGER NOT NULL,
          mean_next_readiness REAL NOT NULL,
          mean_next_fatigue REAL NOT NULL,
          last_updated TEXT NOT NULL
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
        CREATE TABLE overload_suggestions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          week_start TEXT NOT NULL,
          exercise_id INTEGER NOT NULL,
          exercise_name TEXT NOT NULL,
          working_weight_kg REAL NOT NULL,
          reps_csv TEXT NOT NULL,
          rep_low INTEGER NOT NULL,
          rep_high INTEGER NOT NULL,
          action TEXT NOT NULL,
          suggested_weight_kg REAL NOT NULL,
          aim_reps INTEGER,
          card TEXT NOT NULL,
          muscle_groups TEXT NOT NULL,
          UNIQUE(week_start, exercise_id)
        )
      ''');
      await db.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
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
      await createWorkoutSchema(db);
      final batch = db.batch();
      for (final exercise in seedExercises()) {
        batch.insert('exercises', {
          'id': exercise.id,
          'name': exercise.name,
          'category': exercise.category,
          'muscle_groups': jsonEncode(exercise.muscleGroups),
          'aliases': jsonEncode(exercise.aliases),
          'default_load_factor': exercise.defaultLoadFactor,
        });
      }
      await batch.commit(noResult: true);
      await db.insert('settings', {'key': 'round_minutes', 'value': '3'});
    },
    onUpgrade: upgradeFitnessDatabase,
    onDowngrade: (db, oldVersion, newVersion) {
      throw StateError('Cannot open a v$oldVersion database as v$newVersion.');
    },
  );
}

Future<void> upgradeFitnessDatabase(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 2) {
    final setColumns = await db.rawQuery('PRAGMA table_info(sets)');
    final hasRir = setColumns.any((column) => column['name'] == 'rir');
    if (!hasRir) {
      await db.execute('ALTER TABLE sets ADD COLUMN rir INTEGER');
    }
    final blockColumns = await db.rawQuery('PRAGMA table_info(session_blocks)');
    final hasLabel = blockColumns.any((column) => column['name'] == 'label');
    final duration = blockColumns.where(
      (column) => column['name'] == 'duration_min',
    );
    final nullable = duration.isNotEmpty && duration.first['notnull'] == 0;
    if (!(hasLabel && nullable)) {
      await db.execute('''
        CREATE TABLE session_blocks_v2 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          subtype TEXT NOT NULL,
          duration_min INTEGER,
          rpe INTEGER NOT NULL,
          load REAL NOT NULL,
          label TEXT,
          FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        INSERT INTO session_blocks_v2 (id, session_id, subtype, duration_min, rpe, load)
        SELECT id, session_id, subtype, duration_min, rpe, load FROM session_blocks
      ''');
      await db.execute('DROP TABLE session_blocks');
      await db.execute(
        'ALTER TABLE session_blocks_v2 RENAME TO session_blocks',
      );
    }
    await db.insert('settings', {
      'key': 'round_minutes',
      'value': '3',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  if (oldVersion < 3) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goals (
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
  }
  if (oldVersion < 4) {
    await createWorkoutSchema(db);
  }
}

/// Routines and the voice notes attached to a finished session.
/// Safe to run again: an already-upgraded file keeps its rows.
Future<void> createWorkoutSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS routines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      position INTEGER NOT NULL,
      created_on TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS routine_exercises (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      routine_id INTEGER NOT NULL,
      exercise_id INTEGER,
      name TEXT NOT NULL,
      position INTEGER NOT NULL,
      FOREIGN KEY(routine_id) REFERENCES routines(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS routine_sets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      routine_exercise_id INTEGER NOT NULL,
      position INTEGER NOT NULL,
      reps INTEGER,
      weight_kg REAL,
      FOREIGN KEY(routine_exercise_id) REFERENCES routine_exercises(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS voice_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      exercise_id INTEGER,
      exercise_name TEXT,
      transcript TEXT NOT NULL,
      audio_path TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
    )
  ''');
}

List<String> decodeStrings(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const [];
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    return const [];
  }
  return decoded.map((item) => item.toString()).toList();
}
