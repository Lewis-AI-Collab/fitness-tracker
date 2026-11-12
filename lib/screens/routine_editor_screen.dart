import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/training.dart';
import '../models/workout.dart';
import '../services/normalise.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_action.dart';
import '../widgets/icon_tip.dart';
import '../widgets/value_picker.dart';

class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, required this.store, this.routine});

  final Store store;
  final Routine? routine;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _DraftSet {
  _DraftSet({this.reps = 8, this.kg});

  int reps;
  double? kg;
}

class _DraftExercise {
  _DraftExercise({this.exerciseId, String name = '', List<_DraftSet>? sets})
    : nameController = TextEditingController(text: name),
      sets = sets ?? <_DraftSet>[_DraftSet()];

  int? exerciseId;
  final TextEditingController nameController;
  List<_DraftSet> sets;

  String get name => nameController.text;

  void dispose() => nameController.dispose();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  late final TextEditingController _name;
  late final List<_DraftExercise> _exercises;
  late final String _original;
  String? _built;
  var _popping = false;

  @override
  void initState() {
    super.initState();
    final routine = widget.routine;
    _name = TextEditingController(text: routine?.name ?? '');
    _name.addListener(_onName);
    _exercises = [
      for (final exercise in routine?.exercises ?? const <RoutineExercise>[])
        _DraftExercise(
          exerciseId: exercise.exerciseId,
          name: exercise.name,
          sets: [
            for (final set in exercise.sets)
              _DraftSet(reps: set.reps ?? 8, kg: set.weightKg),
          ],
        ),
    ];
    if (_exercises.isEmpty) {
      _exercises.add(_DraftExercise());
    }
    _original = _draftKey();
  }

  String _draftKey() {
    return jsonEncode({
      'name': _name.text,
      'exercises': [
        for (final exercise in _exercises)
          {
            'exerciseId': exercise.exerciseId,
            'name': exercise.name,
            'sets': [
              for (final set in exercise.sets) [set.reps, set.kg],
            ],
          },
      ],
    });
  }

  bool get _dirty => _draftKey() != _original;

  void _onName() {
    if (!mounted || _draftKey() == (_built ?? _original)) {
      return;
    }
    setState(() {});
  }

  Future<void> _maybeLeave() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final ok = await confirmChoice(context);
    if (!ok || !mounted) {
      return;
    }
    setState(() => _popping = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _name.removeListener(_onName);
    _name.dispose();
    for (final exercise in _exercises) {
      exercise.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final existing = widget.routine;
    await widget.store.saveRoutine(
      Routine(
        id: existing?.id ?? 0,
        name: _name.text,
        position: existing?.position ?? 0,
        createdOn: existing?.createdOn ?? '',
        exercises: [
          for (final exercise in _exercises)
            if (exercise.name.trim().isNotEmpty)
              RoutineExercise(
                exerciseId: exercise.exerciseId,
                name: exercise.name,
                sets: [
                  for (final set in exercise.sets)
                    RoutineSet(reps: set.reps, weightKg: set.kg),
                ],
              ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _popping = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _addExercise() {
    setState(() {
      _exercises.add(_DraftExercise());
    });
  }

  void _deleteExercise(int index) {
    final removed = _exercises[index];
    setState(() {
      _exercises.removeAt(index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _moveExercise(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _exercises.length) {
      return;
    }
    setState(() {
      final item = _exercises.removeAt(index);
      _exercises.insert(next, item);
    });
  }

  void _addSet(_DraftExercise exercise) {
    final last = exercise.sets.isEmpty ? null : exercise.sets.last;
    setState(() {
      exercise.sets.add(_DraftSet(reps: last?.reps ?? 8, kg: last?.kg));
    });
  }

  void _deleteSet(_DraftExercise exercise, int index) {
    if (exercise.sets.length <= 1) {
      return;
    }
    setState(() {
      exercise.sets.removeAt(index);
    });
  }

  void _moveSet(_DraftExercise exercise, int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= exercise.sets.length) {
      return;
    }
    setState(() {
      final item = exercise.sets.removeAt(index);
      exercise.sets.insert(next, item);
    });
  }

  Future<void> _pickExercise(int index) async {
    final picked = await showDialog<Exercise>(
      context: context,
      builder: (context) => _ExerciseSearch(exercises: widget.store.exercises),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      final exercise = _exercises[index];
      exercise.exerciseId = picked.id;
      exercise.nameController.text = picked.name;
    });
  }

  Future<void> _pickReps(_DraftExercise exercise, int index) async {
    final set = exercise.sets[index];
    final next = await showValuePicker(
      context: context,
      values: [for (var i = 1; i <= 30; i++) i],
      current: set.reps,
      label: (value) => '${value.toInt()}',
    );
    if (next == null) {
      return;
    }
    setState(() {
      set.reps = next.toInt();
    });
  }

  Future<void> _pickKg(_DraftExercise exercise, int index) async {
    final set = exercise.sets[index];
    final next = await showValuePicker(
      context: context,
      values: [for (var i = 0; i <= 80; i++) i * 2.5],
      current: set.kg ?? 0,
      label: (value) => fmtKg(value.toDouble()),
    );
    if (next == null) {
      return;
    }
    setState(() {
      set.kg = next.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    _built = _draftKey();
    return PopScope(
      canPop: _popping || !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _maybeLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Routine'),
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _maybeLeave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  TextField(
                    key: const ValueKey('routine-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Routine name',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  for (var i = 0; i < _exercises.length; i++) _exerciseCard(i),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('add-exercise'),
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add),
                      label: const Text('Add exercise'),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  key: const ValueKey('save-routine'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Save routine',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exerciseCard(int index) {
    final exercise = _exercises[index];
    return Container(
      key: ObjectKey(exercise),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('exercise-name-$index'),
                  controller: exercise.nameController,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Exercise',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (value) {
                    exercise.exerciseId = widget.store.matchExercise(value)?.id;
                    setState(() {});
                  },
                ),
              ),
              IconTip(
                key: ValueKey('pick-exercise-$index'),
                icon: Icons.list,
                message: 'Exercises',
                compact: true,
                onPressed: () => _pickExercise(index),
              ),
              IconTip(
                key: ValueKey('move-exercise-up-$index'),
                icon: Icons.arrow_upward,
                message: 'Move up',
                compact: true,
                onPressed: index == 0 ? null : () => _moveExercise(index, -1),
              ),
              IconTip(
                key: ValueKey('move-exercise-down-$index'),
                icon: Icons.arrow_downward,
                message: 'Move down',
                compact: true,
                onPressed: index == _exercises.length - 1
                    ? null
                    : () => _moveExercise(index, 1),
              ),
              IconTip(
                key: ValueKey('delete-exercise-$index'),
                icon: Icons.delete_outline,
                message: 'Delete',
                compact: true,
                onPressed: () => _deleteExercise(index),
              ),
            ],
          ),
          for (var s = 0; s < exercise.sets.length; s++)
            _setRow(exercise, index, s),
          TextButton.icon(
            key: ValueKey('add-set-$index'),
            onPressed: () => _addSet(exercise),
            icon: const Icon(Icons.add),
            label: const Text('Add set'),
          ),
        ],
      ),
    );
  }

  Widget _setRow(_DraftExercise exercise, int exerciseIndex, int index) {
    final set = exercise.sets[index];
    final kg = set.kg == null ? '–' : fmtKg(set.kg!);
    return Row(
      children: [
        IconTip(
          key: ValueKey('move-set-up-$exerciseIndex-$index'),
          icon: Icons.arrow_upward,
          message: 'Move set up',
          compact: true,
          onPressed: index == 0 ? null : () => _moveSet(exercise, index, -1),
        ),
        IconTip(
          key: ValueKey('move-set-down-$exerciseIndex-$index'),
          icon: Icons.arrow_downward,
          message: 'Move set down',
          compact: true,
          onPressed: index == exercise.sets.length - 1
              ? null
              : () => _moveSet(exercise, index, 1),
        ),
        Expanded(
          child: Row(
            children: [
              GestureDetector(
                key: ValueKey('set-reps-$exerciseIndex-$index'),
                onTap: () => _pickReps(exercise, index),
                child: Text(
                  '${set.reps}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '×',
                  style: TextStyle(color: AppColors.muted, fontSize: 18),
                ),
              ),
              GestureDetector(
                key: ValueKey('set-kg-$exerciseIndex-$index'),
                onTap: () => _pickKg(exercise, index),
                child: Text(
                  '$kg kg',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (exercise.sets.length > 1)
          IconTip(
            key: ValueKey('delete-set-$exerciseIndex-$index'),
            icon: Icons.close,
            message: 'Delete set',
            compact: true,
            onPressed: () => _deleteSet(exercise, index),
          ),
      ],
    );
  }
}

class _ExerciseSearch extends StatefulWidget {
  const _ExerciseSearch({required this.exercises});

  final List<Exercise> exercises;

  @override
  State<_ExerciseSearch> createState() => _ExerciseSearchState();
}

class _ExerciseSearchState extends State<_ExerciseSearch> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = [
      for (final exercise in widget.exercises)
        if (query.isEmpty ||
            exercise.name.toLowerCase().contains(query) ||
            exercise.aliases.any(
              (alias) => alias.toLowerCase().contains(query),
            ))
          exercise,
    ].take(40);
    return Dialog(
      child: SizedBox(
        width: 320,
        height: 440,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Exercise',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconTip(
                    icon: Icons.close,
                    message: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('exercise-search'),
                decoration: const InputDecoration(hintText: 'Search'),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final exercise in matches)
                    ListTile(
                      title: Text(exercise.name),
                      onTap: () => Navigator.pop(context, exercise),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
