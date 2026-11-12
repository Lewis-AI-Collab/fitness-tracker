import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/training.dart';
import '../models/workout.dart';
import '../services/balance.dart';
import '../services/checkin_scheduler.dart';
import '../services/dates.dart';
import '../services/export_summary.dart';
import '../services/goals.dart';
import '../services/load_model.dart';
import '../services/week_chart.dart';
import '../services/overload.dart';
import '../services/patterns.dart';
import '../services/readiness.dart';
import '../services/rules.dart';
import '../services/voice_parser.dart';
import 'database.dart';
import 'exercise_seed.dart';

class DayBundle {
  const DayBundle({
    required this.date,
    required this.sessions,
    required this.plans,
    required this.warnings,
    this.morning,
    this.evening,
  });

  final DateTime date;
  final List<Session> sessions;
  final List<PlanItem> plans;
  final List<StoredWarning> warnings;
  final CheckIn? morning;
  final CheckIn? evening;
}

class WeekBundle {
  const WeekBundle({
    required this.start,
    required this.days,
    required this.suggestions,
    required this.balance,
    required this.goalLines,
  });

  final DateTime start;
  final List<DayBundle> days;
  final List<StoredSuggestion> suggestions;
  final BalanceReport balance;
  final List<String> goalLines;
}

class Store extends ChangeNotifier {
  Store({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final ValueNotifier<String?> pendingSlot = ValueNotifier(null);

  Database? _db;
  List<Exercise> exercises = [];
  List<Goal> goals = [];
  List<Routine> routines = [];
  ActiveWorkout? activeWorkout;
  CheckInSchedule schedule = CheckInSchedule.defaults;
  int roundMinutes = 3;
  var notificationsDenied = false;
  Future<void> _weekGate = Future<void>.value();
  var _inflight = 0;
  final List<Completer<void>> _idle = [];
  Future<void> _serialTail = Future<void>.value();

  bool get busy => _inflight > 0;

  /// One screen reload talks to sqlite at a time, so a second load does not
  /// sit on the lock with a pending timer.
  Future<T> _serial<T>(Future<T> Function() body) {
    final gate = _serialTail;
    final done = Completer<void>();
    _serialTail = done.future;
    return gate.then((_) async {
      try {
        return await body();
      } finally {
        done.complete();
      }
    });
  }

  /// Completes when screen reloads started by the last change have finished.
  /// Widget tests await this so a sqflite lock timer is not still pending.
  Future<void> get settled {
    if (_inflight == 0) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _idle.add(waiter);
    return waiter.future;
  }

  Future<T> _track<T>(Future<T> future) {
    _inflight++;
    return future.whenComplete(() {
      _inflight--;
      if (_inflight == 0) {
        final waiters = List<Completer<void>>.of(_idle);
        _idle.clear();
        for (final waiter in waiters) {
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }
      }
    });
  }

  DateTime now() => _clock();

  Future<void> init({String? path}) async {
    _db = await openFitnessDatabase(path: path);
    await _ensureSeedExercises();
    exercises = await _readExercises();
    goals = await _readGoals();
    routines = await _readRoutines();
    schedule = await _readSchedule();
    roundMinutes = int.tryParse(await _setting('round_minutes') ?? '') ?? 3;
    notificationsDenied =
        (await _setting('notifications_denied') ?? '0') == '1';
    activeWorkout = _workoutFromJson(await _setting('active_workout'));
    notifyListeners();
  }

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('Store.init has not finished.');
    }
    return database;
  }

  Exercise? exerciseById(int? id) {
    if (id == null) {
      return null;
    }
    for (final exercise in exercises) {
      if (exercise.id == id) {
        return exercise;
      }
    }
    return null;
  }

  Future<void> addAlias(int exerciseId, String alias) async {
    final cleaned = alias.toLowerCase().trim();
    if (cleaned.length < 2 || cleaned.length > 40) {
      return;
    }
    final exercise = exerciseById(exerciseId);
    if (exercise == null) {
      return;
    }
    final existing = exercise.aliases.map((item) => item.toLowerCase()).toSet()
      ..add(exercise.name.toLowerCase());
    if (existing.contains(cleaned)) {
      return;
    }
    final aliases = [...exercise.aliases, cleaned];
    await db.update(
      'exercises',
      {'aliases': jsonEncode(aliases)},
      where: 'id = ?',
      whereArgs: [exerciseId],
    );
    exercises = await _readExercises();
    notifyListeners();
  }

  Future<void> setSchedule(CheckInSchedule next) async {
    schedule = next;
    await _putSetting('morning_enabled', next.morningEnabled ? '1' : '0');
    await _putSetting(
      'morning_hm',
      fmtHm(next.morningHour, next.morningMinute),
    );
    await _putSetting('evening_enabled', next.eveningEnabled ? '1' : '0');
    await _putSetting(
      'evening_hm',
      fmtHm(next.eveningHour, next.eveningMinute),
    );
    notifyListeners();
  }

  Future<void> setNotificationsDenied(bool denied) async {
    notificationsDenied = denied;
    await _putSetting('notifications_denied', denied ? '1' : '0');
    notifyListeners();
  }

  Future<void> addGoal({
    required GoalKind kind,
    String? general,
    int? exerciseId,
    double? targetKg,
    double? distanceKm,
    int? targetPaceS,
  }) async {
    await db.insert('goals', {
      'kind': kind.name,
      'general': general,
      'exercise_id': exerciseId,
      'target_kg': targetKg,
      'distance_km': distanceKm,
      'target_pace_s': targetPaceS,
      'created_on': isoDate(now()),
    });
    goals = await _readGoals();
    notifyListeners();
  }

  Future<void> deleteGoal(int id) async {
    await db.delete('goals', where: 'id = ?', whereArgs: [id]);
    goals = await _readGoals();
    notifyListeners();
  }

  Future<void> updateGoalTarget(int id, double kg) async {
    await db.update(
      'goals',
      {'target_kg': kg},
      where: 'id = ?',
      whereArgs: [id],
    );
    goals = await _readGoals();
    notifyListeners();
  }

  Future<void> updateSet({
    required int id,
    int? setCount,
    int? reps,
    double? weightKg,
  }) async {
    final values = <String, Object?>{};
    if (setCount != null) {
      values['set_count'] = setCount < 1 ? 1 : setCount;
    }
    if (reps != null) {
      values['reps'] = reps;
    }
    if (weightKg != null) {
      values['weight_kg'] = weightKg;
    }
    if (values.isEmpty) {
      return;
    }
    await db.update('sets', values, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> setSessionRpe(int id, int rpe) async {
    final clamped = rpe < 1 ? 1 : (rpe > 10 ? 10 : rpe);
    await db.update(
      'sessions',
      {'rpe': clamped},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  Future<LoadSeries> loadSeries(ChartPeriod period) {
    return _track(_serial(() => _loadSeries(period)));
  }

  Future<LoadSeries> _loadSeries(ChartPeriod period) async {
    final today = dateOnly(now());
    return switch (period) {
      ChartPeriod.day => _daySeries(today),
      ChartPeriod.week => _weekSeries(today),
      ChartPeriod.threeMonths => _spanSeries(
        today,
        weeks: 13,
        title: '3 months',
      ),
      ChartPeriod.year => _yearSeries(today),
    };
  }

  Future<LoadSeries> _daySeries(DateTime today) async {
    final total = _sumLoads(
      await _sessionsBetween(isoDate(today), isoDate(today)),
    );
    final priors = <double>[];
    for (var i = 1; i <= 12 && priors.length < 4; i++) {
      final day = today.subtract(Duration(days: 7 * i));
      final load = _sumLoads(
        await _sessionsBetween(isoDate(day), isoDate(day)),
      );
      if (load > 0) {
        priors.add(load);
      }
    }
    return seriesFrom(
      title: 'Today',
      points: [total],
      labels: [weekdayLabels[today.weekday - 1].substring(0, 1)],
      priorTotals: priors.reversed.toList(),
    );
  }

  Future<LoadSeries> _weekSeries(DateTime today) async {
    final start = weekStart(today);
    final points = <double>[];
    final labels = <String>[];
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      points.add(_sumLoads(await _sessionsBetween(isoDate(day), isoDate(day))));
      labels.add(weekdayLabels[i].substring(0, 1));
    }
    final priors = <double>[];
    for (var i = 1; i <= 12 && priors.length < 4; i++) {
      final from = start.subtract(Duration(days: 7 * i));
      final to = from.add(const Duration(days: 6));
      final load = _sumLoads(
        await _sessionsBetween(isoDate(from), isoDate(to)),
      );
      if (load > 0) {
        priors.add(load);
      }
    }
    return seriesFrom(
      title: 'This week',
      points: points,
      labels: labels,
      priorTotals: priors.reversed.toList(),
    );
  }

  Future<LoadSeries> _spanSeries(
    DateTime today, {
    required int weeks,
    required String title,
  }) async {
    final end = weekStart(today);
    final start = end.subtract(Duration(days: 7 * (weeks - 1)));
    final sessions = await _sessionsBetween(
      isoDate(start),
      isoDate(end.add(const Duration(days: 6))),
    );
    final points = <double>[];
    final labels = <String>[];
    for (var i = 0; i < weeks; i++) {
      final from = start.add(Duration(days: 7 * i));
      final to = from.add(const Duration(days: 6));
      var load = 0.0;
      for (final session in sessions) {
        final day = parseIsoDate(session.date);
        if (!day.isBefore(from) && !day.isAfter(to)) {
          load += loadOf(session);
        }
      }
      points.add(load);
      labels.add('${from.day}');
    }
    final priors = <double>[];
    for (var i = 4; i >= 1; i--) {
      final from = start.subtract(Duration(days: 7 * weeks * i));
      final to = from.add(Duration(days: 7 * weeks - 1));
      priors.add(_sumLoads(await _sessionsBetween(isoDate(from), isoDate(to))));
    }
    return seriesFrom(
      title: title,
      points: points,
      labels: labels,
      priorTotals: priors,
    );
  }

  Future<LoadSeries> _yearSeries(DateTime today) async {
    final sessions = await _sessionsBetween(
      isoDate(DateTime(today.year)),
      isoDate(DateTime(today.year, 12, 31)),
    );
    final points = List<double>.filled(12, 0);
    for (final session in sessions) {
      points[parseIsoDate(session.date).month - 1] += loadOf(session);
    }
    final previous = _sumLoads(
      await _sessionsBetween(
        isoDate(DateTime(today.year - 1)),
        isoDate(DateTime(today.year - 1, 12, 31)),
      ),
    );
    return seriesFrom(
      title: 'This year',
      points: points,
      labels: [for (final month in monthLabels) month.substring(0, 1)],
      priorTotals: [previous],
    );
  }

  Future<void> setRoundMinutes(int minutes) async {
    final next = minutes < 1 ? 1 : minutes;
    roundMinutes = next;
    await _putSetting('round_minutes', '$next');
    notifyListeners();
  }

  Future<DayBundle> loadDay(DateTime day) {
    return _track(_serial(() => _readDay(day)));
  }

  Future<DayBundle> _readDay(DateTime day) async {
    final date = isoDate(day);
    final sessions = await _sessionsBetween(date, date);
    final plans = await _plansBetween(date, date);
    final warnings = await _warningsBetween(date, date);
    final morning = await _checkIn(date, 'morning');
    final evening = await _checkIn(date, 'evening');
    return DayBundle(
      date: dateOnly(day),
      sessions: sessions,
      plans: plans,
      warnings: warnings,
      morning: morning,
      evening: evening,
    );
  }

  Future<WeekBundle> loadWeek(DateTime anchor) {
    // Plan reloads on every store change. Overlapping refreshes both insert
    // the same suggestion row and hit the unique key.
    final run = _weekGate.then((_) => _serial(() => _loadWeek(anchor)));
    _weekGate = run.then((_) {}, onError: (Object _, StackTrace _) {});
    return _track(run);
  }

  Future<WeekBundle> _loadWeek(DateTime anchor) async {
    final start = weekStart(anchor);
    await refreshWarnings(start);
    await refreshSuggestions(start.subtract(const Duration(days: 7)));
    final days = <DayBundle>[];
    for (var i = 0; i < 7; i++) {
      days.add(await _readDay(start.add(Duration(days: i))));
    }
    final suggestions = await suggestionsForWeek(
      isoDate(start.subtract(const Duration(days: 7))),
    );
    final sessions = [for (final day in days) ...day.sessions];
    final weekEnd = start.add(const Duration(days: 6));
    final goalRows = await _readGoals();
    goals = goalRows;
    return WeekBundle(
      start: start,
      days: days,
      suggestions: suggestions,
      balance: buildBalance(start: start, end: weekEnd, sessions: sessions),
      goalLines: goalProgressLines(goalRows, sessions),
    );
  }

  Future<Set<String>> markedDays(DateTime month) {
    return _track(_serial(() => _readMarkedDays(month)));
  }

  Future<Set<String>> _readMarkedDays(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1, 0);
    final sessions = await _sessionsBetween(isoDate(start), isoDate(end));
    final checkins = await _checkInsBetween(isoDate(start), isoDate(end));
    return {
      for (final session in sessions) session.date,
      for (final checkIn in checkins) checkIn.date,
    };
  }

  Future<void> saveParse(ParseResult result, {DateTime? on}) async {
    final day = dateOnly(on ?? now());
    final time = fmtHm(now().hour, now().minute);
    await db.transaction((txn) async {
      await _writeParse(txn, result, isoDate(day), time);
    });
    notifyListeners();
  }

  Future<void> replaceSession(int id, ParseResult result) async {
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }
    final date = rows.first['date'] as String;
    final time = rows.first['start_time'] as String?;
    final clearing = result.sessions.isEmpty;
    final paths = clearing ? await _audioPaths(id) : const <String>[];
    await db.transaction((txn) async {
      await txn.delete('sets', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete(
        'session_blocks',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      if (result.sessions.isEmpty) {
        await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
        return;
      }
      final first = result.sessions.first;
      await txn.update(
        'sessions',
        {
          'type': first.type,
          'duration_min': first.durationMin,
          'rpe': first.rpe,
          'notes': first.notes,
          'raw_transcript': first.raw,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _writeSessionChildren(txn, id, first);
      for (final extra in result.sessions.skip(1)) {
        await _insertSession(txn, extra, date, time);
      }
    });
    notifyListeners();
    if (clearing) {
      await _deletePaths(paths);
    }
  }

  Future<void> deleteSession(int id) async {
    final paths = await _audioPaths(id);
    await db.transaction((txn) async {
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
    notifyListeners();
    await _deletePaths(paths);
  }

  Future<List<String>> _audioPaths(int sessionId) async {
    final rows = await db.query(
      'voice_notes',
      columns: ['audio_path'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    return [
      for (final row in rows)
        if (row['audio_path'] is String &&
            (row['audio_path'] as String).isNotEmpty)
          row['audio_path'] as String,
    ];
  }

  Future<void> _deletePaths(List<String> paths) async {
    for (final path in paths) {
      await _deleteIfPresent(path);
    }
  }

  Future<void> _writeParse(
    DatabaseExecutor txn,
    ParseResult result,
    String date,
    String? time,
  ) async {
    if (result.plans.isNotEmpty) {
      final start = weekStart(parseIsoDate(date));
      for (final plan in result.plans) {
        await txn.insert('plan_items', {
          'date': isoDate(start.add(Duration(days: plan.weekday - 1))),
          'type': plan.type,
          'muscle_groups': jsonEncode(plan.muscleGroups),
          'intensity': plan.intensity,
          'duration_min_est': plan.durationMin,
        });
      }
    }
    for (final session in result.sessions) {
      await _insertSession(txn, session, date, time);
    }
  }

  Future<void> _insertSession(
    DatabaseExecutor txn,
    ParsedSession session,
    String date,
    String? time,
  ) async {
    final id = await txn.insert('sessions', {
      'date': date,
      'start_time': time,
      'type': session.type,
      'duration_min': session.durationMin,
      'rpe': session.rpe,
      'notes': session.notes,
      'raw_transcript': session.raw,
    });
    await _writeSessionChildren(txn, id, session);
  }

  Future<void> _writeSessionChildren(
    DatabaseExecutor txn,
    int id,
    ParsedSession session,
  ) async {
    for (final set in session.sets) {
      final count = set.sets;
      final named = set.rirSetIndex;
      if (named != null && count != null && (named < 0 || named >= count)) {
        await _insertSet(
          txn,
          sessionId: id,
          set: set,
          setCount: count,
          rpe: session.rpe,
          rir: null,
        );
      } else if (named != null && count != null && count > 1) {
        for (var i = 0; i < count; i++) {
          await _insertSet(
            txn,
            sessionId: id,
            set: set,
            setCount: 1,
            rpe: session.rpe,
            rir: i == named ? set.rir : null,
          );
        }
      } else if (set.rirLastOnly && count != null && count > 1) {
        for (var i = 0; i < count; i++) {
          await _insertSet(
            txn,
            sessionId: id,
            set: set,
            setCount: 1,
            rpe: session.rpe,
            rir: i == count - 1 ? set.rir : null,
          );
        }
      } else {
        await _insertSet(
          txn,
          sessionId: id,
          set: set,
          setCount: set.sets,
          rpe: session.rpe,
          rir: set.rir,
        );
      }
      if (set.exerciseId != null) {
        await _putSetting('last_exercise_id', '${set.exerciseId}', txn);
      }
    }
    if (session.distanceKm != null && session.sets.isEmpty) {
      final run = exerciseByName('Run');
      final hike = exerciseByName('Hike');
      final idForType = session.type == 'hike' ? hike?.id : run?.id;
      await txn.insert('sets', {
        'session_id': id,
        'exercise_id': idForType,
        'distance_km': session.distanceKm,
        'duration_s': session.durationMin == null
            ? null
            : session.durationMin! * 60,
      });
    }
    for (final block in session.blocks) {
      await txn.insert('session_blocks', {
        'session_id': id,
        'subtype': block.subtype,
        'duration_min': block.durationMin,
        'rpe': block.rpe,
        'load': block.load,
        'label': block.spoken,
      });
    }
  }

  Future<void> addPlan({
    required DateTime date,
    required String type,
    List<String> muscleGroups = const [],
    String? intensity,
    int? durationMin,
  }) async {
    await db.insert('plan_items', {
      'date': isoDate(date),
      'type': type,
      'muscle_groups': jsonEncode(muscleGroups),
      'intensity': intensity,
      'duration_min_est': durationMin,
    });
    notifyListeners();
  }

  Future<void> deletePlan(int id) async {
    await db.delete('plan_items', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<CheckIn?> checkInOn(String date, String slot) => _checkIn(date, slot);

  Future<void> saveCheckIn(CheckIn checkIn) async {
    await db.insert('checkins', {
      'date': checkIn.date,
      'slot': checkIn.slot,
      'soreness': checkIn.soreness,
      'energy': checkIn.energy,
      'sleep_quality': checkIn.sleepQuality,
      'sleep_hours': checkIn.sleepHours,
      'mood': checkIn.mood,
      'stress': checkIn.stress,
      'session_feel': checkIn.sessionFeel,
      'ate_well': checkIn.ateWell,
      'raw_transcript': checkIn.rawTranscript,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _learn(checkIn.date);
    notifyListeners();
  }

  Future<Exercise?> lastExercise() async {
    final raw = await _setting('last_exercise_id');
    if (raw == null) {
      return null;
    }
    return exerciseById(int.tryParse(raw));
  }

  Future<List<StoredPattern>> patterns() {
    return _track(_serial(() => _readPatterns()));
  }

  Future<List<StoredPattern>> _readPatterns() async {
    final rows = await db.query('patterns', orderBy: 'key');
    return rows
        .map(
          (row) => StoredPattern(
            key: row['key'] as String,
            n: row['n'] as int,
            meanNextReadiness: (row['mean_next_readiness'] as num).toDouble(),
            meanNextFatigue: (row['mean_next_fatigue'] as num).toDouble(),
            lastUpdated: row['last_updated'] as String,
          ),
        )
        .toList();
  }

  Future<List<StoredSuggestion>> suggestionsForWeek(String weekStart) async {
    final rows = await db.query(
      'overload_suggestions',
      where: 'week_start = ?',
      whereArgs: [weekStart],
      orderBy: 'exercise_name',
    );
    return rows.map(_suggestion).toList();
  }

  Future<void> refreshWarnings(DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 6));
    final historyStart = weekStart.subtract(const Duration(days: 56));
    final sessions = await _sessionsBetween(
      isoDate(historyStart),
      isoDate(end),
    );
    final plans = await _plansBetween(isoDate(weekStart), isoDate(end));
    final checkins = await _checkInsBetween(isoDate(weekStart), isoDate(end));
    final scores = _scoresByDay(checkins);
    final previous = <double>[];
    for (var i = 4; i >= 1; i--) {
      final start = weekStart.subtract(Duration(days: 7 * i));
      final weekEnd = start.add(const Duration(days: 7));
      final total = sessions
          .where((session) {
            final day = parseIsoDate(session.date);
            return !day.isBefore(start) && day.isBefore(weekEnd);
          })
          .fold<double>(0, (sum, session) => sum + loadOf(session));
      if (total > 0) {
        previous.add(total);
      }
    }
    final warnings = evaluateRules(
      RulesInput(
        plans: [for (final plan in plans) _planFact(plan)],
        sessions: [for (final session in sessions) _sessionFact(session)],
        readinessByDay: {
          for (final entry in scores.entries) entry.key: entry.value.readiness,
        },
        historicalLoads: [for (final session in sessions) loadOf(session)],
        previousWeekLoads: previous,
        patterns: await _samples(),
      ),
    );
    await db.delete(
      'warnings_log',
      where: 'date >= ? AND date <= ?',
      whereArgs: [isoDate(weekStart), isoDate(end)],
    );
    for (final warning in warnings) {
      await db.insert('warnings_log', {
        'date': isoDate(warning.date),
        'rule': warning.rule,
        'shown': 1,
        'level': warning.level.name,
        'evidence_json': jsonEncode({
          'evidence': warning.evidence,
          'muscle_groups': warning.muscleGroups,
          'evidence_dates': [
            for (final date in warning.evidenceDates) isoDate(date),
          ],
        }),
      });
    }
  }

  Future<void> refreshSuggestions(DateTime sourceWeek) async {
    final end = sourceWeek.add(const Duration(days: 6));
    final sessions = await _sessionsBetween(isoDate(sourceWeek), isoDate(end));
    final checkins = await _checkInsBetween(isoDate(sourceWeek), isoDate(end));
    final scores = _scoresByDay(checkins);
    final plans = await _plansBetween(isoDate(sourceWeek), isoDate(end));
    final historyStart = sourceWeek.subtract(const Duration(days: 21));
    final history = await _sessionsBetween(isoDate(historyStart), isoDate(end));
    final warnings = evaluateRules(
      RulesInput(
        plans: [for (final plan in plans) _planFact(plan)],
        sessions: [for (final session in history) _sessionFact(session)],
        readinessByDay: {
          for (final entry in scores.entries) entry.key: entry.value.readiness,
        },
        patterns: await _samples(),
      ),
    );
    final muscles = warnedMuscles(warnings);
    final priorRows = await suggestionsForWeek(
      isoDate(sourceWeek.subtract(const Duration(days: 7))),
    );
    final priorByExercise = {for (final row in priorRows) row.exerciseId: row};
    final grouped = <int, List<WorkingSet>>{};
    final names = <int, String>{};
    final groups = <int, List<String>>{};
    for (final session in sessions) {
      for (final set in session.sets) {
        final id = set.exerciseId;
        final weight = set.weightKg;
        final reps = set.reps;
        if (id == null || weight == null || reps == null) {
          continue;
        }
        final exercise = exerciseById(id);
        if (exercise == null || exercise.category != 'strength') {
          continue;
        }
        grouped.putIfAbsent(id, () => []);
        final count = set.setCount ?? 1;
        for (var i = 0; i < count; i++) {
          grouped[id]!.add(
            WorkingSet(weightKg: weight, reps: reps, rir: set.rir),
          );
        }
        names[id] = exercise.name;
        groups[id] = exercise.muscleGroups;
      }
    }
    final bias = shapingBias(await _readGoals());
    final suggestions = suggestWeek(
      lifts: [
        for (final entry in grouped.entries)
          LiftWeekInput(
            exerciseId: entry.key,
            exerciseName: names[entry.key]!,
            muscleGroups: groups[entry.key] ?? const [],
            sets: entry.value,
            priorRepLow: priorByExercise[entry.key]?.repLow,
            priorRepHigh: priorByExercise[entry.key]?.repHigh,
          ),
      ],
      context: WeekContext(
        meanReadiness: meanReadiness(
          scores.values.map((score) => score.readiness),
        ),
        warnedMuscles: muscles,
        bias: bias,
      ),
    );
    await db.delete(
      'overload_suggestions',
      where: 'week_start = ?',
      whereArgs: [isoDate(sourceWeek)],
    );
    for (final suggestion in suggestions) {
      await db.insert('overload_suggestions', {
        'week_start': isoDate(sourceWeek),
        'exercise_id': suggestion.exerciseId,
        'exercise_name': suggestion.exerciseName,
        'working_weight_kg': suggestion.workingWeightKg,
        'reps_csv': suggestion.reps.join(','),
        'rep_low': suggestion.repLow,
        'rep_high': suggestion.repHigh,
        'action': suggestion.action.name,
        'suggested_weight_kg': suggestion.suggestedWeightKg,
        'aim_reps': suggestion.aimReps,
        'card': suggestion.card,
        'muscle_groups': jsonEncode(suggestion.muscleGroups),
      });
    }
    await _stampPlans(sourceWeek.add(const Duration(days: 7)), suggestions);
  }

  Future<ExportFiles> exportSession(Session session) {
    final day = parseIsoDate(session.date);
    return exportRange(
      start: day,
      end: day,
      kind: 'workout',
      sessionId: session.id,
    );
  }

  Future<ExportFiles> exportRange({
    required DateTime start,
    required DateTime end,
    required String kind,
    int? sessionId,
  }) async {
    final sessions = await _sessionsBetween(isoDate(start), isoDate(end));
    final exported = sessionId == null
        ? sessions
        : sessions.where((session) => session.id == sessionId).toList();
    final plans = await _plansBetween(isoDate(start), isoDate(end));
    final checkins = await _checkInsBetween(isoDate(start), isoDate(end));
    final warnings = await _warningsBetween(isoDate(start), isoDate(end));
    final scores = _scoresByDay(checkins);
    final suggestionRows = await db.query(
      'overload_suggestions',
      where: 'week_start >= ? AND week_start <= ?',
      whereArgs: [
        isoDate(start.subtract(const Duration(days: 7))),
        isoDate(end),
      ],
    );
    return buildExport(
      ExportSnapshot(
        kind: kind,
        start: start,
        end: end,
        sessions: exported,
        plans: plans,
        checkins: checkins,
        warnings: warnings,
        patterns: await patterns(),
        suggestions: suggestionRows.map(_suggestion).toList(),
        goals: await _readGoals(),
        readinessByDay: {
          for (final entry in scores.entries) entry.key: entry.value.readiness,
        },
        fatigueByDay: {
          for (final entry in scores.entries) entry.key: entry.value.fatigue,
        },
      ),
    );
  }

  Future<void> importSummary(String raw) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('import');
    }
    if (decoded is! Map || decoded['schema'] != 'fitness-summary-v1') {
      throw const FormatException('import');
    }
    final sessions = decoded['sessions'];
    final checkins = decoded['checkins'];
    final plan = decoded['plan'];
    if (sessions is! List || checkins is! List || plan is! List) {
      throw const FormatException('import');
    }
    for (final item in sessions) {
      if (item is! Map || item['date'] is! String || item['type'] is! String) {
        throw const FormatException('import');
      }
      if (item['sets'] is! List || item['blocks'] is! List) {
        throw const FormatException('import');
      }
    }
    for (final item in checkins) {
      if (item is! Map || item['date'] is! String || item['slot'] is! String) {
        throw const FormatException('import');
      }
    }
    for (final item in plan) {
      if (item is! Map || item['date'] is! String || item['type'] is! String) {
        throw const FormatException('import');
      }
    }
    await db.transaction((txn) async {
      for (final item in sessions) {
        final existing = await txn.query(
          'sessions',
          where: "date = ? AND ifnull(start_time, '') = ? AND type = ? AND ifnull(raw_transcript, '') = ?",
          whereArgs: [
            item['date'],
            item['start_time'] ?? '',
            item['type'],
            item['raw_transcript'] ?? '',
          ],
        );
        if (existing.isNotEmpty) {
          continue;
        }
        final id = await txn.insert('sessions', {
          'date': item['date'],
          'start_time': item['start_time'],
          'type': item['type'],
          'duration_min': item['duration_min'],
          'rpe': item['rpe'],
          'notes': item['notes'],
          'raw_transcript': item['raw_transcript'],
        });
        for (final set in item['sets'] as List) {
          if (set is! Map) {
            throw const FormatException('import');
          }
          await txn.insert('sets', {
            'session_id': id,
            'exercise_id': set['exercise_id'],
            'set_count': set['set_count'],
            'reps': set['reps'],
            'weight_kg': set['weight_kg'],
            'distance_km': set['distance_km'],
            'duration_s': set['duration_s'],
            'rpe': set['rpe'],
            'bodyweight': set['bodyweight'] == true ? 1 : 0,
            'rir': set['rir'],
          });
        }
        for (final block in item['blocks'] as List) {
          if (block is! Map) {
            throw const FormatException('import');
          }
          await txn.insert('session_blocks', {
            'session_id': id,
            'subtype': block['subtype'],
            'duration_min': block['duration_min'],
            'rpe': block['rpe'] ?? 0,
            'load': block['load'] ?? 0,
            'label': block['label'],
          });
        }
      }
      for (final item in checkins) {
        await txn.insert('checkins', {
          'date': item['date'],
          'slot': item['slot'],
          'soreness': item['soreness'],
          'energy': item['energy'],
          'sleep_quality': item['sleep_quality'],
          'sleep_hours': item['sleep_hours'],
          'mood': item['mood'],
          'stress': item['stress'],
          'session_feel': item['session_feel'],
          'ate_well': item['ate_well'],
          'raw_transcript': item['raw_transcript'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final item in plan) {
        final muscles = _musclesJson(item['muscle_groups']);
        final existing = await txn.query(
          'plan_items',
          where: "date = ? AND type = ? AND muscle_groups = ? AND ifnull(intensity, '') = ?",
          whereArgs: [
            item['date'],
            item['type'],
            muscles,
            item['intensity'] ?? '',
          ],
        );
        if (existing.isNotEmpty) {
          continue;
        }
        await txn.insert('plan_items', {
          'date': item['date'],
          'type': item['type'],
          'muscle_groups': muscles,
          'intensity': item['intensity'],
          'duration_min_est': item['duration_min_est'],
          'suggestion': item['suggestion'],
        });
      }
    });
    notifyListeners();
  }

  Future<void> _insertSet(
    DatabaseExecutor txn, {
    required int sessionId,
    required ParsedSet set,
    required int? setCount,
    required int? rpe,
    required int? rir,
  }) async {
    await txn.insert('sets', {
      'session_id': sessionId,
      'exercise_id': set.exerciseId,
      'set_count': setCount,
      'reps': set.reps,
      'weight_kg': set.weightKg,
      'bodyweight': set.bodyweight ? 1 : 0,
      'rpe': rpe,
      'rir': rir,
    });
  }

  Exercise? exerciseByName(String name) {
    for (final exercise in exercises) {
      if (exercise.name.toLowerCase() == name.toLowerCase()) {
        return exercise;
      }
    }
    return null;
  }

  Exercise? matchExercise(String name) {
    final cleaned = name.trim().toLowerCase();
    if (cleaned.isEmpty) {
      return null;
    }
    final exact = exerciseByName(cleaned);
    if (exact != null) {
      return exact;
    }
    for (final exercise in exercises) {
      for (final alias in exercise.aliases) {
        if (alias.toLowerCase() == cleaned) {
          return exercise;
        }
      }
    }
    return null;
  }

  Future<void> saveRoutine(Routine routine) async {
    final name = routine.name.trim().isEmpty ? 'Routine' : routine.name.trim();
    await db.transaction((txn) async {
      var id = routine.id;
      if (id == 0) {
        final count = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM routines'),
        );
        id = await txn.insert('routines', {
          'name': name,
          'position': count ?? 0,
          'created_on': isoDate(now()),
        });
      } else {
        await txn.update(
          'routines',
          {'name': name},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'routine_exercises',
          where: 'routine_id = ?',
          whereArgs: [id],
        );
      }
      var position = 0;
      for (final exercise in routine.exercises) {
        final typed = exercise.name.trim();
        if (typed.isEmpty) {
          continue;
        }
        final matched = exercise.exerciseId != null
            ? exerciseById(exercise.exerciseId)
            : matchExercise(typed);
        final exerciseRow = await txn.insert('routine_exercises', {
          'routine_id': id,
          'exercise_id': matched?.id,
          'name': matched?.name ?? typed,
          'position': position,
        });
        position++;
        for (var s = 0; s < exercise.sets.length; s++) {
          final set = exercise.sets[s];
          await txn.insert('routine_sets', {
            'routine_exercise_id': exerciseRow,
            'position': s,
            'reps': set.reps,
            'weight_kg': set.weightKg,
          });
        }
      }
    });
    routines = await _readRoutines();
    notifyListeners();
  }

  Future<void> deleteRoutine(int id) async {
    await db.delete('routines', where: 'id = ?', whereArgs: [id]);
    routines = await _readRoutines();
    notifyListeners();
  }

  void startWorkout({Routine? from}) {
    if (activeWorkout != null) {
      return;
    }
    final exercises = <ActiveExercise>[];
    for (final exercise in from?.exercises ?? const <RoutineExercise>[]) {
      final sets = exercise.sets.isEmpty
          ? <ActiveSet>[ActiveSet()]
          : [
              for (final set in exercise.sets)
                ActiveSet(reps: set.reps ?? 8, weightKg: set.weightKg),
            ];
      final matched = exercise.exerciseId != null
          ? exerciseById(exercise.exerciseId)
          : matchExercise(exercise.name);
      exercises.add(
        ActiveExercise(
          exerciseId: matched?.id ?? exercise.exerciseId,
          name: matched?.name ?? exercise.name,
          sets: sets,
        ),
      );
    }
    final rawName = from?.name.trim() ?? '';
    activeWorkout = ActiveWorkout(
      routineId: from == null || from.id == 0 ? null : from.id,
      name: rawName.isEmpty ? 'Workout' : rawName,
      startedAt: now(),
      exercises: exercises,
    );
    notifyListeners();
    _queueActive();
  }

  void addActiveExercise(String name) {
    final workout = activeWorkout;
    if (workout == null) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final matched = matchExercise(trimmed);
    workout.exercises.add(
      ActiveExercise(
        exerciseId: matched?.id,
        name: matched?.name ?? trimmed,
        sets: [ActiveSet()],
      ),
    );
    workout.exerciseIndex = workout.exercises.length - 1;
    notifyListeners();
    _queueActive();
  }

  void addActiveSet() {
    final current = activeWorkout?.current;
    if (current == null) {
      return;
    }
    final last = current.sets.isEmpty ? null : current.sets.last;
    current.sets.add(
      ActiveSet(reps: last?.reps ?? 8, weightKg: last?.weightKg),
    );
    notifyListeners();
    _queueActive();
  }

  void toggleActiveSet(int index) {
    final workout = activeWorkout;
    final current = workout?.current;
    if (workout == null || current == null) {
      return;
    }
    if (index < 0 || index >= current.sets.length) {
      return;
    }
    final set = current.sets[index];
    set.done = !set.done;
    if (set.done) {
      workout.restToken += 1;
    }
    notifyListeners();
    _queueActive();
  }

  void updateActiveSet(
    int index, {
    int? reps,
    double? weightKg,
    bool editWeight = false,
  }) {
    final current = activeWorkout?.current;
    if (current == null || index < 0 || index >= current.sets.length) {
      return;
    }
    final set = current.sets[index];
    if (reps != null) {
      set.reps = reps;
    }
    if (editWeight) {
      set.weightKg = weightKg;
    }
    notifyListeners();
    _queueActive();
  }

  void stepExercise(int delta) {
    final workout = activeWorkout;
    if (workout == null || workout.exercises.isEmpty) {
      return;
    }
    final next = workout.exerciseIndex + delta;
    if (next < 0 || next >= workout.exercises.length) {
      return;
    }
    workout.exerciseIndex = next;
    notifyListeners();
    _queueActive();
  }

  void setRestSeconds(int seconds) {
    final workout = activeWorkout;
    if (workout == null) {
      return;
    }
    workout.restSeconds = seconds.clamp(15, 300).toInt();
    notifyListeners();
    _queueActive();
  }

  void addActiveNote({
    required String transcript,
    String? audioPath,
    int? exerciseId,
    String? exerciseName,
  }) {
    final workout = activeWorkout;
    if (workout == null) {
      return;
    }
    final text = transcript.trim();
    final path = audioPath?.trim();
    final storedPath = path == null || path.isEmpty ? null : path;
    if (text.isEmpty && storedPath == null) {
      return;
    }
    final name = exerciseName?.trim();
    workout.notes.add(
      VoiceNote(
        exerciseId: exerciseId,
        exerciseName: name == null || name.isEmpty ? null : name,
        transcript: text,
        audioPath: storedPath,
        createdAt: now().toIso8601String(),
      ),
    );
    notifyListeners();
    _queueActive();
  }

  void deleteActiveNote(int index) {
    final workout = activeWorkout;
    if (workout == null || index < 0 || index >= workout.notes.length) {
      return;
    }
    final note = workout.notes.removeAt(index);
    notifyListeners();
    _queueActive();
    unawaited(_deleteIfPresent(note.audioPath));
  }

  Future<int?>? _finishGate;

  Future<int?> finishWorkout() {
    final gate = _finishGate;
    if (gate != null) {
      return gate;
    }
    final run = _finishWorkout();
    _finishGate = run;
    return run.whenComplete(() {
      if (identical(_finishGate, run)) {
        _finishGate = null;
      }
    });
  }

  Future<int?> _finishWorkout() async {
    final workout = activeWorkout;
    if (workout == null) {
      return null;
    }
    final logged =
        workout.notes.isNotEmpty ||
        workout.exercises.any(
          (exercise) => exercise.sets.any((set) => set.done),
        );
    if (!logged) {
      await discardWorkout();
      return null;
    }
    final minutes = now().difference(workout.startedAt).inMinutes;
    final sessionId = await db.transaction((txn) async {
      final id = await txn.insert('sessions', {
        'date': isoDate(dateOnly(workout.startedAt)),
        'start_time': fmtHm(workout.startedAt.hour, workout.startedAt.minute),
        'type': 'gym',
        'duration_min': minutes > 0 ? minutes : null,
        'notes': workout.name,
      });
      for (final exercise in workout.exercises) {
        final matched = exercise.exerciseId != null
            ? exerciseById(exercise.exerciseId)
            : matchExercise(exercise.name);
        final bodyweight = matched?.bodyweight ?? false;
        var logged = false;
        for (final set in exercise.sets) {
          if (!set.done) {
            continue;
          }
          logged = true;
          final added = set.weightKg != null && set.weightKg != 0;
          await txn.insert('sets', {
            'session_id': id,
            'exercise_id': matched?.id,
            'set_count': 1,
            'reps': set.reps,
            'weight_kg': set.weightKg,
            'bodyweight': bodyweight && !added ? 1 : 0,
          });
        }
        if (logged && matched != null) {
          await _putSetting('last_exercise_id', '${matched.id}', txn);
        }
      }
      for (final note in workout.notes) {
        await txn.insert('voice_notes', {
          'session_id': id,
          'exercise_id': note.exerciseId,
          'exercise_name': note.exerciseName,
          'transcript': note.transcript,
          'audio_path': note.audioPath,
          'created_at': note.createdAt,
        });
      }
      return id;
    });
    activeWorkout = null;
    await _clearActive();
    scheduleMicrotask(notifyListeners);
    return sessionId;
  }

  Future<void> discardWorkout() async {
    final notes = activeWorkout?.notes.toList() ?? const <VoiceNote>[];
    activeWorkout = null;
    await _clearActive();
    notifyListeners();
    for (final note in notes) {
      await _deleteIfPresent(note.audioPath);
    }
  }

  void _queueActive() {
    final raw = _workoutToJson(activeWorkout);
    // Root zone so a widget test's fake clock does not sit on the write.
    unawaited(Zone.root.run(() => _track(_serial(() => _storeActive(raw)))));
  }

  Future<void> _clearActive() {
    return Zone.root.run(() => _track(_serial(() => _storeActive(null))));
  }

  Future<void> _storeActive(String? raw) async {
    if (raw == null) {
      await db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: ['active_workout'],
      );
      return;
    }
    await _putSetting('active_workout', raw);
  }

  String? _workoutToJson(ActiveWorkout? workout) {
    if (workout == null) {
      return null;
    }
    return jsonEncode({
      'routineId': workout.routineId,
      'name': workout.name,
      'startedAt': workout.startedAt.toIso8601String(),
      'exerciseIndex': workout.exerciseIndex,
      'restSeconds': workout.restSeconds,
      'restToken': workout.restToken,
      'exercises': [
        for (final exercise in workout.exercises)
          {
            'exerciseId': exercise.exerciseId,
            'name': exercise.name,
            'sets': [
              for (final set in exercise.sets)
                {'reps': set.reps, 'weightKg': set.weightKg, 'done': set.done},
            ],
          },
      ],
      'notes': [
        for (final note in workout.notes)
          {
            'exerciseId': note.exerciseId,
            'exerciseName': note.exerciseName,
            'transcript': note.transcript,
            'audioPath': note.audioPath,
            'createdAt': note.createdAt,
          },
      ],
    });
  }

  ActiveWorkout? _workoutFromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final exercises = <ActiveExercise>[];
      final rawExercises = decoded['exercises'];
      if (rawExercises is List) {
        for (final item in rawExercises) {
          if (item is! Map) {
            continue;
          }
          final sets = <ActiveSet>[];
          final rawSets = item['sets'];
          if (rawSets is List) {
            for (final set in rawSets) {
              if (set is! Map) {
                continue;
              }
              sets.add(
                ActiveSet(
                  reps: (set['reps'] as num?)?.toInt() ?? 8,
                  weightKg: (set['weightKg'] as num?)?.toDouble(),
                  done: set['done'] == true,
                ),
              );
            }
          }
          exercises.add(
            ActiveExercise(
              exerciseId: (item['exerciseId'] as num?)?.toInt(),
              name: item['name'] as String? ?? 'Exercise',
              sets: sets,
            ),
          );
        }
      }
      final notes = <VoiceNote>[];
      final rawNotes = decoded['notes'];
      if (rawNotes is List) {
        for (final item in rawNotes) {
          if (item is! Map) {
            continue;
          }
          notes.add(
            VoiceNote(
              exerciseId: (item['exerciseId'] as num?)?.toInt(),
              exerciseName: item['exerciseName'] as String?,
              transcript: item['transcript'] as String? ?? '',
              audioPath: item['audioPath'] as String?,
              createdAt: item['createdAt'] as String? ?? '',
            ),
          );
        }
      }
      final started = DateTime.tryParse(decoded['startedAt'] as String? ?? '');
      if (started == null) {
        return null;
      }
      return ActiveWorkout(
        routineId: (decoded['routineId'] as num?)?.toInt(),
        name: decoded['name'] as String? ?? 'Workout',
        startedAt: started,
        exerciseIndex: (decoded['exerciseIndex'] as num?)?.toInt() ?? 0,
        restSeconds: (decoded['restSeconds'] as num?)?.toInt() ?? 90,
        restToken: (decoded['restToken'] as num?)?.toInt() ?? 0,
        exercises: exercises,
        notes: notes,
      );
    } on Object {
      return null;
    }
  }

  Future<void> deleteVoiceNote(int id) async {
    if (id == 0) {
      return;
    }
    final rows = await db.query(
      'voice_notes',
      columns: ['audio_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await db.delete('voice_notes', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
    if (rows.isNotEmpty) {
      await _deleteIfPresent(rows.first['audio_path'] as String?);
    }
  }

  Future<void> _deleteIfPresent(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<Routine>> _readRoutines() async {
    final routineRows = await db.query('routines', orderBy: 'position, id');
    final result = <Routine>[];
    for (final row in routineRows) {
      final id = row['id'] as int;
      final exerciseRows = await db.query(
        'routine_exercises',
        where: 'routine_id = ?',
        whereArgs: [id],
        orderBy: 'position, id',
      );
      final exercises = <RoutineExercise>[];
      for (final exercise in exerciseRows) {
        final exerciseRowId = exercise['id'] as int;
        final setRows = await db.query(
          'routine_sets',
          where: 'routine_exercise_id = ?',
          whereArgs: [exerciseRowId],
          orderBy: 'position, id',
        );
        exercises.add(
          RoutineExercise(
            id: exerciseRowId,
            exerciseId: exercise['exercise_id'] as int?,
            name: exercise['name'] as String,
            sets: [
              for (final set in setRows)
                RoutineSet(
                  id: set['id'] as int,
                  reps: set['reps'] as int?,
                  weightKg: (set['weight_kg'] as num?)?.toDouble(),
                ),
            ],
          ),
        );
      }
      result.add(
        Routine(
          id: id,
          name: row['name'] as String,
          position: row['position'] as int,
          createdOn: row['created_on'] as String,
          exercises: exercises,
        ),
      );
    }
    return result;
  }

  Future<void> _stampPlans(
    DateTime targetWeek,
    List<OverloadSuggestion> suggestions,
  ) async {
    final plans = await _plansBetween(
      isoDate(targetWeek),
      isoDate(targetWeek.add(const Duration(days: 6))),
    );
    for (final plan in plans) {
      if (plan.type != 'gym') {
        continue;
      }
      final lines = suggestions
          .where((suggestion) => _planMatches(plan, suggestion))
          .map((suggestion) => suggestion.card)
          .toList();
      await db.update(
        'plan_items',
        {'suggestion': lines.isEmpty ? null : lines.join('\n')},
        where: 'id = ?',
        whereArgs: [plan.id],
      );
    }
  }

  bool _planMatches(PlanItem plan, OverloadSuggestion suggestion) {
    if (plan.muscleGroups.isEmpty) {
      return true;
    }
    final planned = plan.muscleGroups.map((item) => item.toLowerCase()).toSet();
    if (planned.any(legGroups.contains)) {
      return isLowerBody(suggestion.muscleGroups);
    }
    return suggestion.muscleGroups.any(
      (muscle) => planned.contains(muscle.toLowerCase()),
    );
  }

  Future<void> _learn(String outcomeDate) async {
    final morning = await _checkIn(outcomeDate, 'morning');
    final evening = await _checkIn(outcomeDate, 'evening');
    final score = scoreCheckIns(
      soreness: morning?.soreness,
      energy: morning?.energy,
      sleepQuality: morning?.sleepQuality,
      mood: morning?.mood,
      stress: morning?.stress,
      eveningEnergy: evening?.energy,
      ateWell: evening?.ateWell,
      sessionFeel: evening?.sessionFeel,
      eveningStress: evening?.stress,
    );
    if (score == null) {
      return;
    }
    final day = parseIsoDate(outcomeDate);
    final previous = await _sessionsBetween(
      isoDate(day.subtract(const Duration(days: 1))),
      isoDate(day.subtract(const Duration(days: 1))),
    );
    final earlier = await _sessionsBetween(
      isoDate(day.subtract(const Duration(days: 2))),
      isoDate(day.subtract(const Duration(days: 2))),
    );
    final book = PatternBook()..samples.addAll(await _samples());
    book.learn(
      outcomeDay: day,
      dayMinus1: previous.map(_signatureInput).toList(),
      dayMinus2: earlier.map(_signatureInput).toList(),
      readiness: score.readiness,
      fatigue: score.fatigue,
    );
    await db.delete('pattern_samples');
    await db.delete('patterns');
    for (final sample in book.samples) {
      await db.insert('pattern_samples', {
        'pattern_key': sample.key,
        'outcome_date': isoDate(sample.outcomeDate),
        'readiness': sample.readiness,
        'fatigue': sample.fatigue,
      });
    }
    final keys = book.samples.map((sample) => sample.key).toSet();
    for (final key in keys) {
      final stats = book.stats(key);
      await db.insert('patterns', {
        'key': key,
        'n': stats.n,
        'mean_next_readiness': stats.meanReadiness,
        'mean_next_fatigue': stats.meanFatigue,
        'last_updated': isoDate(now()),
      });
    }
  }

  DaySignatureInput _signatureInput(Session session) {
    return DaySignatureInput(
      type: session.type,
      rpe: session.rpe,
      muscleGroups: _muscles(session),
      subtypes: [for (final block in session.blocks) block.subtype],
      load: loadOf(session),
    );
  }

  SessionFact _sessionFact(Session session) {
    return SessionFact(
      at: _at(session),
      type: session.type,
      load: loadOf(session),
      rpe: session.rpe,
      muscleGroups: _muscles(session),
      subtypes: [for (final block in session.blocks) block.subtype],
    );
  }

  PlanFact _planFact(PlanItem plan) {
    return PlanFact(
      date: parseIsoDate(plan.date),
      type: plan.type,
      load: planLoadOf(plan),
      intensity: plan.intensity,
      muscleGroups: plan.muscleGroups,
      durationMin: plan.durationMinEst,
    );
  }

  List<String> _muscles(Session session) {
    final muscles = <String>{};
    for (final set in session.sets) {
      muscles.addAll(set.muscleGroups);
    }
    return muscles.toList();
  }

  DateTime _at(Session session) {
    final day = parseIsoDate(session.date);
    final time = session.startTime;
    if (time == null || !time.contains(':')) {
      return DateTime(day.year, day.month, day.day, 12);
    }
    final parts = time.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  Map<String, ReadinessScore> _scoresByDay(List<CheckIn> checkins) {
    final grouped = <String, List<CheckIn>>{};
    for (final checkIn in checkins) {
      grouped.putIfAbsent(checkIn.date, () => []).add(checkIn);
    }
    final scores = <String, ReadinessScore>{};
    for (final entry in grouped.entries) {
      CheckIn? morning;
      CheckIn? evening;
      for (final checkIn in entry.value) {
        if (checkIn.slot == 'morning') {
          morning = checkIn;
        } else {
          evening = checkIn;
        }
      }
      final score = scoreCheckIns(
        soreness: morning?.soreness,
        energy: morning?.energy,
        sleepQuality: morning?.sleepQuality,
        mood: morning?.mood,
        stress: morning?.stress,
        eveningEnergy: evening?.energy,
        ateWell: evening?.ateWell,
        sessionFeel: evening?.sessionFeel,
        eveningStress: evening?.stress,
      );
      if (score != null) {
        scores[entry.key] = score;
      }
    }
    return scores;
  }

  Future<List<PatternSample>> _samples() async {
    final rows = await db.query('pattern_samples');
    return [
      for (final row in rows)
        PatternSample(
          key: row['pattern_key'] as String,
          outcomeDate: parseIsoDate(row['outcome_date'] as String),
          readiness: (row['readiness'] as num).toDouble(),
          fatigue: (row['fatigue'] as num).toDouble(),
        ),
    ];
  }

  Future<void> _ensureSeedExercises() async {
    final rows = await db.query('exercises', columns: ['name']);
    final names = {for (final row in rows) row['name'] as String};
    final batch = db.batch();
    var missing = false;
    for (final exercise in seedExercises()) {
      if (names.contains(exercise.name)) {
        continue;
      }
      missing = true;
      batch.insert('exercises', {
        'id': exercise.id,
        'name': exercise.name,
        'category': exercise.category,
        'muscle_groups': jsonEncode(exercise.muscleGroups),
        'aliases': jsonEncode(exercise.aliases),
        'default_load_factor': exercise.defaultLoadFactor,
      });
    }
    if (missing) {
      await batch.commit(noResult: true);
    }
  }

  Future<List<Exercise>> _readExercises() async {
    final rows = await db.query('exercises', orderBy: 'name');
    return [
      for (final row in rows)
        Exercise(
          id: row['id'] as int,
          name: row['name'] as String,
          category: row['category'] as String,
          muscleGroups: decodeStrings(row['muscle_groups'] as String?),
          aliases: decodeStrings(row['aliases'] as String?),
          defaultLoadFactor: (row['default_load_factor'] as num).toDouble(),
          bodyweight: seededBodyweight(row['name'] as String),
        ),
    ];
  }

  Future<List<Goal>> _readGoals() async {
    final rows = await db.query('goals', orderBy: 'id');
    return [
      for (final row in rows)
        Goal(
          id: row['id'] as int,
          kind: goalKindFrom(row['kind'] as String),
          general: row['general'] as String?,
          exerciseId: row['exercise_id'] as int?,
          exerciseName: exerciseById(row['exercise_id'] as int?)?.name,
          targetKg: (row['target_kg'] as num?)?.toDouble(),
          distanceKm: (row['distance_km'] as num?)?.toDouble(),
          targetPaceS: row['target_pace_s'] as int?,
          createdOn: row['created_on'] as String,
        ),
    ];
  }

  Future<CheckInSchedule> _readSchedule() async {
    final morning = await _setting('morning_hm') ?? '08:00';
    final evening = await _setting('evening_hm') ?? '21:00';
    final morningParts = morning.split(':');
    final eveningParts = evening.split(':');
    return CheckInSchedule(
      morningEnabled: (await _setting('morning_enabled') ?? '1') == '1',
      morningHour: int.parse(morningParts[0]),
      morningMinute: int.parse(morningParts[1]),
      eveningEnabled: (await _setting('evening_enabled') ?? '1') == '1',
      eveningHour: int.parse(eveningParts[0]),
      eveningMinute: int.parse(eveningParts[1]),
    );
  }

  Future<String?> _setting(String key) async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> _putSetting(
    String key,
    String value, [
    DatabaseExecutor? exec,
  ]) async {
    await (exec ?? db).insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Session>> _sessionsBetween(String start, String end) async {
    final rows = await db.query(
      'sessions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date, start_time, id',
    );
    final sessions = <Session>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final setRows = await db.query(
        'sets',
        where: 'session_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      final blockRows = await db.query(
        'session_blocks',
        where: 'session_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      final noteRows = await db.query(
        'voice_notes',
        where: 'session_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      sessions.add(
        Session(
          id: id,
          date: row['date'] as String,
          startTime: row['start_time'] as String?,
          type: row['type'] as String,
          durationMin: row['duration_min'] as int?,
          rpe: row['rpe'] as int?,
          notes: row['notes'] as String?,
          rawTranscript: row['raw_transcript'] as String?,
          voiceNotes: [
            for (final note in noteRows)
              VoiceNote(
                id: note['id'] as int,
                sessionId: id,
                exerciseId: note['exercise_id'] as int?,
                exerciseName: note['exercise_name'] as String?,
                transcript: note['transcript'] as String? ?? '',
                audioPath: note['audio_path'] as String?,
                createdAt: note['created_at'] as String? ?? '',
              ),
          ],
          sets: [
            for (final set in setRows)
              SetRow(
                id: set['id'] as int,
                sessionId: id,
                exerciseId: set['exercise_id'] as int?,
                exerciseName: exerciseById(set['exercise_id'] as int?)?.name,
                setCount: set['set_count'] as int?,
                reps: set['reps'] as int?,
                weightKg: (set['weight_kg'] as num?)?.toDouble(),
                distanceKm: (set['distance_km'] as num?)?.toDouble(),
                durationS: set['duration_s'] as int?,
                rpe: set['rpe'] as int?,
                bodyweight: (set['bodyweight'] as int? ?? 0) == 1,
                rir: set['rir'] as int?,
                muscleGroups:
                    exerciseById(set['exercise_id'] as int?)?.muscleGroups ??
                    const [],
              ),
          ],
          blocks: [
            for (final block in blockRows)
              SessionBlock(
                id: block['id'] as int,
                sessionId: id,
                subtype: block['subtype'] as String,
                durationMin: block['duration_min'] as int?,
                rpe: block['rpe'] as int,
                load: (block['load'] as num?)?.toDouble() ?? 0,
                label: block['label'] as String?,
              ),
          ],
        ),
      );
    }
    return sessions;
  }

  Future<List<PlanItem>> _plansBetween(String start, String end) async {
    final rows = await db.query(
      'plan_items',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date, id',
    );
    return [
      for (final row in rows)
        PlanItem(
          id: row['id'] as int,
          date: row['date'] as String,
          type: row['type'] as String,
          muscleGroups: decodeStrings(row['muscle_groups'] as String?),
          intensity: row['intensity'] as String?,
          durationMinEst: row['duration_min_est'] as int?,
          suggestion: row['suggestion'] as String?,
        ),
    ];
  }

  Future<List<CheckIn>> _checkInsBetween(String start, String end) async {
    final rows = await db.query(
      'checkins',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date, slot',
    );
    return rows.map(_checkInFrom).toList();
  }

  Future<CheckIn?> _checkIn(String date, String slot) async {
    final rows = await db.query(
      'checkins',
      where: 'date = ? AND slot = ?',
      whereArgs: [date, slot],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _checkInFrom(rows.first);
  }

  CheckIn _checkInFrom(Map<String, Object?> row) {
    return CheckIn(
      id: row['id'] as int,
      date: row['date'] as String,
      slot: row['slot'] as String,
      soreness: row['soreness'] as int?,
      energy: row['energy'] as int?,
      sleepQuality: row['sleep_quality'] as int?,
      sleepHours: (row['sleep_hours'] as num?)?.toDouble(),
      mood: row['mood'] as int?,
      stress: row['stress'] as int?,
      sessionFeel: row['session_feel'] as int?,
      ateWell: row['ate_well'] as int?,
      rawTranscript: row['raw_transcript'] as String?,
    );
  }

  Future<List<StoredWarning>> _warningsBetween(String start, String end) async {
    final rows = await db.query(
      'warnings_log',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date, id',
    );
    return [
      for (final row in rows)
        () {
          final payload = jsonDecode(row['evidence_json'] as String);
          final map = payload is Map ? payload : const <String, Object?>{};
          return StoredWarning(
            id: row['id'] as int,
            date: row['date'] as String,
            rule: row['rule'] as String,
            shown: (row['shown'] as int) == 1,
            level: row['level'] as String,
            evidence: map['evidence'] as String? ?? '',
            muscleGroups: [
              for (final item in (map['muscle_groups'] as List? ?? const []))
                item.toString(),
            ],
            evidenceDates: [
              for (final item in (map['evidence_dates'] as List? ?? const []))
                item.toString(),
            ],
          );
        }(),
    ];
  }

  StoredSuggestion _suggestion(Map<String, Object?> row) {
    return StoredSuggestion(
      id: row['id'] as int? ?? 0,
      weekStart: row['week_start'] as String,
      exerciseId: row['exercise_id'] as int,
      exerciseName: row['exercise_name'] as String,
      workingWeightKg: (row['working_weight_kg'] as num).toDouble(),
      repsCsv: row['reps_csv'] as String,
      repLow: row['rep_low'] as int,
      repHigh: row['rep_high'] as int,
      action: row['action'] as String,
      suggestedWeightKg: (row['suggested_weight_kg'] as num).toDouble(),
      aimReps: row['aim_reps'] as int?,
      card: row['card'] as String,
      muscleGroups: decodeStrings(row['muscle_groups'] as String?),
    );
  }
}

double _sumLoads(List<Session> sessions) {
  return sessions.fold<double>(0, (sum, session) => sum + loadOf(session));
}

double loadOf(Session session) {
  return sessionLoad(
    type: session.type,
    durationMin: session.durationMin,
    rpe: session.rpe,
    setCount: session.sets.fold<int>(
      0,
      (sum, set) => sum + (set.setCount ?? 1),
    ),
    blocks: [
      for (final block in session.blocks)
        BlockLoad(durationMin: block.durationMin ?? 0, rpe: block.rpe),
    ],
  );
}

double planLoadOf(PlanItem plan) {
  final minutes =
      plan.durationMinEst ??
      switch (plan.type) {
        'muay_thai' => 60,
        'run' => 30,
        'hike' => 90,
        'yoga' => 30,
        _ => 45,
      };
  final rpe = resolvedRpe(type: plan.type, intensity: plan.intensity);
  return (minutes * rpe).toDouble();
}

String _musclesJson(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is List) {
    return jsonEncode(value);
  }
  return '[]';
}

String sessionLine(Session session) {
  if (session.sets.length == 1 && session.type == 'gym') {
    final set = session.sets.single;
    final name = set.exerciseName ?? '?';
    final load = set.bodyweight
        ? 'bodyweight'
        : set.weightKg == null
        ? null
        : '${_trim(set.weightKg!)} kg';
    final core = '$name · ${set.setCount ?? 1}×${set.reps ?? '-'}';
    return load == null ? core : '$core · $load';
  }
  final bits = <String>[_label(session.type)];
  final distance = session.sets
      .map((set) => set.distanceKm)
      .whereType<double>()
      .toList();
  if (distance.isNotEmpty) {
    bits.add('${_trim(distance.first)} km');
  }
  if (session.durationMin != null) {
    bits.add('${session.durationMin} min');
  }
  if (session.rpe != null) {
    bits.add('RPE ${session.rpe}');
  }
  return bits.join(' · ');
}

String _label(String type) => switch (type) {
  'muay_thai' => 'Muay Thai',
  'gym' => 'Gym',
  'run' => 'Run',
  'hike' => 'Hike',
  'yoga' => 'Yoga',
  _ => 'Other',
};

String _trim(double value) {
  if ((value - value.round()).abs() < 0.001) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String planLine(PlanItem plan) {
  final bits = <String>[_label(plan.type)];
  if (plan.muscleGroups.isNotEmpty) {
    bits.add(plan.muscleGroups.join(', '));
  }
  if (plan.intensity != null) {
    bits.add(plan.intensity!);
  }
  return bits.join(' · ');
}
