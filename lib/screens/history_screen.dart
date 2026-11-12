import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/training.dart';
import '../services/dates.dart';
import '../services/workout_recorder.dart';
import '../theme/app_theme.dart';
import '../widgets/icon_tip.dart';
import '../widgets/set_log.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.store,
    this.initialDay,
    this.recorder,
  });

  final Store store;
  final DateTime? initialDay;
  final WorkoutRecorder? recorder;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late DateTime _month;
  Set<String> _marks = {};

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDay ?? widget.store.now();
    _month = DateTime(initial.year, initial.month);
    widget.store.addListener(_load);
    _load();
    if (widget.initialDay != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _open(widget.initialDay!);
      });
    }
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final day = widget.initialDay;
    if (day != null && day != oldWidget.initialDay) {
      setState(() {
        _month = DateTime(day.year, day.month);
      });
      _load();
      _open(day);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final marks = await widget.store.markedDays(_month);
    if (mounted) {
      setState(() => _marks = marks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('${monthLabels[_month.month - 1]} ${_month.year}'),
        actions: [
          IconTip(
            icon: Icons.chevron_left,
            message: 'Previous month',
            onPressed: () {
              setState(() {
                _month = DateTime(_month.year, _month.month - 1);
              });
              _load();
            },
          ),
          IconTip(
            icon: Icons.chevron_right,
            message: 'Next month',
            onPressed: () {
              setState(() {
                _month = DateTime(_month.year, _month.month + 1);
              });
              _load();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                for (final label in weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                for (var day = 1; day <= days; day++)
                  _cell(DateTime(_month.year, _month.month, day)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(DateTime day) {
    final marked = _marks.contains(isoDate(day));
    return InkWell(
      key: ValueKey('history-${isoDate(day)}'),
      onTap: () => _open(day),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: marked ? AppColors.accent : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(DateTime day) async {
    final bundle = await widget.store.loadDay(day);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtWeekdayDate(day),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                for (final session in bundle.sessions)
                  SetLog(
                    session: session,
                    goals: widget.store.goals,
                    onPlayNote: widget.recorder == null
                        ? null
                        : (note) => widget.recorder!.play(
                            audioPath: note.audioPath,
                            transcript: note.transcript,
                          ),
                    onDeleteNote: (note) =>
                        widget.store.deleteVoiceNote(note.id),
                  ),
                if (bundle.morning != null)
                  Text('Morning · ${_checkLine(bundle.morning!)}'),
                if (bundle.evening != null)
                  Text('Evening · ${_checkLine(bundle.evening!)}'),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconTip(
                    icon: Icons.close,
                    message: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _checkLine(CheckIn checkIn) {
  final bits = <String>[];
  void add(String name, Object? value) {
    if (value != null) {
      bits.add('$name $value');
    }
  }

  add('soreness', checkIn.soreness);
  add('energy', checkIn.energy);
  add('sleep', checkIn.sleepQuality);
  add('hours', checkIn.sleepHours);
  add('mood', checkIn.mood);
  add('stress', checkIn.stress);
  add('feel', checkIn.sessionFeel);
  add('ate', checkIn.ateWell);
  return bits.join(' · ');
}
