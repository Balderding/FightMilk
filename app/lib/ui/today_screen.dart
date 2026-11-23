import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/program.dart';
import '../domain/units.dart';
import '../domain/volume.dart';
import 'ai_sheet.dart';
import '../ai/prompt.dart';
import 'coach_screen.dart';
import 'coaching_screen.dart';
import 'gyms_screen.dart';
import '../domain/plan_maker.dart';
import 'timers_screen.dart';
import 'app_state.dart';
import 'log_screen.dart';
import 'pickers.dart';
import 'reports_screen.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'today_edit.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  final AppState s;
  const TodayScreen({super.key, required this.s});

  /// Do another day of the plan today.
  Future<void> _otherDay(BuildContext context, Plan plan, int di) async {
    final i = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          const Padding(padding: EdgeInsets.all(4), child: Text('Do another day today', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          for (var k = 0; k < plan.days.length; k++)
            if (k != di)
              ListTile(
                title: Text(plan.days[k].name),
                subtitle: Dim('${plan.days[k].items.length} exercises', size: 12),
                onTap: () => Navigator.pop(c, k),
              ),
        ]),
      ),
    );
    if (i != null) await s.pickDay(i);
  }

  String _src(Plan p) => p.program != null ? 'Program' : switch (p.source) { 'ai' => 'AI plan', 'mine' => 'My plan', _ => 'Built-in plan' };

  @override
  Widget build(BuildContext context) {
    final plan = s.plan;
    final day = s.today;
    if (plan == null || day == null || plan.days.isEmpty) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('No plan yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s: s))), child: const Text('Make my plan')),
            ]),
          ),
        ),
      );
    }
    final di = s.session?.dayIndex ?? s.todayIndex;
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(day.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                Dim(plan.weeksPerCycle > 1
                    ? '${plan.name} · week ${s.programWeek.$1} of ${plan.weeksPerCycle} · cycle ${s.programWeek.$2} · ~${dayMinutes(day, s.lib)} min'
                    : 'Week ${s.week} · day ${di + 1} of ${plan.days.length} · ~${dayMinutes(day, s.lib)} min${(s.climbStep ?? 0) == 0 ? '' : ' · extras ${s.climbStep! > 0 ? '+' : ''}${s.climbStep} set'}'),
                if (s.carefulNote != null) Dim(s.carefulNote!, size: 12),
                const SizedBox(height: 4),
                ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded, // 48 dp to tap (F367)
                  avatar: const Icon(Icons.fitness_center, size: 16, color: C.teal),
                  label: Text(s.activeGym == null ? 'Set up your gym' : 'At: ${s.activeGym!.name}${s.takenToday.isEmpty ? '' : ' · ${s.takenToday.length} taken'}'),
                  onPressed: () => s.gyms.isEmpty
                      ? Navigator.push(context, MaterialPageRoute(builder: (_) => GymsScreen(s: s)))
                      : gymSheet(context, s),
                ),
              ]),
            ),
            Flexible(child: Tag(_src(plan), ai: plan.source == 'ai')), // may shrink at a large text size (F364)
            IconButton(
                tooltip: 'Ask AI: questions, or tell it to set things up',
                icon: const Icon(Icons.auto_awesome, color: C.gold),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s))),
              ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'deload') {
                  await s.setDeload(!s.inDeload);
                } else if (v == 'timers') {
                  if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => TimersScreen(s: s)));
                }
              },
              itemBuilder: (c) => [
                if (!s.settings.simple) const PopupMenuItem(value: 'timers', child: Text('Timers (stopwatch, EMOM, Tabata)')),
                if (s.session == null) PopupMenuItem(value: 'deload', child: Text(s.inDeload ? 'End the deload week' : 'Deload this week (lighter)')),
              ],
            ),
          ]),
        ),
        if (s.session != null && s.restLeft != null) _RestBanner(s: s),
        Expanded(
          child: ListView(children: [
            // hints scroll with the list, so any number of them fits on a small screen
            // the cards and chips above the exercises scroll too: at a large text size they never push the Start button off (F364)
            if (s.session == null && s.showTour)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("What's here", style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Dim('• Today: your next workout. Tap Start, then one tap per set; the app moves on by itself.\n'
                        '• Plan: your week. Tap an exercise to change sets, reps and rest.\n'
                        '• History and Progress: every workout, records and charts.\n'
                        '• Ask AI: "chest and arms with drop sets", "the bench is taken". Works even with the AI off.\n'
                        '• Settings: your gym, rest, reminders, backup. Simple mode hides the extras.', size: 13),
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: s.hideTour, child: const Text('Got it'))),
                  ]),
                ),
              ),
            if (s.session == null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Row(children: [
                  ActionChip(
                    avatar: const Icon(Icons.skip_next, size: 18, color: C.teal),
                    label: const Text('Skip day'),
                    onPressed: () async {
                      if (await confirm(context, 'Skip ${day.name}?', 'The next day in your rotation comes up instead.', yes: 'Skip')) await s.skipToday();
                    },
                  ),
                  const SizedBox(width: 6),
                  if (plan.days.length > 1)
                    ActionChip(avatar: const Icon(Icons.swap_horiz, size: 18, color: C.teal), label: const Text('Other day'), onPressed: () => _otherDay(context, plan, di)),
                  const SizedBox(width: 6),
                  ActionChip(avatar: const Icon(Icons.bolt, size: 18, color: C.teal), label: const Text('Quick workout'), onPressed: () => quickWorkout(context, s)),
                  if (!s.settings.simple) ...[
                    const SizedBox(width: 6),
                    ActionChip(avatar: const Icon(Icons.healing, size: 18, color: C.teal), label: Text(s.soreToday.isEmpty ? 'Sore today?' : 'Sore: ${s.soreToday.length}'), onPressed: () => soreSheet(context, s)),
                  ],
                ]),
              ),
            if (s.session != null && DateTime.now().difference(s.session!.started) > const Duration(hours: 3))
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('This workout started ${DateTime.now().difference(s.session!.started).inHours} hours ago. Still going?', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      FilledButton.tonal(onPressed: () => s.finishWorkout(), child: const Text('Finish it')),
                      OutlinedButton(
                        onPressed: () async {
                          if (await confirm(context, 'Throw it away?', 'All sets from this workout are deleted.', yes: 'Throw away')) await s.throwAwayWorkout();
                        },
                        child: const Text('Throw away'),
                      ),
                    ]),
                  ]),
                ),
              ),
            if (s.session == null && s.inDeload)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  leading: const Icon(Icons.spa_outlined, color: C.teal),
                  title: const Text('Deload week'),
                  subtitle: const Dim('Fewer sets at about 90%. Your progress does not move this week, so you come back fresh.', size: 12),
                  trailing: s.deloadUntil != null && DateTime.now().isBefore(s.deloadUntil!) ? TextButton(onPressed: () => s.setDeload(false), child: const Text('End it')) : null,
                ),
              ),
            if (s.session == null && s.restDay)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  leading: const Icon(Icons.bedtime_outlined, color: C.teal),
                  title: const Text('Rest day'),
                  subtitle: Dim('You train ${s.profile!.weekdays.map((d) => weekdayShort[d - 1]).join(', ')}. Next: ${s.nextTrainingDay}, ${day.name}.', size: 12),
                  trailing: TextButton(onPressed: () => s.pickDay(s.todayIndex), child: const Text('Train anyway')),
                ),
              ),
            if (s.session == null && s.programNotes.isNotEmpty)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  leading: const Icon(Icons.trending_up, color: C.green),
                  title: const Text('After your last workout'),
                  subtitle: Dim(s.programNotes.join('\n'), size: 12),
                  trailing: TextButton(
                      onPressed: s.clearProgramNotes,
                      child: const Text('OK')),
                ),
              ),
            if (s.session == null && s.settings.checkin)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Dim('How do you feel today?'),
                  for (final (v, l) in const [(1, 'Rough'), (2, 'OK'), (3, 'Great')])
                    Padding(
                      padding: EdgeInsets.zero,
                      child: ChoiceChip(
                        label: Text(l, style: TextStyle(color: s.feeling == v ? C.onTeal : C.text)),
                        selected: s.feeling == v,
                        showCheckmark: false,
                        onSelected: (on) => s.setFeeling(on ? v : null),
                      ),
                    ),
                ]),
              ),
            if (s.session == null) WeekStripCard(s: s),
            if (s.session == null && plan.program != null) _GraduateHint(s: s),
            if (s.session == null && s.soreToday.isNotEmpty) _SoreCard(s: s),
            if (s.session == null) _RecoveryCard(s: s),
            if (s.session == null && !s.inDeload && !s.settings.simple) _StallHint(s: s),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (day.items.isEmpty)
                  Problem([s.profile?.pregnancy != null && s.careDropped > 0 ? 'Nothing here fits careful mode: pick another day or a Quick workout.' : 'This day has no exercises. Add some under Plan.']),
                for (var i = 0; i < day.items.length; i++) _ExTile(s: s, item: day.items[i], index: i),
                // one tap: add an exercise, for today or the plan too
                Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => addTodayItem(context, s), icon: const Icon(Icons.add), label: const Text('Add exercise'))),
              ]),
            ),
            if (s.session == null) Padding(padding: const EdgeInsets.only(top: 8), child: TipCard(s: s)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: day.items.isEmpty
                  ? null
                  : () async {
                      await s.startWorkout();
                      if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => LogScreen(s: s)));
                    },
              child: Text(s.session == null ? 'Start workout' : 'Resume workout'),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ExTile extends StatelessWidget {
  final AppState s;
  final PlanItem item;
  final int index;
  const _ExTile({required this.s, required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final e = s.lib.byId(item.exerciseId);
    if (e == null) return Card(child: ListTile(title: Text('Unknown exercise ${item.exerciseId}')));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => exerciseInfo(context, s, e),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ExIcon(s.iconFor(e)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              FutureBuilder<Target>(
                future: s.targetFor(item),
                builder: (c, snap) {
                  final t = snap.data;
                  final reps = item.repLow == item.repHigh ? '${item.repLow}' : '${item.repLow}-${item.repHigh}';
                  final w = t?.kg == null ? '' : (e.bodyweight ? (t!.kg! > 0 ? ' @ +${fmtWeight(t.kg!, s.unit)} ${unitLabel(s.unit)}' : ' bodyweight') : ' @ ${fmtWeight(t!.kg!, s.unit)} ${unitLabel(s.unit)}');
                  // programs: each set's reps and the weight range, not "9 x 1-5" (P2-3)
                  final ws = [for (final x in t?.perSet ?? const <double?>[]) if (x != null) x];
                  final line = item.perSet != null
                      ? '${repsShort(item.perSet!)}${ws.isEmpty ? '' : ' · ${fmtWeight(ws.reduce((a, b) => a < b ? a : b), s.unit)}${ws.toSet().length > 1 ? '-${fmtWeight(ws.reduce((a, b) => a > b ? a : b), s.unit)}' : ''} ${unitLabel(s.unit)}'}'
                      : '${item.sets} × $reps${e.timed ? ' s' : ''}$w';
                  return Text.rich(TextSpan(children: [
                    TextSpan(text: line, style: const TextStyle(color: C.dim, fontSize: 13)),
                    if (t?.up == true) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.arrow_upward, size: 14, color: C.gold))),
                  ]));
                },
              ),
            ]),
          ),
          TextButton(
            onPressed: () async {
              final r = await swapSheet(context, s, e, exclude: {for (final it in s.today!.items) it.exerciseId});
              if (r == null) return;
              final ok = await s.swap(index, r.$1, forever: r.$2);
              if (!ok && context.mounted) toast(context, 'Changed for today only: that exercise is not in your plan for this day.');
            },
            child: const Text('Swap'),
          ),
          IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, color: C.dim), onPressed: () => removeTodayItem(context, s, index)),
        ]),
      ),
      ),
    );
  }
}

/// Rest countdown that stays visible after leaving the logging screen.
class _RestBanner extends StatefulWidget {
  final AppState s;
  const _RestBanner({required this.s});
  @override
  State<_RestBanner> createState() => _RestBannerState();
}

class _RestBannerState extends State<_RestBanner> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.s.restLeft ?? Duration.zero;
    final done = left == Duration.zero;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: const Color(0xFF3B2F0B),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LogScreen(s: widget.s))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.timer_outlined, color: C.gold),
              const SizedBox(width: 10),
              Expanded(child: Text(done ? 'Rest over: time for your next set' : 'Resting ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w600))),
              const Text('Back to workout', style: TextStyle(color: C.gold)),
            ]),
          ),
        ),
      ),
    );
  }
}


/// "Ask AI to adjust today", with an optional note on how today is going.
Future<void> adjustToday(BuildContext context, AppState s) async {
  final notes = <String>{};
  final free = TextEditingController();
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('How is today going?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Dim('Optional. The AI adjusts today\'s workout to it.', size: 13),
            const SizedBox(height: 10),
            Pills<String>(
              values: todayNotes.keys.toList(),
              label: (k) => const {'short': 'Short on time', 'tired': 'Tired', 'great': 'Feeling great', 'hurts': 'Something hurts', 'busy': 'Gym is busy'}[k]!,
              selected: notes,
              onTap: (k) => set(() => notes.contains(k) ? notes.remove(k) : notes.add(k)),
            ),
            const SizedBox(height: 10),
            TextField(enableIMEPersonalizedLearning: false, controller: free, decoration: const InputDecoration(hintText: 'Anything else? e.g. "no bench today"')),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Adjust today')),
          ]),
        ),
      ),
    ),
  );
  if (go != true || !context.mounted) return;
  final note = [for (final k in todayNotes.keys) if (notes.contains(k)) todayNotes[k]!, free.text.trim()].where((x) => x.isNotEmpty).join(' ');
  await runAi(context, s, () => s.aiTodayRequest(note: note));
}

/// "Today's guide": the coach's short brief for the session, shown in a sheet.
Future<void> todaysGuide(BuildContext context, AppState s) async {
  final a = await runAsk(context, s, s.aiGuideRequest);
  if (a == null || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("Today's guide: ${s.today?.name ?? ''}", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Flexible(child: SingleChildScrollView(child: SelectableText(plainText(a), style: const TextStyle(fontSize: 15, height: 1.4)))),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text("Let's go")),
        ]),
      ),
    ),
  );
}

/// "Quick workout": tick the muscles, pick a length, and it is today's workout (gym-aware).
Future<void> quickWorkout(BuildContext context, AppState s) async {
  const areas = {'chest': 'Chest', 'back': 'Back', 'shoulders': 'Shoulders', 'arms': 'Arms', 'legs': 'Legs', 'glutes': 'Glutes', 'core': 'Core', 'full': 'Full body'};
  final picked = <String>{};
  var mins = s.profile?.minutes ?? 60;
  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Quick workout', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const Dim('Pick what to train today. Uses your gym\'s equipment; your plan stays as it is.', size: 12),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in areas.entries)
                FilterChip(label: Text(a.value), selected: picked.contains(a.key), onSelected: (v) => set(() => v ? picked.add(a.key) : picked.remove(a.key))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final m in const [30, 45, 60, 90]) ChoiceChip(label: Text('$m min'), selected: mins == m, showCheckmark: false, onSelected: (_) => set(() => mins = m)),
            ]),
            const SizedBox(height: 12),
            FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true), child: const Text("Make it today's workout")),
          ]),
        ),
      ),
    ),
  );
  if (go != true || s.profile == null || s.plan == null) return;
  final names = {'chest': 'Chest', 'back': 'Back', 'shoulders': 'Shoulders', 'arms': 'Arms', 'legs': 'Legs', 'glutes': 'Glutes', 'core': 'Core', 'full': 'Full body'};
  final order = [for (final k in areas.keys) if (picked.contains(k)) k];
  final title = order.length == 1 ? names[order.first]! : '${order.sublist(0, order.length - 1).map((k) => names[k]).join(', ')} & ${names[order.last]}';
  final d = makeDayFor(order, s.profile!, s.lib, minutes: mins, name: title);
  if (d.items.isEmpty) {
    if (context.mounted) toast(context, 'Your gym has nothing for that. Check Settings → Your gyms.');
    return;
  }
  await s.setToday(d);
  if (context.mounted) toast(context, '$title is today\'s workout (${d.items.length} exercises).');
}

/// "Several lifts are stalling": suggests a deload week.
/// Sore today (F236): exercises that are hard on it, and one tap to swap them for today.
class _SoreCard extends StatelessWidget {
  final AppState s;
  const _SoreCard({required this.s});
  @override
  Widget build(BuildContext context) {
    final n = s.soreItems.length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        leading: const Icon(Icons.healing, color: C.gold),
        title: Text('Sore today: ${s.soreToday.map((j) => jointLabel[j]!.toLowerCase()).join(', ')}'),
        subtitle: Dim(n == 0 ? 'Nothing in today\'s workout is hard on it.' : '$n exercise${n == 1 ? ' is' : 's are'} hard on it today.', size: 12),
        onTap: () => soreSheet(context, s),
        trailing: n == 0
            ? null
            : TextButton(
                onPressed: () async {
                  final k = await s.swapSore();
                  if (context.mounted) toast(context, k == 0 ? 'Nothing that fits to swap to: go light or leave it out' : 'Swapped $k for today');
                },
                child: const Text('Swap')),
      ),
    );
  }
}

/// Pick what is sore today (F236). Cleared tomorrow; "go easy on" in setup is for good.
Future<void> soreSheet(BuildContext context, AppState s) async {
  final sel = {...s.soreToday};
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Sore today?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const Dim('Only for today. Exercises that are hard on it get flagged, with a swap. For something that lasts, use Setup → More choices → Go easy on.', size: 12),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final j in Joint.values)
                FilterChip(label: Text(jointLabel[j]!), selected: sel.contains(j), showCheckmark: false, onSelected: (v) => set(() => v ? sel.add(j) : sel.remove(j))),
            ]),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(sel.isEmpty ? 'Nothing is sore' : 'Done')),
          ]),
        ),
      ),
    ),
  );
  if (ok == true) await s.setSore(sel);
}

/// Recovery (F232) and rest-day (F234) hints before a workout.
class _RecoveryCard extends StatefulWidget {
  final AppState s;
  const _RecoveryCard({required this.s});
  @override
  State<_RecoveryCard> createState() => _RecoveryCardState();
}

class _RecoveryCardState extends State<_RecoveryCard> {
  String? _key;
  Future<RecoveryHint?>? _hint;

  /// One look per day shown and change that matters, not one per rebuild.
  Future<RecoveryHint?> _get() {
    final s = widget.s;
    final k = '${s.plan?.id}|${s.todayIndex}|${s.finishedOnPlan}|${s.restHintOff}|${s.settings.simple}|${s.pickedDay}';
    if (k != _key || _hint == null) {
      _key = k;
      _hint = s.recoveryHint();
    }
    return _hint!;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return FutureBuilder<RecoveryHint?>(
        future: _get(),
        builder: (c, snap) {
          final h = snap.data;
          if (h == null) return const SizedBox.shrink();
          final b = h.betterDay;
          return Column(children: [
            if (h.rest != null)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  leading: const Icon(Icons.hotel_outlined, color: C.sky),
                  title: const Text('A day off may be better'),
                  subtitle: Dim(h.rest!, size: 12),
                  trailing: TextButton(onPressed: s.hideRestHint, child: const Text('Not today')),
                ),
              ),
            if (h.warn != null || b != null)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  leading: const Icon(Icons.battery_charging_full, color: C.gold),
                  title: const Text('Still recovering'),
                  subtitle: Dim('${h.warn ?? 'Today\'s muscles are ${h.ready}% recovered.'}${b == null ? '' : ' ${s.plan!.days[b].name} trains more rested muscles.'}', size: 12),
                  trailing: b == null ? null : TextButton(onPressed: () => s.pickDay(b), child: const Text('Do that')),
                ),
              ),
          ]);
        },
      );
  }
}

/// "Time to graduate" from a beginner program (F223), until it is put away.
class _GraduateHint extends StatefulWidget {
  final AppState s;
  const _GraduateHint({required this.s});
  @override
  State<_GraduateHint> createState() => _GraduateHintState();
}

class _GraduateHintState extends State<_GraduateHint> {
  static final Set<String> _hidden = {}; // plans whose hint was put away this run
  @override
  Widget build(BuildContext context) {
    final id = widget.s.plan?.id ?? '';
    if (_hidden.contains(id)) return const SizedBox.shrink();
    return FutureBuilder<String?>(
      future: widget.s.graduateHint(),
      builder: (c, snap) {
        final h = snap.data;
        if (h == null) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ListTile(
            leading: const Icon(Icons.school_outlined, color: C.gold),
            title: const Text('Time to graduate?'),
            subtitle: Dim(h, size: 12),
            trailing: TextButton(onPressed: () => setState(() => _hidden.add(id)), child: const Text('Not yet')),
          ),
        );
      },
    );
  }
}

class _StallHint extends StatelessWidget {
  final AppState s;
  const _StallHint({required this.s});
  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: s.stalling(),
        builder: (c, snap) {
          final n = snap.data ?? 0;
          if (n < 3) return const SizedBox.shrink();
          return Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ListTile(
              leading: const Icon(Icons.trending_flat, color: C.gold),
              title: Text('$n lifts missed reps last time'),
              subtitle: const Dim('A lighter week often fixes that. Your progress stays where it is.', size: 12),
              trailing: TextButton(onPressed: () => s.setDeload(true), child: const Text('Deload this week')),
            ),
          );
        },
      );
}
