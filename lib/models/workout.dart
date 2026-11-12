import 'training.dart';

class RoutineSet {
  const RoutineSet({this.id = 0, this.reps, this.weightKg});

  final int id;
  final int? reps;
  final double? weightKg;
}

class RoutineExercise {
  const RoutineExercise({
    this.id = 0,
    this.exerciseId,
    required this.name,
    this.sets = const [],
  });

  final int id;
  final int? exerciseId;
  final String name;
  final List<RoutineSet> sets;
}

class Routine {
  const Routine({
    this.id = 0,
    required this.name,
    this.position = 0,
    this.createdOn = '',
    this.exercises = const [],
  });

  final int id;
  final String name;
  final int position;
  final String createdOn;
  final List<RoutineExercise> exercises;
}

class ActiveSet {
  ActiveSet({this.reps = 8, this.weightKg, this.done = false});

  int reps;
  double? weightKg;
  bool done;
}

class ActiveExercise {
  ActiveExercise({this.exerciseId, required this.name, required this.sets});

  int? exerciseId;
  String name;
  List<ActiveSet> sets;
}

class ActiveWorkout {
  ActiveWorkout({
    this.routineId,
    required this.name,
    required this.startedAt,
    this.exerciseIndex = 0,
    this.restSeconds = 90,
    this.restToken = 0,
    required this.exercises,
    List<VoiceNote>? notes,
  }) : notes = notes ?? <VoiceNote>[];

  final int? routineId;
  final String name;
  final DateTime startedAt;
  int exerciseIndex;
  int restSeconds;
  int restToken;
  final List<ActiveExercise> exercises;
  final List<VoiceNote> notes;

  ActiveExercise? get current {
    if (exercises.isEmpty) {
      return null;
    }
    final index = exerciseIndex.clamp(0, exercises.length - 1).toInt();
    return exercises[index];
  }
}
