class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.muscleGroups,
    required this.aliases,
    this.defaultLoadFactor = 1,
    this.bodyweight = false,
  });

  final int id;
  final String name;
  final String category;
  final List<String> muscleGroups;
  final List<String> aliases;
  final double defaultLoadFactor;

  /// A pull-up, dip, or push-up: a bare number is not added kilograms.
  final bool bodyweight;

  Exercise copyWith({List<String>? aliases}) {
    return Exercise(
      id: id,
      name: name,
      category: category,
      muscleGroups: muscleGroups,
      aliases: aliases ?? this.aliases,
      defaultLoadFactor: defaultLoadFactor,
      bodyweight: bodyweight,
    );
  }
}

class SetRow {
  const SetRow({
    this.id = 0,
    this.sessionId = 0,
    this.exerciseId,
    this.exerciseName,
    this.setCount,
    this.reps,
    this.weightKg,
    this.distanceKm,
    this.durationS,
    this.rpe,
    this.bodyweight = false,
    this.muscleGroups = const [],
    this.rir,
  });

  final int id;
  final int sessionId;
  final int? exerciseId;
  final String? exerciseName;
  final int? setCount;
  final int? reps;
  final double? weightKg;
  final double? distanceKm;
  final int? durationS;
  final int? rpe;
  final bool bodyweight;
  final List<String> muscleGroups;
  final int? rir;
}

class SessionBlock {
  const SessionBlock({
    this.id = 0,
    this.sessionId = 0,
    required this.subtype,
    required this.durationMin,
    required this.rpe,
    required this.load,
    this.label,
  });

  final int id;
  final int sessionId;
  final String subtype;
  final int? durationMin;
  final int rpe;
  final double load;
  final String? label;
}

class Session {
  const Session({
    this.id = 0,
    required this.date,
    this.startTime,
    required this.type,
    this.durationMin,
    this.rpe,
    this.notes,
    this.rawTranscript,
    this.sets = const [],
    this.blocks = const [],
    this.voiceNotes = const [],
  });

  final int id;
  final String date;
  final String? startTime;
  final String type;
  final int? durationMin;
  final int? rpe;
  final String? notes;
  final String? rawTranscript;
  final List<SetRow> sets;
  final List<SessionBlock> blocks;
  final List<VoiceNote> voiceNotes;
}

class VoiceNote {
  const VoiceNote({
    this.id = 0,
    this.sessionId = 0,
    this.exerciseId,
    this.exerciseName,
    this.transcript = '',
    this.audioPath,
    required this.createdAt,
  });

  final int id;
  final int sessionId;
  final int? exerciseId;
  final String? exerciseName;
  final String transcript;
  final String? audioPath;
  final String createdAt;
}

class PlanItem {
  const PlanItem({
    this.id = 0,
    required this.date,
    required this.type,
    this.muscleGroups = const [],
    this.intensity,
    this.durationMinEst,
    this.suggestion,
  });

  final int id;
  final String date;
  final String type;
  final List<String> muscleGroups;
  final String? intensity;
  final int? durationMinEst;
  final String? suggestion;
}

class CheckIn {
  const CheckIn({
    this.id = 0,
    required this.date,
    required this.slot,
    this.soreness,
    this.energy,
    this.sleepQuality,
    this.sleepHours,
    this.mood,
    this.stress,
    this.sessionFeel,
    this.ateWell,
    this.rawTranscript,
  });

  final int id;
  final String date;
  final String slot;
  final int? soreness;
  final int? energy;
  final int? sleepQuality;
  final double? sleepHours;
  final int? mood;
  final int? stress;
  final int? sessionFeel;
  final int? ateWell;
  final String? rawTranscript;

  CheckIn copyWith({
    int? soreness,
    int? energy,
    int? sleepQuality,
    double? sleepHours,
    int? mood,
    int? stress,
    int? sessionFeel,
    int? ateWell,
    String? rawTranscript,
  }) {
    return CheckIn(
      id: id,
      date: date,
      slot: slot,
      soreness: soreness ?? this.soreness,
      energy: energy ?? this.energy,
      sleepQuality: sleepQuality ?? this.sleepQuality,
      sleepHours: sleepHours ?? this.sleepHours,
      mood: mood ?? this.mood,
      stress: stress ?? this.stress,
      sessionFeel: sessionFeel ?? this.sessionFeel,
      ateWell: ateWell ?? this.ateWell,
      rawTranscript: rawTranscript ?? this.rawTranscript,
    );
  }
}

class StoredPattern {
  const StoredPattern({
    required this.key,
    required this.n,
    required this.meanNextReadiness,
    required this.meanNextFatigue,
    required this.lastUpdated,
  });

  final String key;
  final int n;
  final double meanNextReadiness;
  final double meanNextFatigue;
  final String lastUpdated;
}

class StoredWarning {
  const StoredWarning({
    this.id = 0,
    required this.date,
    required this.rule,
    required this.shown,
    required this.level,
    required this.evidence,
    this.muscleGroups = const [],
    this.evidenceDates = const [],
  });

  final int id;
  final String date;
  final String rule;
  final bool shown;
  final String level;
  final String evidence;
  final List<String> muscleGroups;
  final List<String> evidenceDates;
}

enum GoalKind { pace, lift, general }

GoalKind goalKindFrom(String raw) => switch (raw) {
  'pace' => GoalKind.pace,
  'lift' => GoalKind.lift,
  'general' => GoalKind.general,
  _ => GoalKind.general,
};

class Goal {
  const Goal({
    this.id = 0,
    required this.kind,
    this.general,
    this.exerciseId,
    this.exerciseName,
    this.targetKg,
    this.distanceKm,
    this.targetPaceS,
    required this.createdOn,
  });

  final int id;
  final GoalKind kind;

  /// `strength`, `fitness`, or `hypertrophy` when [kind] is [GoalKind.general].
  final String? general;
  final int? exerciseId;
  final String? exerciseName;
  final double? targetKg;
  final double? distanceKm;

  /// Target pace in seconds per kilometre.
  final int? targetPaceS;
  final String createdOn;
}

class StoredSuggestion {
  const StoredSuggestion({
    this.id = 0,
    required this.weekStart,
    required this.exerciseId,
    required this.exerciseName,
    required this.workingWeightKg,
    required this.repsCsv,
    required this.repLow,
    required this.repHigh,
    required this.action,
    required this.suggestedWeightKg,
    this.aimReps,
    required this.card,
    this.muscleGroups = const [],
  });

  final int id;
  final String weekStart;
  final int exerciseId;
  final String exerciseName;
  final double workingWeightKg;
  final String repsCsv;
  final int repLow;
  final int repHigh;
  final String action;
  final double suggestedWeightKg;
  final int? aimReps;
  final String card;
  final List<String> muscleGroups;
}
