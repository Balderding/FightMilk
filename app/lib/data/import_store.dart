import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/exercise.dart';
import '../domain/import.dart';
import '../domain/plan.dart';
import 'backup.dart';
import 'repo.dart';

/// Saving an import (batch 21, F333): only ever adds. Each import is listed in kv 'imports' with
/// the ids it added, so it can be undone whole. Workouts already on the phone (one that started
/// within 2 minutes) are left out unless the person asks.

const _uuid = Uuid();

class ImportRecord {
  final String id, label;
  final DateTime at;
  final List<String> sessions, body;
  final List<String> exercises; // lifts it touched, for the progression rebuild on undo
  /// The touched lifts' saved state (weights, training max, stage) from before the import, as
  /// stored (null: the lift had none), so Undo puts them back (review 6 P2-1, self7 P1-2).
  final Map<String, String?> lifts;
  final DateTime? from, to; // the dates of the workouts and weigh-ins it brought in (N43)
  const ImportRecord(this.id, this.label, this.at, this.sessions, this.body, this.exercises, {this.lifts = const {}, this.from, this.to});
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'at': at.millisecondsSinceEpoch, 's': sessions, 'b': body, 'e': exercises, 'l': lifts, if (from != null) 'f': from!.millisecondsSinceEpoch, if (to != null) 't': to!.millisecondsSinceEpoch};
  factory ImportRecord.fromJson(Map<String, dynamic> j) => ImportRecord(j['id'] as String, j['label'] as String, DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      [for (final x in j['s'] as List) x as String], [for (final x in j['b'] as List) x as String], [for (final x in (j['e'] ?? const []) as List) x as String],
      lifts: {for (final e in ((j['l'] ?? const {}) as Map).entries) e.key as String: e.value as String?},
      from: j['f'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['f'] as int),
      to: j['t'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['t'] as int));
}

Future<List<ImportRecord>> importRecords(Repo r) async {
  try {
    final v = await r.kvGet('imports');
    return v == null ? [] : [for (final x in jsonDecode(v) as List) ImportRecord.fromJson((x as Map).cast<String, dynamic>())];
  } catch (_) {
    return [];
  }
}

/// Workouts in [read] that are already on the phone: a workout that started within 2 minutes
/// (the set count can differ when some exercises were left out).
Future<Set<int>> duplicates(Repo r, ImportRead read) async {
  final have = [for (final x in await r.db.rawQuery('SELECT started FROM session WHERE finished IS NOT NULL')) x['started'] as int];
  final out = <int>{};
  for (var i = 0; i < read.workouts.length; i++) {
    final t = read.workouts[i].start.millisecondsSinceEpoch;
    if (have.any((h) => (h - t).abs() <= 120000)) out.add(i);
  }
  return out;
}

/// Weigh-ins in [read] already on the phone, or twice in the file: within 10 minutes of another
/// (review 6 P2-2, self7 P2-5).
Future<Set<int>> bodyDuplicates(Repo r, ImportRead read) async {
  final have = [for (final x in await r.db.rawQuery('SELECT at FROM body WHERE kg IS NOT NULL')) x['at'] as int];
  final out = <int>{};
  for (var i = 0; i < read.body.length; i++) {
    final t = read.body[i].$1.millisecondsSinceEpoch;
    if (have.any((h) => (h - t).abs() <= 600000)) {
      out.add(i);
    } else {
      have.add(t); // a second one in the same file is a duplicate too
    }
  }
  return out;
}

/// Saves the workouts (and weigh-ins) of [read]. [names]: the file's exercise name -> our id, or
/// null to leave that exercise out. [skip]: workout indexes to leave out (duplicates).
/// Returns the record, so it can be undone.
Future<ImportRecord> saveImport(Repo r, ImportRead read, Map<String, String?> names, {Set<int> skip = const {}, Set<int> skipBody = const {}, required String label}) async {
  final id = _uuid.v4();
  final sessions = <String>[], body = <String>[];
  final touched = <String>{};
  // the lifts' states now, to put back on Undo
  final lifts = <String, String?>{};
  for (final ex in {for (final v in names.values) if (v != null) v}) {
    final row = await r.db.query('lift_state', where: 'exercise_id = ?', whereArgs: [ex]);
    lifts[ex] = row.isEmpty ? null : row.first['json'] as String;
  }
  await r.db.transaction((tx) async {
    for (var i = 0; i < read.workouts.length; i++) {
      if (skip.contains(i)) continue;
      final w = read.workouts[i];
      final sets = [for (final s in w.sets) if (names[s.exercise] != null) s];
      if (sets.isEmpty) continue;
      // the day as a plan day, so History shows it like any workout
      final items = <PlanItem>[];
      for (final s in sets) {
        final ex = names[s.exercise]!;
        if (items.any((x) => x.exerciseId == ex)) continue;
        final mine = [for (final x in sets) if (names[x.exercise] == ex && x.type != SetType.warmup) x.reps];
        final lo = mine.isEmpty ? 1 : mine.reduce((a, b) => a < b ? a : b), hi = mine.isEmpty ? 1 : mine.reduce((a, b) => a > b ? a : b);
        items.add(PlanItem(exerciseId: ex, sets: mine.isEmpty ? 1 : mine.length.clamp(1, 20), repLow: lo.clamp(1, 600), repHigh: hi.clamp(1, 600), restSec: 120));
      }
      final sid = _uuid.v4();
      final end = w.end != null && w.end!.isAfter(w.start) ? w.end! : w.start.add(Duration(minutes: (sets.length * 2).clamp(5, 240)));
      await tx.insert('session', {
        'id': sid,
        'plan_id': 'import:$id',
        'day_index': 0,
        'day': jsonEncode(PlanDay(name: w.name, items: items).toJson()),
        'started': w.start.millisecondsSinceEpoch,
        'finished': end.millisecondsSinceEpoch,
        'note': 'Imported',
      });
      for (var k = 0; k < sets.length; k++) {
        final s = sets[k];
        final ex = names[s.exercise]!;
        touched.add(ex);
        await tx.insert('set_log', {
          'id': _uuid.v4(),
          'session_id': sid,
          'exercise_id': ex,
          'kg': s.kg,
          'reps': s.reps,
          'ord': k,
          'at': w.start.millisecondsSinceEpoch + k * 60000 ~/ 2,
          'type': s.type.name,
          'rpe': s.rpe,
          'note': s.note,
          'side': '',
          'secs': s.secs,
          'meters': s.meters,
        });
      }
      sessions.add(sid);
    }
    for (var i = 0; i < read.body.length; i++) {
      if (skipBody.contains(i)) continue;
      final b = read.body[i];
      final bid = _uuid.v4();
      await tx.insert('body', {'id': bid, 'at': b.$1.millisecondsSinceEpoch, 'kg': b.$2, 'fat': b.$3});
      body.add(bid);
    }
    final rec = ImportRecord(id, label, DateTime.now(), sessions, body, touched.toList(), lifts: {for (final e in touched) e: lifts[e]}, from: _span(read).$1, to: _span(read).$2);
    final old = await tx.query('kv', where: 'k = ?', whereArgs: ['imports']);
    List list;
    try {
      list = old.isEmpty ? [] : jsonDecode(old.first['v'] as String) as List;
    } catch (_) {
      list = [];
    }
    await tx.insert('kv', {'k': 'imports', 'v': jsonEncode([...list, rec.toJson()])}, conflictAlgorithm: ConflictAlgorithm.replace);
  });
  return ImportRecord(id, label, DateTime.now(), sessions, body, touched.toList(), lifts: {for (final e in touched) e: lifts[e]}, from: _span(read).$1, to: _span(read).$2);
}

(DateTime?, DateTime?) _span(ImportRead r) {
  final all = [for (final w in r.workouts) w.start, for (final b in r.body) b.$1]..sort();
  return all.isEmpty ? (null, null) : (all.first, all.last);
}

/// Takes one import out again: its workouts, sets and weigh-ins, and puts each touched lift's
/// state back as it was before (review 6 P2-1, self7 P1-2), unless it was trained in the app
/// since the import. Returns the lifts that still need their weights worked out from history.
Future<List<String>> undoImport(Repo r, String id) async {
  final recs = await importRecords(r);
  final rec = recs.where((x) => x.id == id).firstOrNull;
  if (rec == null) return const [];
  await r.db.transaction((tx) async {
    for (final s in rec.sessions) {
      await tx.delete('set_log', where: 'session_id = ?', whereArgs: [s]);
      await tx.delete('session', where: 'id = ?', whereArgs: [s]);
    }
    for (final b in rec.body) {
      await tx.delete('body', where: 'id = ?', whereArgs: [b]);
    }
    await tx.insert('kv', {'k': 'imports', 'v': jsonEncode([for (final x in recs) if (x.id != id) x.toJson()])}, conflictAlgorithm: ConflictAlgorithm.replace);
    await noteUndone(tx, rec.sessions, rec.body); // a later merge never brings them back (review 7, P2-3)
  });
  final rebuild = <String>[];
  for (final ex in rec.exercises) {
    if (!rec.lifts.containsKey(ex)) {
      rebuild.add(ex); // an import made before the states were kept
      continue;
    }
    final later = Sqflite.firstIntValue(await r.db.rawQuery(
            'SELECT COUNT(*) FROM session w JOIN set_log s ON s.session_id = w.id WHERE s.exercise_id = ? AND w.finished IS NOT NULL AND w.finished > ?', [ex, rec.at.millisecondsSinceEpoch])) ??
        0;
    if (later > 0) {
      rebuild.add(ex); // trained since: worked out from the history that is left
      continue;
    }
    await r.db.delete('lift_state', where: 'exercise_id = ?', whereArgs: [ex]);
    final before = rec.lifts[ex];
    if (before != null) await r.db.insert('lift_state', {'exercise_id': ex, 'json': before});
  }
  return rebuild;
}
