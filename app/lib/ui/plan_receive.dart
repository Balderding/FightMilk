import 'package:flutter/material.dart';

import '../domain/plan_share.dart';
import '../domain/program.dart' show scriptWords;
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// A plan someone sent (a file, a link, a QR code or pasted text): read with every check, shown
/// first, saved as a new plan only when the person says so (batch 20, F327; MCP guardrails).
/// Returns true when a plan was saved.
Future<bool> receivePlan(BuildContext context, AppState s, String input) async {
  final r = readSharedPlan(input, s.lib);
  if (!r.ok) {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Not a plan the app can use'),
        content: Text([...r.problems, if (r.unknown.isNotEmpty) 'Exercises this app does not have: ${r.unknown.take(8).join(', ')}'].join('\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
    return false;
  }
  final plan = r.plan!;
  final fixes = s.profile == null ? <GymFix>[] : gymFixes(plan, s.profile!, s.lib);
  final swap = {for (var i = 0; i < fixes.length; i++) if (fixes[i].to != null) i};
  var useScripts = false; // the plan's own rules stay out until the person says "Use these rules"
  if (!context.mounted) return false;
  final how = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            Text('A plan to add: ${plan.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Dim('${plan.days.length} day${plan.days.length == 1 ? '' : 's'}. It is saved as a new plan; your plans stay as they are.', size: 12),
            const SizedBox(height: 8),
            for (final d in plan.days.take(7))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${d.name}: ${d.items.map((i) => '${s.lib.byId(i.exerciseId)?.name} ${i.sets}×${i.repLow}${i.repHigh > i.repLow ? '-${i.repHigh}' : ''}').join(', ')}', style: const TextStyle(fontSize: 13)),
              ),
            if (plan.days.length > 7) Dim('… and ${plan.days.length - 7} more days', size: 12),
            if (r.unknown.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Left out (not in this app): ${r.unknown.take(8).join(', ')}${r.unknown.length > 8 ? ' and ${r.unknown.length - 8} more' : ''}', style: const TextStyle(color: C.gold, fontSize: 13)),
            ],
            for (final n in r.notes) Text(n, style: const TextStyle(color: C.gold, fontSize: 13)),
            if (fixes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('For your gym', style: TextStyle(fontWeight: FontWeight.w600)),
              for (var i = 0; i < fixes.length; i++)
                fixes[i].to == null
                    ? Dim('${fixes[i].from.name} ${fixes[i].why}; no swap found. Change it in Plan after.', size: 12)
                    : SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: swap.contains(i),
                        onChanged: (v) => set(() => v ? swap.add(i) : swap.remove(i)),
                        title: Text('Swap ${fixes[i].from.name} for ${fixes[i].to!.name}'),
                        subtitle: Dim('${fixes[i].from.name} ${fixes[i].why}.', size: 12),
                      ),
            ],
            // the plan's own progression rules: one heading, each line in plain words, one choice
            // (review 5, P2-1, P2-2); the sender's comments were taken out when it was read
            if (r.scripts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('This plan has its own progression rule${r.scripts.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Dim('They decide when the weight goes up or down. Left out, these lifts use the usual rule.', size: 12),
              for (final e in r.scripts.entries) ...[
                const SizedBox(height: 6),
                Text(s.lib.byId(e.key.split('#').first)?.name ?? e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                for (final (w, big) in scriptWords(e.value))
                  Text(w, key: big ? const Key('bigRule') : null, style: TextStyle(fontSize: 13, color: big ? C.gold : C.text, fontWeight: big ? FontWeight.w600 : FontWeight.w400)),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  color: C.card2,
                  child: Text(e.value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: C.dim)),
                ),
              ],
              const SizedBox(height: 6),
              Pills<bool>(
                values: const [false, true],
                label: (v) => v ? 'Use these rules' : 'Leave them out',
                selected: {useScripts},
                onTap: (v) => set(() => useScripts = v),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(key: const Key('receiveSave'), onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save as a new plan')),
            const SizedBox(height: 6),
            // not over a workout that is going (review 5, P3-N34): saved, used later from Plan
            if (s.session == null) OutlinedButton(key: const Key('receiveUse'), onPressed: () => Navigator.pop(c, 'use'), child: const Text('Save it and use it now'))
            else const Dim('A workout is going: the plan is saved, and you can use it from Plan after.', size: 12),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ]),
        ),
      ),
    ),
  );
  if (how == null) return false;
  var p = applyFixes(plan, [for (final i in swap) fixes[i]]);
  if (useScripts) p = withScripts(p, r.scripts);
  if (how == 'use') {
    await s.usePlan(p);
  } else {
    await s.repo.savePlan(p, makeActive: false);
    await s.reload();
  }
  if (context.mounted) toast(context, how == 'use' ? 'Now using ${p.name}.' : 'Saved ${p.name} with your plans.');
  return true;
}
