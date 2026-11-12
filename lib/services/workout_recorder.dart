import 'speech_capture.dart';
import 'voice_audio.dart';

class VoiceCapture {
  const VoiceCapture({
    this.transcript = '',
    this.audioPath,
    this.denied = false,
  });

  final String transcript;
  final String? audioPath;
  final bool denied;
}

class MicPermissionDenied implements Exception {
  const MicPermissionDenied();
}

/// One voice note during a workout: start, stop, play back.
/// Tests pass a fake. The phone uses speech plus an audio file.
abstract class WorkoutRecorder {
  Future<void> start();

  Future<VoiceCapture> stop();

  Future<void> play({String? audioPath, String? transcript});

  Future<void> cancel();
}

class SpeechWorkoutRecorder implements WorkoutRecorder {
  SpeechWorkoutRecorder(this._speech, {this.audio});

  final SpeechCapture _speech;
  final VoiceAudio? audio;
  String _latest = '';
  String? _path;
  var _speechReady = false;

  @override
  Future<void> start() async {
    _latest = '';
    _path = null;
    _speechReady = await _speech.ensureReady();
    try {
      _path = await audio?.start();
    } on Object {
      _path = null;
    }
    final heard = _path != null && _path!.isNotEmpty;
    if (!_speechReady && !heard) {
      throw const MicPermissionDenied();
    }
    if (!_speechReady) {
      return;
    }
    try {
      await _speech.start(onText: (words, _) => _latest = words);
    } on Object {
      if (!heard) {
        throw const MicPermissionDenied();
      }
    }
  }

  @override
  Future<VoiceCapture> stop() async {
    if (_speechReady) {
      try {
        await _speech.stop();
      } on Object {
        // Keep whatever was heard before the mic closed.
      }
    }
    var path = _path;
    try {
      path = await audio?.stop() ?? _path;
    } on Object {
      path = _path;
    }
    return VoiceCapture(transcript: _latest.trim(), audioPath: path);
  }

  @override
  Future<void> play({String? audioPath, String? transcript}) async {
    if ((audioPath == null || audioPath.isEmpty) &&
        (transcript == null || transcript.trim().isEmpty)) {
      return;
    }
    final player = audio;
    if (audioPath == null || audioPath.isEmpty || player == null) {
      return;
    }
    try {
      await player.play(audioPath);
    } on Object {
      // A missing file should not take down the session.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } on Object {
      // Already stopped.
    }
    try {
      await audio?.cancel();
    } on Object {
      // Already stopped.
    }
    _latest = '';
    _path = null;
  }
}
