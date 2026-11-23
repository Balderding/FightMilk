import 'dart:convert';

import '../domain/exercise.dart';
import '../domain/library.dart';
import '../domain/units.dart';
import 'repo.dart';

/// Every logged set as a CSV in the column layout Strong uses, which Hevy, Liftosaur and most
/// spreadsheets can import. Weights are in the user's unit. Nothing is sent anywhere: the user
/// saves the file where they like.
const csvHeader = ['Date', 'Workout Name', 'Duration', 'Exercise Name', 'Set Order', 'Weight', 'Reps', 'Distance', 'Seconds', 'Notes', 'Workout Notes', 'RPE'];

Future<String> exportCsv(Repo r, Library lib, Unit unit) async {
  final rows = <List<String>>[csvHeader];
  for (final s in await r.db.query('session', orderBy: 'started')) {
    final sets = await r.db.query('set_log', where: 'session_id = ?', whereArgs: [s['id']], orderBy: 'ord, at');
    if (sets.isEmpty) continue;
    final started = DateTime.fromMillisecondsSinceEpoch(s['started'] as int);
    final end = s['finished'] as int? ?? sets.last['at'] as int;
    String name;
    try {
      name = (jsonDecode(s['day'] as String) as Map)['name'] as String;
    } catch (_) {
      name = 'Workout';
    }
    final order = <String, int>{};
    for (final row in sets) {
      final x = SetLog.fromJson(row);
      final id = x.exerciseId;
      final e = lib.byId(id);
      // Strong marks warm-up, drop and failure sets with W / D / F instead of a number
      final mark = switch (x.type) { SetType.warmup => 'W', SetType.drop => 'D', SetType.failure => 'F', _ => null };
      if (mark == null) order[id] = (order[id] ?? 0) + 1;
      final secs = x.secs ?? (e?.timed == true ? x.reps : 0);
      final rpe = x.rpeOrEffort;
      rows.add([
        csvDate(started),
        name,
        csvDuration(Duration(milliseconds: end - (s['started'] as int))),
        e?.name ?? id,
        mark ?? '${order[id]}',
        csvNum(toUnit(x.kg, unit)),
        e?.timed == true ? '0' : '${x.reps}',
        csvNum(x.meters ?? 0),
        '$secs',
        [if (x.side.isNotEmpty) x.side == 'L' ? 'left' : 'right', if (x.type == SetType.amrap) 'AMRAP', if (x.type == SetType.restpause) 'rest-pause', if (x.note.isNotEmpty) x.note].join('; '),
        s['note'] as String? ?? '',
        rpe == null ? '' : csvNum(rpe),
      ]);
    }
  }
  return rows.map((r) => r.map(csvField).join(',')).join('\r\n') + '\r\n';
}

String csvDate(DateTime d) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
}

/// "1h 5m" / "45m", as Strong writes it.
String csvDuration(Duration d) {
  final m = d.inMinutes;
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}

/// 102.5, 100 (no trailing .0), at most 2 decimals.
String csvNum(double v) {
  final r = (v * 100).round() / 100;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

/// A CSV cell. Text that a spreadsheet would run as a formula (= + - @, tab, CR, LF or the
/// full-width ＝＋－＠ first) gets a ' in front, as OWASP advises; plain numbers like -2.5 stay
/// numbers (review 5, P2-4).
String csvField(String s) {
  final l = s.trimLeft();
  final risky = (s.isNotEmpty && '\t\r\n'.contains(s[0])) || (l.isNotEmpty && '=+-@＝＋－＠'.contains(l[0]) && !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(l));
  final v = risky ? "'$s" : s;
  return '"${v.replaceAll('"', '""')}"';
}
