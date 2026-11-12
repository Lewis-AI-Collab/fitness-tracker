import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/training.dart';
import '../services/normalise.dart';
import '../theme/app_theme.dart';
import 'finish_sheet.dart';
import 'icon_tip.dart';
import 'pace_flag.dart';
import 'value_picker.dart';
import 'voice_note_list.dart';

class SetLog extends StatelessWidget {
  const SetLog({
    super.key,
    required this.session,
    required this.goals,
    this.store,
    this.onEdit,
    this.onDelete,
    this.onPlayNote,
    this.onDeleteNote,
  });

  final Session session;
  final List<Goal> goals;
  final Store? store;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(VoiceNote note)? onPlayNote;
  final void Function(VoiceNote note)? onDeleteNote;

  @override
  Widget build(BuildContext context) {
    final logged = [
      for (final set in session.sets)
        if (set.reps != null || set.weightKg != null || set.distanceKm != null)
          set,
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _title(logged)),
              PaceFlagIcon(session: session, goals: goals),
              if (store != null)
                IconTip(
                  icon: Icons.task_alt,
                  message: 'Finish',
                  compact: true,
                  onPressed: () => showFinishSheet(
                    context,
                    session: session,
                    onSave: (rpe) => store!.setSessionRpe(session.id, rpe),
                  ),
                ),
              if (onEdit != null)
                IconTip(
                  icon: Icons.edit_outlined,
                  message: 'Edit',
                  compact: true,
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                IconTip(
                  icon: Icons.delete_outline,
                  message: 'Delete',
                  compact: true,
                  onPressed: onDelete,
                ),
            ],
          ),
          if (logged.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                sessionLine(session),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            for (final set in logged) _card(context, set),
          for (final block in session.blocks)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${block.label ?? _block(block.subtype)} · ${block.durationMin == null ? '?' : '${block.durationMin} min'} · RPE ${block.rpe}',
              ),
            ),
          VoiceNoteList(
            notes: session.voiceNotes,
            onPlay: onPlayNote == null
                ? null
                : (index) => onPlayNote!(session.voiceNotes[index]),
            onDelete: onDeleteNote == null
                ? null
                : (index) => onDeleteNote!(session.voiceNotes[index]),
          ),
        ],
      ),
    );
  }

  Widget _title(List<SetRow> logged) {
    final names = logged
        .map((set) => set.exerciseName)
        .whereType<String>()
        .toSet()
        .join(', ');
    return Text(
      names.isEmpty ? sessionLine(session) : names,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );
  }

  Widget _card(BuildContext context, SetRow set) {
    final live = store != null && set.id != 0;
    if (set.distanceKm != null && set.reps == null && set.weightKg == null) {
      return _shell(
        child: Text(
          '${fmtKm(set.distanceKm!)} km',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
      );
    }
    final kg = set.bodyweight && (set.weightKg == null || set.weightKg == 0)
        ? 'BW'
        : '${fmtKg(set.weightKg ?? 0)} kg';
    return _shell(
      child: Row(
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _number(
                    key: const ValueKey('set-reps'),
                    text: '${set.reps ?? '-'}',
                    onTap: live ? () => _pickReps(context, set) : null,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '×',
                      style: TextStyle(fontSize: 20, color: AppColors.muted),
                    ),
                  ),
                  _number(
                    key: const ValueKey('set-kg'),
                    text: kg,
                    accent: true,
                    onTap: live ? () => _pickKg(context, set) : null,
                  ),
                ],
              ),
            ),
          ),
          if (live) ...[
            IconTip(
              icon: Icons.remove,
              message: 'Remove set',
              compact: true,
              onPressed: () {
                final count = set.setCount ?? 1;
                if (count > 1) {
                  store!.updateSet(id: set.id, setCount: count - 1);
                }
              },
            ),
            Text(
              '${set.setCount ?? 1}',
              key: const ValueKey('set-count'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            IconTip(
              icon: Icons.add,
              message: 'Add set',
              compact: true,
              onPressed: () => store!.updateSet(
                id: set.id,
                setCount: (set.setCount ?? 1) + 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: cardBox(),
      child: child,
    );
  }

  Widget _number({
    required Key key,
    required String text,
    required VoidCallback? onTap,
    bool accent = false,
  }) {
    final style = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: accent ? AppColors.accent : AppColors.ink,
    );
    final label = Text(text, key: key, style: style);
    if (onTap == null) {
      return label;
    }
    return GestureDetector(onTap: onTap, child: label);
  }

  Future<void> _pickReps(BuildContext context, SetRow set) async {
    final next = await showValuePicker(
      context: context,
      values: [for (var i = 1; i <= 30; i++) i],
      current: set.reps ?? 8,
      label: (value) => '${value.toInt()}',
    );
    if (next == null) {
      return;
    }
    await store!.updateSet(id: set.id, reps: next.toInt());
  }

  Future<void> _pickKg(BuildContext context, SetRow set) async {
    final next = await showValuePicker(
      context: context,
      values: [for (var i = 0; i <= 80; i++) i * 2.5],
      current: set.weightKg ?? 0,
      label: (value) => fmtKg(value.toDouble()),
    );
    if (next == null) {
      return;
    }
    await store!.updateSet(id: set.id, weightKg: next.toDouble());
  }
}

String _block(String subtype) => switch (subtype) {
  'technique' => 'Technique',
  'pads' => 'Pads',
  'clinch' => 'Clinch',
  'sparring' => 'Sparring',
  'conditioning' => 'Conditioning',
  'other' => 'Other',
  _ => subtype,
};
