import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/body.dart';
import '../domain/stats.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'history_screen.dart';
import 'lift_chart.dart';
import 'theme.dart';
import 'widgets.dart';

/// Progress → Body (batch 19): body weight, body fat, tape, photos, the weigh-in reminder, and
/// the strength scores. Everything stays on this phone; photos are never in the gallery or the AI.
class BodyScreen extends StatefulWidget {
  final AppState s;
  const BodyScreen({super.key, required this.s});
  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  AppState get s => widget.s;

  Future<void> _weighIn() async {
    if (await showWeighIn(context, s) && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final u = s.unit;
    final label = paintLabel(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Body')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _weighIn, icon: const Icon(Icons.monitor_weight_outlined), label: const Text('Weigh in')),
      body: CachedFuture<(List<(String, DateTime, double?, double?)>, (Map<String, double>, Map<String, int>), Map<String, List<Pt>>)>(
        cacheKey: '${s.historyVersion}|${s.tape.length}|${s.photos.length}|${s.profile?.heightCm}|${s.settings.weighAt}|${s.aims.length}',
        load: () async {
          final e = <String, List<Pt>>{};
          for (final id in const ['back_squat', 'bench_press', 'deadlift']) {
            e[id] = seriesOf(await s.repo.setsOf(id), ChartKind.e1rm);
          }
          return (await s.repo.bodyLog(), await s.mainLifts(), e);
        },
        builder: (c, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          final (log, (maxes, workouts), e1) = d;
          final simple = s.settings.simple; // Simple keeps the weight card and the weigh-in (review 4, P2-6)
          final weights = [for (final b in log.reversed) if (b.$3 != null) Pt(b.$2, b.$3!, '')];
          final recent = [for (final p in weights) if (DateTime.now().difference(p.at).inDays <= 120) p];
          final rate = ratePerWeek([for (final p in weights) if (DateTime.now().difference(p.at).inDays <= 28) p]);
          final goal = s.aims.where((g) => g.kind == 'body').firstOrNull;
          // only a recent body fat % goes with today's weight (review 4, P2-5)
          final fat = [for (final b in log) if (b.$4 != null && DateTime.now().difference(b.$2).inDays <= 30) b.$4!].firstOrNull;
          final oldFat = fat == null && log.any((b) => b.$4 != null);
          final bw = s.bodyKgNow;
          final h = s.profile?.heightCm;
          final total = totalByMonth(e1);
          final sbd = ['back_squat', 'bench_press', 'deadlift'].every(maxes.containsKey) ? maxes['back_squat']! + maxes['bench_press']! + maxes['deadlift']! : null;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
            // body weight (F299) with the goal line
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Body weight', style: TextStyle(fontWeight: FontWeight.w700)),
                  if (weights.isEmpty) const Dim('No weigh-ins yet. Tap Weigh in.', size: 12.5),
                  if (weights.isNotEmpty) ...[
                    Text('${fmtWeight(weights.last.v, u)} ${unitLabel(u)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    Dim(
                        [
                          if (showSevenDay(weights, DateTime.now())) '7-day average ${fmtWeight(sevenDayAverage(weights).last, u)} ${unitLabel(u)}',
                          if (rate != null) 'about ${rate >= 0 ? '+' : '−'}${fmtWeight(rate.abs(), u)} ${unitLabel(u)} a week (last 4 weeks)',
                          if (goal != null) 'goal ${fmtWeight(goal.target, u)} ${unitLabel(u)}',
                        ].join(' · '),
                        size: 12),
                    if (recent.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          height: 170,
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: ChartPainter(
                              pts: [for (final p in recent) Pt(p.at, toUnit(p.v, u), '')],
                              avg: sevenDayAverage(recent).map((x) => toUnit(x, u)).toList(),
                              label: label,
                              lines: goal == null ? const [] : [(toUnit(goal.target, u), 'Goal')],
                              smooth: s.settings.chartSmooth,
                              dots: s.settings.chartDots,
                            ),
                          ),
                        ),
                      ),
                    if (recent.length > 1) const Dim('Dots: weigh-ins. Line: the 7-day average.', size: 12),
                  ],
                ]),
              ),
            ),
            // body fat and derived numbers (F300)
            if (!simple)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(child: Text('Body numbers', style: TextStyle(fontWeight: FontWeight.w700))),
                    TextButton(onPressed: _height, child: Text(h == null ? 'Add height' : 'Height ${fmtHeight(h, u)}')),
                  ]),
                  if (bw == null) const Dim('Weigh in to see them.', size: 12),
                  if (bw != null && h != null) Text('BMI ${bmi(bw, h).toStringAsFixed(1)}'),
                  if (bw != null && fat != null) Text('Body fat ${fat.toStringAsFixed(1)}% · lean mass about ${fmtWeight(leanMass(bw, fat), u)} ${unitLabel(u)} (estimate)'),
                  if (bw != null && fat != null && h != null) Text('FFMI about ${ffmi(bw, fat, h).toStringAsFixed(1)} (estimate)'),
                  if (bw != null && (fat == null || h == null))
                    Dim('${h == null ? 'Add your height for BMI. ' : ''}${fat == null ? (oldFat ? 'Add a recent body fat % (last 30 days) for lean mass and FFMI.' : 'Add a body fat % when you weigh in for lean mass and FFMI.') : ''}', size: 12),
                  if (fat != null) const Dim('Lean mass and FFMI are estimates: they are only as good as the body fat number (home scales can be several points off).', size: 12),
                  const Dim('BMI does not know muscle from fat; for lifters FFMI says more.', size: 12),
                ]),
              ),
            ),
            if (!simple) _TapeCard(s: s),
            if (!simple) _PhotosCard(s: s),
            // morning weigh-in reminder (F303), off by default
            Card(
              child: SwitchListTile(
                value: s.settings.weighAt >= 0,
                onChanged: (v) async {
                  var at = 7 * 60;
                  if (v) {
                    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 0));
                    if (t == null) return;
                    at = t.hour * 60 + t.minute;
                  }
                  await s.saveSettings(s.settings.copyWith(weighAt: v ? at : -1));
                  if (mounted) setState(() {});
                },
                title: const Text('Morning weigh-in reminder'),
                subtitle: FutureBuilder<bool?>(
                  future: s.settings.weighAt < 0 ? Future.value(true) : s.notifier.enabled(),
                  builder: (c, n) => Dim(
                      s.settings.weighAt < 0
                          ? 'Off'
                          : n.data == false
                              ? 'Notifications are off for FightMilk in Android settings, so nothing will show.'
                              : 'Every day at ${s.settings.weighAt ~/ 60}:${(s.settings.weighAt % 60).toString().padLeft(2, '0')}, for the 2 weeks after each visit; not on a day you have weighed in.',
                      size: 12),
                ),
              ),
            ),
            // strength scores (F305-F309)
            if (!simple)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Strength', style: TextStyle(fontWeight: FontWeight.w700)),
                  if (s.profile?.sex == null && bw != null && maxes.isNotEmpty)
                    Row(children: [
                      const Expanded(child: Dim("Levels and points use the men's tables because no sex is set.", size: 12)),
                      TextButton(key: const Key('setSex'), onPressed: _sex, child: const Text('Set it')),
                    ]),
                  if (bw == null) const Dim('Weigh in once: the scores are fair for body weight.', size: 12),
                  if (bw != null && maxes.isEmpty) const Dim('Do a squat, bench, deadlift, overhead press or barbell row to see your levels.', size: 12),
                  if (bw != null && maxes.isNotEmpty) ...[
                    Text('Strength score ${strengthScore(maxes, bw, female: s.female)} / 100', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.teal)),
                    const Dim('From your best est. 1-rep max of the last 90 days, against your body weight. Our own rough guide, not a published table.', size: 12),
                    const SizedBox(height: 6),
                    for (final e in maxes.entries)
                      () {
                        final (lvl, next, part) = strengthLevelOf(e.key, e.value, bw, female: s.female);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(s.lib.byId(e.key)?.name ?? e.key)),
                              Text(lvl < 0 ? 'Getting started' : levelNames5[lvl], style: const TextStyle(color: C.gold, fontWeight: FontWeight.w600)),
                            ]),
                            LinearProgressIndicator(value: part, backgroundColor: C.card2, color: C.teal),
                            Dim('${fmtWeight(e.value, u)} ${unitLabel(u)}${next == null ? '' : ' · next level at ${fmtWeight(next, u)} ${unitLabel(u)}'}', size: 12),
                          ]),
                        );
                      }(),
                    for (final (a, b, r, usual) in laggingLifts(maxes, workouts: workouts))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Dim(
                            '${s.lib.byId(a)?.name} is low next to your ${(s.lib.byId(b)?.name ?? b).toLowerCase()} (${(r * 100).round()}% of it; many lifters are near ${(usual * 100).round()}%). Proportions differ, so it is only a hint.',
                            size: 12),
                      ),
                    if (sbd != null) ...[
                      const SizedBox(height: 8),
                      Text('Estimated total ${fmtWeight(sbd, u)} ${unitLabel(u)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Dim('Squat + bench + deadlift, from your best est. 1-rep maxes: not a meet total.', size: 12),
                      Dim('DOTS ${dots(sbd, bw, female: s.female).toStringAsFixed(1)} · Wilks (original) ${wilks(sbd, bw, female: s.female).toStringAsFixed(1)} · IPF GL ${ipfGl(sbd, bw, female: s.female).toStringAsFixed(1)} (estimates)', size: 12),
                      // the formulas stop at the edges of their body weight range (review 5, P3-N31)
                      if (pointsEdge(bw, female: s.female) != null) Dim(pointsEdge(bw, female: s.female)!, size: 12),
                      if (total.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SizedBox(height: 120, child: CustomPaint(size: Size.infinite, painter: ChartPainter(pts: [for (final (m, v) in total) Pt(m, toUnit(v, u), '')], label: label))),
                        ),
                    ],
                  ],
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  /// One tap from the Strength card to the sex answer (review 4, P2-5); the same answer as Setup →
  /// About you, used for the tables and first weights only.
  Future<void> _sex() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      builder: (b) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Which tables to use'), subtitle: Dim('The same answer as Setup → About you. Only for the strength tables and first weights.', size: 12)),
          ListTile(title: const Text('Female'), onTap: () => Navigator.pop(b, 'f')),
          ListTile(title: const Text('Male'), onTap: () => Navigator.pop(b, 'm')),
        ]),
      ),
    );
    if (v != null && s.profile != null) await s.saveProfile(s.profile!.copyWith(sex: v));
    if (mounted) setState(() {});
  }

  Future<void> _height() async {
    final c = TextEditingController(text: s.profile?.heightCm == null ? '' : (s.unit == Unit.kg ? '${s.profile!.heightCm!.round()}' : fmtHeight(s.profile!.heightCm!, s.unit).replaceAll(' ft ', "'").replaceAll(' in', '')));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (b) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(b).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(enableIMEPersonalizedLearning: false, controller: c, autofocus: true, keyboardType: s.unit == Unit.kg ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: 'Height', suffixText: s.unit == Unit.kg ? 'cm' : null, hintText: s.unit == Unit.kg ? '178' : "5'10 or 70 in")),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(b, true), child: const Text('Save')),
        ]),
      ),
    );
    final v = parseHeight(c.text);
    if (ok == true && v != null && s.profile != null) await s.saveProfile(s.profile!.copyWith(heightCm: v));
    if (mounted) setState(() {});
  }
}

/// The weigh-in sheet (Body screen and the Progress card): body weight, optional fat %, and the
/// day. A number out of range keeps the sheet open with a plain line (review 4, P2-3).
/// True when a weigh-in was saved. [prefillKg] and [note] come from a link (F354): the number
/// is only filled in; the person checks it and taps Save.
Future<bool> showWeighIn(BuildContext context, AppState s, {double? prefillKg, String? note}) async {
  final u = s.unit;
  final kg = TextEditingController(text: prefillKg == null ? '' : fmtWeight(prefillKg, u)), fat = TextEditingController();
  var day = DateTime.now();
  String? err;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        void save() {
          final w = double.tryParse(kg.text.replaceAll(',', '.'));
          final f = fat.text.trim().isEmpty ? null : double.tryParse(fat.text.replaceAll(',', '.').replaceAll('%', ''));
          if (w == null || !validBodyKg(fromUnit(w, u))) {
            set(() => err = 'That looks off. Body weight between ${fmtWeight(bodyKgMin, u)} and ${fmtWeight(bodyKgMax, u)} ${unitLabel(u)}.');
            return;
          }
          if (fat.text.trim().isNotEmpty && (f == null || !validFat(f))) {
            set(() => err = 'Body fat is a percent between ${fatMin.round()} and ${fatMax.round()}.');
            return;
          }
          Navigator.pop(c, true);
        }

        final today = DateUtils.isSameDay(day, DateTime.now());
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Text('Weigh in', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              TextButton.icon(
                key: const Key('weighDay'),
                onPressed: () async {
                  final d = await showDatePicker(context: c, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)), lastDate: DateTime.now());
                  if (d != null) set(() => day = today && DateUtils.isSameDay(d, DateTime.now()) ? day : DateTime(d.year, d.month, d.day, 8));
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text(today ? 'Today' : fmtDate(day)),
              ),
            ]),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, style: const TextStyle(color: C.gold, fontSize: 13))),
            const SizedBox(height: 8),
            TextField(enableIMEPersonalizedLearning: false, controller: kg, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Body weight', suffixText: unitLabel(u)), onChanged: (_) => set(() => err = null)),
            TextField(enableIMEPersonalizedLearning: false, controller: fat, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Body fat (optional)', suffixText: '%'), onChanged: (_) => set(() => err = null)),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: C.gold))),
            const SizedBox(height: 10),
            FilledButton(onPressed: save, child: const Text('Save')),
          ]),
        );
      },
    ),
  );
  if (saved != true) return false;
  final w = fromUnit(double.parse(kg.text.replaceAll(',', '.')), u);
  final f = fat.text.trim().isEmpty ? null : double.parse(fat.text.replaceAll(',', '.').replaceAll('%', ''));
  await s.repo.logBody(w, fat: f, at: DateUtils.isSameDay(day, DateTime.now()) ? null : day);
  await s.reload();
  s.applyPrefs(); // weighed in today: today's reminder goes (P3-N23)
  return true;
}

/// Tape measurements (F301): neck to calves, left and right, and your own kinds.
class _TapeCard extends StatelessWidget {
  final AppState s;
  const _TapeCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final latest = <String, Tape>{}, first = <String, Tape>{};
    for (final t in s.tape) {
      first.putIfAbsent(t.label, () => t);
      latest[t.label] = t;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Tape', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.straighten, size: 18), label: const Text('Measure')),
          ]),
          if (latest.isEmpty) const Dim('Arms, waist, thighs… measure every few weeks, same time of day.', size: 12),
          for (final e in latest.entries)
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TapeHistoryScreen(s: s, label: e.key))),
              child: Row(children: [
              Expanded(child: Text(e.key)),
              Text(fmtLen(e.value.cm, s.unit)),
              SizedBox(
                width: 70,
                child: Text(
                  first[e.key] == e.value ? '' : '${e.value.cm >= first[e.key]!.cm ? '+' : '−'}${fmtNum(toLen((e.value.cm - first[e.key]!.cm).abs(), s.unit))}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: C.dim, fontSize: 12),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: C.dim),
            ]),
            ),
          if (latest.isNotEmpty) const Dim('Tap a row to see its history or fix a typo.', size: 12),
        ]),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    var part = 'waist', side = '';
    final own = TextEditingController(), cm = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Measure', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in [...tapeParts.keys, 'own'])
                ChoiceChip(label: Text(p == 'own' ? 'My own' : '${p[0].toUpperCase()}${p.substring(1)}'), selected: part == p, showCheckmark: false, onSelected: (_) => set(() => part = p)),
            ]),
            if (part == 'own') TextField(enableIMEPersonalizedLearning: false, controller: own, decoration: const InputDecoration(labelText: 'What (e.g. lower waist)')),
            if (tapeParts[part] == true)
              Wrap(spacing: 6, children: [
                for (final (v, l) in const [('L', 'Left'), ('R', 'Right')]) ChoiceChip(label: Text(l), selected: side == v, showCheckmark: false, onSelected: (_) => set(() => side = v)),
              ]),
            TextField(enableIMEPersonalizedLearning: false, controller: cm, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Size', suffixText: lengthUnit(s.unit))),
            const SizedBox(height: 10),
            if (tapeParts[part] == true && side.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Dim('Pick left or right.', size: 12)),
            const SizedBox(height: 10),
            // a sided part needs its side (review 4, P2-8: it used to become "left" by itself)
            FilledButton(onPressed: tapeParts[part] == true && side.isEmpty ? null : () => Navigator.pop(c, true), child: const Text('Save')),
          ]),
        ),
      ),
    );
    final n = double.tryParse(cm.text.replaceAll(',', '.'));
    final v = n == null ? null : fromLen(n, s.unit);
    final name = part == 'own' ? own.text.trim().toLowerCase() : part;
    if (ok != true || v == null || v <= 0 || v > 300 || name.isEmpty) return;
    await s.addTape(name, v, side: tapeParts[part] == true ? side : '');
  }
}

/// One body part's measurements, newest first; swipe one away to delete it, with Undo (P2-8).
class TapeHistoryScreen extends StatelessWidget {
  final AppState s;
  final String label;
  const TapeHistoryScreen({super.key, required this.s, required this.label});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(label)),
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final rows = [for (var i = s.tape.length - 1; i >= 0; i--) if (s.tape[i].label == label) i];
            if (rows.isEmpty) return const Center(child: Dim('No measurements left.'));
            return ListView(children: [
              const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Dim('Swipe a row away to delete it.', size: 12)),
              for (final i in rows)
                Dismissible(
                  key: ValueKey('tape-${s.tape[i].at.millisecondsSinceEpoch}-$i'),
                  background: Container(color: C.card2, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete_outline, color: C.gold)),
                  onDismissed: (_) async {
                    final t = s.tape[i];
                    await s.removeTape(i);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text('Deleted ${fmtLen(t.cm, s.unit)} from ${fmtDate(t.at)}'), action: SnackBarAction(label: 'Undo', onPressed: () => s.insertTape(i, t))));
                  },
                  child: ListTile(title: Text(fmtLen(s.tape[i].cm, s.unit)), subtitle: Dim(fmtDate(s.tape[i].at), size: 12)),
                ),
            ]);
          },
        ),
      );
}

/// Progress photos (F302): kept only in the app's own folder, never in the gallery or the AI.
class _PhotosCard extends StatefulWidget {
  final AppState s;
  const _PhotosCard({required this.s});
  @override
  State<_PhotosCard> createState() => _PhotosCardState();
}

class _PhotosCardState extends State<_PhotosCard> {
  final picked = <String>[];

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final l = [...s.photos]..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Progress photos', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: () async {
                final f = await FilePicker.pickFiles(dialogTitle: 'Pick a photo', type: FileType.image);
                if (f.isEmpty) return;
                await s.addPhoto(await f.first.readAsBytes());
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add'),
            ),
          ]),
          const Dim('The app keeps its own copy, inside the app only: not in the backup file or the AI. The photo you picked stays where it was; delete it there if you like. Tap two to compare; long-press a photo to delete it.', size: 12),
          if (l.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 110,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final ph in l)
                    GestureDetector(
                      onTap: () => setState(() => picked.contains(ph['id']) ? picked.remove(ph['id']) : (picked.length < 2 ? picked.add(ph['id'] as String) : null)),
                      onLongPress: () async {
                        if (await confirm(context, 'Delete this photo?', 'It is removed from the app.', yes: 'Delete')) {
                          await s.removePhoto(ph['id'] as String);
                          if (mounted) setState(() => picked.remove(ph['id']));
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(border: Border.all(color: picked.contains(ph['id']) ? C.gold : Colors.transparent, width: 2)),
                        child: Column(children: [
                          Expanded(child: Image.file(File(s.photoPath(ph)), width: 70, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 70, child: Icon(Icons.broken_image)))),
                          Dim(fmtDate(DateTime.fromMillisecondsSinceEpoch(ph['at'] as int)).split(' ').skip(1).join(' '), size: 12),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          if (picked.length == 2)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Side by side')),
                      body: Row(children: [
                        for (final id in picked)
                          Expanded(
                            child: Column(children: [
                              Expanded(child: Image.file(File(s.photoPath(s.photos.firstWhere((x) => x['id'] == id))), fit: BoxFit.contain)),
                              Dim(fmtDate(DateTime.fromMillisecondsSinceEpoch(s.photos.firstWhere((x) => x['id'] == id)['at'] as int)), size: 12),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ),
                icon: const Icon(Icons.compare),
                label: const Text('Side by side'),
              ),
            ),
        ]),
      ),
    );
  }
}
