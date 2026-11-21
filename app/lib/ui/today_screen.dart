import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/plan.dart';
import '../domain/units.dart';
import 'ai_sheet.dart';
import '../ai/prompt.dart';
import 'coach_screen.dart';
import 'gyms_screen.dart';
import '../domain/plan_maker.dart';
import 'timers_screen.dart';
import 'app_state.dart';
import 'log_screen.dart';
import 'pickers.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  final AppState s;
  const TodayScreen({super.key, required this.s});

  String _src(Plan p) => switch (p.source) { 'ai' => 'AI plan', 'mine' => 'My plan', _ => 'Built-in plan' };

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
              FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s: s))), child: const Text('Make a plan')),
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
                Dim('Week ${s.week} · day ${di + 1} of ${plan.days.length} · ~${s.profile?.minutes ?? 60} min'),
                const SizedBox(height: 4),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.fitness_center, size: 16, color: C.teal),
                  label: Text(s.activeGym == null ? 'Set up your gym' : 'At: ${s.activeGym!.name}${s.takenToday.isEmpty ? '' : ' · ${s.takenToday.length} taken'}'),
                  onPressed: () => s.gyms.isEmpty
                      ? Navigator.push(context, MaterialPageRoute(builder: (_) => GymsScreen(s: s)))
                      : gymSheet(context, s),
                ),
              ]),
            ),
            Tag(_src(plan), ai: plan.source == 'ai'),
            IconButton(
                tooltip: 'Ask AI: questions, or tell it to set things up',
                icon: const Icon(Icons.auto_awesome, color: C.gold),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s))),
              ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'skip') {
                  if (await confirm(context, 'Skip ${day.name}?', 'The next day in your rotation comes up instead.', yes: 'Skip')) await s.skipToday();
                } else if (v.startsWith('day:')) {
                  s.pickDay(int.parse(v.substring(4)));
                } else if (v == 'ai') {
                  if (context.mounted) await adjustToday(context, s);
                } else if (v == 'guide') {
                  if (context.mounted) await todaysGuide(context, s);
                } else if (v == 'quick') {
                  if (context.mounted) await quickWorkout(context, s);
                } else if (v == 'deload') {
                  await s.setDeload(!s.inDeload);
                } else if (v == 'timers') {
                  if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => TimersScreen(s: s)));
                }
              },
              itemBuilder: (c) => [
                if (s.session == null) const PopupMenuItem(value: 'quick', child: Text('Quick workout: pick muscles')),
                const PopupMenuItem(value: 'timers', child: Text('Timers (stopwatch, EMOM, Tabata)')),
                if (s.session == null) PopupMenuItem(value: 'deload', child: Text(s.inDeload ? 'End the deload week' : 'Deload this week (lighter)')),
                if (s.session == null) const PopupMenuItem(value: 'skip', child: Text('Skip this day')),
                if (s.session == null)
                  for (var i = 0; i < plan.days.length; i++)
                    if (i != di) PopupMenuItem(value: 'day:$i', child: Text('Do ${plan.days[i].name} instead')),
                if (s.settings.aiOn) const PopupMenuItem(value: 'guide', child: Text("Today's guide")),
                if (s.settings.aiOn) const PopupMenuItem(value: 'ai', child: Text('Ask AI to adjust today')),
              ],
            ),
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
        if (s.session != null && s.restLeft != null) _RestBanner(s: s),
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
        if (s.session == null && !s.inDeload) _StallHint(s: s),
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
        if (s.session == null && day.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.campaign_outlined, color: C.gold),
                const SizedBox(width: 10),
                Expanded(child: Text('Hey! Today is ${day.name}: ${day.items.length} exercises, about ${s.profile?.minutes ?? 60} minutes. Start the workout now!', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
            if (day.items.isEmpty) const Problem(['This day has no exercises. Add some under Plan.']),
            for (var i = 0; i < day.items.length; i++) _ExTile(s: s, item: day.items[i], index: i),
            if (s.settings.aiOn && s.session == null)
              TextButton.icon(onPressed: () async {
                await adjustToday(context, s);
              }, icon: const Icon(Icons.auto_awesome, color: C.gold), label: const Text('Ask AI to adjust today')),
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
                  return Text.rich(TextSpan(children: [
                    TextSpan(text: '${item.sets} × $reps${e.timed ? ' s' : ''}$w', style: const TextStyle(color: C.dim, fontSize: 13)),
                    if (t?.up == true) const TextSpan(text: '  ↑', style: TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
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
