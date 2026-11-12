import 'dart:io';

import 'package:fitness_tracker/app.dart';
import 'package:fitness_tracker/data/database.dart';
import 'package:fitness_tracker/main.dart';
import 'package:fitness_tracker/services/checkin_scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

class _Deny implements NotificationPort {
  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> scheduleDaily(ScheduledSlot slot) async {}

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> refreshTimezone() async {}
}

void main() {
  test('a newer database opens the error screen', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('fitness-newer');
    final path = '${directory.path}/newer.db';
    final newer = await openDatabase(
      path,
      version: fitnessSchemaVersion + 1,
      onCreate: (db, version) async {},
    );
    await newer.close();

    final app = await startApp(databasePath: path, notifications: _Deny());
    expect(app, isA<DatabaseErrorApp>());
  });

  test('a denied permission on launch turns check-ins off', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('fitness-deny');
    final app = await startApp(
      databasePath: '${directory.path}/fitness.db',
      notifications: _Deny(),
    );
    expect(app, isA<FitnessApp>());
    final fitness = app as FitnessApp;
    expect(fitness.store.schedule.morningEnabled, isFalse);
    expect(fitness.store.schedule.eveningEnabled, isFalse);
    expect(fitness.store.notificationsDenied, isTrue);
  });

  testWidgets('the database error screen is an icon', (tester) async {
    await tester.pumpWidget(const DatabaseErrorApp());
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byTooltip('Database'), findsOneWidget);
    expect(find.textContaining('Cannot'), findsNothing);
  });

  testWidgets('a denied launch shows the notifications icon', (tester) async {
    final store = await tester.runAsync(openStore);
    await tester.runAsync(() => store!.setNotificationsDenied(true));
    await tester.pumpWidget(
      FitnessApp(store: store!, scheduler: CheckInScheduler(_Deny())),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    expect(find.byIcon(Icons.notifications_off), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });
}
