import 'package:flutter/material.dart';

import '../domain/body.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'body_screen.dart';
import 'history_screen.dart';
import 'log_screen.dart';
import 'widgets.dart';

/// Where an app shortcut (long-press the icon, F352) or the Quick Settings tile (F353) leads.
/// Each one only opens a screen: nothing is started or saved until the person taps it there
/// (other apps could send the same intent; D15 is the owner's to decide before anything writes).
const shortcutPlaces = {'today', 'weight', 'last'};

/// A fightmilk:// link that only opens a screen (F354; also from an NFC sticker, F356):
/// `fightmilk://start` (or `today`), `fightmilk://last`, `fightmilk://weight`, with
/// `?kg=80` or `?lb=176` to fill the number in. Null: not one of these (it opens nothing).
/// [kg] is null when there is no number, or when the one in the link is not a body weight
/// ([odd] then says so).
({String go, double? kg, bool odd})? readLink(String link) {
  if (link.length > 200) return null;
  final u = Uri.tryParse(link.trim());
  if (u == null || u.scheme.toLowerCase() != 'fightmilk') return null;
  final host = u.host.toLowerCase();
  final go = switch (host) { 'start' || 'today' => 'today', 'weight' => 'weight', 'last' => 'last', _ => null };
  if (go == null) return null;
  if (go != 'weight') return (go: go, kg: null, odd: false);
  final q = u.queryParameters;
  final raw = q['kg'] ?? q['lb'];
  if (raw == null) return (go: go, kg: null, odd: false);
  final n = double.tryParse(raw.replaceAll(',', '.'));
  final kg = n == null ? null : (q.containsKey('kg') ? n : fromUnit(n, Unit.lb));
  return kg != null && kg.isFinite && validBodyKg(kg) ? (go: go, kg: kg, odd: false) : (go: go, kg: null, odd: true);
}

/// Opens [go]; [tab] moves the bottom bar (0 Today, 2 History). Unknown places open nothing.
/// From a link, [kg] fills the weigh-in in (never saved without the person's tap).
Future<void> openShortcut(BuildContext context, AppState s, String go, void Function(int) tab, {double? kg, bool fromLink = false, bool odd = false}) async {
  switch (go) {
    case 'today':
      tab(0);
      // a workout in progress opens where it was left
      if (s.session != null) await Navigator.push(context, MaterialPageRoute(builder: (_) => LogScreen(s: s)));
    case 'weight':
      tab(0);
      // the person sees the weigh-in and taps Save
      await showWeighIn(context, s,
          prefillKg: kg,
          note: !fromLink
              ? null
              : odd
                  ? 'The number in the link did not look like a body weight, so it was left out.'
                  : kg == null
                      ? null
                      : 'Filled in from a link. Check it, then tap Save.');
    case 'last':
      final h = await s.repo.history(limit: 1);
      if (!context.mounted) return;
      if (h.isEmpty) return toast(context, 'No workout yet.');
      tab(2);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetail(s: s, session: h.first)));
  }
}
