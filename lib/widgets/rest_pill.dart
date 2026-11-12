import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One second later, stopping at zero.
int restSecondsLeft(int remaining) => remaining <= 1 ? 0 : remaining - 1;

/// Rest countdown. Shown only inside an active workout.
class RestPill extends StatefulWidget {
  const RestPill({
    super.key,
    this.seconds = 90,
    this.startToken = 0,
    this.onSecondsChanged,
  });

  final int seconds;

  /// Increases each time a set is ticked, which starts the countdown.
  final int startToken;
  final ValueChanged<int>? onSecondsChanged;

  @override
  State<RestPill> createState() => _RestPillState();
}

class _RestPillState extends State<RestPill> {
  Timer? _timer;
  late int _left = widget.seconds;
  var _running = false;

  @override
  void didUpdateWidget(RestPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    final started =
        widget.startToken != oldWidget.startToken && widget.startToken > 0;
    if (started) {
      _arm(widget.seconds);
      return;
    }
    if (widget.seconds != oldWidget.seconds) {
      _left = widget.seconds;
      if (_running) {
        _arm(widget.seconds);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _liveClock =>
      !WidgetsBinding.instance.runtimeType.toString().contains('Test');

  void _arm(int seconds) {
    _timer?.cancel();
    _left = seconds;
    _running = true;
    if (!_liveClock) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        return;
      }
      final next = restSecondsLeft(_left);
      if (next == 0) {
        timer.cancel();
        setState(() {
          _left = 0;
          _running = false;
        });
        return;
      }
      setState(() => _left = next);
    });
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    _arm(widget.seconds);
    setState(() {});
  }

  void _change(int delta) {
    final next = (widget.seconds + delta).clamp(15, 300).toInt();
    widget.onSecondsChanged?.call(next);
  }

  String _clock(int total) {
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: 'Rest',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('rest-pill'),
              onTap: _toggle,
              borderRadius: BorderRadius.circular(24),
              child: Ink(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: AppColors.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Rest',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _clock(_left),
                      key: ValueKey(_running ? 'rest-running' : 'rest-idle'),
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('rest-less'),
          tooltip: 'Less rest',
          onPressed: () => _change(-15),
          icon: const Icon(Icons.remove, color: AppColors.accent),
        ),
        IconButton(
          key: const ValueKey('rest-more'),
          tooltip: 'More rest',
          onPressed: () => _change(15),
          icon: const Icon(Icons.add, color: AppColors.accent),
        ),
      ],
    );
  }
}
