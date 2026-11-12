import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/checkin_scheduler.dart';
import '../services/dates.dart';
import '../services/speech_capture.dart';
import '../services/voice_audio.dart';
import '../services/workout_recorder.dart';
import '../theme/app_theme.dart';
import 'checkin_screen.dart';
import 'history_screen.dart';
import 'insights_screen.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.scheduler,
    this.speech,
    this.recorder,
  });

  final Store store;
  final CheckInScheduler scheduler;
  final SpeechCapture? speech;
  final WorkoutRecorder? recorder;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  var _index = 0;
  late final SpeechCapture _speech = widget.speech ?? SpeechCapture();
  late final WorkoutRecorder _notes =
      widget.recorder ??
      SpeechWorkoutRecorder(_speech, audio: RecordVoiceAudio());
  DateTime? _historyDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.pendingSlot.addListener(_onPending);
    widget.store.addListener(_refresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.pendingSlot.removeListener(_onPending);
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.scheduler.onResume(widget.store.schedule);
    }
  }

  void _onPending() {
    final value = widget.store.pendingSlot.value;
    if (value == null || !mounted) {
      return;
    }
    widget.store.pendingSlot.value = null;
    if (value == 'morning' || value == 'evening') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              CheckInScreen(store: widget.store, slot: value, speech: _speech),
        ),
      );
      return;
    }
    if (value.startsWith('history:')) {
      final day = parseIsoDate(value.substring('history:'.length));
      setState(() {
        _index = 2;
        _historyDay = day;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(store: widget.store, speech: _speech, recorder: _notes),
      PlanScreen(store: widget.store),
      HistoryScreen(
        store: widget.store,
        initialDay: _historyDay,
        recorder: _notes,
      ),
      InsightsScreen(store: widget.store),
      SettingsScreen(store: widget.store, scheduler: widget.scheduler),
    ];
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          if (widget.store.notificationsDenied)
            const Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: 'Notifications',
                child: Icon(Icons.notifications_off, color: AppColors.accent),
              ),
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _tab(0, Icons.today_outlined, 'Today'),
                _tab(1, Icons.calendar_view_week_outlined, 'Plan'),
                _tab(2, Icons.calendar_month_outlined, 'History'),
                _tab(3, Icons.insights_outlined, 'Insights'),
                _tab(4, Icons.settings_outlined, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, String message) {
    final selected = _index == index;
    return Tooltip(
      message: message,
      child: IconButton(
        key: ValueKey('tab-$message'),
        onPressed: () => setState(() => _index = index),
        icon: Icon(icon, color: selected ? AppColors.accent : AppColors.muted),
      ),
    );
  }
}
