import 'library.dart';
import 'plan.dart';

/// Supersets and circuits: plan items with the same group number are done together, one set of
/// each in turn, with the full rest only after the round.

int _free(List<PlanItem> l) {
  var g = 1;
  while (l.any((x) => x.group == g)) {
    g++;
  }
  return g;
}

/// Item [i] and the one after it go together (joining a group the next one is already in).
List<PlanItem> supersetWithNext(List<PlanItem> items, int i) {
  if (i < 0 || i + 1 >= items.length) return items;
  final l = [...items];
  final g = l[i].group ?? l[i + 1].group ?? _free(l);
  l[i] = l[i].copyWith(group: g);
  l[i + 1] = l[i + 1].copyWith(group: g);
  return l;
}

/// Take item [i] out of its group; a group left with one exercise is no group at all.
List<PlanItem> ungroup(List<PlanItem> items, int i) {
  if (i < 0 || i >= items.length || items[i].group == null) return items;
  final g = items[i].group;
  final l = [...items];
  l[i] = l[i].copyWith(clearGroup: true);
  final left = [for (var k = 0; k < l.length; k++) if (l[k].group == g) k];
  if (left.length == 1) l[left.first] = l[left.first].copyWith(clearGroup: true);
  return l;
}

/// Pair opposite muscles among the accessories to save time (the first, main lift stays alone).
/// Partners are moved next to each other.
List<PlanItem> autoSupersets(List<PlanItem> items, Library lib) {
  if (items.length < 3) return items;
  const pairs = [
    ({'chest'}, {'back', 'lats'}),
    ({'biceps'}, {'triceps'}),
    ({'quads'}, {'hamstrings'}),
    ({'shoulders'}, {'back', 'lats', 'rear_delts'}),
    ({'glutes'}, {'core'}),
    ({'calves'}, {'core'}),
  ];
  String m(PlanItem it) => lib.byId(it.exerciseId)?.primary.first ?? '';
  final rest = [for (final it in items.skip(1)) it.copyWith(clearGroup: true)];
  final out = <PlanItem>[items.first.copyWith(clearGroup: true)];
  var g = 1;
  while (rest.isNotEmpty) {
    final a = rest.removeAt(0);
    var j = rest.indexWhere((b) => pairs.any((p) => (p.$1.contains(m(a)) && p.$2.contains(m(b))) || (p.$2.contains(m(a)) && p.$1.contains(m(b)))));
    if (j < 0 && rest.isNotEmpty && m(rest.first) != m(a)) j = 0; // any two different muscles
    if (j < 0) {
      out.add(a);
      continue;
    }
    final b = rest.removeAt(j);
    out.add(a.copyWith(group: g));
    out.add(b.copyWith(group: g));
    g++;
  }
  return out;
}

/// After a set of item [cur]: the next exercise of the round (index), or null when the round is
/// done (or [cur] is in no group). [done] = sets that count, per exercise id.
int? nextInRound(List<PlanItem> items, int cur, Map<String, int> done) {
  final g = items[cur].group;
  if (g == null) return null;
  final members = [for (var k = 0; k < items.length; k++) if (items[k].group == g) k];
  final pos = members.indexOf(cur);
  // the rest of this round: members after cur that still have sets left
  for (final k in members.skip(pos + 1)) {
    if ((done[items[k].exerciseId] ?? 0) < items[k].sets) return k;
  }
  return null;
}

/// After the round: the first member that still has sets (start of the next round), or null.
int? roundStart(List<PlanItem> items, int cur, Map<String, int> done) {
  final g = items[cur].group;
  if (g == null) return null;
  for (var k = 0; k < items.length; k++) {
    if (items[k].group == g && (done[items[k].exerciseId] ?? 0) < items[k].sets) return k;
  }
  return null;
}

/// "A1", "A2", "B1"... for display; '' when not grouped.
String groupLabel(List<PlanItem> items, int i) {
  final g = items[i].group;
  if (g == null) return '';
  final groups = <int>[];
  for (final it in items) {
    if (it.group != null && !groups.contains(it.group)) groups.add(it.group!);
  }
  final letter = String.fromCharCode(65 + groups.indexOf(g).clamp(0, 25));
  final n = [for (var k = 0; k <= i; k++) if (items[k].group == g) k].length;
  return '$letter$n';
}
