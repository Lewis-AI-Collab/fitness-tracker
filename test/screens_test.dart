import 'package:fitness_tracker/app.dart';
import 'package:fitness_tracker/data/store.dart';
import 'package:fitness_tracker/screens/today_screen.dart';
import 'package:fitness_tracker/services/checkin_scheduler.dart';
import 'package:fitness_tracker/services/speech_capture.dart';
import 'package:fitness_tracker/services/voice_parser.dart';
import 'package:fitness_tracker/theme/app_theme.dart';
import 'package:fitness_tracker/widgets/confirm_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

class RecordingNotifications implements NotificationPort {
  final List<String> calls = [];

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel:$id');
  }

  @override
  Future<void> scheduleDaily(ScheduledSlot slot) async {
    calls.add('schedule:${slot.payload}:${slot.hour}:${slot.minute}');
  }

  @override
  Future<bool> requestPermissions() async {
    calls.add('permissions');
    return true;
  }

  @override
  Future<void> refreshTimezone() async {
    calls.add('timezone');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('today lists the session and both check-in buttons', (tester) async {
    final store = await _ready(tester);
    await _pump(tester, store, RecordingNotifications());

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Mon 12 Oct'), findsOneWidget);
    expect(find.text('Gym · legs · hard'), findsOneWidget);
    expect(find.text('Bench press'), findsWidgets);
    expect(find.text('70 kg'), findsWidgets);
    expect(find.byKey(const ValueKey('set-reps')), findsWidgets);
    expect(find.byTooltip('Rest'), findsNothing);
    expect(find.byKey(const ValueKey('rest-pill')), findsNothing);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('No routines yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('share')), findsOneWidget);
    expect(find.byKey(const ValueKey('morning-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('evening-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('mic')), findsOneWidget);
  });

  testWidgets('morning and evening check-ins open, edit, and save', (tester) async {
    final store = await _ready(tester);
    await _pump(tester, store, RecordingNotifications());

    await tester.tap(find.byKey(const ValueKey('morning-status')));
    await _settle(tester);
    expect(find.text('Morning'), findsWidgets);
    expect(find.text('Soreness'), findsOneWidget);
    expect(find.text('Sleep hours'), findsOneWidget);
    expect(find.text('2'), findsWidgets);

    await tester.drag(find.byType(Slider).at(1), const Offset(80, 0));
    await _settle(tester);
    await tester.tap(find.byTooltip('Save'));
    await _backOnToday(tester);

    final morning = await tester.runAsync(() => store.checkInOn('2026-10-12', 'morning'));
    expect(morning, isNotNull);
    expect(morning!.energy, isNot(5));

    await tester.tap(find.byKey(const ValueKey('evening-status')));
    await _settle(tester);
    expect(find.text('Evening'), findsWidgets);
    expect(find.text('Session feel'), findsOneWidget);
    expect(find.text('Ate well'), findsOneWidget);
    await tester.tap(find.byTooltip('Save'));
    await _backOnToday(tester);
    final evening = await tester.runAsync(() => store.checkInOn('2026-10-12', 'evening'));
    expect(evening, isNotNull);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('plan shows weekly cards and a warning pop-out', (tester) async {
    final store = await _ready(tester);
    await _pump(tester, store, RecordingNotifications());

    await tester.tap(find.byKey(const ValueKey('tab-Plan')));
    await _settle(
      tester,
      ready: () => find.text('12–18 Oct 2026').evaluate().isNotEmpty,
    );

    expect(find.text('12–18 Oct 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-cards')), findsOneWidget);
    expect(find.text('Bench: 80 kg x 7,7 -> keep 80, aim 8s'), findsOneWidget);
    expect(find.text('Row: 50 kg x 12,12 -> 52.5 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('load-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('balance')), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('warning-2026-10-12')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('plan-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('warning-2026-10-12')));
    await _settle(tester);
    expect(find.textContaining('Thai hard'), findsOneWidget);
    expect(find.textContaining('Next-day fatigue 8, 7, 9'), findsOneWidget);
    await tester.tap(find.byTooltip('17 Sep'));
    await _settle(tester);
    expect(find.text('Sep 2026'), findsOneWidget);
  });

  testWidgets('settings times reschedule and hide unit choices', (tester) async {
    final store = await _ready(tester);
    final port = RecordingNotifications();
    await _pump(tester, store, port);

    await tester.tap(find.byKey(const ValueKey('tab-Settings')));
    await _settle(tester);
    expect(find.byTooltip('08:00'), findsOneWidget);
    expect(find.byTooltip('21:00'), findsOneWidget);
    expect(find.textContaining('mile'), findsNothing);
    expect(find.textContaining('pound'), findsNothing);
    expect(find.textContaining('Units'), findsNothing);
    expect(find.text('lb'), findsNothing);

    port.calls.clear();
    await tester.tap(find.byKey(const ValueKey('Morning-switch')));
    await _settle(
      tester,
      ready: () => port.calls.contains('cancel:${CheckInSchedule.morningId}'),
    );
    expect(store.schedule.morningEnabled, isFalse);
    expect(port.calls, contains('cancel:${CheckInSchedule.morningId}'));
    expect(
      port.calls.where((call) => call.startsWith('schedule:morning')),
      isEmpty,
    );
    expect(port.calls, contains('schedule:evening:21:0'));
  });

  testWidgets('history opens a logged day', (tester) async {
    final store = await _ready(tester);
    await _pump(tester, store, RecordingNotifications());

    await tester.tap(find.byKey(const ValueKey('tab-History')));
    await _settle(tester);
    expect(find.text('Oct 2026'), findsOneWidget);
    expect(find.text('Mon'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('history-2026-10-12')));
    await _settle(
      tester,
      ready: () => find.textContaining('Morning ·').evaluate().isNotEmpty,
    );
    expect(find.text('Mon 12 Oct'), findsWidgets);
    expect(find.textContaining('Morning ·'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await _settle(tester);
  });

  testWidgets('confirm card shows a gym set and a Thai combo, then auto-saves', (
    tester,
  ) async {
    final store = await _ready(tester);
    await _pump(tester, store, RecordingNotifications());
    final parser = VoiceParser(store.exercises);

    await _showConfirm(
      tester,
      store,
      parser.parse('bench press, 4 sets of 8 at 70 kilos'),
      autoSave: false,
    );
    expect(find.byKey(const ValueKey('confirm-card')), findsOneWidget);
    expect(find.text('Bench press · 4×8 · 70 kg'), findsWidgets);
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);

    await _showConfirm(
      tester,
      store,
      parser.parse('an hour of technique and pads and 30 minutes of clinch'),
      autoSave: false,
    );
    expect(find.textContaining('Technique'), findsWidgets);
    expect(find.textContaining('Pads'), findsWidgets);
    expect(find.textContaining('Clinch'), findsWidgets);
    await tester.tap(find.byTooltip('Save'));
    await _settle(
      tester,
      ready: () => find.byKey(const ValueKey('confirm-card')).evaluate().isEmpty,
    );
    final day = await tester.runAsync(() => store.loadDay(DateTime(2026, 10, 12)));
    expect(day!.sessions.where((session) => session.blocks.length == 3), isNotEmpty);

    final before = (await tester.runAsync(() => store.loadDay(DateTime(2026, 10, 12))))!
        .sessions
        .length;
    await _showConfirm(
      tester,
      store,
      parser.parse('squats 5 by 5 100k'),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await _settle(tester);
    expect(find.byKey(const ValueKey('confirm-card')), findsNothing);
    final after = (await tester.runAsync(() => store.loadDay(DateTime(2026, 10, 12))))!;
    expect(after.sessions.length, before + 1);
    expect(
      after.sessions.any((session) => sessionLine(session) == 'Back squat · 5×5 · 100 kg'),
      isTrue,
    );
  });

  testWidgets('a denied notification permission leaves the toggle off', (tester) async {
    final store = await _ready(tester);
    final port = _DenyingNotifications();
    await _pump(tester, store, port);

    await tester.tap(find.byKey(const ValueKey('tab-Settings')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('Morning-switch')));
    await _settle(
      tester,
      ready: () {
        final morning = tester.widget<Switch>(find.byKey(const ValueKey('Morning-switch')));
        return !morning.value && port.calls.contains('schedule:evening:21:0');
      },
    );
    expect(store.schedule.morningEnabled, isFalse);

    port.calls.clear();
    await tester.tap(find.byKey(const ValueKey('Morning-switch')));
    await _settle(
      tester,
      ready: () =>
          port.calls.contains('permissions') &&
          find.byIcon(Icons.notifications_off).evaluate().isNotEmpty,
    );
    expect(store.schedule.morningEnabled, isFalse);
    expect(port.calls, ['permissions']);
    expect(find.byIcon(Icons.notifications_off), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('confirm card flags a rejected RIR and a converted weight', (tester) async {
    final store = await _ready(tester);
    await _pump(tester, store, RecordingNotifications());
    final parser = VoiceParser.seeded();
    await _showConfirm(
      tester,
      store,
      parser.parse('bench 3x8 at 100 pounds not to failure'),
      autoSave: false,
    );
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    expect(find.byTooltip('kg'), findsOneWidget);
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);

    await _showConfirm(
      tester,
      store,
      parser.parse('bench 3x8 at 15 kg'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('confirm-card')), findsOneWidget);
    expect(find.byTooltip('Bar'), findsOneWidget);
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);

    await _showConfirm(
      tester,
      store,
      parser.parse('bench 3x8 at 100 pounds'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('confirm-card')), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);

    await _showConfirm(tester, store, parser.parse('ran 3 miles'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('confirm-card')), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);

    await _showConfirm(
      tester,
      store,
      parser.parse('bench 3x8 failed on set 0'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('confirm-card')), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);

    await _showConfirm(tester, store, parser.parse('muay thai sparring'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('confirm-card')), findsOneWidget);
    expect(find.text('?'), findsWidgets);
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);

    await _showConfirm(
      tester,
      store,
      parser.parse('muay thai sparring'),
      autoSave: false,
    );
    expect(find.text('?'), findsWidgets);
    expect(find.textContaining('0 min'), findsNothing);
  });

  testWidgets('set picker, share deck, and period pop-out', (tester) async {
    final store = await _ready(tester);
    await _pump(tester, store, RecordingNotifications());

    await tester.tap(find.byKey(const ValueKey('set-reps')));
    await _until(tester, () => find.byKey(const ValueKey('pick-9')).evaluate().isNotEmpty);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pick-9')));
    await _until(
      tester,
      () =>
          find.byKey(const ValueKey('pick-9')).evaluate().isEmpty &&
          find.text('9').evaluate().isNotEmpty,
    );
    expect(find.text('9'), findsWidgets);

    await tester.tap(find.byTooltip('Add set'));
    await _until(tester, () {
      final finder = find.byKey(const ValueKey('set-count'));
      if (finder.evaluate().isEmpty) {
        return false;
      }
      return tester.widget<Text>(finder).data == '5';
    });
    expect(find.text('5'), findsWidgets);

    await tester.tap(find.byTooltip('Finish'));
    await _until(
      tester,
      () => find.byKey(const ValueKey('finish-sheet')).evaluate().isNotEmpty,
    );
    expect(find.textContaining('How hard'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    final save = find.descendant(
      of: find.byKey(const ValueKey('finish-sheet')),
      matching: find.byTooltip('Save'),
    );
    tester.widget<IconButton>(find.descendant(of: save, matching: find.byType(IconButton))).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('finish-sheet')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('share')));
    await _until(tester, () => find.text('WORKOUT').evaluate().isNotEmpty);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Grok'), findsOneWidget);
    expect(find.byTooltip('Share'), findsWidgets);
    expect(find.text('DAY'), findsWidgets);
    await tester.fling(
      find.byKey(const ValueKey('share-deck')),
      const Offset(-400, 0),
      1200,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('WEEK'), findsWidgets);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('WORKOUT'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-Plan')));
    await _until(tester, () => find.byKey(const ValueKey('load-hero')).evaluate().isNotEmpty);
    final pull = tester.widget<Container>(find.byKey(const ValueKey('balance-bar-Pull')));
    final push = tester.widget<Container>(find.byKey(const ValueKey('balance-bar-Push')));
    expect((pull.decoration! as BoxDecoration).color, AppColors.accent);
    expect((push.decoration! as BoxDecoration).color, AppColors.ink);

    await tester.tap(find.byKey(const ValueKey('period')));
    await _until(tester, () => find.byKey(const ValueKey('period-menu')).evaluate().isNotEmpty);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('3 months'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.text('3 months'));
    await tester.pump(const Duration(milliseconds: 400));
    await _until(
      tester,
      () => find
          .descendant(
            of: find.byKey(const ValueKey('load-hero')),
            matching: find.text('3 months'),
          )
          .evaluate()
          .isNotEmpty,
    );
  });
}

class _DenyingNotifications extends RecordingNotifications {
  @override
  Future<bool> requestPermissions() async {
    calls.add('permissions');
    return false;
  }
}

Future<Store> _ready(WidgetTester tester) async {
  final store = await tester.runAsync(openStore);
  await tester.runAsync(() => seedDemo(store!));
  return store!;
}

Store? _liveStore;

/// Lets sqlite finish on real time, then pumps so the test returns with no
/// lock timer still pending.
Future<void> _quiet(WidgetTester tester, Store store) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    if (!store.busy) {
      return;
    }
  }
  fail('Database work did not finish');
}

Future<void> _pump(WidgetTester tester, Store store, RecordingNotifications port) async {
  _liveStore = store;
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await _quiet(tester, store);
  });
  await tester.pumpWidget(
    FitnessApp(
      store: store,
      scheduler: CheckInScheduler(port),
      speech: SpeechCapture(),
    ),
  );
  await _settle(
    tester,
    ready: () => find.text('Gym · legs · hard').evaluate().isNotEmpty,
  );
}

/// sqflite finishes on real time, outside FakeAsync. [ready] waits until that
/// work has updated the tree or the notification port, instead of a fixed slice.
Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump();
    if (ready()) {
      await tester.pump();
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  }
  fail('Timed out waiting for the screen');
}

Future<void> _settle(WidgetTester tester, {bool Function()? ready}) async {
  const slices = 40;
  final limit = ready == null ? 8 : slices;
  for (var i = 0; i < limit; i++) {
    await tester.pump();
    if (ready != null && ready()) {
      break;
    }
    if (i + 1 >= limit) {
      break;
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  }
  await tester.pumpAndSettle();
  final store = _liveStore;
  if (store != null) {
    await _quiet(tester, store);
  }
}

/// Check-in save learns patterns on real sqlite time, then pops. A single
/// short wait can return while that route still covers Today. The reloads
/// finish on real time before the test returns.
Future<void> _backOnToday(WidgetTester tester) async {
  final today = find.byKey(const ValueKey('evening-status'));
  for (var i = 0; i < 40; i++) {
    await tester.pump();
    if (today.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      final store = _liveStore;
      if (store != null) {
        await _quiet(tester, store);
      }
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  }
  fail('Check-in did not return to Today');
}

Future<void> _showConfirm(
  WidgetTester tester,
  Store store,
  ParseResult result, {
  bool autoSave = true,
}) async {
  final context = tester.element(find.byType(TodayScreen));
  showDialog<void>(
    context: context,
    builder: (context) => ConfirmCard(
      result: result,
      exercises: store.exercises,
      onAlias: store.addAlias,
      onSave: (draft) => store.saveParse(draft),
      autoSaveAfter: autoSave ? const Duration(seconds: 3) : null,
    ),
  );
  await _settle(tester);
}

