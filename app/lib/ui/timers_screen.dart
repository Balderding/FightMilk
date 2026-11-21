import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sounds.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Stopwatch, countdown, EMOM, Tabata and a tap rep counter. Buzz and sound at each change.
class TimersScreen extends StatefulWidget {
  final AppState s;
  const TimersScreen({super.key, required this.s});
  @override
  State<TimersScreen> createState() => _TimersScreenState();
}

enum _Mode { stopwatch, countdown, emom, tabata, reps }

const _modeLabel = {_Mode.stopwatch: 'Stopwatch', _Mode.countdown: 'Countdown', _Mode.emom: 'EMOM', _Mode.tabata: 'Tabata', _Mode.reps: 'Rep counter'};

class _TimersScreenState extends State<TimersScreen> {
  _Mode mode = _Mode.stopwatch;
  Timer? _t;
  DateTime? _start;
  Duration _paused = Duration.zero;
  int countdown = 60; // seconds
  int emomEvery = 60, emomRounds = 10;
  int tabWork = 20, tabRest = 10, tabRounds = 8;
  int reps = 0;
  int _lastPhase = -1;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Duration get _elapsed => _start == null ? _paused : _paused + DateTime.now().difference(_start!);
  bool get running => _start != null;

  void _toggle() {
    setState(() {
      if (running) {
        _paused = _elapsed;
        _start = null;
        _t?.cancel();
      } else {
        _start = DateTime.now();
        _t = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
      }
    });
  }

  void _reset() {
    _t?.cancel();
    setState(() {
      _start = null;
      _paused = Duration.zero;
      _lastPhase = -1;
      reps = 0;
    });
  }

  void _beep() {
    HapticFeedback.heavyImpact();
    widget.s.sounds.play(Reward.restOver);
  }

  /// (big text, small text, phase number to buzz on change, finished)
  (String, String, int, bool) get _view {
    final e = _elapsed;
    String mmss(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
    switch (mode) {
      case _Mode.stopwatch:
        return ('${mmss(e.inSeconds)}.${(e.inMilliseconds % 1000 ~/ 100)}', 'Stopwatch', 0, false);
      case _Mode.countdown:
        final left = countdown - e.inSeconds;
        return (mmss(left.clamp(0, 99999)), left <= 0 ? 'Done' : 'Countdown', left <= 0 ? 1 : 0, left <= 0);
      case _Mode.emom:
        final round = e.inSeconds ~/ emomEvery;
        final left = emomEvery - e.inSeconds % emomEvery;
        final done = round >= emomRounds;
        return (done ? 'Done' : mmss(left), done ? '$emomRounds rounds' : 'Round ${round + 1} of $emomRounds', round, done);
      case _Mode.tabata:
        final cycle = tabWork + tabRest;
        final round = e.inSeconds ~/ cycle;
        final inCycle = e.inSeconds % cycle;
        final work = inCycle < tabWork;
        final done = round >= tabRounds;
        final left = work ? tabWork - inCycle : cycle - inCycle;
        return (done ? 'Done' : mmss(left), done ? '$tabRounds rounds' : '${work ? 'WORK' : 'rest'} · round ${round + 1} of $tabRounds', round * 2 + (work ? 0 : 1), done);
      case _Mode.reps:
        return ('$reps', 'Tap anywhere to count', reps, false);
    }
  }

  void _tick() {
    if (!mounted) return;
    final (_, _, phase, done) = _view;
    if (phase != _lastPhase) {
      if (_lastPhase >= 0 && mode != _Mode.stopwatch) _beep();
      _lastPhase = phase;
    }
    if (done) {
      _paused = _elapsed;
      _start = null;
      _t?.cancel();
    }
    setState(() {});
  }

  Widget _stepper(String label, int v, int step, int min, int max, void Function(int) f) => Row(children: [
        Expanded(child: Text(label)),
        IconButton(onPressed: running ? null : () => setState(() => f((v - step).clamp(min, max))), icon: const Icon(Icons.remove)),
        SizedBox(width: 60, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(onPressed: running ? null : () => setState(() => f((v + step).clamp(min, max))), icon: const Icon(Icons.add)),
      ]);

  @override
  Widget build(BuildContext context) {
    final (big, small, _, _) = _view;
    return Scaffold(
      appBar: AppBar(title: const Text('Timers')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in _Mode.values)
            ChoiceChip(
              label: Text(_modeLabel[m]!, style: TextStyle(color: m == mode ? C.onTeal : C.text)),
              selected: m == mode,
              showCheckmark: false,
              onSelected: running ? null : (_) => setState(() {
                mode = m;
                _reset();
              }),
            ),
        ]),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: mode == _Mode.reps
              ? () {
                  HapticFeedback.selectionClick();
                  setState(() => reps++);
                }
              : null,
          child: Container(
            height: 220,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(18)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(big, style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w700, color: C.gold, fontFeatures: [FontFeature.tabularFigures()])),
              Dim(small, size: 15),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (mode != _Mode.reps)
          Row(children: [
            Expanded(child: FilledButton(onPressed: _toggle, child: Text(running ? 'Pause' : 'Start'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _reset, child: const Text('Reset'))),
          ])
        else
          OutlinedButton(onPressed: _reset, child: const Text('Reset')),
        const SizedBox(height: 12),
        if (mode == _Mode.countdown) _stepper('Seconds', countdown, 15, 15, 3600, (v) => countdown = v),
        if (mode == _Mode.emom) ...[
          _stepper('Every (seconds)', emomEvery, 15, 15, 300, (v) => emomEvery = v),
          _stepper('Rounds', emomRounds, 1, 1, 60, (v) => emomRounds = v),
        ],
        if (mode == _Mode.tabata) ...[
          _stepper('Work (seconds)', tabWork, 5, 5, 120, (v) => tabWork = v),
          _stepper('Rest (seconds)', tabRest, 5, 5, 120, (v) => tabRest = v),
          _stepper('Rounds', tabRounds, 1, 1, 30, (v) => tabRounds = v),
        ],
        const SizedBox(height: 8),
        const Dim('EMOM: start a set every minute on the minute. Tabata: 20 s hard, 10 s rest, 8 rounds.', size: 12),
      ]),
    );
  }
}
