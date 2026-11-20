import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../domain/coach.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/units.dart';
import '../services/sounds.dart';
import 'anim/exercise_anim.dart';
import 'app_state.dart';
import 'pickers.dart';
import 'theme.dart';
import 'widgets.dart';

/// The screen that matters most: one tap per set, weight and reps already filled in.
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
  final Set<String> _asked = {};
  DateTime? _setAt; // when the last set was logged (for effort taps)
  int? _lastReps;
  bool _lastWasFinal = false;
  Effort? _effort;

  PlanDay get day => s.session!.day;
  PlanItem get item => day.items[ex];
  Exercise get e => s.lib.byId(item.exerciseId)!;
  List<SetLog> get mine => sets.where((x) => x.exerciseId == item.exerciseId).toList();

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
    if (left != null && left == Duration.zero && !_beeped) {
      _beeped = true;
      HapticFeedback.heavyImpact();
      s.sounds.play(Reward.restOver);
    }
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
        final n = sets.where((x) => x.exerciseId == day.items[i].exerciseId).length;
        if (n < day.items[i].sets) {
          ex = i;
          break;
        }
        ex = i;
      }
    }
    target = await s.targetFor(item);
    last = await s.repo.lastTime(item.exerciseId, notSession: s.session!.id);
    final m = mine;
    if (m.isNotEmpty) {
      kg = m.last.kg;
      reps = m.last.reps;
    } else {
      kg = target?.kg ?? 0;
      reps = target?.reps ?? item.repLow;
    }
    loaded = true;
    if (mounted) setState(() {});
    if (mine.isEmpty && target?.kg == null && last.isEmpty && !e.bodyweight && !_asked.contains(item.exerciseId)) {
      _asked.add(item.exerciseId);
      WidgetsBinding.instance.addPostFrameCallback((_) => _firstTime());
    }
  }

  /// First time doing a lift: ask what they can handle instead of starting at zero.
  Future<void> _firstTime() async {
    if (!mounted) return;
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: Text('First time: ${e.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What weight can you do for about ${item.repLow} reps${e.equipment == Equipment.dumbbell || e.equipment == Equipment.kettlebell ? ' (per dumbbell)' : ''}? A guess is fine; the app adjusts after this workout.'),
          const SizedBox(height: 10),
          TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(suffixText: unitLabel(s.unit))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Skip')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Use it'))],
      ),
    );
    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (n != null && n > 0 && mounted) setState(() => kg = roundToStep(fromUnit(n, s.unit), e.step, s.unit));
  }

  void _go(int i) {
    if (i < 0 || i >= day.items.length) return;
    ex = i;
    _load();
  }

  double get _step => stepKg(e.step, s.unit);

  bool _saving = false;

  Future<void> _done() async {
    if (_saving) return; // a quick double tap logs one set, not two
    _saving = true;
    setState(() {});
    try {
      HapticFeedback.mediumImpact();
      final it = item, ex = e;
      final before = mine.length;
      await s.repo.logSet(s.session!.id, it.exerciseId, kg, reps);
      await _load();
      final exerciseDone = before + 1 == it.sets;
      final allDone = day.items.every((x) => sets.where((y) => y.exerciseId == x.exerciseId).length >= x.sets);
      s.sounds.play(allDone ? Reward.workout : (exerciseDone ? Reward.exercise : Reward.set));
      _beeped = false;
      _setAt = DateTime.now();
      _lastReps = reps;
      _lastWasFinal = exerciseDone;
      _effort = null;
      if (allDone) {
        s.stopRest();
      } else {
        s.startRest(Duration(seconds: _restFor(ex, it, reps, exerciseDone, null)));
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
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
    if (left.inSeconds <= 0) return _stopRest();
    _beeped = false;
    s.startRest(left);
  }

  String _guide() {
    final m = mine;
    final left = s.restLeft;
    final allDone = day.items.every((x) => sets.where((y) => y.exerciseId == x.exerciseId).length >= x.sets);
    final exDone = m.length >= item.sets;
    final next = ex + 1 < day.items.length ? s.lib.byId(day.items[ex + 1].exerciseId)?.name : null;
    final reps = item.repLow == item.repHigh ? '${item.repLow}' : '${item.repLow}-${item.repHigh}';
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
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Change this set', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              BigStepper(value: fmtWeight(k, s.unit), unit: unitLabel(s.unit), onMinus: () => set(() => k = (k - _step).clamp(0, 2000)), onPlus: () => set(() => k += _step)),
              const SizedBox(height: 8),
              BigStepper(value: '$r', unit: 'reps', onMinus: () => set(() => r = (r - 1).clamp(0, 500)), onPlus: () => set(() => r++)),
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
    if (res == 'save') await s.repo.updateSet(x.id, k, r);
    if (res == 'delete') await s.repo.deleteSet(x.id);
    if (res != null) await _load();
  }

  Future<void> _typeWeight() async {
    final c = TextEditingController(text: fmtWeight(kg, s.unit));
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Weight'),
        content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true, decoration: InputDecoration(suffixText: unitLabel(s.unit))),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('OK'))],
      ),
    );
    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (n != null && n >= 0) setState(() => kg = fromUnit(n, s.unit));
  }

  Future<void> _note() async {
    final c = TextEditingController(text: s.session!.note);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Workout note'),
        content: TextField(controller: c, maxLines: 4, autofocus: true),
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

  Future<void> _finish() async {
    final n = sets.length;
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Finish workout?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Dim(n == 0 ? 'No sets logged, so nothing will be saved and today stays next in line.' : '$n sets logged. Weights for next time are worked out from what you did.', size: 14),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(c, 'finish'), child: const Text('Finish')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Keep going')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(c, 'throw'), child: const Text('Throw this workout away', style: TextStyle(color: C.gold))),
          ]),
        ),
      ),
    );
    if (res == 'throw') {
      if (!mounted) return;
      if (!await confirm(context, 'Throw it away?', 'All sets from this workout are deleted.', yes: 'Throw away')) return;
      await s.throwAwayWorkout();
    } else if (res == 'finish') {
      if (sets.isNotEmpty) s.sounds.play(Reward.workout);
      await s.finishWorkout();
    } else {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  String _lastText() {
    if (last.isEmpty) return 'First time';
    return 'Last time ${last.map((x) => e.bodyweight && x.kg == 0 ? '${x.reps}' : '${fmtWeight(x.kg, s.unit)}×${x.reps}').join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || s.session == null || day.items.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final m = mine;
    final rows = m.length > item.sets ? m.length : item.sets;
    final left = s.restLeft;
    final showRest = left != null && (left > Duration.zero || !_beeped);
    final reps = item.repLow == item.repHigh ? '${item.repLow}' : '${item.repLow}-${item.repHigh}';
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(day.name),
          actions: [TextButton(onPressed: _finish, child: const Text('Finish'))],
        ),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 16), children: [
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: day.items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (c, i) {
                  if (i == day.items.length) return ActionChip(label: const Text('+ Add'), onPressed: _addExercise);
                  final it = day.items[i];
                  final n = sets.where((x) => x.exerciseId == it.exerciseId).length;
                  final done = n >= it.sets;
                  return ChoiceChip(
                    label: Text('${i + 1}${done ? ' ✓' : ''}', style: TextStyle(color: i == ex ? C.onTeal : (done ? C.green : C.text))),
                    selected: i == ex,
                    showCheckmark: false,
                    onSelected: (_) => _go(i),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Center(child: ExerciseAnim(key: ValueKey(e.id), e: e, size: 150)),
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
                  Dim('Target ${item.sets} × $reps${e.timed ? ' s' : ''} · ${_lastText()}'),
                  if (e.equipment == Equipment.dumbbell || e.equipment == Equipment.kettlebell) const Dim('Weight per dumbbell', size: 12),
                  if (e.equipment == Equipment.band) const Dim('Band: log reps (weight optional) · tap for how-to', size: 12)
                  else if (e.bodyweight) const Dim('Weight = added weight (0 = bodyweight) · tap for how-to', size: 12)
                  else const Dim('Tap for how to do it', size: 12),
                ]),
              ),
              const Icon(Icons.info_outline, color: C.dim),
            ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 13,
                child: BigStepper(
                  value: fmtWeight(kg, s.unit),
                  unit: unitLabel(s.unit),
                  onMinus: () => setState(() => kg = (kg - _step).clamp(0, 2000)),
                  onPlus: () => setState(() => kg = kg + _step),
                  onTapValue: _typeWeight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: BigStepper(value: '${this.reps}', unit: e.timed ? 'seconds' : 'reps', onMinus: () => setState(() => this.reps = (this.reps - 1).clamp(0, 500)), onPlus: () => setState(() => this.reps++)),
              ),
            ]),
            const SizedBox(height: 10),
            FilledButton(onPressed: _saving ? null : _done, child: const Text('Done set')),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (var i = 0; i < rows; i++)
                    InkWell(
                      onLongPress: i < m.length ? () => _editSet(m[i]) : null,
                      onTap: i < m.length ? () => _editSet(m[i]) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: i < m.length ? C.green : (i == m.length ? C.gold : C.dim),
                            fontWeight: i == m.length ? FontWeight.w700 : FontWeight.normal,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          child: Row(children: [
                            SizedBox(width: 60, child: Text('Set ${i + 1}')),
                            Expanded(child: Text(i < m.length ? '${fmtWeight(m[i].kg, s.unit)} ${unitLabel(s.unit)}' : (target?.kg == null ? '–' : '${fmtWeight(target!.kg!, s.unit)} ${unitLabel(s.unit)}'))),
                            Expanded(child: Text(i < m.length ? '${m[i].reps} ${e.timed ? 's' : 'reps'}' : '$reps ${e.timed ? 's' : 'reps'}')),
                            SizedBox(width: 20, child: Text(i < m.length ? '✓' : '')),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            if (left != null && left == Duration.zero)
              Card(child: ListTile(leading: const Icon(Icons.timer_off_outlined, color: C.gold), title: const Text('Rest over: time for your next set'), trailing: TextButton(onPressed: _stopRest, child: const Text('OK')))),
            if (showRest && left > Duration.zero && _setAt != null && !_lastWasFinal && s.settings.rest == null && s.settings.smartRest)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
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
            if (showRest && left > Duration.zero)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    const Dim('Rest'),
                    Text('${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: C.gold, fontFeatures: [FontFeature.tabularFigures()])),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      OutlinedButton(onPressed: () => _addRest(-30), child: const Text('−30s')),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: () => _addRest(30), child: const Text('+30s')),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: _stopRest, child: const Text('Skip')),
                    ]),
                  ]),
                ),
              ),
            const SizedBox(height: 4),
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: ex > 0 ? () => _go(ex - 1) : null, icon: const Icon(Icons.chevron_left), label: const Text('Back')),
              OutlinedButton(onPressed: _note, child: const Text('Note')),
              OutlinedButton(onPressed: _swap, child: const Text('Swap')),
              OutlinedButton.icon(
                onPressed: ex < day.items.length - 1 ? () => _go(ex + 1) : _finish,
                icon: const Icon(Icons.chevron_right),
                label: Text(ex < day.items.length - 1 ? 'Next' : 'Finish'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
