import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../domain/coach.dart';
import '../domain/exercise.dart';
import '../domain/plates.dart';
import '../domain/warmup_text.dart';
import '../domain/plan.dart';
import '../domain/program.dart';
import '../domain/superset.dart';
import '../domain/units.dart';
import '../services/sounds.dart';
import 'anim/exercise_anim.dart';
import 'app_state.dart';
import 'coach_screen.dart';
import 'coaching_screen.dart';
import 'pickers.dart';
import 'theme.dart';
import 'timers_screen.dart';
import 'widgets.dart';

/// The screen that matters most: one tap per set, weight and reps already filled in.
/// F086: how long after the last touch the screen goes dark in a rest (tests shorten it).
Duration restDimAfter = const Duration(seconds: 8);

class LogScreen extends StatefulWidget {
  final AppState s;
  const LogScreen({super.key, required this.s});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  AppState get s => widget.s;
  int ex = 0;
  List<SetLog> sets = [];
  double kg = 0;
  int reps = 0;
  bool loaded = false;
  Target? target;
  List<SetLog> last = [];

  Timer? _timer;
  bool _beeped = false;
  int? _undoEx; // the exercise the Undo button's set belongs to
  DateTime? _setAt; // when the last set was logged (for effort taps)
  int? _lastReps;
  bool _lastWasFinal = false;
  Effort? _effort;
  String? _lastSetId; // the set the effort tap belongs to
  SetType _type = SetType.work; // what the next "Done set" logs
  String _exNote = ''; // pinned note for this exercise (seat height, grip...)
  double _bestE1rm = 0; // records before today, for the live record flash
  double _bestKg = 0;
  Map<int, int> _bestRepsAt = {}; // weight (rounded to 0.1 kg) -> most reps ever

  PlanDay get day => s.session!.day;
  PlanItem get item => day.items[ex];
  Exercise get e => s.lib.byId(item.exerciseId)!;
  List<SetLog> get mine => sets.where((x) => x.key == liftKey(item)).toList();

  /// Warm-up rows for this exercise: only the first big lift for its main muscle today, only
  /// before the first working set, and only when there is a weight to warm up to.
  List<(double, int)> get _warmups {
    if (!s.warmupsOn || !e.compound) return const [];
    final w = target?.kg ?? (counted.isEmpty ? null : counted.first.kg);
    if (w == null || w <= 0) return const [];
    final muscle = e.primary.first;
    for (var i = 0; i < ex; i++) {
      final o = s.lib.byId(day.items[i].exerciseId);
      if (o != null && o.compound && o.primary.first == muscle) return const [];
    }
    final ps = s.plateSetup;
    return warmupsFor(w, e, s.unit, barKg: barFor(e, barKg: ps.bar, smithKg: ps.smith));
  }

  Future<void> _logWarmup(double wkg, int wreps) async {
    HapticFeedback.selectionClick();
    final l = await s.repo.logSet(s.session!.id, item.exerciseId, wkg, wreps, type: SetType.warmup, slot: liftKey(item));
    _lastSetId = l.id;
    _undoEx = ex;
    await _load();
    _beeped = false;
    s.startRest(const Duration(seconds: 60));
  }

  /// Plates per side for the weight on screen (null = not a plate-loaded lift).
  (List<double>, double)? get _plates {
    final ps = s.plateSetup;
    final bar = barFor(e, barKg: ps.bar, smithKg: ps.smith);
    if (bar == null || kg <= 0) return null;
    return platesFor(kg, bar, ps.plates, s.unit);
  }

  /// Sets that count toward the plan (not warm-ups or drop sets).
  List<SetLog> get counted => mine.where((x) => x.counts).toList();

  /// Sets done for a plan slot (the same exercise twice in a day counts apart).
  int _countedFor(PlanItem it) => sets.where((x) => x.key == liftKey(it) && x.counts).length;

  /// The type the next set should be: the last planned set takes the item's style.
  SetType _defaultType() {
    final n = counted.length;
    if (item.perSet != null) return n < item.perSet!.length && item.perSet![n].amrap ? SetType.amrap : SetType.work;
    if (n == item.sets - 1) {
      return switch (item.style) { 'amrap' => SetType.amrap, 'failure' => SetType.failure, 'restpause' => SetType.restpause, _ => SetType.work };
    }
    return SetType.work;
  }

  /// F086: the last touch; the screen dims [restDimAfter] after it while a rest runs.
  DateTime _touchAt = DateTime.now();

  bool get _dimmed {
    final left = s.restLeft;
    return s.settings.dimRest && left != null && left > Duration.zero && DateTime.now().difference(_touchAt) >= restDimAfter;
  }

  @override
  void initState() {
    super.initState();
    if (s.settings.keepAwake) WakelockPlus.enable().ignore();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    _beeped = s.restLeft == Duration.zero;
    _load(first: true);
  }

  void _tick() {
    if (!mounted) return;
    final left = s.restLeft;
    if (left != null && left.inMilliseconds > 9500 && left.inMilliseconds <= 10000) HapticFeedback.lightImpact(); // 10 s to go
    if (left != null && left == Duration.zero && !_beeped) {
      _beeped = true;
      HapticFeedback.heavyImpact();
      s.sounds.play(Reward.restOver);
    }
    // "Rest over" counts up for a while, then goes away by itself (nothing to tap away)
    if (left == Duration.zero && (s.restOver?.inMinutes ?? 0) >= 3) s.stopRest();
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable().ignore();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    sets = await s.repo.setsFor(s.session!.id);
    if (first) {
      // resume on the first exercise that isn't finished
      for (var i = 0; i < day.items.length; i++) {
        final n = _countedFor(day.items[i]);
        if (n < day.items[i].sets) {
          ex = i;
          break;
        }
        ex = i;
      }
    }
    target = await s.targetFor(item);
    last = await s.repo.lastTime(item.exerciseId, notSession: s.session!.id);
    _exNote = await s.repo.exNote(item.exerciseId);
    final hist = [for (final x in await s.repo.setsOf(item.exerciseId)) if (x.counts) x];
    _bestE1rm = hist.fold<double>(0, (a, x) => e1rm(x.kg, x.reps) > a ? e1rm(x.kg, x.reps) : a);
    _bestKg = hist.fold<double>(0, (a, x) => x.kg > a ? x.kg : a);
    _bestRepsAt = {};
    for (final x in hist) {
      final k = (x.kg * 10).round();
      if (x.reps > (_bestRepsAt[k] ?? 0)) _bestRepsAt[k] = x.reps;
    }
    _type = _defaultType();
    final m = counted;
    final ps = item.perSet;
    if (ps != null && m.length < ps.length) {
      // programs: each set has its own target; a set with no weight yet keeps the last one
      kg = target?.perSet?[m.length] ?? (m.isNotEmpty ? m.last.kg : (target?.kg ?? 0));
      reps = ps[m.length].reps;
    } else if (m.isNotEmpty) {
      kg = m.last.kg;
      reps = m.last.reps;
    } else {
      kg = target?.kg ?? 0;
      reps = target?.reps ?? item.repLow;
    }
    loaded = true;
    final gnext = item.group == null ? null : roundStart(day.items, ex, {for (final x in day.items) x.exerciseId: _countedFor(x)});
    s.restNext = gnext != null ? (s.lib.byId(day.items[gnext].exerciseId)?.name ?? '') : counted.length < item.sets ? e.name : (ex + 1 < day.items.length ? s.lib.byId(day.items[ex + 1].exerciseId)?.name ?? '' : '');
    if (mounted) setState(() {});
  }

  /// The reps of the set coming up (programs: that set's own).
  int get _setReps {
    final ps = item.perSet;
    return ps != null && counted.length < ps.length ? ps[counted.length].reps : item.repLow;
  }

  /// First time doing a lift (no target, no history): the weight is picked on the screen, no pop-up.
  bool get _firstTimeLift => mine.isEmpty && target?.kg == null && last.isEmpty && !e.bodyweight;

  /// Quick jumps for the weight, in the user's unit.
  List<double> get _jumps => s.unit == Unit.lb ? const [-10, 10, 25, 45] : const [-5, 5, 10, 20];

  void _jump(double d) => setState(() => kg = roundToStep((kg + fromUnit(d, s.unit)).clamp(0, 2000).toDouble(), e.step, s.unit));

  void _go(int i) {
    if (i < 0 || i >= day.items.length) return;
    ex = i;
    _load();
  }

  double get _step => stepKg(e.step, s.unit);

  /// The weight shown on a set row not done yet (programs: that set's own weight).
  String _plannedKg(int i) {
    final ps = target?.perSet;
    if (ps == null || i >= ps.length) return target?.kg == null ? '–' : '${fmtWeight(target!.kg!, s.unit)} ${unitLabel(s.unit)}';
    final w = ps[i];
    return w == null ? '–' : '${fmtWeight(w, s.unit)} ${unitLabel(s.unit)}';
  }

  String _plannedReps(int i) {
    final ps = item.perSet;
    if (ps != null && i < ps.length) return '${ps[i].reps}${ps[i].amrap ? '+' : ''} ${e.timed ? 's' : 'reps'}';
    return '$reps ${e.timed ? 's' : 'reps'}';
  }

  bool _saving = false;
  bool _dropOffered = false;

  /// A weighted lift with no weight yet (first time, no history): Done asks for one first (P1-8).
  bool get _needsWeight => !e.bodyweight && kg <= 0 && _type != SetType.warmup;

  Future<void> _done() async {
    if (_saving) return; // a quick double tap logs one set, not two
    if (_needsWeight) {
      await _pickWeight();
      if (!mounted || kg <= 0) return; // nothing picked: nothing logged
    }
    _saving = true;
    setState(() {});
    try {
      HapticFeedback.mediumImpact();
      final ex0 = this.ex;
      final it = item, ex = e;
      final type = _type;
      final wasDrop = _dropOffered;
      final before = counted.length;
      final prevAt = sets.isEmpty ? null : sets.map((x) => x.at).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      final rest = prevAt == null ? null : DateTime.now().difference(prevAt).inSeconds;
      final logged = await s.repo.logSet(s.session!.id, it.exerciseId, kg, reps, type: type, rest: rest, slot: liftKey(it));
      _lastSetId = logged.id;
      _undoEx = ex0;
      final wasBest = _bestE1rm, wasKg = _bestKg;
      await _load();
      if (mounted) _afterSet(logged, ex, it, wasBest, wasKg, type);
      final exerciseDone = type != SetType.warmup && type != SetType.drop && before + 1 == it.sets;
      final allDone = day.items.every((x) => _countedFor(x) >= x.sets);
      // a drop set right after the planned last set: lighter weight, go again with no rest
      if (exerciseDone && it.style == 'drop') {
        _type = SetType.drop;
        kg = roundToStep(kg * 0.8, ex.step, s.unit);
        _dropOffered = true;
      }
      s.sounds.play(allDone ? Reward.workout : (exerciseDone ? Reward.exercise : Reward.set));
      _beeped = false;
      _setAt = DateTime.now();
      _lastReps = reps;
      _lastWasFinal = exerciseDone;
      _effort = null;
      // superset: on to the partner with a short break; the full rest after the round
      final doneMap = {for (final x in day.items) x.exerciseId: _countedFor(x)};
      final cur = day.items.indexWhere((x) => liftKey(x) == liftKey(it));
      final partner = (type == SetType.warmup || cur < 0 || _dropOffered) ? null : nextInRound(day.items, cur, doneMap);
      final again = (partner == null && cur >= 0 && type != SetType.warmup && !_dropOffered) ? roundStart(day.items, cur, doneMap) : null;
      if (partner != null) {
        s.startRest(const Duration(seconds: 15));
        _go(partner);
      } else if (again != null && again != cur) {
        s.startRest(Duration(seconds: _restFor(ex, it, reps, false, null)));
        _go(again);
      } else if (allDone && !_dropOffered) {
        s.stopRest();
      } else if (_dropOffered && type != SetType.drop) {
        s.stopRest(); // drop set: straight on
      } else {
        if (type == SetType.drop) _dropOffered = false;
        s.startRest(Duration(seconds: type == SetType.warmup ? 60 : _restFor(ex, it, reps, exerciseDone, null)));
      }
      // this exercise is finished (its drop set too): on to the next one that isn't, while the rest runs
      final finishedHere = it.group == null && ((exerciseDone && it.style != 'drop') || (type == SetType.drop && wasDrop));
      if (finishedHere && !allDone && cur >= 0) {
        final n = day.items.length;
        for (var k = 1; k < n; k++) {
          final j = (cur + k) % n;
          if (_countedFor(day.items[j]) < day.items[j].sets) {
            _go(j);
            break;
          }
        }
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  /// Undo bar, a gold flash for a new record, and what happens next time after the last set.
  void _afterSet(SetLog x, Exercise exr, PlanItem it, double wasBest, double wasKg, SetType type) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    String? msg;
    final counts = type != SetType.warmup && type != SetType.drop;
    if (counts && !exr.bodyweight && wasBest > 0 && e1rm(x.kg, x.reps) > wasBest + 0.05) {
      msg = '🏆 New record: est. 1RM ${fmtWeight(e1rm(x.kg, x.reps), s.unit)} ${unitLabel(s.unit)}';
      s.sounds.play(Reward.exercise);
    } else if (counts && !exr.bodyweight && wasKg > 0 && x.kg > wasKg + 0.05) {
      msg = '🏆 Heaviest yet: ${fmtWeight(x.kg, s.unit)} ${unitLabel(s.unit)}';
    }
    final done = counted.length >= it.sets && counts;
    if (msg == null && done && ruleFor(s.plan?.program, it) == null) {
      final c = counted;
      if (c.every((y) => y.reps >= it.repHigh)) {
        msg = 'All sets at the top of the range: next time the weight goes up.';
      } else if (c.any((y) => y.reps < it.repLow)) {
        msg = 'Some sets short: same weight next time.';
      } else {
        msg = 'In range: next time aim for one more rep.';
      }
    }
    // a plain set shows nothing (Undo sits in the bottom bar); only records and "next time" get a short line
    if (msg == null) return;
    m.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  /// Undo the last logged set (the button in the bottom bar).
  Future<void> _undo() async {
    final id = _lastSetId;
    if (id == null) return;
    HapticFeedback.selectionClick();
    await s.repo.deleteSet(id);
    _lastSetId = null;
    _dropOffered = false;
    s.stopRest();
    if (_undoEx != null && _undoEx! < day.items.length) ex = _undoEx!;
    _undoEx = null;
    await _load();
  }

  /// Log the rest of this exercise's planned sets with the numbers on screen.
  Future<void> _fillRest() async {
    final left = item.sets - counted.length;
    if (left <= 0) return;
    if (!await confirm(context, 'Fill $left set${left == 1 ? '' : 's'}?', 'Logs $left × ${fmtWeight(kg, s.unit)} ${unitLabel(s.unit)} × $reps for ${e.name}.', yes: 'Fill')) return;
    for (var i = 0; i < left; i++) {
      await s.repo.logSet(s.session!.id, item.exerciseId, kg, reps, slot: liftKey(item));
    }
    s.stopRest();
    await _load();
  }

  /// Every exercise of the workout with its progress; tap one to go there.
  Future<void> _overview() async {
    final i = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          const Padding(padding: EdgeInsets.all(4), child: Text('This workout', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          for (var k = 0; k < day.items.length; k++)
            ListTile(
              selected: k == ex,
              leading: Text('${k + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
              title: Text(s.lib.byId(day.items[k].exerciseId)?.name ?? day.items[k].exerciseId),
              subtitle: Dim('${_countedFor(day.items[k])} of ${day.items[k].sets} sets', size: 12),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_countedFor(day.items[k]) >= day.items[k].sets) const Icon(Icons.check, color: C.green),
                IconButton(tooltip: 'Move up', icon: const Icon(Icons.arrow_upward, size: 20), onPressed: k == 0 ? null : () => Navigator.pop(c, -1000 - k)),
                IconButton(tooltip: 'Move down', icon: const Icon(Icons.arrow_downward, size: 20), onPressed: k == day.items.length - 1 ? null : () => Navigator.pop(c, -2000 - k)),
                IconButton(
                  tooltip: 'Take out for today',
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: day.items.length < 2 || _countedFor(day.items[k]) > 0 ? null : () => Navigator.pop(c, -3000 - k),
                ),
              ]),
              onTap: () => Navigator.pop(c, k),
            ),
        ]),
      ),
    );
    if (i == null) return;
    if (i >= 0) return _go(i);
    final k = (-i) % 1000, op = (-i) ~/ 1000;
    final l = [...day.items];
    final cur = day.items[ex].exerciseId;
    if (op == 1 && k > 0) l.insert(k - 1, l.removeAt(k));
    if (op == 2 && k < l.length - 1) l.insert(k + 1, l.removeAt(k));
    if (op == 3) l.removeAt(k);
    await s.setToday(day.copyWith(items: l));
    ex = l.indexWhere((x) => x.exerciseId == cur).clamp(0, l.length - 1);
    await _load();
    if (mounted) _overview();
  }

  /// Every past workout of this lift.
  Future<void> _liftHistory() async {
    final all = await s.repo.setsOf(item.exerciseId);
    if (!mounted) return;
    final by = <String, List<SetLog>>{};
    for (final x in all) {
      (by[x.sessionId] ??= []).add(x);
    }
    final rows = by.values.toList().reversed.toList();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .95,
        builder: (c2, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
          Text(e.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Dim('${rows.length} workouts', size: 12),
          if (all.any((x) => x.type != SetType.work)) const Dim(setTypeKey, size: 12),
          const SizedBox(height: 8),
          if (rows.isEmpty) const Dim('Nothing yet.'),
          for (final l in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.first.at == null ? '' : '${l.first.at!.year}-${l.first.at!.month.toString().padLeft(2, '0')}-${l.first.at!.day.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(l.map((x) => '${setTypeLetter[x.type]!.isEmpty ? '' : '${setTypeLetter[x.type]} '}${fmtWeight(x.kg, s.unit)}×${x.reps}').join(', '), style: const TextStyle(color: C.dim)),
              ]),
            ),
        ]),
      ),
    );
  }

  Future<void> _typeReps() async {
    final c = TextEditingController(text: '$reps');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: Text(e.timed ? 'Seconds' : 'Reps'),
        content: TextField(enableIMEPersonalizedLearning: false, controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('OK'))],
      ),
    );
    final n = int.tryParse(v ?? '');
    if (n != null && n >= 0 && n <= 999) setState(() => reps = n);
  }

  /// Swipe a logged set away to delete it (with Undo).
  Widget _swipe(SetLog? x, Widget child) {
    if (x == null) return child;
    return Dismissible(
      key: ValueKey('set-${x.id}'),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), color: C.card2, child: const Icon(Icons.delete_outline, color: C.gold)),
      onDismissed: (_) async {
        await s.repo.deleteSet(x.id);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Set deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: () async {
            await s.repo.restoreSet(x);
            await _load();
          }),
        ));
      },
      child: child,
    );
  }

  DateTime? _holdStart;

  /// Timed exercises (planks, hangs, carries): Start, then Stop fills in the seconds.
  void _hold() {
    if (_holdStart == null) {
      HapticFeedback.mediumImpact();
      setState(() => _holdStart = DateTime.now());
    } else {
      final sec = DateTime.now().difference(_holdStart!).inSeconds;
      HapticFeedback.heavyImpact();
      setState(() {
        reps = sec;
        _holdStart = null;
      });
    }
  }

  Duration get _elapsed => DateTime.now().difference(s.session!.started);

  String get _clock {
    final d = _elapsed;
    return d.inHours > 0 ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}' : '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  /// A one-line form cue from the how-to (its last sentence).
  String get _cue {
    final parts = e.about.split(RegExp(r'(?<=[.!])\s+')).where((x) => x.trim().isNotEmpty).toList();
    return parts.length < 2 ? '' : parts.last.trim();
  }

  int _restFor(Exercise ex, PlanItem it, int done, bool last, Effort? ef) {
    if (s.settings.rest != null) return s.settings.rest!;
    if (!s.settings.smartRest) return it.restSec;
    return smartRest(ex, it, done, lastSet: last, effort: ef);
  }

  /// "How was that set?" adjusts the rest that is already running.
  void _setEffort(Effort ef) {
    if (_setAt == null || _lastReps == null) return;
    final total = Duration(seconds: _restFor(e, item, _lastReps!, _lastWasFinal, ef));
    final left = total - DateTime.now().difference(_setAt!);
    setState(() => _effort = ef);
    if (_lastSetId != null) s.repo.updateSetInfo(_lastSetId!, effort: ef.index + 1).ignore();
    if (ef == Effort.max && _lastReps! < item.repLow && !e.bodyweight && counted.length < item.sets) {
      kg = (kg - _step).clamp(0, 2000);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All-out and short on reps: next set is one step lighter.')));
    }
    if (left.inSeconds <= 0) return _stopRest();
    _beeped = false;
    s.startRest(left);
  }

  String _guide() {
    final m = counted;
    final left = s.restLeft;
    final allDone = day.items.every((x) => _countedFor(x) >= x.sets);
    final exDone = m.length >= item.sets;
    final next = ex + 1 < day.items.length ? s.lib.byId(day.items[ex + 1].exerciseId)?.name : null;
    final ps = item.perSet;
    final reps = ps != null && m.length < ps.length
        ? '${ps[m.length].reps}${ps[m.length].amrap ? '+' : ''}'
        : (item.repLow == item.repHigh ? '${item.repLow}' : '${item.repLow}-${item.repHigh}');
    final w = kg > 0 && !e.bodyweight ? '${fmtWeight(kg, s.unit)} ${unitLabel(s.unit)}' : null;
    return guideLine(
      name: e.name,
      setNo: m.length + 1,
      sets: item.sets,
      weight: w,
      reps: e.timed ? '$reps s' : reps,
      resting: left != null && left > Duration.zero,
      restOver: left != null && left == Duration.zero,
      exerciseDone: exDone,
      nextName: next,
      workoutDone: allDone,
      firstOfWorkout: sets.isEmpty,
      warmupShown: sets.isEmpty && s.warmupsOn && !s.settings.simple,
    );
  }

  void _addRest(int sec) {
    final left = s.restLeft;
    if (left == null) return;
    final n = left + Duration(seconds: sec);
    if (n.inSeconds <= 0) return _stopRest();
    _beeped = false;
    s.startRest(n);
  }

  void _stopRest() => s.stopRest();

  Future<void> _editSet(SetLog x) async {
    var k = x.kg, r = x.reps;
    var type = x.type;
    var rpe = x.rpe;
    var side = x.side;
    final note = TextEditingController(text: x.note);
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true, // scrolls on small phones and above the keyboard
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('Change this set', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                TextButton.icon(onPressed: () => Navigator.pop(c, 'hurt'), icon: const Icon(Icons.healing, size: 18), label: const Text('That hurt')),
              ]),
              const SizedBox(height: 12),
              BigStepper(value: fmtWeight(k, s.unit), unit: unitLabel(s.unit), onMinus: () => set(() => k = (k - _step).clamp(0, 2000)), onPlus: () => set(() => k += _step)),
              const SizedBox(height: 8),
              BigStepper(value: '$r', unit: 'reps', onMinus: () => set(() => r = (r - 1).clamp(0, 500)), onPlus: () => set(() => r++)),
              const SizedBox(height: 10),
              if (!s.settings.simple) ...[
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in SetType.values)
                  ChoiceChip(label: Text(setTypeLabel[t]!), selected: type == t, showCheckmark: false, onSelected: (_) => set(() => type = t)),
              ]),
              const SizedBox(height: 8),
              const Dim('RPE: how hard it was. 10 = not one more rep, 9 = one left, 8 = two left.', size: 12),
              Row(children: [
                const Text('RPE  '),
                Expanded(
                  child: Wrap(spacing: 4, children: [
                    for (final v in const [6.0, 7.0, 8.0, 9.0, 10.0])
                      ChoiceChip(label: Text(v.toStringAsFixed(0)), selected: rpe == v, showCheckmark: false, onSelected: (_) => set(() => rpe = rpe == v ? null : v)),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final (v, l) in const [('', 'Both sides'), ('L', 'Left'), ('R', 'Right')])
                  ChoiceChip(label: Text(l), selected: side == v, showCheckmark: false, onSelected: (_) => set(() => side = v)),
              ]),
              ],
              TextField(enableIMEPersonalizedLearning: false, controller: note, decoration: const InputDecoration(hintText: 'Note for this set (optional)')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete set'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save'))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (res == 'save') {
      await s.repo.updateSet(x.id, k, r);
      await s.repo.updateSetInfo(x.id, type: type, rpe: rpe, clearRpe: rpe == null, side: side, note: note.text.trim());
    }
    if (res == 'delete') await s.repo.deleteSet(x.id);
    if (res == 'hurt') return _hurt(x);
    if (res != null) await _load();
  }

  /// "That hurt" (F235): where, then swap it, stop it for today or carry on lighter. The next
  /// two workouts of it start lighter too.
  Future<void> _hurt(SetLog x) async {
    Joint? j = e.joints.length == 1 ? e.joints.first : null;
    var always = false;
    final what = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('That hurt: ${e.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Dim('Where? (optional)', size: 12),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in [...e.joints, ...Joint.values.where((v) => !e.joints.contains(v))])
                  ChoiceChip(label: Text(jointLabel[k]!), selected: j == k, showCheckmark: false, onSelected: (v) => set(() => j = v ? k : null)),
              ]),
              if (j != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: always,
                  onChanged: (v) => set(() => always = v ?? false),
                  title: Text('Go easy on my ${jointLabel[j]!.toLowerCase()} from now on'),
                  subtitle: const Dim('New plans and swaps leave out exercises that are hard on it.', size: 12),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Dim('Pain is a sign to stop, not to push through. If it is sharp, swells, or is still there in a few days, get it checked.', size: 12),
              ),
              ListTile(leading: const Icon(Icons.swap_horiz), title: Text('Swap ${e.name} for today'), onTap: () => Navigator.pop(c, 'swap')),
              ListTile(leading: const Icon(Icons.stop_circle_outlined), title: const Text('Stop it for today'), subtitle: const Dim('The sets done so far count.', size: 12), onTap: () => Navigator.pop(c, 'stop')),
              if (!e.bodyweight) ListTile(leading: const Icon(Icons.south), title: const Text('Keep going 20% lighter'), onTap: () => Navigator.pop(c, 'lighter')), // P3-4
              ListTile(leading: const Icon(Icons.edit_note), title: const Text('Just note it'), onTap: () => Navigator.pop(c, 'note')),
              const Dim('Every choice notes it on the set, and the next two times you do it start 20% and then 10% lighter.', size: 12),
            ]),
          ),
        ),
      ),
    );
    if (what == null) return;
    await s.flagPain(e.id, j);
    if (always && j != null && s.profile != null) await s.saveProfile(s.profile!.copyWith(avoid: {...s.profile!.avoid, j!}));
    final tag = 'Hurt${j == null ? '' : ' (${jointLabel[j]!.toLowerCase()})'}';
    await s.repo.updateSetInfo(x.id, note: [if (x.note.isNotEmpty) x.note, tag].join(' · '));
    if (what == 'swap') return _swap();
    if (what == 'stop') {
      final l = [...day.items];
      l[ex] = item.copyWith(sets: _countedFor(item).clamp(1, 99));
      await s.setToday(day.copyWith(items: l));
    }
    await _load();
    if (what == 'lighter' && mounted && !e.bodyweight) setState(() => kg = roundToStep(kg * 0.8, e.step, s.unit));
  }

  /// Tap the weight: a grid of nearby weights to pick with one tap; typing is the fallback.
  Future<void> _pickWeight() async {
    final st = _step;
    // no weight yet: a barbell starts at the empty bar, everything else at one step
    final bar = e.equipment == Equipment.barbell && kg <= 0 ? fromUnit(s.unit == Unit.lb ? 45 : 20, s.unit) : null;
    final start = bar ?? ((kg - 12 * st) < st ? st : kg - 12 * st);
    final values = [for (var i = 0; i < 30; i++) roundToStep(start + i * st, e.step, s.unit)];
    final v = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_firstTimeLift ? 'Pick a weight you can do for about ${repsWord(_setReps)}' : 'Weight', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (e.equipment == Equipment.dumbbell || e.equipment == Equipment.kettlebell) const Dim('Per dumbbell', size: 12),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 5,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final w in values)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: (w - kg).abs() < 0.01 ? C.teal : C.card2, foregroundColor: (w - kg).abs() < 0.01 ? C.onTeal : C.text),
                    onPressed: () => Navigator.pop(c, w),
                    child: Text(fmtWeight(w, s.unit), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => Navigator.pop(c, -1.0), icon: const Icon(Icons.keyboard_outlined), label: const Text('Type a number')),
          ]),
        ),
      ),
    );
    if (v == null || !mounted) return;
    if (v < 0) return _typeWeight();
    setState(() => kg = v);
  }

  Future<void> _typeWeight() async {
    final c = TextEditingController(text: fmtWeight(kg, s.unit));
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Weight'),
        content: TextField(enableIMEPersonalizedLearning: false, controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true, decoration: InputDecoration(suffixText: unitLabel(s.unit))),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('OK'))],
      ),
    );
    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (n != null && n >= 0) setState(() => kg = fromUnit(n, s.unit));
  }

  Future<void> _note() async {
    final which = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text('Note for ${e.name}'), subtitle: const Dim('Shown every time you do it: seat height, grip, cues', size: 12), onTap: () => Navigator.pop(c, 'ex')),
          ListTile(leading: const Icon(Icons.notes), title: const Text('Note for this workout'), onTap: () => Navigator.pop(c, 'workout')),
        ]),
      ),
    );
    if (which == null || !mounted) return;
    if (which == 'ex') {
      final c = TextEditingController(text: _exNote);
      final v = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: C.card,
          title: Text(e.name),
          content: TextField(enableIMEPersonalizedLearning: false, controller: c, maxLines: 3, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. seat 4, pins at 6, wide grip')),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save'))],
        ),
      );
      if (v != null) {
        await s.repo.setExNote(e.id, v);
        await _load();
      }
      return;
    }
    final c = TextEditingController(text: s.session!.note);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Workout note'),
        content: TextField(enableIMEPersonalizedLearning: false, controller: c, maxLines: 4, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save'))],
      ),
    );
    if (v != null) {
      await s.repo.setSessionNote(s.session!.id, v);
      await s.reload();
    }
  }

  Future<void> _addExercise() async {
    final picked = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => ExercisePicker(s: s, exclude: {for (final it in day.items) it.exerciseId})));
    if (picked == null) return;
    final it = PlanItem(exerciseId: picked.id, sets: 3, repLow: picked.repLow, repHigh: picked.repHigh, restSec: picked.compound ? 120 : 75);
    await s.setToday(day.copyWith(items: [...day.items, it]));
    _go(day.items.length - 1);
  }

  Future<void> _swap() async {
    final r = await swapSheet(context, s, e, exclude: {for (final it in day.items) it.exerciseId});
    if (r == null) return;
    final ok = await s.swap(ex, r.$1, forever: r.$2);
    if (!ok && mounted) toast(context, 'Changed for today only: that exercise is not in your plan for this day.');
    await _load();
  }

  /// One step: the summary, stars, "bad day" and "keep today's changes" on one sheet.
  Future<void> _finish() async {
    final n = sets.length;
    final summary = n == 0 ? '' : await _summaryText();
    final next = n == 0 ? const <NextLine>[] : await s.previewNext();
    var showNext = false;
    final changed = _changedFromPlan();
    if (!mounted) return;
    var rating = 0;
    var excuse = false;
    var keep = false;
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(n == 0 ? 'Finish workout?' : 'Workout done', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (n > 0) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.fitness_center, color: C.gold, size: 20)),
              ]),
              const SizedBox(height: 6),
              if (n == 0) const Dim('No sets logged, so nothing will be saved and today stays next in line.', size: 14),
              if (n > 0) ...[
                Text(summary),
                if (next.isNotEmpty) () {
                  // "Bad day": weights do not drop, so the lines that would go down stay the same;
                  // folded to one line so Save stays on screen (review 2, P2-5)
                  final l = [for (final x in next) if (!(excuse && x.change < 0)) x];
                  final shown = next.length == 1 ? l : (showNext ? l : const <NextLine>[]);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(next.length == 1 ? 'Next time' : 'Next time: ${nextSummary([...l, for (final x in next) if (excuse && x.change < 0) NextLine(x.text, 0)])}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (next.length > 1) TextButton(onPressed: () => set(() => showNext = !showNext), child: Text(showNext ? 'Hide' : 'Show')),
                      ]),
                      for (final x in shown) Dim('• ${x.text}', size: 13),
                    ]),
                  );
                }(),
                if (s.settings.aiOn)
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => Navigator.pop(c, 'finish_ai'), icon: const Icon(Icons.auto_awesome, size: 18), label: const Text('Save, then ask AI for a summary'))),
                const SizedBox(height: 6),
                const Text('How was it?'),
                Row(children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(onPressed: () => set(() => rating = rating == i ? 0 : i), icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: C.gold, size: 30)),
                ]),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: excuse,
                  onChanged: (v) => set(() => excuse = v ?? false),
                  title: const Text("Bad day: don't count missed reps"),
                  subtitle: const Dim('Weights stay where they were instead of dropping.', size: 12),
                ),
                if (changed)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: keep,
                    onChanged: (v) => set(() => keep = v ?? false),
                    title: const Text("Keep today's changes in my plan"),
                    subtitle: const Dim('Swaps, added or removed exercises become part of this day.', size: 12),
                  ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Cool-down stretches'),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Dim('Hold each 20-30 s', size: 12),
                    for (final l in coolDown([for (final id in {for (final x in sets) x.exerciseId}) if (s.lib.byId(id) != null) s.lib.byId(id)!])) Dim('• $l', size: 13),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(height: 52, child: FilledButton(onPressed: () => Navigator.pop(c, 'finish'), child: Text(n == 0 ? 'Finish' : 'Save and finish'))),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Keep going')),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(c, 'throw'), child: const Text('Throw this workout away', style: TextStyle(color: C.gold))),
            ]),
          ),
        ),
      ),
    );
    if (res == 'throw') {
      if (!mounted) return;
      if (!await confirm(context, 'Throw it away?', 'All sets from this workout are deleted.', yes: 'Throw away')) return;
      await s.throwAwayWorkout();
    } else if (res == 'finish' || res == 'finish_ai') {
      if (n > 0) s.sounds.play(Reward.workout);
      final planDay = s.session!.dayIndex;
      final todayDay = day;
      await s.finishWorkout(excuse: excuse, rating: rating == 0 ? null : rating);
      if (keep && n > 0 && s.plan != null && planDay >= 0 && planDay < s.plan!.days.length) {
        final pl = s.plan!;
        final days = [...pl.days]..[planDay] = todayDay.copyWith(name: pl.days[planDay].name);
        await s.savePlanEdits(pl.copyWith(source: pl.source == 'built-in' ? 'mine' : pl.source, days: days, userEdited: true));
      }
    } else {
      return;
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    if (res == 'finish_ai') nav.push(MaterialPageRoute(builder: (_) => CoachScreen(s: s, ask: 'Sum up the workout I just finished: what went well, and what to do next time.')));
  }

  bool _changedFromPlan() {
    final pl = s.plan;
    final di = s.session?.dayIndex ?? -1;
    if (pl == null || di < 0 || di >= pl.days.length) return false;
    final a = pl.days[di].items.map((x) => x.toJson().toString()).join('|');
    final b = day.items.map((x) => x.toJson().toString()).join('|');
    return a != b;
  }

  /// Time, sets, volume and records beaten, in plain lines.
  Future<String> _summaryText() async {
    final mins = DateTime.now().difference(s.session!.started).inMinutes;
    final work = sets.where((x) => x.counts).toList();
    final vol = work.fold<double>(0, (a, x) => a + x.kg * x.reps);
    final records = <String>[];
    for (final id in {for (final x in work) x.exerciseId}) {
      final ex = s.lib.byId(id);
      if (ex == null || ex.bodyweight) continue;
      final before = [for (final x in await s.repo.setsOf(id)) if (x.counts && x.sessionId != s.session!.id) x];
      if (before.isEmpty) continue;
      final best = before.fold<double>(0, (a, x) => e1rm(x.kg, x.reps) > a ? e1rm(x.kg, x.reps) : a);
      final now = work.where((x) => x.exerciseId == id).fold<double>(0, (a, x) => e1rm(x.kg, x.reps) > a ? e1rm(x.kg, x.reps) : a);
      if (now > best + 0.05) records.add('${ex.name}: est. 1RM ${fmtWeight(now, s.unit)} ${unitLabel(s.unit)}');
    }
    final short = [for (final it in day.items) if (_countedFor(it) < it.sets) s.lib.byId(it.exerciseId)?.name ?? it.exerciseId];
    final b = StringBuffer()
      ..writeln('$mins min · ${work.length} sets · ${fmtNum(toUnit(vol, s.unit).roundToDouble())} ${unitLabel(s.unit)} lifted')
      ..writeln();
    if (records.isNotEmpty) {
      b.writeln('🏆 New records:');
      for (final r in records) {
        b.writeln('• $r');
      }
      b.writeln();
    }
    if (short.isNotEmpty) b.writeln('Not all sets done: ${short.join(', ')}. Those lifts stay at the same weight.');
    b.write('Next weights are worked out from what you did.');
    return b.toString();
  }

  String _lastText() {
    if (last.isEmpty) return 'First time';
    return 'Last time ${last.map((x) => e.bodyweight && x.kg == 0 ? '${x.reps}' : '${fmtWeight(x.kg, s.unit)}×${x.reps}').join(', ')}';
  }

  String _mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  /// Always at the bottom, in thumb reach: the rest timer, Undo, Done set and Finish.
  Widget _bottomBar() {
    final left = s.restLeft;
    final resting = left != null && left > Duration.zero;
    final over = left != null && left == Duration.zero;
    final allDone = day.items.every((x) => _countedFor(x) >= x.sets);
    Widget small(String t, VoidCallback f) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: SizedBox(height: 48, child: OutlinedButton(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(48, 48)), onPressed: f, child: Text(t))),
        );
    return Material(
      color: C.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (resting)
              Row(children: [
                Expanded(child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: PopupMenuButton<int>(
                  tooltip: 'Set the rest',
                  onSelected: (sec) {
                    final since = _setAt == null ? Duration.zero : DateTime.now().difference(_setAt!);
                    final n = Duration(seconds: sec) - since;
                    if (n.inSeconds <= 0) return _stopRest();
                    _beeped = false;
                    s.startRest(n);
                  },
                  itemBuilder: (c) => [for (final sec in const [60, 90, 120, 180]) PopupMenuItem(value: sec, child: Text('Rest ${_mmss(Duration(seconds: sec))}'))],
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.timer_outlined, color: C.gold),
                    const SizedBox(width: 6),
                    Text(_mmss(left), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.gold, fontFeatures: [FontFeature.tabularFigures()])),
                    const Icon(Icons.arrow_drop_down, color: C.dim),
                  ]),
                )))),
                small('−30s', () => _addRest(-30)),
                small('+30s', () => _addRest(30)),
                small('Skip', _stopRest),
              ]),
            if (over)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.timer_off_outlined, color: C.gold),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Rest over${s.restOver == null ? '' : ' · +${_mmss(s.restOver!)}'}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 4),
            Row(textDirection: thumbRow, children: [
              if (_lastSetId != null)
                SizedBox(width: 52, height: 56, child: IconButton(tooltip: 'Undo last set', onPressed: _saving ? null : _undo, icon: const Icon(Icons.undo))),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: allDone
                      ? FilledButton(onPressed: _finish, child: const Text('Finish workout', style: TextStyle(fontSize: 18)))
                      : FilledButton(onPressed: _saving ? null : _done, child: Text(_needsWeight ? 'Pick weight' : (_type == SetType.work ? 'Done set' : 'Done: ${setTypeLabel[_type]!.toLowerCase()}'), style: const TextStyle(fontSize: 18))),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(height: 56, child: allDone ? OutlinedButton(onPressed: _saving ? null : _done, child: const Text('+ Set')) : OutlinedButton(onPressed: _finish, child: const Text('Finish'))),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || s.session == null || day.items.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final all = mine;
    final m = counted;
    final rows = m.length > item.sets ? m.length : item.sets;
    final left = s.restLeft;
    final simple = s.settings.simple;
    final lt = [for (final x in last) if (x.counts) x];
    final warm = all.where((x) => x.type == SetType.warmup).length;
    final reps = item.repLow == item.repHigh ? '${item.repLow}' : '${item.repLow}-${item.repHigh}';
    final dim = _dimmed;
    return PopScope(
      // dark in a rest: the first Back only wakes the screen, like a touch (review 5, P3-N39)
      canPop: !dim,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && dim) setState(() => _touchAt = DateTime.now());
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => dim ? null : _touchAt = DateTime.now(),
        child: Stack(children: [
      Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(day.name),
            Dim('$_clock · ${sets.where((x) => x.counts).length} sets · ${fmtNum(toUnit(sets.where((x) => x.counts).fold<double>(0, (a, x) => a + x.kg * x.reps), s.unit).roundToDouble())} ${unitLabel(s.unit)}', size: 12),
          ]),
          actions: [
            IconButton(tooltip: 'All exercises', icon: const Icon(Icons.list_alt), onPressed: _overview),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'fill') _fillRest();
                if (v == 'timers') Navigator.push(context, MaterialPageRoute(builder: (_) => TimersScreen(s: s)));
                if (v == 'finish') _finish();
              },
              itemBuilder: (c) => [
                if (counted.length < item.sets) const PopupMenuItem(value: 'fill', child: Text('Fill the rest of this exercise')),
                const PopupMenuItem(value: 'timers', child: Text('Timers (stopwatch, EMOM, Tabata)')),
                const PopupMenuItem(value: 'finish', child: Text('Finish workout')),
              ],
            ),
          ],
        ),
        bottomNavigationBar: _bottomBar(),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 16), children: [
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: day.items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (c, i) {
                  if (i == day.items.length) return ActionChip(label: const Text('+ Add'), onPressed: _addExercise);
                  final it = day.items[i];
                  final done = _countedFor(it) >= it.sets;
                  final gl = groupLabel(day.items, i);
                  return ChoiceChip(
                    label: Text('${gl.isEmpty ? '${i + 1}' : gl}${done ? ' ✓' : ''}', style: TextStyle(color: i == ex ? C.onTeal : (done ? C.green : C.text))),
                    selected: i == ex,
                    showCheckmark: false,
                    onSelected: (_) => _go(i),
                  );
                },
              ),
            ),
            if (sets.isEmpty && s.warmupsOn && !s.settings.simple)
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.local_fire_department_outlined, color: C.gold),
                  title: const Text('Warm-up first (about 5 min)'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final l in generalWarmup([for (final it in day.items) if (s.lib.byId(it.exerciseId) != null) s.lib.byId(it.exerciseId)!])) Text('• $l')],
                ),
              ),
            const SizedBox(height: 8),
            GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -300) _go(ex + 1);
                if (v > 300) _go(ex - 1);
              },
              child: Center(child: ExerciseAnim(key: ValueKey(e.id), e: e, size: 150)),
            ),
            if (day.items.length > 1) const Center(child: Dim('Swipe the picture for the next exercise', size: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.campaign_outlined, color: C.gold),
                const SizedBox(width: 10),
                Expanded(child: Text(_guide(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => exerciseInfo(context, s, e),
              child: Row(children: [
              ExIcon(s.iconFor(e), size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  Text(
                      item.perSet != null
                          ? 'Target ${setsPlain(item.perSet!)}'
                          : 'Target ${item.sets} × $reps${e.timed ? ' s' : ''}${item.style.isEmpty ? '' : ', last set ${lastSetStyles[item.style]!.toLowerCase()}'}',
                      style: const TextStyle(color: C.dim, fontSize: 13)),
                  if (target?.tm != null && !s.settings.simple) Dim('Training max ${fmtWeight(target!.tm!, s.unit)} ${unitLabel(s.unit)} · % sets come from it', size: 12),
                  if (target?.why != null)
                    Row(children: [
                      Flexible(child: Text(target!.why!, style: const TextStyle(color: C.teal, fontSize: 12.5))),
                      // it does not hurt any more: back to the normal weights (P3-3)
                      if (s.ramp.containsKey(item.exerciseId))
                        TextButton(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: () async {
                              await s.clearRamp(item.exerciseId);
                              await _load();
                            },
                            child: const Text('Back to normal')),
                    ]),
                  InkWell(
                    onTap: () => whySheet(context, s, e, item, ex, target, setReps: item.perSet != null ? _setReps : null),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48), // 48 dp to tap (F367)
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.help_outline, size: 15, color: C.teal),
                        const SizedBox(width: 4),
                        Flexible(child: Text(target?.reason == null ? 'Why this?' : 'Why? ${target!.reason}', style: const TextStyle(color: C.teal, fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)), // P3-N6
                      ]),
                    ),
                  ),
                  if (_cue.isNotEmpty) Text(_cue, style: const TextStyle(color: C.sky, fontSize: 12.5, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (_exNote.isNotEmpty)
                    Row(children: [const Icon(Icons.push_pin, size: 14, color: C.gold), const SizedBox(width: 4), Expanded(child: Text(_exNote, style: const TextStyle(color: C.gold, fontSize: 13)))]),
                  if (e.equipment == Equipment.dumbbell || e.equipment == Equipment.kettlebell) const Dim('Weight per dumbbell', size: 12),
                  if (e.equipment == Equipment.band) const Dim('Band: log reps (weight optional) · tap for how-to', size: 12)
                  else if (e.bodyweight) const Dim('Weight = added weight (0 = bodyweight) · tap for how-to', size: 12)
                  else const Dim('Tap for how to do it', size: 12),
                ]),
              ),
              const Icon(Icons.info_outline, color: C.dim),
            ]),
            ),
            // last time, as a button: the whole history of this lift
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 40)),
                onPressed: _liftHistory,
                icon: const Icon(Icons.history, size: 18),
                label: Text(_lastText(), overflow: TextOverflow.ellipsis),
              ),
            ),
            if (_firstTimeLift)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('First time: set a weight you can do for about ${repsWord(_setReps)}. A guess is fine; it adjusts after today. Tap the number for a quick pick.', style: const TextStyle(color: C.gold, fontSize: 13)),
              ),
            const SizedBox(height: 4),
            Row(textDirection: thumbRow, children: [
              Expanded(
                flex: 13,
                child: BigStepper(
                  value: fmtWeight(kg, s.unit),
                  unit: unitLabel(s.unit),
                  onMinus: () => setState(() => kg = (kg - _step).clamp(0, 2000)),
                  onPlus: () => setState(() => kg = kg + _step),
                  onTapValue: _pickWeight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: BigStepper(value: '${this.reps}', unit: e.timed ? 'seconds' : 'reps', onMinus: () => setState(() => this.reps = (this.reps - 1).clamp(0, 500)), onPlus: () => setState(() => this.reps++), onTapValue: _typeReps),
              ),
            ]),
            if (!e.bodyweight)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final d in _jumps)
                    ActionChip(label: Text('${d > 0 ? '+' : '−'}${fmtNum(d.abs())}'), onPressed: () => _jump(d)),
                ]),
              ),
            if (!simple && !e.bodyweight && kg > 0 && (_bestRepsAt[(kg * 10).round()] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Dim(
                  this.reps > _bestRepsAt[(kg * 10).round()]!
                      ? '${this.reps} reps here would beat your best at this weight (${_bestRepsAt[(kg * 10).round()]})'
                      : 'Best at this weight: ${_bestRepsAt[(kg * 10).round()]} reps · ${_bestRepsAt[(kg * 10).round()]! + 1} = new record',
                  size: 12,
                ),
              ),
            if (_plates != null)
              InkWell(
                onTap: () => plateSheet(context, s, kg, e),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48), // 48 dp to tap (F367)
                  child: Row(children: [
                    const Icon(Icons.album_outlined, size: 18, color: C.teal),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Per side: ${platesText(_plates!.$1)}${!simple && (_plates!.$2 - kg).abs() > 0.05 ? '  (closest you can load: ${fmtWeight(_plates!.$2, s.unit)})' : ''}',
                        style: const TextStyle(color: C.teal),
                      ),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
            if (e.timed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _hold,
                    icon: Icon(_holdStart == null ? Icons.play_arrow : Icons.stop),
                    label: Text(_holdStart == null ? 'Start the hold timer' : 'Stop: ${DateTime.now().difference(_holdStart!).inSeconds} s (target ${item.repLow}-${item.repHigh} s)'),
                  ),
                ),
              ),
            if (!simple)
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                PopupMenuButton<SetType>(
                  tooltip: 'Kind of set',
                  initialValue: _type,
                  onSelected: (t) => setState(() => _type = t),
                  itemBuilder: (c) => [
                    for (final t in SetType.values)
                      PopupMenuItem(
                        value: t,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(setTypeLabel[t]!), Dim(setTypeHelp[t]!, size: 12)]),
                      ),
                  ],
                  child: Chip(
                    avatar: Icon(Icons.tune, size: 16, color: _type == SetType.work ? C.dim : C.gold),
                    label: Text('Kind: ${setTypeLabel[_type]!}', style: TextStyle(color: _type == SetType.work ? C.text : C.gold)),
                  ),
                ),
                if (m.isNotEmpty && _type == SetType.work && !_dropOffered && item.perSet == null) // not on a program's planned sets (P3-7)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _type = SetType.drop;
                      kg = roundToStep(kg * 0.8, e.step, s.unit);
                    }),
                    icon: const Icon(Icons.trending_down, size: 18),
                    label: const Text('Drop set (−20%)'),
                  ),
              ]),
            if (_type == SetType.drop && _dropOffered)
              const Padding(padding: EdgeInsets.only(top: 6), child: Dim('Drop set: weight lowered by about 20%. Go again straight away, as many reps as you can.', size: 12)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  if (m.isEmpty)
                    for (final (i, (wkg, wreps)) in _warmups.indexed)
                      InkWell(
                        onTap: warm > i ? null : () => _logWarmup(wkg, wreps),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.centerLeft,
                          child: DefaultTextStyle.merge(
                            style: TextStyle(color: warm > i ? C.green : C.sky),
                            child: Row(children: [
                              SizedBox(width: 64, child: Text('Warm-up ${i + 1}')),
                              Expanded(child: Text('${fmtWeight(wkg, s.unit)} ${unitLabel(s.unit)}')),
                              Expanded(child: Text(repsWord(wreps))), // "1 rep" (P3-N10)
                              Text(warm > i ? '✓' : 'tap when done', style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                        ),
                      ),
                  for (final x in all.where((x) => !x.counts && !(m.isEmpty && x.type == SetType.warmup && _warmups.isNotEmpty)))
                    InkWell(
                      onTap: () => _editSet(x),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        child: Row(children: [
                          SizedBox(width: 64, child: Text(setTypeLabel[x.type]!, style: const TextStyle(color: C.sky, fontWeight: FontWeight.w700))),
                          Expanded(child: Text('${fmtWeight(x.kg, s.unit)} ${unitLabel(s.unit)}', style: const TextStyle(color: C.sky))),
                          Expanded(child: Text('${x.reps} ${e.timed ? 's' : 'reps'}', style: const TextStyle(color: C.sky))),
                          SizedBox(width: 20, child: Text(x.note.isEmpty ? '' : '✎', style: const TextStyle(color: C.sky))),
                        ]),
                      ),
                    ),
                  for (var i = 0; i < rows; i++)
                    _swipe(i < m.length ? m[i] : null, InkWell(
                      onTap: i < m.length ? () => _editSet(m[i]) : null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: i < m.length ? C.green : (i == m.length ? C.gold : C.dim),
                            fontWeight: i == m.length ? FontWeight.w700 : FontWeight.normal,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          child: Row(children: [
                            SizedBox(width: 64, child: Text(i < m.length && m[i].type != SetType.work ? 'Set ${i + 1} ${setTypeLetter[m[i].type]}' : 'Set ${i + 1}')),
                            Expanded(child: Text(i < m.length ? '${fmtWeight(m[i].kg, s.unit)} ${unitLabel(s.unit)}' : _plannedKg(i))),
                            Expanded(child: Text(i < m.length ? '${m[i].reps} ${e.timed ? 's' : 'reps'}' : _plannedReps(i))),
                            if (i >= m.length && i < lt.length)
                              // last time's numbers for this set: tap to use them
                              TextButton(
                                style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
                                onPressed: () => setState(() {
                                  kg = lt[i].kg;
                                  this.reps = lt[i].reps;
                                }),
                                child: Text('use ${fmtWeight(lt[i].kg, s.unit)}×${lt[i].reps}', style: const TextStyle(fontSize: 12, color: C.sky, fontWeight: FontWeight.normal)),
                              ),
                            if (i < m.length && m[i].effort != null)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(shape: BoxShape.circle, color: const [C.green, C.teal, C.gold, C.sky][(m[i].effort! - 1).clamp(0, 3)]),
                              ),
                            SizedBox(width: 20, child: Text(i < m.length ? (m[i].note.isEmpty ? '✓' : '✎') : '')),
                          ]),
                        ),
                      ),
                    )),
                  if (m.any((x) => x.type != SetType.work))
                    const Padding(padding: EdgeInsets.fromLTRB(14, 2, 14, 4), child: Align(alignment: Alignment.centerLeft, child: Dim(setTypeKey, size: 12))),
                ]),
              ),
            ),
            if (!simple && s.settings.effortChips && left != null && left > Duration.zero && _setAt != null && !_lastWasFinal && s.settings.rest == null && s.settings.smartRest)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Dim('How was that set?'),
                  for (final ef in Effort.values)
                    ChoiceChip(
                      label: Text(effortLabel[ef]!, style: TextStyle(color: _effort == ef ? C.onTeal : C.text)),
                      selected: _effort == ef,
                      showCheckmark: false,
                      onSelected: (_) => _setEffort(ef),
                    ),
                ]),
              ),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: ex > 0 ? () => _go(ex - 1) : null, icon: const Icon(Icons.chevron_left), label: const Text('Back')),
              OutlinedButton(onPressed: _note, child: const Text('Note')),
              OutlinedButton(onPressed: _swap, child: const Text('Swap')),
              OutlinedButton.icon(onPressed: ex < day.items.length - 1 ? () => _go(ex + 1) : null, icon: const Icon(Icons.chevron_right), label: const Text('Next')),
            ]),
          ]),
        ),
      ),
      // F086: dark while resting; every touch on it only wakes the screen (nothing under it is pressed)
      if (dim)
        Positioned.fill(
          // a Material above the text: no yellow "no Material" underline, the app's font (review 5, P2-6)
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
            key: const Key('restDim'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _touchAt = DateTime.now()),
            child: ColoredBox(
              color: const Color(0xF2000000),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_mmss(left!), style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300, color: Color(0xFF5E6B73), fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 8),
                  const Text('Resting · tap to wake', style: TextStyle(color: Color(0xFF4A555C), fontSize: 14)),
                ]),
              ),
            ),
          ),
        )),
        ]),
      ),
    );
  }
}

/// The bar drawn with its plates (one side), in plain colours with the number on each plate.
Future<void> plateSheet(BuildContext context, AppState s, double kg, Exercise e) {
  final ps = s.plateSetup;
  final bar = barFor(e, barKg: ps.bar, smithKg: ps.smith) ?? 0;
  final (plates, made) = platesFor(kg, bar, ps.plates, s.unit);
  Color col(double p) {
    final big = ps.plates.isEmpty ? p : ps.plates.reduce((a, b) => a > b ? a : b);
    final f = p / big;
    if (f > 0.9) return C.navy;
    if (f > 0.7) return C.teal;
    if (f > 0.5) return C.gold;
    if (f > 0.2) return C.green;
    if (f > 0.1) return C.sky;
    return C.dim;
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fmtWeight(made, s.unit)} ${unitLabel(s.unit)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Dim(bar > 0 ? 'Bar ${fmtWeight(bar, s.unit)} ${unitLabel(s.unit)} + on each side:' : 'On each side:'),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(width: 40, height: 14, color: C.dim),
              for (final p in plates)
                Container(
                  margin: const EdgeInsets.only(right: 3),
                  width: 26,
                  height: 50 + 70 * (p / (ps.plates.isEmpty ? p : ps.plates.reduce((a, b) => a > b ? a : b))),
                  decoration: BoxDecoration(color: col(p), borderRadius: BorderRadius.circular(4), border: Border.all(color: C.line)),
                  alignment: Alignment.center,
                  child: RotatedBox(quarterTurns: 3, child: Text(fmtNum(p), style: const TextStyle(fontWeight: FontWeight.w700, color: C.text))),
                ),
              Container(width: 30, height: 10, color: C.dim),
            ]),
          ),
          const SizedBox(height: 8),
          Text(plates.isEmpty ? 'Just the bar.' : 'Per side: ${platesText(plates)}'),
          if ((made - kg).abs() > 0.05) Dim('${fmtWeight(kg, s.unit)} cannot be made with these plates; this is the closest below.', size: 12),
          const SizedBox(height: 6),
          const Dim('Bar and plates come from your gym (Settings → Your gyms).', size: 12),
        ]),
      ),
    ),
  );
}
