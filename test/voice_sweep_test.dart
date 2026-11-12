import 'dart:io';

import 'package:fitness_tracker/data/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Directory _notes;
late String _db;

Future<Store> _open() async {
  final store = Store(
    clock: () => DateTime(2026, 10, 12, 9),
    voiceNotesDir: _notes,
  );
  await store.init(path: _db);
  return store;
}

File _clip(String name) {
  final file = File('${_notes.path}/$name');
  file.writeAsStringSync('aac');
  return file;
}

Future<void> _savedNote(Store store, String date, String? audio) async {
  final id = await store.db.insert('sessions', {'date': date, 'type': 'gym'});
  await store.db.insert('voice_notes', {
    'session_id': id,
    'transcript': 'note',
    'audio_path': audio,
    'created_at': '${date}T10:00:00',
  });
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('voice_sweep');
    _notes = Directory('${root.path}/Documents/voice_notes')
      ..createSync(recursive: true);
    _db = '${root.path}/fitness.db';
  });

  test('startup keeps every recording a saved session points at', () async {
    var store = await _open();
    final kept = <File>[];
    for (var i = 0; i < 40; i++) {
      final file = _clip('${100 + i}.m4a');
      kept.add(file);
      final day = DateTime(2024, 1, 1).add(Duration(days: i * 20));
      await _savedNote(store, day.toIso8601String().substring(0, 10), file.path);
    }
    await _savedNote(store, '2026-01-01', null);
    final orphan = _clip('99.m4a');
    await store.db.close();
    store = await _open();
    expect(kept.where((file) => !file.existsSync()), isEmpty);
    expect(orphan.existsSync(), isFalse);
  });

  test('startup matches by file name after the app folder moves', () async {
    var store = await _open();
    final saved = _clip('200.m4a');
    final open = _clip('201.m4a');
    const old = '/var/mobile/Containers/Data/Application/OLD/Documents/voice_notes';
    await _savedNote(store, '2026-01-01', '$old/200.m4a');
    store.startWorkout();
    store.addActiveNote(transcript: 'open', audioPath: '$old/201.m4a');
    await store.settled;
    await store.db.close();
    store = await _open();
    expect(saved.existsSync(), isTrue);
    expect(open.existsSync(), isTrue);
  });

  test('startup leaves files outside the notes folder alone', () async {
    var store = await _open();
    final outside = File('${_notes.parent.path}/300.m4a')
      ..writeAsStringSync('aac');
    final nested = File('${_notes.path}/sub/301.m4a')
      ..createSync(recursive: true);
    await store.db.close();
    store = await _open();
    expect(outside.existsSync(), isTrue);
    expect(nested.existsSync(), isTrue);
  });
}
