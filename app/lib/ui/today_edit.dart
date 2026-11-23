import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/plan.dart' show liftKey;
import 'app_state.dart';
import 'pickers.dart' show ExercisePicker;
import 'theme.dart';
import 'widgets.dart';

/// Today only, or the plan too? Null: backed out.
Future<bool?> askTodayOrPlan(BuildContext context, {required String title, required String plan}) => showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            FilledButton(key: const Key('todayOnly'), onPressed: () => Navigator.pop(c, false), child: const Text('Today only')),
            const SizedBox(height: 8),
            OutlinedButton(key: const Key('planToo'), onPressed: () => Navigator.pop(c, true), child: Text(plan)),
          ]),
        ),
      ),
    );

/// Removes exercise [i] of today (or of the workout in progress), asking "today only or the plan
/// too", saying first when logged sets go with it, and offering Undo. Returns true when removed.
Future<bool> removeTodayItem(BuildContext context, AppState s, int i) async {
  final d = s.today!;
  final it = d.items[i];
  final name = s.lib.byId(it.exerciseId)?.name ?? it.exerciseId;
  if (s.session != null && d.items.length < 2) {
    toast(context, 'A workout needs one exercise. Finish it, or throw it away, instead.');
    return false;
  }
  final logged = s.session == null ? 0 : (await s.repo.setsFor(s.session!.id)).where((x) => x.exerciseId == it.exerciseId && (x.slot == null || x.slot == liftKey(it))).length;
  if (!context.mounted) return false;
  if (logged > 0 && !await confirm(context, 'Remove $name?', 'Its $logged logged set${logged == 1 ? '' : 's'} from this workout ${logged == 1 ? 'is' : 'are'} deleted too. You can undo it right after.', yes: 'Remove')) return false;
  if (!context.mounted) return false;
  final plan = await askTodayOrPlan(context, title: 'Remove $name', plan: 'Remove from my plan too');
  if (plan == null) return false;
  final r = await s.removeFromToday(i, forever: plan);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(plan ? '$name removed from today and your plan.' : '$name removed for today.'), action: SnackBarAction(label: 'Undo', onPressed: () => s.undoRemoveToday(r))));
  }
  return true;
}

/// Picks an exercise and adds it to today (or the workout in progress), today only or the plan
/// too. Returns the exercise added, or null.
Future<Exercise?> addTodayItem(BuildContext context, AppState s) async {
  final e = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => ExercisePicker(s: s, exclude: {for (final it in s.today!.items) it.exerciseId})));
  if (e == null || !context.mounted) return null;
  final plan = await askTodayOrPlan(context, title: 'Add ${e.name}', plan: 'Add to my plan too');
  if (plan == null) return null;
  await s.addToToday(e, forever: plan);
  if (context.mounted) toast(context, plan ? '${e.name} added to today and your plan.' : '${e.name} added for today.');
  return e;
}
