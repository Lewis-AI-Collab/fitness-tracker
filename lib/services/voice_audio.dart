import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records a voice note to a file and plays that file back.
abstract class VoiceAudio {
  Future<String?> start();

  Future<String?> stop();

  Future<void> cancel();

  Future<void> play(String path);
}

class RecordVoiceAudio implements VoiceAudio {
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  var _open = false;

  AudioRecorder get _mic => _recorder ??= AudioRecorder();

  @override
  Future<String?> start() async {
    try {
      final allowed = await _mic.hasPermission();
      if (!allowed) {
        return null;
      }
      final root = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(root.path, 'voice_notes'));
      await folder.create(recursive: true);
      final path = p.join(
        folder.path,
        '${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      await _mic.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _open = true;
      return path;
    } on Object {
      _open = false;
      return null;
    }
  }

  @override
  Future<String?> stop() async {
    if (!_open) {
      return null;
    }
    _open = false;
    try {
      return await _mic.stop();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_open && _recorder == null) {
      return;
    }
    _open = false;
    try {
      await _mic.cancel();
    } on Object {
      // Nothing left to discard.
    }
  }

  @override
  Future<void> play(String path) async {
    final file = await _existing(path);
    if (file == null) {
      return;
    }
    final player = _player ??= AudioPlayer();
    await player.stop();
    await player.play(DeviceFileSource(file));
  }

  Future<String?> _existing(String path) async {
    if (await File(path).exists()) {
      return path;
    }
    try {
      final root = await getApplicationDocumentsDirectory();
      final fallback = p.join(root.path, 'voice_notes', p.basename(path));
      if (await File(fallback).exists()) {
        return fallback;
      }
    } on Object {
      return null;
    }
    return null;
  }
}
