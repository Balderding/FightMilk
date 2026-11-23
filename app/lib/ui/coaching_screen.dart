import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/explain.dart';
import '../domain/plan.dart';
import '../domain/progression.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'coach_screen.dart';
import 'history_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'plan_receive.dart';
import '../domain/plan_share.dart' show shareMaxBytes;

/// Batch 16 screens: how the weights move, what the app changed, and why.

/// Settings → Progression → How the weights move (F241).
class RulesScreen extends StatelessWidget {
  final AppState s;
  const RulesScreen({super.key, required this.s});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('How the weights move')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          const Dim('These follow your settings (Settings → Progression), so they change when you change them.', size: 12.5),
          const SizedBox(height: 8),
          for (final (h, b) in rulesText(progressRules, deloadEvery: s.settings.deloadEvery, climb: s.settings.climb, u: s.unit))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(h, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 2), Dim(b, size: 13.5)]),
            ),
        ]),
      );
}

/// Plan → Changes (F242): every weight the app moved, why, and Undo. AI changes have their own list.
class ChangesScreen extends StatefulWidget {
  final AppState s;
  const ChangesScreen({super.key, required this.s});
  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final l = s.autoChanges;
    return Scaffold(
      appBar: AppBar(title: const Text('Changes')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome, color: C.teal),
            title: const Text('AI changes'),
            subtitle: Dim('${s.aiChanges.length} change${s.aiChanges.length == 1 ? '' : 's'} the AI made, each with Undo', size: 12),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AiChangesScreen(s: s))),
          ),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text('Weights the app moved', style: TextStyle(fontWeight: FontWeight.w700))),
        if (l.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Dim('Nothing yet. After each workout, every weight that goes up or down shows here with the reason.')),
        for (var i = 0; i < l.length; i++)
          Card(
            child: ListTile(
              title: Text(s.autoChangeText(l[i]), style: const TextStyle(fontSize: 14)),
              subtitle: Dim(fmtDate(DateTime.fromMillisecondsSinceEpoch(l[i]['at'] as int)), size: 12),
              trailing: l[i]['undone'] == true
                  ? const Dim('Undone', size: 12)
                  : TextButton(
                      onPressed: () async {
                        final ok = await s.undoAutoChange(i);
                        if (!context.mounted) return;
                        toast(context, ok ? 'Put back' : 'It moved again since, so this one cannot be put back. Change the weight in a workout instead.');
                        setState(() {});
                      },
                      child: const Text('Undo')),
            ),
          ),
      ]),
    );
  }
}

/// The "Why?" tap on a target in a workout (F238-F240): this weight, this exercise, this rest.
Future<void> whySheet(BuildContext context, AppState s, Exercise e, PlanItem it, int index, Target? t, {int? setReps}) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Why: ${e.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('This weight', style: TextStyle(fontWeight: FontWeight.w600)),
            Dim(
                [
                  if (t?.why != null) '${t!.why}.',
                  if (t?.tm != null) 'Sets are a % of your training max (${fmtWeight(t!.tm!, s.unit)} ${unitLabel(s.unit)}).',
                  t?.reason ??
                      (t?.tm != null
                          ? 'Set by the program from your training max.'
                          : (t?.kg == null ? 'First time: pick a weight you could do 2 more reps with. The app takes it from there.' : 'Last time\'s weight: nothing has moved it yet.')),
                ].join(' '),
                size: 13.5),
            const SizedBox(height: 10),
            const Text('This exercise', style: TextStyle(fontWeight: FontWeight.w600)),
            Dim(exerciseWhy(e, index, s.profile, sore: s.soreToday), size: 13.5),
            const SizedBox(height: 10),
            const Text('This rest', style: TextStyle(fontWeight: FontWeight.w600)),
            Dim(restWhy(e, it, smart: s.settings.smartRest, planRest: s.settings.rest ?? it.restSec, setReps: setReps), size: 13.5),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RulesScreen(s: s)));
                  },
                  child: const Text('All the rules')),
            ),
          ]),
        ),
      ),
    );

/// Tip of the day on Today (F246).
class TipCard extends StatelessWidget {
  final AppState s;
  const TipCard({super.key, required this.s});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (s.settings.simple || !s.settings.tips || s.tipOff == '${now.year}-${now.month}-${now.day}') return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        leading: const Icon(Icons.lightbulb_outline, color: C.gold),
        title: const Text('Tip'),
        subtitle: Dim(tipOfDay(now), size: 12.5),
        trailing: IconButton(tooltip: 'Put away for today', icon: const Icon(Icons.close, size: 18), onPressed: s.hideTip),
      ),
    );
  }
}

/// Progress → one change for next week (F248): worked out by the app, or asked of the AI.
class WeeklyReviewCard extends StatelessWidget {
  final AppState s;
  final String? shown; // the lift on screen, whose Stuck card already says it
  const WeeklyReviewCard({super.key, required this.s, this.shown});
  @override
  Widget build(BuildContext context) => CachedFuture<String?>(
        cacheKey: '${s.historyVersion}|${s.plan?.id}|$shown',
        load: () => s.weeklySuggestion(shown: shown),
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Next week', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Dim(snap.data ?? 'On track: same plan, keep going.', size: 13),
                if (s.settings.aiOn)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s, ask: 'Look at my last week of training and suggest one change for next week.'))),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Ask AI for one change')),
                  ),
              ]),
            ),
          );
        },
      );
}

/// A stuck lift on Progress (F243, F244, F249): the notice, a variation for a block, or ask the AI.
class StallCard extends StatelessWidget {
  final AppState s;
  final Exercise e;
  const StallCard({super.key, required this.s, required this.e});
  @override
  Widget build(BuildContext context) => CachedFuture<Stall?>(
        cacheKey: '${s.historyVersion}|${e.id}',
        load: () => s.stallFor(e),
        builder: (c, snap) {
          final st = snap.data;
          if (st == null) return const SizedBox.shrink();
          final v = s.variationFor(e);
          final inBlock = s.blockSwapOf(e.id) != null;
          final canSwap = s.blockSwapPlaces(e.id).isNotEmpty; // not a program's % lift (review 2, P1-3)
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.trending_flat, color: C.gold, size: 20), SizedBox(width: 6), Text('Stuck', style: TextStyle(fontWeight: FontWeight.w600))]),
                const SizedBox(height: 4),
                Dim(stallAdvice(e, st), size: 13),
                Wrap(spacing: 4, children: [
                  if (v != null && !inBlock && canSwap)
                    TextButton.icon(
                      onPressed: () async {
                        final got = await s.swapForBlock(e.id);
                        if (context.mounted) toast(context, got == null ? 'No variation fits your gym' : '${got.name} for 4 weeks, then back to ${e.name}');
                      },
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text('${v.name} for 4 weeks'),
                    ),
                  if (inBlock) const Padding(padding: EdgeInsets.all(8), child: Dim('A variation is in your plan for now.', size: 12)),
                  if (s.settings.aiOn)
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => CoachScreen(s: s, ask: 'My ${e.name} has had no new best in ${st.weeks} weeks. Look at my recent sets and suggest one fix.'))),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Ask AI'),
                    ),
                ]),
              ]),
            ),
          );
        },
      );
}

/// Import a plan written as text (F251): a .txt/.md/.csv file, or pasted. Read on the phone; when
/// lines are not understood and the AI is on, it can be asked to read it instead.
Future<void> importPlanSheet(BuildContext context, AppState s) async {
  final text = TextEditingController();
  String? shared; // a picked FightMilk plan file: read whole (up to 1 MB) with the shared-plan checks
  final res = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: C.card,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Import a plan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const Dim('Paste a plan or a FightMilk plan link, or pick a file (.txt, .md, .csv, or a FightMilk .json). Day names on their own line, then one exercise per line, like "Bench press 3x8-10".', size: 12),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await FilePicker.pickFiles(dialogTitle: 'Pick a plan file (text)');
                if (f.isEmpty) return;
                final bytes = await f.first.readAsBytes();
                if (bytes.length > shareMaxBytes) {
                  if (c.mounted) toast(c, 'That file is too big to be a plan (over 1 MB).');
                  return;
                }
                final all = utf8.decode(bytes, allowMalformed: true);
                if (all.trimLeft().startsWith('{')) {
                  shared = all;
                  if (c.mounted) Navigator.pop(c, 'shared');
                  return;
                }
                text.text = all.characters.take(8000).toString();
              },
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Pick a file'),
            ),
            const SizedBox(height: 8),
            TextField(enableIMEPersonalizedLearning: false, controller: text, minLines: 6, maxLines: 12, decoration: const InputDecoration(hintText: 'Push\nBench press 4x6-8\nOverhead press 3x8-10\n\nPull\nDeadlift 3x5\n...')),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => Navigator.pop(c, 'read'), child: const Text('Read it')),
          ]),
        ),
      ),
    ),
  );
  if (res == 'shared' && shared != null && context.mounted) {
    await receivePlan(context, s, shared!);
    return;
  }
  if (res != 'read' || text.text.trim().isEmpty || !context.mounted) return;
  // a FightMilk plan file, link or QR text: the shared-plan checks and preview (batch 20, F327)
  final raw = text.text.trim();
  if (raw.startsWith('{') || raw.startsWith('fightmilk:')) {
    await receivePlan(context, s, raw);
    return;
  }
  final r = parseTextPlan(text.text, s.lib, profile: s.profile);
  final aiCan = s.settings.aiOn;
  if (r.plan == null) {
    if (aiCan && await confirm(context, 'Not a plan the app can read', 'No exercise lines with sets and reps were found. Ask the AI to read it? The text is sent to the AI you picked.', yes: 'Ask AI')) {
      if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s, ask: 'Make this my plan:\n${text.text.characters.take(3000)}')));
    } else if (context.mounted) {
      toast(context, 'No exercise lines with sets and reps found');
    }
    return;
  }
  final p = r.plan!;
  final body = [
    for (final d in p.days) '${d.name}: ${d.items.map((i) => '${s.lib.byId(i.exerciseId)?.name} ${i.sets}×${i.repLow}${i.repHigh > i.repLow ? '-${i.repHigh}' : ''}').join(', ')}',
    if (r.unknown.isNotEmpty) '\nNot understood (left out): ${r.unknown.take(6).join('; ')}${r.unknown.length > 6 ? ' …' : ''}',
    if (r.days > p.days.length) '\n${p.days.length} days kept of ${r.days}.',
    '\nYour current plan is kept under Saved plans.',
  ].join('\n');
  if (!context.mounted) return;
  final ok = await confirm(context, 'Use this plan? (${p.days.length} days)', body, yes: 'Use it');
  if (ok) {
    await s.usePlan(p);
    if (context.mounted) toast(context, 'Imported: ${p.name}');
  } else if (r.unknown.isNotEmpty && aiCan && context.mounted) {
    if (await confirm(context, 'Ask the AI instead?', 'It may understand the lines the app did not. The text is sent to the AI you picked.', yes: 'Ask AI') && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s, ask: 'Make this my plan:\n${text.text.characters.take(3000)}')));
    }
  }
}

