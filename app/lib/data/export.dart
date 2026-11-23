import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseFactory, databaseFactory;

import '../domain/exercise.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/stats.dart';
import '../domain/units.dart';
import 'backup.dart';
import 'csv_export.dart';
import 'pdf.dart';
import 'xlsx.dart';
import 'repo.dart';

/// Every way data leaves the app as a file (batch 20, F310-F320). Nothing here sends anything:
/// the person saves the file or hands it to an app through the share menu.
///
/// The hard rule (review 4): **no progress photo, photo file, photo path or photo list ever goes
/// into any export, share or backup.** Photos live in their own folder and in the kv row
/// 'photos'; no code here reads either, and the SQLite copy deletes the row before it is handed
/// out. `export_test` scans every format for them.
///
/// Body data (weigh-ins, body fat, tape, height) goes in only when the person said yes
/// ([ExportOptions.body]); the screen asks once, in plain words, when a format holds any.

enum ExportKind {
  strong, // F310 Strong's CSV (Hevy, Liftosaur and spreadsheets read it)
  hevy, // F311
  fitnotes, // F311
  liftosaur, // F311
  everything, // F312 one row per set, every column
  bodyCsv, // F314 weigh-ins, body fat, tape
  plansCsv, // F314
  recordsCsv, // F314
  text, // F315 plain text / Markdown
  tcx, // F318 Garmin / Strava upload by hand
  sqlite, // F319 the database as it is (photo list removed)
  backup, // the app's own JSON backup
  xlsx, // F316 one Excel file: workouts, sets, body, records, plans
  pdf, // F317 a report for the dates: totals, lifts, body weight, workouts
  all, // a zip of every CSV plus the format notes
}

const exportLabel = {
  ExportKind.strong: 'Sets: Strong CSV',
  ExportKind.hevy: 'Sets: Hevy CSV',
  ExportKind.fitnotes: 'Sets: FitNotes CSV',
  ExportKind.liftosaur: 'Sets: Liftosaur CSV',
  ExportKind.everything: 'Sets: every column (CSV)',
  ExportKind.bodyCsv: 'Body: weigh-ins and tape (CSV)',
  ExportKind.plansCsv: 'Plans (CSV)',
  ExportKind.recordsCsv: 'Records (CSV)',
  ExportKind.text: 'Workouts as text (Markdown)',
  ExportKind.tcx: 'Workouts for Garmin or Strava (.tcx)',
  ExportKind.sqlite: 'The database (SQLite)',
  ExportKind.backup: 'Backup (FightMilk JSON)',
  ExportKind.xlsx: 'Spreadsheet (Excel .xlsx)',
  ExportKind.pdf: 'Report (PDF)',
  ExportKind.all: 'Everything (zip of CSVs)',
};

/// Kinds that can hold body data, so the screen asks first.
const bodyKinds = {ExportKind.bodyCsv, ExportKind.sqlite, ExportKind.backup, ExportKind.xlsx, ExportKind.pdf, ExportKind.all};

/// Kinds that take a date range (the others are whole files).
const datedKinds = {
  ExportKind.strong, ExportKind.hevy, ExportKind.fitnotes, ExportKind.liftosaur, ExportKind.everything, ExportKind.bodyCsv, ExportKind.text, ExportKind.tcx, ExportKind.xlsx, ExportKind.pdf, ExportKind.all, //
};

class ExportOptions {
  final Unit unit;
  final DateTime? from, to; // to is inclusive (the whole day)
  final bool body; // weigh-ins, body fat, tape, height
  const ExportOptions({required this.unit, this.from, this.to, this.body = false});

  bool inRange(DateTime d) => (from == null || !d.isBefore(DateTime(from!.year, from!.month, from!.day))) && (to == null || d.isBefore(DateTime(to!.year, to!.month, to!.day + 1)));
}

class ExportFile {
  final String name;
  final String mime;
  final Uint8List bytes;
  const ExportFile(this.name, this.mime, this.bytes);
}

String _stamp(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
String _csv(List<List<String>> rows) => rows.map((r) => r.map(csvField).join(',')).join('\r\n') + '\r\n';

/// One finished workout with its sets, oldest first.
class _Workout {
  final String id, name, note;
  final DateTime start, end;
  final List<SetLog> sets;
  _Workout(this.id, this.name, this.note, this.start, this.end, this.sets);
}

Future<List<_Workout>> _workouts(Repo r, ExportOptions o) async {
  final out = <_Workout>[];
  for (final s in await r.db.query('session', where: 'finished IS NOT NULL', orderBy: 'started')) {
    final start = DateTime.fromMillisecondsSinceEpoch(s['started'] as int);
    if (!o.inRange(start)) continue;
    final sets = [for (final x in await r.db.query('set_log', where: 'session_id = ?', whereArgs: [s['id']], orderBy: 'ord, at')) SetLog.fromJson(x)];
    if (sets.isEmpty) continue;
    String name;
    try {
      name = (jsonDecode(s['day'] as String) as Map)['name'] as String;
    } catch (_) {
      name = 'Workout';
    }
    out.add(_Workout(s['id'] as String, name, s['note'] as String? ?? '', start, DateTime.fromMillisecondsSinceEpoch(s['finished'] as int), sets));
  }
  return out;
}

String _iso(DateTime d) => d.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

/// Builds one export. [lib] names the exercises; [tape] is the app's tape list (only used with
/// [ExportOptions.body]).
Future<ExportFile> buildExport(ExportKind k, Repo r, Library lib, ExportOptions o, {List<Map<String, dynamic>> tape = const [], DatabaseFactory? factory}) async {
  final day = _stamp(DateTime.now());
  final u = o.unit;
  switch (k) {
    case ExportKind.strong:
      return ExportFile('fightmilk-strong-${u.name}-$day.csv', 'text/csv', _utf8(await _strong(r, lib, o)));
    case ExportKind.hevy:
      return ExportFile('fightmilk-hevy-$day.csv', 'text/csv', _utf8(await _hevy(r, lib, o)));
    case ExportKind.fitnotes:
      return ExportFile('fightmilk-fitnotes-$day.csv', 'text/csv', _utf8(await _fitnotes(r, lib, o)));
    case ExportKind.liftosaur:
      return ExportFile('fightmilk-liftosaur-$day.csv', 'text/csv', _utf8(await _liftosaur(r, lib, o)));
    case ExportKind.everything:
      return ExportFile('fightmilk-sets-all-columns-$day.csv', 'text/csv', _utf8(_csv(await _everythingRows(r, lib, o))));
    case ExportKind.bodyCsv:
      return ExportFile('fightmilk-body-$day.csv', 'text/csv', _utf8(_csv(await _bodyRows(r, o, tape))));
    case ExportKind.plansCsv:
      return ExportFile('fightmilk-plans-$day.csv', 'text/csv', _utf8(_csv(await _plansRows(r, lib))));
    case ExportKind.recordsCsv:
      return ExportFile('fightmilk-records-${u.name}-$day.csv', 'text/csv', _utf8(_csv(await _recordsRows(r, lib, u))));
    case ExportKind.xlsx:
      return ExportFile('fightmilk-$day.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', xlsx({
        'Workouts': await _workoutRows(r, lib, o),
        'Sets': await _everythingRows(r, lib, o),
        if (o.body) 'Body': await _bodyRows(r, o, tape),
        'Records': await _recordsRows(r, lib, u),
        'Plans': await _plansRows(r, lib),
      }));
    case ExportKind.pdf:
      return ExportFile('fightmilk-report-$day.pdf', 'application/pdf', await reportPdf(r, lib, o, tape: tape));
    case ExportKind.text:
      return ExportFile('fightmilk-workouts-$day.md', 'text/markdown', _utf8(await workoutsText(r, lib, o)));
    case ExportKind.tcx:
      return ExportFile('fightmilk-workouts-$day.tcx', 'application/vnd.garmin.tcx+xml', _utf8(await _tcx(r, lib, o)));
    case ExportKind.sqlite:
      return ExportFile('fightmilk-$day.sqlite', 'application/vnd.sqlite3', await _sqlite(r, o, factory ?? databaseFactory));
    case ExportKind.backup:
      return ExportFile('workout-backup-$day.json', 'application/json', _utf8(await exportBackup(r, body: o.body)));
    case ExportKind.all:
      final a = Archive();
      for (final x in [ExportKind.strong, ExportKind.everything, ExportKind.plansCsv, ExportKind.recordsCsv, if (o.body) ExportKind.bodyCsv]) {
        final f = await buildExport(x, r, lib, o, tape: tape);
        a.addFile(ArchiveFile(f.name, f.bytes.length, f.bytes));
      }
      final notes = _utf8(formatNotes);
      a.addFile(ArchiveFile('README.txt', notes.length, notes));
      return ExportFile('fightmilk-export-$day.zip', 'application/zip', Uint8List.fromList(ZipEncoder().encode(a)));
  }
}

// ---------- sets ----------

Future<String> _strong(Repo r, Library lib, ExportOptions o) async {
  if (o.from == null && o.to == null) return exportCsv(r, lib, o.unit); // F310: the full Strong file
  final rows = <List<String>>[csvHeader];
  for (final w in await _workouts(r, o)) {
    final order = <String, int>{};
    for (final x in w.sets) {
      final e = lib.byId(x.exerciseId);
      final mark = switch (x.type) { SetType.warmup => 'W', SetType.drop => 'D', SetType.failure => 'F', _ => null };
      if (mark == null) order[x.exerciseId] = (order[x.exerciseId] ?? 0) + 1;
      final rpe = x.rpeOrEffort;
      rows.add([
        csvDate(w.start), w.name, csvDuration(w.end.difference(w.start)), e?.name ?? x.exerciseId, mark ?? '${order[x.exerciseId]}', //
        csvNum(toUnit(x.kg, o.unit)), e?.timed == true ? '0' : '${x.reps}', csvNum(x.meters ?? 0), '${x.secs ?? (e?.timed == true ? x.reps : 0)}',
        [if (x.side.isNotEmpty) x.side == 'L' ? 'left' : 'right', if (x.note.isNotEmpty) x.note].join('; '), w.note, rpe == null ? '' : csvNum(rpe),
      ]);
    }
  }
  return _csv(rows);
}

/// Hevy's own export columns (its importer reads the same).
Future<String> _hevy(Repo r, Library lib, ExportOptions o) async {
  final lb = o.unit == Unit.lb;
  final rows = <List<String>>[
    ['title', 'start_time', 'end_time', 'description', 'exercise_title', 'superset_id', 'exercise_notes', 'set_index', 'set_type', lb ? 'weight_lbs' : 'weight_kg', 'reps', 'distance_km', 'duration_seconds', 'rpe'],
  ];
  for (final w in await _workouts(r, o)) {
    final idx = <String, int>{};
    for (final x in w.sets) {
      final e = lib.byId(x.exerciseId);
      final i = idx[x.exerciseId] = (idx[x.exerciseId] ?? -1) + 1;
      final type = switch (x.type) { SetType.warmup => 'warmup', SetType.drop => 'dropset', SetType.failure => 'failure', _ => 'normal' };
      rows.add([
        w.name, csvDate(w.start), csvDate(w.end), w.note, e?.name ?? x.exerciseId, '', x.note, '$i', type, //
        csvNum(toUnit(x.kg, o.unit)), e?.timed == true ? '' : '${x.reps}', x.meters == null ? '' : csvNum(x.meters! / 1000), '${x.secs ?? (e?.timed == true ? x.reps : '')}',
        x.rpe == null ? '' : csvNum(x.rpe!),
      ]);
    }
  }
  return _csv(rows);
}

/// FitNotes' CSV columns.
Future<String> _fitnotes(Repo r, Library lib, ExportOptions o) async {
  final rows = <List<String>>[
    ['Date', 'Exercise', 'Category', o.unit == Unit.lb ? 'Weight (lbs)' : 'Weight (kgs)', 'Reps', 'Distance', 'Distance Unit', 'Time', 'Comment'],
  ];
  for (final w in await _workouts(r, o)) {
    for (final x in w.sets) {
      final e = lib.byId(x.exerciseId);
      final secs = x.secs ?? (e?.timed == true ? x.reps : null);
      rows.add([
        _stamp(w.start), e?.name ?? x.exerciseId, e == null || e.primary.isEmpty ? '' : _cat(e.primary.first), csvNum(toUnit(x.kg, o.unit)), e?.timed == true ? '' : '${x.reps}', //
        x.meters == null ? '' : csvNum(x.meters!), x.meters == null ? '' : 'm', secs == null ? '' : _hms(secs), x.note,
      ]);
    }
  }
  return _csv(rows);
}

String _cat(String m) => m.isEmpty ? '' : '${m[0].toUpperCase()}${m.substring(1)}';
String _hms(int s) => '${(s ~/ 3600).toString().padLeft(2, '0')}:${(s % 3600 ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

/// Liftosaur's history CSV columns (best effort; its importer also reads Strong's file).
Future<String> _liftosaur(Repo r, Library lib, ExportOptions o) async {
  final rows = <List<String>>[
    ['Workout DateTime', 'Program', 'Day Name', 'Exercise', 'Equipment', 'Is Warmup Set?', 'Required Reps', 'Completed Reps', 'RPE', 'Completed Weight Value', 'Completed Weight Unit', 'Completed Time'],
  ];
  for (final w in await _workouts(r, o)) {
    for (final x in w.sets) {
      final e = lib.byId(x.exerciseId);
      rows.add([
        _iso(w.start), 'FightMilk', w.name, e?.name ?? x.exerciseId, e == null ? '' : equipmentLabel[e.equipment] ?? '', x.type == SetType.warmup ? '1' : '0', //
        '', '${x.reps}', x.rpe == null ? '' : csvNum(x.rpe!), csvNum(toUnit(x.kg, o.unit)), unitLabel(o.unit), _iso(x.at ?? w.start),
      ]);
    }
  }
  return _csv(rows);
}

/// F312: one row per set with every column the app has (kg and lb both).
Future<List<List<String>>> _everythingRows(Repo r, Library lib, ExportOptions o) async {
  final rows = <List<String>>[
    [
      'set_id', 'workout_id', 'date', 'workout', 'note', 'set_number', 'exercise_id', 'exercise', 'muscles', 'equipment', 'type', 'kg', 'lb', 'reps', 'seconds', 'meters', //
      'side', 'effort', 'rpe', 'rest_seconds', 'e1rm_kg', 'e1rm_lb', 'set_note', 'plan_slot',
    ],
  ];
  for (final w in await _workouts(r, o)) {
    final n = <String, int>{};
    for (final x in w.sets) {
      final e = lib.byId(x.exerciseId);
      final i = n[x.exerciseId] = (n[x.exerciseId] ?? 0) + 1;
      final one = x.reps > 0 && x.kg > 0 && e?.timed != true ? e1rm(x.kg, x.reps) : null;
      rows.add([
        x.id, w.id, csvDate(x.at ?? w.start), w.name, w.note, '$i', x.exerciseId, e?.name ?? '', e == null ? '' : [...e.primary, ...e.secondary].join(' '), //
        e == null ? '' : equipmentLabel[e.equipment] ?? '', x.type.name, csvNum(x.kg), csvNum(kgToLb(x.kg)), '${x.reps}', '${x.secs ?? ''}', x.meters == null ? '' : csvNum(x.meters!),
        x.side, '${x.effort ?? ''}', x.rpe == null ? '' : csvNum(x.rpe!), '${x.rest ?? ''}', one == null ? '' : csvNum(one), one == null ? '' : csvNum(kgToLb(one)), x.note, x.slot ?? '',
      ]);
    }
  }
  return rows;
}

/// One row per workout (the Excel "Workouts" sheet and the PDF table).
Future<List<List<String>>> _workoutRows(Repo r, Library lib, ExportOptions o) async {
  final rows = <List<String>>[
    ['date', 'workout', 'minutes', 'sets', 'volume_${unitLabel(o.unit)}', 'exercises', 'note'],
  ];
  for (final w in await _workouts(r, o)) {
    final work = [for (final x in w.sets) if (x.type != SetType.warmup) x];
    final vol = work.fold<double>(0, (a, x) => a + x.kg * x.reps);
    final names = <String>{for (final x in w.sets) lib.byId(x.exerciseId)?.name ?? x.exerciseId};
    rows.add([csvDate(w.start), w.name, '${w.end.difference(w.start).inMinutes}', '${work.length}', csvNum(toUnit(vol, o.unit).roundToDouble()), names.join(', '), w.note]);
  }
  return rows;
}

// ---------- the PDF report (F317) ----------

/// A report for the dates: totals, the best est. 1-rep max of the main lifts as small charts,
/// body weight (only with [ExportOptions.body]) and a table of the workouts.
Future<Uint8List> reportPdf(Repo r, Library lib, ExportOptions o, {List<Map<String, dynamic>> tape = const []}) async {
  final u = o.unit;
  final doc = PdfDoc('FightMilk report');
  final ws = await _workouts(r, o);
  var pg = doc.page();
  var y = 50.0;
  final range = o.from == null && o.to == null ? 'All time' : '${o.from == null ? 'start' : _stamp(o.from!)} to ${o.to == null ? 'today' : _stamp(o.to!)}';
  pg.text(40, y, 'FightMilk report', size: 20, bold: true);
  y += 18;
  pg.text(40, y, '$range  -  made ${_stamp(DateTime.now())}', size: 10, gray: 0.35);
  y += 26;
  final work = [for (final w in ws) for (final x in w.sets) if (x.type != SetType.warmup) x];
  final vol = work.fold<double>(0, (a, x) => a + x.kg * x.reps);
  final mins = ws.fold<int>(0, (a, w) => a + w.end.difference(w.start).inMinutes);
  for (final (k, v) in [('Workouts', '${ws.length}'), ('Sets', '${work.length}'), ('Volume', '${fmtNum(toUnit(vol, u).roundToDouble())} ${unitLabel(u)}'), ('Time', '${mins ~/ 60} h ${mins % 60} min')]) {
    pg.box(40 + [('Workouts'), ('Sets'), ('Volume'), ('Time')].indexOf(k) * 130.0, y, 120, 44, fill: 0.95, gray: 0.8);
    final x0 = 48 + [('Workouts'), ('Sets'), ('Volume'), ('Time')].indexOf(k) * 130.0;
    pg.text(x0, y + 16, k, size: 9, gray: 0.35);
    pg.text(x0, y + 34, v, size: 14, bold: true);
  }
  y += 66;

  // main lifts: best est. 1-rep max per workout, as small charts
  final lifts = <String, List<(DateTime, double)>>{};
  for (final w in ws) {
    for (final x in w.sets) {
      final e = lib.byId(x.exerciseId);
      if (e == null || e.timed || e.bodyweight || x.reps < 1 || x.reps > 12 || x.kg <= 0 || x.type == SetType.warmup) continue;
      final v = e1rm(x.kg, x.reps);
      final l = lifts.putIfAbsent(x.exerciseId, () => []);
      if (l.isNotEmpty && l.last.$1 == w.start) {
        if (v > l.last.$2) l[l.length - 1] = (w.start, v);
      } else {
        l.add((w.start, v));
      }
    }
  }
  final top = (lifts.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length))).take(4).toList();
  if (top.isNotEmpty) {
    pg.text(40, y, 'Est. 1-rep max (best per workout)', size: 12, bold: true);
    y += 12;
    for (var i = 0; i < top.length; i++) {
      final x0 = 40 + (i % 2) * 262.0, y0 = y + (i ~/ 2) * 130.0;
      _chart(pg, x0, y0, 250, 115, lib.byId(top[i].key)?.name ?? top[i].key, [for (final p in top[i].value) (p.$1, toUnit(p.$2, u))], unitLabel(u));
    }
    y += ((top.length + 1) ~/ 2) * 130.0 + 10;
  }

  // body weight, only when the person said yes
  if (o.body) {
    final bw = [for (final b in (await r.bodyLog()).reversed) if (b.$3 != null && o.inRange(b.$2)) (b.$2, toUnit(b.$3!, u))];
    if (bw.length > 1) {
      _chart(pg, 40, y, 512, 115, 'Body weight', bw, unitLabel(u));
      y += 130;
    }
  }

  // the workouts as a table, on as many pages as it takes
  void head() {
    pg.text(40, y, 'Workouts', size: 12, bold: true);
    y += 16;
    for (final (x, s) in [(40.0, 'Date'), (110.0, 'Workout'), (250.0, 'Min'), (285.0, 'Sets'), (320.0, 'Exercises')]) {
      pg.text(x, y, s, size: 9, bold: true, gray: 0.3);
    }
    y += 4;
    pg.line(40, y, 555, y, gray: 0.6);
    y += 12;
  }

  if (y > 700) {
    pg = doc.page();
    y = 50;
  }
  head();
  for (final w in ws.reversed) {
    if (y > 800) {
      pg = doc.page();
      y = 50;
      head();
    }
    final names = <String>{for (final x in w.sets) lib.byId(x.exerciseId)?.name ?? x.exerciseId}.join(', ');
    pg.text(40, y, _stamp(w.start), size: 9);
    pg.text(110, y, fit(w.name, 26), size: 9);
    pg.text(250, y, '${w.end.difference(w.start).inMinutes}', size: 9);
    pg.text(285, y, '${w.sets.where((x) => x.type != SetType.warmup).length}', size: 9);
    pg.text(320, y, fit(names, 52), size: 9);
    y += 14;
  }
  if (ws.isEmpty) pg.text(40, y, 'No workouts in these dates.', size: 10, gray: 0.35);
  return doc.bytes();
}

/// A small line chart: a frame, the low and high value, first and last date.
void _chart(PdfPage pg, double x, double y, double w, double h, String title, List<(DateTime, double)> pts, String unit) {
  pg.box(x, y, w, h, gray: 0.8);
  pg.text(x + 8, y + 14, title, size: 10, bold: true);
  if (pts.isEmpty) return;
  final lo = pts.map((p) => p.$2).reduce((a, b) => a < b ? a : b), hi = pts.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
  final t0 = pts.first.$1.millisecondsSinceEpoch.toDouble(), t1 = pts.last.$1.millisecondsSinceEpoch.toDouble();
  final cx = x + 40, cy = y + 24, cw = w - 52, ch = h - 44;
  double px(DateTime d) => t1 == t0 ? cx + cw / 2 : cx + (d.millisecondsSinceEpoch - t0) / (t1 - t0) * cw;
  double py(double v) => hi == lo ? cy + ch / 2 : cy + ch - (v - lo) / (hi - lo) * ch;
  pg.text(x + 6, cy + 6, fmtNum(hi), size: 8, gray: 0.35);
  pg.text(x + 6, cy + ch, fmtNum(lo), size: 8, gray: 0.35);
  pg.text(cx, y + h - 6, _stamp(pts.first.$1), size: 7, gray: 0.35);
  pg.text(cx + cw - 44, y + h - 6, _stamp(pts.last.$1), size: 7, gray: 0.35);
  pg.text(x + w - 30, y + 14, unit, size: 8, gray: 0.35);
  pg.path([for (final p in pts) (px(p.$1), py(p.$2))], width: 1.2, gray: 0.1);
  for (final p in pts) {
    pg.box(px(p.$1) - 1.2, py(p.$2) - 1.2, 2.4, 2.4, fill: 0.1, gray: 0.1);
  }
}

// ---------- the plan to print (F328) ----------

/// One page per week of the plan, with boxes to write the weight and reps of each set in.
Uint8List planPdf(Plan plan, Library lib, {int weeks = 4}) {
  final doc = PdfDoc(plan.name);
  final n = plan.weeksPerCycle > 1 ? plan.weeksPerCycle : weeks;
  for (var wk = 1; wk <= n; wk++) {
    final pg = doc.page();
    var y = 46.0;
    pg.text(40, y, '${plan.name}  -  week $wk', size: 16, bold: true);
    y += 14;
    pg.text(40, y, 'Write the weight and reps of each set in its box.', size: 9, gray: 0.35);
    y += 18;
    for (final d in plan.days) {
      if (y > 780) break; // a very long week is cut; the app has the rest
      pg.text(40, y, d.name, size: 11, bold: true);
      pg.text(380, y, 'Date: ____________', size: 9, gray: 0.35);
      y += 6;
      for (final it in d.items) {
        if (y > 800) break;
        final e = lib.byId(it.exerciseId);
        y += 14;
        pg.text(46, y, fit(e?.name ?? it.exerciseId, 28), size: 9);
        pg.text(46, y + 9, '${it.sets} x ${it.repLow}${it.repHigh > it.repLow ? '-${it.repHigh}' : ''}${e?.timed == true ? ' s' : ''}', size: 7, gray: 0.4);
        for (var k = 0; k < it.sets && k < 8; k++) {
          pg.box(200 + k * 44.0, y - 9, 40, 16, gray: 0.6);
        }
        y += 6;
      }
      y += 18;
    }
  }
  return doc.bytes();
}

// ---------- body, plans, records (F314) ----------

Future<List<List<String>>> _bodyRows(Repo r, ExportOptions o, List<Map<String, dynamic>> tape) async {
  final rows = <List<String>>[
    ['date', 'what', 'part', 'side', 'value', 'unit'],
  ];
  if (!o.body) return rows; // asked and said no: headers only
  for (final b in (await r.bodyLog()).reversed) {
    if (!o.inRange(b.$2)) continue;
    if (b.$3 != null) rows.add([csvDate(b.$2), 'body weight', '', '', csvNum(toUnit(b.$3!, o.unit)), unitLabel(o.unit)]);
    if (b.$4 != null) rows.add([csvDate(b.$2), 'body fat', '', '', csvNum(b.$4!), '%']);
  }
  for (final t in tape) {
    final at = DateTime.fromMillisecondsSinceEpoch(t['at'] as int);
    if (!o.inRange(at)) continue;
    final cm = (t['cm'] as num).toDouble();
    rows.add([csvDate(at), 'tape', t['p'] as String, switch (t['s']) { 'L' => 'left', 'R' => 'right', _ => '' }, csvNum(toLen(cm, o.unit)), lengthUnit(o.unit)]);
  }
  return rows;
}

Future<List<List<String>>> _plansRows(Repo r, Library lib) async {
  final rows = <List<String>>[
    ['plan', 'in_use', 'day', 'order', 'exercise_id', 'exercise', 'sets', 'reps_low', 'reps_high', 'rest_seconds', 'last_set', 'superset'],
  ];
  final active = await r.activePlan();
  for (final p in [if (active != null) active, ...await r.oldPlans()]) {
    for (final d in p.days) {
      for (var i = 0; i < d.items.length; i++) {
        final it = d.items[i];
        rows.add([p.name, p == active ? 'yes' : 'no', d.name, '${i + 1}', it.exerciseId, lib.byId(it.exerciseId)?.name ?? '', '${it.sets}', '${it.repLow}', '${it.repHigh}', '${it.restSec}', it.style, it.group == null ? '' : '${it.group}']);
      }
    }
  }
  return rows;
}

Future<List<List<String>>> _recordsRows(Repo r, Library lib, Unit u) async {
  final rows = <List<String>>[
    ['exercise', 'record', 'value', 'unit', 'date'],
  ];
  final ids = [for (final x in await r.db.rawQuery('SELECT DISTINCT exercise_id FROM set_log ORDER BY exercise_id')) x['exercise_id'] as String];
  for (final id in ids) {
    final e = lib.byId(id);
    if (e == null) continue;
    final sets = await r.setsOf(id);
    if (sets.isEmpty) continue;
    for (final rec in currentRecords(recordHistory(sets, e)).values) {
      final (v, unit) = switch (rec.kind) {
        RecordKind.mostReps => (csvNum(rec.value), 'reps'),
        RecordKind.longestHold => (csvNum(rec.value), 's'),
        RecordKind.farthest => (csvNum(rec.value), 'm'),
        _ => (csvNum(toUnit(rec.value, u)), unitLabel(u)),
      };
      rows.add([e.name, recordLabel[rec.kind]!, v, unit, _stamp(rec.at)]);
    }
  }
  return rows;
}

// ---------- text (F315) ----------

/// Workouts as plain text / Markdown, for notes apps or the person's own AI.
Future<String> workoutsText(Repo r, Library lib, ExportOptions o) async {
  final b = StringBuffer('# FightMilk workouts\n');
  for (final w in await _workouts(r, o)) {
    b.write('\n${workoutText(w.name, w.start, w.end, w.sets, lib, o.unit, note: w.note)}');
  }
  return b.toString();
}

/// One workout as text ("copy as text", F315; also shared from History).
String workoutText(String name, DateTime start, DateTime? end, List<SetLog> sets, Library lib, Unit u, {String note = ''}) {
  final b = StringBuffer('## $name, ${_stamp(start)}${end == null ? '' : ' (${end.difference(start).inMinutes} min)'}\n');
  if (note.isNotEmpty) b.write('$note\n');
  final by = <String, List<SetLog>>{};
  for (final x in sets) {
    by.putIfAbsent(x.exerciseId, () => []).add(x);
  }
  for (final e in by.entries) {
    final ex = lib.byId(e.key);
    final parts = [
      for (final x in e.value)
        '${x.type == SetType.warmup ? 'warm-up ' : ''}${ex?.timed == true ? '${x.secs ?? x.reps} s' : '${x.kg > 0 ? '${fmtWeight(x.kg, u)} ${unitLabel(u)} × ' : ''}${x.reps}'}${x.side.isEmpty ? '' : (x.side == 'L' ? ' left' : ' right')}'
    ];
    b.write('- ${ex?.name ?? e.key}: ${parts.join(', ')}\n');
  }
  return b.toString();
}

// ---------- .tcx (F318) ----------

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Each workout as a TCX activity ("Other"), with its time and the sets in the notes, for the
/// person to upload to Garmin Connect or Strava by hand. (A .fit file is binary and gives these
/// sites nothing more for weights, so only .tcx is made.)
Future<String> _tcx(Repo r, Library lib, ExportOptions o) async {
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n'
      '<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">\n<Activities>\n');
  for (final w in await _workouts(r, o)) {
    final secs = w.end.difference(w.start).inSeconds;
    b.write('<Activity Sport="Other">\n<Id>${_iso(w.start)}</Id>\n<Lap StartTime="${_iso(w.start)}">\n'
        '<TotalTimeSeconds>$secs</TotalTimeSeconds>\n<DistanceMeters>0</DistanceMeters>\n<Calories>0</Calories>\n'
        '<Intensity>Active</Intensity>\n<TriggerMethod>Manual</TriggerMethod>\n</Lap>\n'
        '<Notes>${_xml(workoutText(w.name, w.start, w.end, w.sets, lib, o.unit, note: w.note))}</Notes>\n</Activity>\n');
  }
  b.write('</Activities>\n</TrainingCenterDatabase>\n');
  return b.toString();
}

// ---------- SQLite (F319) ----------

/// A whole copy of the open database [db] at [path]: VACUUM INTO where SQLite has it (3.27+),
/// else the newest changes are first written from the WAL into the main file, so a plain copy
/// of that file holds them too (older phones; minSdk 24, PLAN-next change 12).
Future<void> copyDatabase(Database db, String path, {bool vacuumInto = true}) async {
  if (vacuumInto) {
    try {
      await db.execute('VACUUM INTO ?', [path]);
      return;
    } catch (_) {}
  }
  try {
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (_) {}
  File(db.path).copySync(path);
}

/// A copy of the database with the photo list removed (and the body data, unless asked for),
/// vacuumed so nothing deleted is left in free pages.
Future<Uint8List> _sqlite(Repo r, ExportOptions o, DatabaseFactory f) async {
  final tmp = Directory.systemTemp.createTempSync('fmexport');
  try {
    final path = '${tmp.path}${Platform.pathSeparator}copy.sqlite';
    await copyDatabase(r.db, path);
    final db = await f.openDatabase(path);
    // settings by allow-list, the same as the backup (review 5, P1-1): no photo list, undo logs or
    // day state, and without body data no tape, body fields or body goal
    final kv = exportKvRows(await db.query('kv'), body: o.body);
    await db.delete('kv');
    for (final row in kv) {
      await db.insert('kv', row);
    }
    if (!o.body) await db.delete('body');
    await db.execute('VACUUM');
    await db.close();
    return File(path).readAsBytesSync();
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

// ---------- F320 the formats, written up ----------

const formatNotes = '''FightMilk export files

All files are made on the phone and only go where you save or send them.
Progress photos are never in any export, share or backup.
Body data (weigh-ins, body fat, tape, height) is only in a file when you said yes.

Sets: Strong CSV      Strong's columns: Date, Workout Name, Duration, Exercise Name, Set Order
                      (W/D/F for warm-up/drop/failure), Weight, Reps, Distance, Seconds, Notes,
                      Workout Notes, RPE. Weights in the unit you picked.
Sets: Hevy CSV        Hevy's columns (weight_kg or weight_lbs, set_type, rpe ...).
Sets: FitNotes CSV    FitNotes' columns (Date, Exercise, Category, Weight, Reps, Distance, Time).
Sets: Liftosaur CSV   Liftosaur's history columns (best effort).
Sets: every column    One row per set: ids, date, workout, set number, exercise id and name,
                      muscles, equipment, type, kg and lb, reps, seconds, meters, side, effort
                      (1 easy - 4 all-out), RPE, rest, est. 1-rep max in kg and lb, notes.
Body                  date, what (body weight / body fat / tape), part, side, value, unit.
Plans                 plan, in use, day, order, exercise id and name, sets, reps, rest, last-set
                      style, superset group.
Records               exercise, record, value, unit, date.
''';
