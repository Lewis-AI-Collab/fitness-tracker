import 'package:flutter/material.dart';

import '../models/training.dart';
import 'icon_tip.dart';

class VoiceNoteList extends StatelessWidget {
  const VoiceNoteList({
    super.key,
    required this.notes,
    this.onPlay,
    this.onDelete,
  });

  final List<VoiceNote> notes;
  final void Function(int index)? onPlay;
  final void Function(int index)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < notes.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _line(notes[i]),
                    key: ValueKey('voice-note-$i'),
                    style: const TextStyle(fontSize: 16, height: 1.3),
                  ),
                ),
                if (onPlay != null)
                  IconTip(
                    key: ValueKey('play-note-$i'),
                    icon: Icons.play_arrow,
                    message: 'Play',
                    compact: true,
                    onPressed: () => onPlay!(i),
                  ),
                if (onDelete != null)
                  IconTip(
                    key: ValueKey('delete-note-$i'),
                    icon: Icons.delete_outline,
                    message: 'Delete note',
                    compact: true,
                    onPressed: () => onDelete!(i),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _line(VoiceNote note) {
    final said = note.transcript.trim().isEmpty
        ? 'Voice note'
        : note.transcript.trim();
    final who = note.exerciseName?.trim();
    if (who == null || who.isEmpty) {
      return said;
    }
    return '$who · $said';
  }
}
