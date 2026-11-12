import 'package:fitness_tracker/services/speech_capture.dart';
import 'package:fitness_tracker/services/voice_audio.dart';
import 'package:fitness_tracker/services/workout_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

class _Speech extends SpeechCapture {
  _Speech(this.ready);
  final bool ready;
  @override
  Future<bool> ensureReady() async => ready;
  @override
  Future<void> start({
    required void Function(String words, bool done) onText,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _Audio implements VoiceAudio {
  _Audio(this.path);
  final String? path;
  @override
  Future<String?> start() async => path;
  @override
  Future<String?> stop() async => path;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> play(String path) async {}
}

void main() {
  test('no speech and no mic file is reported as denied', () async {
    final recorder = SpeechWorkoutRecorder(_Speech(false), audio: _Audio(null));
    await expectLater(recorder.start(), throwsA(isA<MicPermissionDenied>()));
  });

  test('a recording without speech still counts', () async {
    final recorder = SpeechWorkoutRecorder(
      _Speech(false),
      audio: _Audio('/a.m4a'),
    );
    await recorder.start();
    expect((await recorder.stop()).audioPath, '/a.m4a');
  });
}
