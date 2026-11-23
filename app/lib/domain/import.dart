import 'exercise.dart';
import 'library.dart';
import 'units.dart';

/// Reading other apps' history (batch 21, F330-F335). The file is a stranger's, so: a size cap,
/// never a throw on bad input (a [ImportRead] with a plain [ImportRead.problem] instead), text
/// cleaned of hidden marks and of the ' a CSV export puts before formula-like text, and every
/// guess (the unit, the date order, the exercise names) shown to the person before anything is
/// saved. Nothing here touches the database or the network.

const importMaxBytes = 8 * 1024 * 1024;
const importMaxRows = 200000;
const _cellMax = 300;

// ---------- CSV ----------

/// Rows of a CSV text: quotes, doubled quotes, CR/LF, a BOM, and ; or tab as the separator when
/// the header has no commas. Cells are cut at 300 characters and cleaned (see [cleanCell]).
/// At most [importMaxRows] rows; null means it is not a table at all.
/// What [readCsv] noticed besides the rows.
class CsvInfo {
  int? openQuoteLine; // a quote opened on this line (1-based) is never closed
  int lines = 0; // lines in the file
}

List<List<String>>? readCsv(String text, [CsvInfo? info]) {
  var t = text;
  if (t.startsWith('﻿')) t = t.substring(1);
  final firstLine = t.split('\n').first;
  final sep = firstLine.contains(',') ? ',' : (firstLine.contains(';') ? ';' : (firstLine.contains('\t') ? '\t' : ','));
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false, wasQuoted = false;
  var line = 1, quoteLine = 0;
  void endCell() {
    row.add(cleanCell(cell.toString(), quoted: wasQuoted));
    cell.clear();
    wasQuoted = false;
  }

  void endRow() {
    endCell();
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == '\n') line++;
    if (quoted) {
      if (c == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          if (cell.length < _cellMax * 2) cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else if (cell.length < _cellMax * 2) {
        cell.write(c);
      }
      continue;
    }
    if (c == '"' && cell.isEmpty) {
      quoted = true;
      wasQuoted = true;
      quoteLine = line;
    } else if (c == sep) {
      endCell();
      if (row.length > 200) return null; // not a table we know
    } else if (c == '\n') {
      endRow();
      if (rows.length > importMaxRows + 1) return rows; // capped (the header and more data rows); the reader says so
    } else if (c != '\r' && cell.length < _cellMax * 2) {
      cell.write(c);
    }
  }
  if (info != null) {
    info.lines = line;
    if (quoted) info.openQuoteLine = quoteLine;
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows.isEmpty ? null : rows;
}

final _hidden = RegExp('[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F\\u200B-\\u200F\\u202A-\\u202E\\u2066-\\u2069\\uFEFF]');

/// A cell made safe: hidden and bidi marks out, at most 300 characters, and the ' that CSV
/// exports (ours too) put before formula-like text taken off again; the text is never run
/// as a formula in the app, and our own export puts it back.
String cleanCell(String s, {bool quoted = false}) {
  var v = s.replaceAll(_hidden, '');
  if (!quoted) v = v.trim();
  if (v.length > 1 && v[0] == "'" && ('=+-@＝＋－＠\t\r\n'.contains(v[1]) || '=+-@＝＋－＠'.contains(v.substring(1).trimLeft().isEmpty ? ' ' : v.substring(1).trimLeft()[0]))) v = v.substring(1);
  final r = v.runes.toList();
  return r.length > _cellMax ? String.fromCharCodes(r.take(_cellMax)) : v;
}

/// Whether a shared text is a table (a header line with separators) rather than a plan.
bool looksLikeCsv(String text) {
  final t = text.trimLeft();
  if (t.isEmpty || t.startsWith('{') || t.startsWith('fightmilk:')) return false;
  // decided by the header row itself (review 6 P2-5, self7 P3-5): a word like "updated" in a plan's
  // first line is not a date column, and Hevy's header has no "date" at all
  final rows = readCsv(t.split('\n').first);
  if (rows == null || rows.first.length < 2) return false;
  final (fmt, m) = guessColumns(rows.first);
  if (fmt != ImportFormat.generic && fmt != ImportFormat.body) return true;
  if (fmt == ImportFormat.body) return m.date >= 0 && m.bodyKg >= 0;
  return m.exercise >= 0 && (m.weight >= 0 || m.reps >= 0) && m.date >= 0;
}

// ---------- the formats ----------

enum ImportFormat { strong, hevy, fitnotes, liftosaur, fitbod, fightmilk, body, generic }

const importFormatName = {
  ImportFormat.strong: 'Strong (or FightMilk) CSV',
  ImportFormat.hevy: 'Hevy CSV',
  ImportFormat.fitnotes: 'FitNotes CSV',
  ImportFormat.liftosaur: 'Liftosaur CSV',
  ImportFormat.fitbod: 'Fitbod CSV',
  ImportFormat.fightmilk: 'FightMilk CSV (every column)',
  ImportFormat.body: 'Body weight CSV',
  ImportFormat.generic: 'A CSV with its own columns',
};

/// Which column holds what (-1 = none). [unitCol] holds a unit per row (kg / lbs).
class ColumnMap {
  final int date, time, end, workout, exercise, weight, unitCol, reps, secs, meters, rpe, note, order, type, warmup, bodyKg, fat, duration, sets, distUnitCol;
  final double metersPer; // the distance column's unit in metres (1000 for km); a unit column wins
  final Unit? weightUnit; // the unit the header names; null = not said
  final bool durationSecs; // the duration column is in seconds, not "1h 5m"
  const ColumnMap({
    this.date = -1,
    this.time = -1,
    this.end = -1,
    this.workout = -1,
    this.exercise = -1,
    this.weight = -1,
    this.unitCol = -1,
    this.reps = -1,
    this.secs = -1,
    this.meters = -1,
    this.rpe = -1,
    this.note = -1,
    this.order = -1,
    this.type = -1,
    this.warmup = -1,
    this.bodyKg = -1,
    this.fat = -1,
    this.duration = -1,
    this.sets = -1,
    this.distUnitCol = -1,
    this.metersPer = 1,
    this.weightUnit,
    this.durationSecs = false,
  });
}

String _h(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9()]+'), ' ').trim();

/// The format and the columns, from the header row.
(ImportFormat, ColumnMap) guessColumns(List<String> header) {
  final h = [for (final x in header) _h(x)];
  int col(List<String> names) {
    for (final n in names) {
      final i = h.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  int has(bool Function(String) f) {
    for (var i = 0; i < h.length; i++) {
      if (f(h[i])) return i;
    }
    return -1;
  }

  if (h.contains('set id') && h.contains('workout id') && h.contains('kg')) {
    return (ImportFormat.fightmilk, ColumnMap(date: col(['date']), workout: col(['workout']), exercise: col(['exercise']), weight: col(['kg']), reps: col(['reps']), secs: col(['seconds']), meters: col(['meters']), rpe: col(['rpe']), note: col(['set note']), type: col(['type']), weightUnit: Unit.kg));
  }
  final strongW = has((x) => x == 'weight' || x.startsWith('weight ('));
  if (h.contains('exercise name') && h.contains('set order') && strongW >= 0) {
    // Strong: the old file (Weight, Weight Unit, "1h 5m") and 6.x (2024+: semicolons,
    // "Weight (kg)", "Duration (sec)", "Workout #" first)
    final secs = h.contains('duration (sec)');
    return (
      ImportFormat.strong,
      ColumnMap(
          date: col(['date']),
          workout: col(['workout name']),
          duration: col(['duration (sec)', 'duration']),
          durationSecs: secs,
          exercise: col(['exercise name']),
          order: col(['set order']),
          weight: strongW,
          unitCol: col(['weight unit']),
          reps: col(['reps']),
          meters: col(['distance (meters)', 'distance (m)', 'distance']),
          metersPer: h.contains('distance (meters)') || h.contains('distance (m)') ? 1 : 1000, // the old file's Distance is km
          secs: col(['seconds']),
          note: col(['notes']),
          rpe: col(['rpe']),
          weightUnit: h[strongW].contains('lb') ? Unit.lb : (h[strongW].contains('kg') ? Unit.kg : null))
    );
  }
  if (h.contains('exercise title') && h.contains('set index')) {
    final lb = h.contains('weight lbs');
    return (ImportFormat.hevy, ColumnMap(date: col(['start time']), end: col(['end time']), workout: col(['title']), exercise: col(['exercise title']), order: col(['set index']), type: col(['set type']), weight: col(['weight kg', 'weight lbs']), reps: col(['reps']), meters: col(['distance km', 'distance miles']), metersPer: h.contains('distance miles') ? 1609.344 : 1000, secs: col(['duration seconds']), rpe: col(['rpe']), note: col(['exercise notes']), weightUnit: lb ? Unit.lb : Unit.kg));
  }
  if (h.contains('exercise') && h.contains('category') && has((x) => x.startsWith('weight (')) >= 0) {
    final w = has((x) => x.startsWith('weight ('));
    return (ImportFormat.fitnotes, ColumnMap(date: col(['date']), exercise: col(['exercise']), weight: w, reps: col(['reps']), meters: col(['distance']), distUnitCol: col(['distance unit']), secs: col(['time']), note: col(['comment']), weightUnit: h[w].contains('lb') ? Unit.lb : Unit.kg));
  }
  if (h.contains('workout datetime') && h.contains('completed reps')) {
    return (ImportFormat.liftosaur, ColumnMap(date: col(['workout datetime']), workout: col(['day name']), exercise: col(['exercise']), warmup: col(['is warmup set']), reps: col(['completed reps']), rpe: col(['rpe', 'completed rpe']), weight: col(['completed weight value']), unitCol: col(['completed weight unit'])));
  }
  final fitbodW = has((x) => x.startsWith('weight(') || x.startsWith('weight ('));
  if (h.contains('iswarmup') && fitbodW >= 0) {
    return (ImportFormat.fitbod, ColumnMap(date: col(['date']), exercise: col(['exercise']), reps: col(['reps']), weight: fitbodW, secs: col(['duration(s)', 'duration (s)']), meters: col(['distance(m)', 'distance (m)']), warmup: col(['iswarmup']), note: col(['note']), weightUnit: h[fitbodW].contains('lb') ? Unit.lb : Unit.kg));
  }
  // anything else: guess by the names people use
  final ex = col(['exercise', 'exercise name', 'exercise title', 'name', 'movement', 'lift', 'activity']);
  final w = has((x) => x.startsWith('weight') || x.startsWith('load') || x == 'kg' || x == 'lbs' || x == 'lb');
  final date = has((x) => x.contains('date') || x == 'day' || x == 'when' || x.contains('time'));
  Unit? u;
  if (w >= 0 && (h[w].contains('lb') || h[w].contains('pound'))) u = Unit.lb;
  if (w >= 0 && (h[w].contains('kg') || h[w].contains('kilo'))) u = Unit.kg;
  final repsCol = has((x) => x == 'reps' || x == 'rep' || x.startsWith('reps'));
  if (ex < 0 && repsCol >= 0) return (ImportFormat.generic, ColumnMap(date: date)); // sets without an exercise: said plainly
  if (ex < 0) {
    // no exercise and no reps: a body weight log (date, weight[, fat])
    final fat = has((x) => x.contains('fat'));
    final bw = has((x) => x.contains('weight') || x == 'kg' || x == 'lbs' || x == 'lb');
    return (ImportFormat.body, ColumnMap(date: date, bodyKg: bw, fat: fat, weightUnit: bw >= 0 && h[bw].contains('lb') ? Unit.lb : (bw >= 0 && h[bw].contains('kg') ? Unit.kg : null)));
  }
  return (
    ImportFormat.generic,
    ColumnMap(
      date: date,
      workout: () {
        final n = col(['workout name', 'title', 'session', 'routine']);
        if (n >= 0) return n;
        final w0 = col(['workout']);
        return w0 >= 0 && !header[w0].contains('#') ? w0 : -1; // "Workout #" is a number, not a name
      }(),
      order: col(['set order']),
      type: col(['set type', 'type']),
      exercise: ex,
      weight: w,
      unitCol: col(['unit', 'units', 'weight unit']),
      reps: has((x) => x == 'reps' || x == 'rep' || x.startsWith('reps')),
      rpe: col(['rpe']),
      note: has((x) => x.contains('note') || x.contains('comment')),
      secs: has((x) => x.contains('second') || x == 'duration'),
      time: col(['time', 'start time', 'clock']),
      sets: col(['sets']),
      meters: has((x) => x.startsWith('distance')),
      metersPer: () {
        final d = has((x) => x.startsWith('distance'));
        if (d < 0) return 1.0;
        return h[d].contains('km') ? 1000.0 : (h[d].contains('mi') ? 1609.344 : 1.0);
      }(),
      distUnitCol: col(['distance unit']),
      weightUnit: u,
    )
  );
}

// ---------- dates and numbers ----------

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

/// A date and time as other apps write them: "2026-11-05 18:30:00", ISO with T and Z,
/// "2026/11/05", "05/11/2026" or "11/05/2026" ([dayFirst] decides), "5 Nov 2026, 18:30".
DateTime? readDate(String s, {bool dayFirst = true}) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final hm = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false).firstMatch(t);
  var hh = hm == null ? 12 : int.parse(hm.group(1)!), mm = hm == null ? 0 : int.parse(hm.group(2)!);
  var ap = hm?.group(4)?.toLowerCase();
  if (hm == null) {
    // only the hour (review 7, P3-14: it was dropped): "2026-11-05T18" (ISO, maybe with a zone)
    // or "6pm" / "6 PM" anywhere
    final iso = RegExp(r'^\d{4}[/.-]\d{1,2}[/.-]\d{1,2}[T ](\d{1,2})(?:Z|[+-]\d{2}(?::?\d{2})?)?$').firstMatch(t);
    final ampm = RegExp(r'\b(\d{1,2})\s*(am|pm)\b', caseSensitive: false).firstMatch(t);
    if (iso != null) {
      hh = int.parse(iso.group(1)!);
      if (hh > 23) return null;
    } else if (ampm != null) {
      hh = int.parse(ampm.group(1)!);
      ap = ampm.group(2)!.toLowerCase();
      if (hh < 1 || hh > 12) return null;
    }
  }
  if (ap == 'pm' && hh < 12) hh += 12;
  if (ap == 'am' && hh == 12) hh = 0;
  final ymd = RegExp(r'^(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})').firstMatch(t);
  if (ymd != null) {
    // every part checked first: DateTime.parse would roll 2026-02-31 over to 3 March and take
    // 9999 (review 6 P1-3)
    final sec = hm?.group(3) == null ? 0 : int.parse(hm!.group(3)!);
    final base = _make(int.parse(ymd.group(1)!), int.parse(ymd.group(2)!), int.parse(ymd.group(3)!), hh, mm);
    if (base == null || sec > 59) return null;
    // a time zone (Z, +01:00) is then read the usual way, for the local time
    final iso = DateTime.tryParse(t.replaceFirst(' ', 'T'));
    if (iso != null && iso.isUtc) return iso.toLocal();
    return base.add(Duration(seconds: sec));
  }
  final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})').firstMatch(t);
  if (dmy != null) {
    var a = int.parse(dmy.group(1)!), b = int.parse(dmy.group(2)!), y = int.parse(dmy.group(3)!);
    if (y < 100) y += 2000;
    final (d, m) = a > 12 ? (a, b) : (b > 12 ? (b, a) : (dayFirst ? (a, b) : (b, a)));
    return _make(y, m, d, hh, mm);
  }
  final words = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})').firstMatch(t) ?? RegExp(r'^([A-Za-z]{3})[a-z]*\s+(\d{1,2}),?\s+(\d{4})').firstMatch(t);
  if (words != null) {
    final g1 = words.group(1)!, g2 = words.group(2)!;
    final monFirst = RegExp(r'^[A-Za-z]').hasMatch(g1);
    final m = _months[(monFirst ? g1 : g2).toLowerCase()];
    final d = int.tryParse(monFirst ? g2 : g1);
    if (m != null && d != null) return _make(int.parse(words.group(3)!), m, d, hh, mm);
  }
  return null;
}

DateTime? _make(int y, int m, int d, int hh, int mm) {
  if (y < 1990 || y > DateTime.now().year + 1 || m < 1 || m > 12 || d < 1 || d > 31 || hh > 23 || mm > 59) return null;
  final x = DateTime(y, m, d, hh, mm);
  return x.month == m ? x : null; // 31 Feb is not a day
}

/// Whether the dates in [col] read both ways (no part above 12 anywhere): the person picks.
bool datesAmbiguous(List<List<String>> rows, int col) {
  var any = false;
  for (final r in rows) {
    if (col < 0 || col >= r.length) continue;
    final m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-]\d{2,4}').firstMatch(r[col].trim());
    if (m == null) continue;
    any = true;
    if (int.parse(m.group(1)!) > 12 || int.parse(m.group(2)!) > 12) return false;
  }
  return any;
}

/// A number, or why not (review 6 P2-3, self7 P2-2): "100", "102.5", "102,5" (decimal comma),
/// "1,234.5" and "1.234,5" (thousands); "1,005" is ambiguous (a thousand and five, or one point
/// zero zero five) and is refused; at most a million either way, finite.
(double?, String?) readNumber(String s) {
  final t = s.trim().replaceAll(' ', '');
  if (t.isEmpty) return (null, null);
  double? v;
  if (RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(t)) {
    v = double.tryParse(t);
  } else if (RegExp(r'^[+-]?\d+,\d{3}$').hasMatch(t)) {
    return (null, '"$s" could be a thousand or a decimal');
  } else if (RegExp(r'^[+-]?\d+,\d{1,2}$').hasMatch(t)) {
    v = double.tryParse(t.replaceAll(',', '.'));
  } else if (RegExp(r'^[+-]?\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(t)) {
    v = double.tryParse(t.replaceAll(',', ''));
  } else if (RegExp(r'^[+-]?\d{1,3}(\.\d{3})+,\d+$').hasMatch(t)) {
    v = double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  } else {
    return (null, '"$s" is not a number');
  }
  if (v == null || !v.isFinite || v.abs() > 1e6) return (null, '"$s" is out of range');
  return (v, null);
}

double? readNum(String s) => readNumber(s).$1;

/// "1:30", "00:01:30", "90", "90s" in seconds; null when not a time of at most a day.
int? readSecs(String s) {
  final t = s.trim().toLowerCase().replaceAll('s', '');
  if (t.isEmpty) return null;
  int? v;
  if (t.contains(':')) {
    final p = t.split(':').map(int.tryParse).toList();
    if (p.length > 3 || p.any((x) => x == null || x < 0 || x > 99999)) return null;
    v = p.fold<int>(0, (a, x) => a * 60 + x!);
  } else {
    final d = readNum(t);
    v = d == null ? null : d.round();
  }
  return v == null || v < 0 || v > 86400 ? null : v;
}

// ---------- what was read ----------

class ImportSet {
  final String exercise; // as the file names it
  final double kg; // in kg
  final int reps;
  final int? secs;
  final double? meters;
  final SetType type;
  final double? rpe;
  final String note;
  const ImportSet(this.exercise, this.kg, this.reps, {this.secs, this.meters, this.type = SetType.work, this.rpe, this.note = ''});
}

class ImportWorkout {
  final DateTime start;
  DateTime? end;
  final String name;
  final List<ImportSet> sets;
  ImportWorkout(this.start, this.end, this.name, this.sets);
}

class ImportRead {
  final String? problem; // set: nothing could be read, in plain words
  final ImportFormat format;
  final List<ImportWorkout> workouts;
  final List<(DateTime, double, double?)> body; // weigh-ins: when, kg, fat %
  final List<String> skipped; // the first rows left out, with why
  final int skippedCount;
  final Unit unit; // the unit weights were read in
  final String unitWhy; // why, for the preview
  final bool unitGuessed; // the file does not say: the person should check
  final bool dateAmbiguous; // 05/06 could be either: the person picks
  final bool dayFirst;
  final bool capped; // more than [importMaxRows] rows: the rest was left out
  const ImportRead({
    this.problem,
    this.format = ImportFormat.generic,
    this.workouts = const [],
    this.body = const [],
    this.skipped = const [],
    this.skippedCount = 0,
    this.unit = Unit.kg,
    this.unitWhy = '',
    this.unitGuessed = false,
    this.dateAmbiguous = false,
    this.dayFirst = true,
    this.capped = false,
  });
  bool get ok => problem == null && (workouts.isNotEmpty || body.isNotEmpty);
  int get sets => workouts.fold(0, (a, w) => a + w.sets.length);
  Set<String> get names => {for (final w in workouts) for (final s in w.sets) s.exercise};
}

ImportRead _no(String why) => ImportRead(problem: why);

/// Reads a history file. [unit] and [dayFirst] are the person's choice once they have seen the
/// guesses; null = guess. Never throws.
ImportRead readImport(String text, {required Unit appUnit, Unit? unit, bool? dayFirst}) {
  try {
    if (text.length > importMaxBytes) return _no('That file is too big to import (over 8 MB).');
    if (text.trim().isEmpty) return _no('The file is empty.');
    if (text.contains('\u0000') || text.contains('���')) return _no('That is not a text file (or not UTF-8). Save it as CSV and try again.');
    final info = CsvInfo();
    final rows = readCsv(text, info);
    if (info.openQuoteLine != null) {
      // one stray quote would swallow the rest of the file (review 6 P2-4)
      return _no('A quote (") opened on line ${info.openQuoteLine} is never closed, so lines ${info.openQuoteLine} to ${info.lines} could not be read. Fix that line and try again.');
    }
    if (rows == null || rows.length < 2) return _no('That is not a table with a header row and data.');
    final capped = rows.length > importMaxRows + 1;
    final header = rows.first;
    // a second header row and rows that are there twice (two exports pasted together, N52)
    final seen = <String>{};
    var repeated = 0;
    final data = <List<String>>[];
    for (final r in rows.sublist(1, capped ? importMaxRows + 1 : rows.length)) {
      final k = r.join('\u0001');
      if (k == header.join('\u0001') || !seen.add(k)) {
        repeated++;
        continue;
      }
      data.add(r);
    }
    final (fmt, m) = guessColumns(header);
    final ambiguous = m.date >= 0 && datesAmbiguous(data, m.date);
    final df = dayFirst ?? (fmt == ImportFormat.fitnotes ? false : !_usLike(data, m.date));
    // the unit: the file's own word, else the person's choice, else their app unit (said so)
    final (u, why, guessed) = m.weightUnit != null
        ? (unit ?? m.weightUnit!, unit != null && unit != m.weightUnit ? 'you chose ${unitLabel(unit)} (the file says ${unitLabel(m.weightUnit!)})' : 'the file says ${unitLabel(m.weightUnit!)}', false)
        : m.unitCol >= 0
            ? (unit ?? appUnit, 'each row says its unit', false)
            : (unit ?? appUnit, unit != null ? 'you chose ${unitLabel(unit)}' : '${importFormatName[fmt]} does not say: read as ${unitLabel(appUnit)}, your unit. Change it if the file is in ${appUnit == Unit.kg ? 'lb' : 'kg'}.', unit == null);
    if (m.date < 0) return _no('No date column was found (a column named Date).');
    final skipped = <String>[];
    var skippedN = 0;
    void skip(int row, String why) {
      skippedN++;
      if (skipped.length < 50) skipped.add('Row ${row + 2}: $why');
    }

    String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i] : '';
    final future = DateTime.now().add(const Duration(days: 1)); // a day of slack for time zones
    if (repeated > 0) {
      skippedN += repeated;
      skipped.add('$repeated repeated row${repeated == 1 ? '' : 's'} left out (the same row twice, or a second header)');
    }
    if (fmt == ImportFormat.body) {
      if (m.bodyKg < 0) return _no('No exercise or weight column was found.');
      final body = <(DateTime, double, double?)>[];
      for (var i = 0; i < data.length; i++) {
        final d = readDate(at(data[i], m.date), dayFirst: df), w = readNum(at(data[i], m.bodyKg));
        if (d == null) {
          skip(i, 'no date it can read');
          continue;
        }
        if (d.isAfter(future)) {
          skip(i, 'a date in the future (${at(data[i], m.date)})');
          continue;
        }
        if (w == null) {
          final why = readNumber(at(data[i], m.bodyKg)).$2;
          skip(i, why == null ? 'no weight' : 'the weight $why');
          continue;
        }
        final kg = fromUnit(w, u);
        if (kg < 20 || kg > 400) {
          skip(i, 'a body weight of ${fmtNum(w)} ${unitLabel(u)} is out of range');
          continue;
        }
        final f = m.fat >= 0 ? readNum(at(data[i], m.fat)) : null;
        body.add((d, kg, f != null && f >= 3 && f <= 60 ? f : null));
      }
      var why2 = why;
      if (guessed && u == Unit.kg && body.length >= 3) {
        final kgs = [for (final b in body) b.$2]..sort();
        if (kgs[kgs.length ~/ 2] > 130) why2 = '$why Most of these are over 130 kg: they look like lb.';
      }
      return ImportRead(format: fmt, body: body, skipped: skipped, skippedCount: skippedN, unit: u, unitWhy: why2, unitGuessed: guessed, dateAmbiguous: ambiguous, dayFirst: df, capped: capped);
    }
    if (m.exercise < 0) return _no('No exercise column was found.');
    // group the rows into workouts: same start and same workout name
    final byKey = <String, ImportWorkout>{};
    var restRows = 0;
    final lastOf = <String, (ImportWorkout, DateTime)>{}; // generic files: the workout a name last had, and its last row
    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      final when0 = readDate(at(r, m.date), dayFirst: df);
      if (when0 == null) {
        skip(i, 'no date it can read ("${at(r, m.date)}")');
        continue;
      }
      var when = when0;
      // a "Time" column with a clock time is the time of day (self7 P2-3), not seconds
      final tod = m.time >= 0 ? RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?$', caseSensitive: false).firstMatch(at(r, m.time).trim()) : null;
      if (tod != null && !at(r, m.date).contains(':')) {
        var hh = int.parse(tod.group(1)!);
        final mi = int.parse(tod.group(2)!);
        final ap = tod.group(4)?.toLowerCase();
        if (ap == 'pm' && hh < 12) hh += 12;
        if (ap == 'am' && hh == 12) hh = 0;
        if (hh > 23 || mi > 59) {
          skip(i, 'the time "${at(r, m.time)}" is not a time of day');
          continue;
        }
        when = DateTime(when.year, when.month, when.day, hh, mi, int.tryParse(tod.group(3) ?? '0') ?? 0);
      }
      if (when.isAfter(future)) {
        skip(i, 'a date in the future (${at(r, m.date)})');
        continue;
      }
      final name = at(r, m.exercise).trim();
      if (name.isEmpty) {
        skip(i, 'no exercise name');
        continue;
      }
      final mark = at(r, m.order).trim().toUpperCase();
      if (mark == 'REST TIMER' || mark == 'REST') {
        restRows++;
        continue;
      }
      final typeTxt = at(r, m.type).trim().toLowerCase();
      final warm = mark == 'W' || typeTxt == 'warmup' || typeTxt == 'warm-up' || ['1', 'true', 'yes'].contains(at(r, m.warmup).trim().toLowerCase());
      final type = warm
          ? SetType.warmup
          : (mark == 'D' || typeTxt == 'dropset' || typeTxt == 'drop')
              ? SetType.drop
              : (mark == 'F' || typeTxt == 'failure')
                  ? SetType.failure
                  : SetType.work;
      // the weight: empty is 0 (bodyweight); "100 kg" / "225 lbs" carry their unit; anything
      // else that does not read is a left-out row, never a silent 0 (review 6 P2-3, self7 P2-2)
      var wTxt = at(r, m.weight).trim();
      Unit? cellUnit;
      final wu = RegExp(r'^(.*?)\s*(kgs?|kilos?|lbs?|pounds?)$', caseSensitive: false).firstMatch(wTxt);
      if (wu != null && wu.group(1)!.isNotEmpty) {
        cellUnit = wu.group(2)!.toLowerCase().startsWith('k') ? Unit.kg : Unit.lb;
        wTxt = wu.group(1)!;
      }
      final (wv, wBad) = readNumber(wTxt);
      if (wBad != null) {
        skip(i, 'the weight $wBad');
        continue;
      }
      final w = wv ?? 0;
      final unitTxt = at(r, m.unitCol).toLowerCase();
      final rowUnit = cellUnit ?? (m.unitCol >= 0 ? (unitTxt.startsWith('lb') || unitTxt.startsWith('pound') ? Unit.lb : (unitTxt.startsWith('kg') ? Unit.kg : u)) : u);
      if (w < 0 || w > (rowUnit == Unit.kg ? 700 : 1550)) {
        skip(i, 'a weight of $wTxt ${unitLabel(rowUnit)} is out of range');
        continue;
      }
      final kg = fromUnit(w, rowUnit);
      final (reps, repsBad) = readNumber(at(r, m.reps));
      if (repsBad != null) {
        skip(i, 'the reps $repsBad');
        continue;
      }
      final secsTxt = at(r, m.secs).trim();
      final secs = readSecs(secsTxt);
      if (secsTxt.isNotEmpty && secs == null && readNum(secsTxt) != 0) {
        skip(i, 'the time "$secsTxt" is not a time of at most a day');
        continue;
      }
      final (dist, distBad) = readNumber(at(r, m.meters));
      if (distBad != null) {
        skip(i, 'the distance $distBad');
        continue;
      }
      // distance in metres, by the column's or the row's unit word (self7 P2-7, review 6 N49)
      final du = at(r, m.distUnitCol).trim().toLowerCase();
      final per = du.isEmpty ? m.metersPer : (du.startsWith('km') || du.startsWith('kilo') ? 1000.0 : (du.startsWith('mi') ? 1609.344 : (du.startsWith('ft') || du.startsWith('feet') ? 0.3048 : (du.startsWith('yd') || du.startsWith('yard') ? 0.9144 : 1.0))));
      final meters = dist == null ? null : dist * per;
      if (meters != null && (meters < 0 || meters > 1000000)) {
        skip(i, 'a distance of ${at(r, m.meters)} is out of range');
        continue;
      }
      if ((reps == null || reps <= 0) && (secs == null || secs <= 0) && (meters == null || meters <= 0)) {
        skip(i, 'no reps, time or distance');
        continue;
      }
      if (reps != null && (reps < 0 || reps > 1000)) {
        skip(i, '${at(r, m.reps)} reps is out of range');
        continue;
      }
      // a "Sets" column: that many sets of this row (self7 P2-3)
      final setsTxt = at(r, m.sets).trim();
      final (nSets, setsBad) = readNumber(setsTxt);
      if (setsBad != null || (nSets != null && (nSets < 1 || nSets > 20 || nSets != nSets.roundToDouble()))) {
        skip(i, 'the sets "$setsTxt" is not 1-20');
        continue;
      }
      final rpe = readNum(at(r, m.rpe));
      final wn0 = at(r, m.workout).trim();
      // other apps' files with a time per set: rows of one workout name within 3 hours of the
      // last are one workout (review 6 P2-6)
      final prev = fmt == ImportFormat.generic ? lastOf[wn0] : null;
      final key = prev != null && !when.isBefore(prev.$2) && when.difference(prev.$2).inMinutes <= 180 ? byKey.entries.firstWhere((e) => identical(e.value, prev.$1)).key : '${when.millisecondsSinceEpoch ~/ 60000}|$wn0';
      final wk = byKey.putIfAbsent(key, () {
        final dur = at(r, m.duration);
        DateTime? end = m.end >= 0 ? readDate(at(r, m.end), dayFirst: df) : null;
        final ds = m.durationSecs ? readSecs(dur) : null;
        if (end == null && ds != null && ds > 0 && ds <= 86400) end = when.add(Duration(seconds: ds));
        final hm = RegExp(r'(?:(\d+)h)?\s*(?:(\d+)m)?').firstMatch(dur.replaceAll(' ', ''));
        if (end == null && !m.durationSecs && hm != null && (hm.group(1) != null || hm.group(2) != null)) end = when.add(Duration(hours: int.tryParse(hm.group(1) ?? '0') ?? 0, minutes: int.tryParse(hm.group(2) ?? '0') ?? 0));
        final wn = at(r, m.workout).trim();
        return ImportWorkout(when, end, wn.isEmpty ? 'Imported workout' : wn, []);
      });
      if (fmt == ImportFormat.generic) {
        lastOf[wn0] = (wk, when);
        if (when.isAfter(wk.start) && (wk.end == null || when.isAfter(wk.end!))) wk.end = when;
      }
      for (var k = 0; k < (nSets ?? 1).round(); k++) {
        if (wk.sets.length >= 300) {
          skip(i, 'over 300 sets in one workout');
          break;
        }
        wk.sets.add(ImportSet(name, kg, (reps ?? 0).round(), secs: secs, meters: meters, type: type, rpe: rpe != null && rpe >= 1 && rpe <= 10 ? rpe : null, note: at(r, m.note).trim()));
      }
    }
    final ws = byKey.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    if (restRows > 0) {
      skippedN += restRows;
      skipped.insert(0, '$restRows rest-timer row${restRows == 1 ? '' : 's'} left out (they are not sets)');
    }
    if (ws.isEmpty) return ImportRead(problem: 'No sets could be read.${skipped.isEmpty ? '' : ' ${skipped.first}.'}', skipped: skipped, skippedCount: skippedN);
    return ImportRead(format: fmt, workouts: ws, skipped: skipped, skippedCount: skippedN, unit: u, unitWhy: why, unitGuessed: guessed, dateAmbiguous: ambiguous, dayFirst: df, capped: capped);
  } catch (e) {
    return _no('That file could not be read as workout history.');
  }
}

/// True when the dates look month-first (a middle part above 12).
bool _usLike(List<List<String>> rows, int col) {
  for (final r in rows) {
    if (col < 0 || col >= r.length) continue;
    final m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-]\d{2,4}').firstMatch(r[col].trim());
    if (m == null) continue;
    if (int.parse(m.group(2)!) > 12) return true;
    if (int.parse(m.group(1)!) > 12) return false;
  }
  return false;
}

// ---------- exercise names (F332) ----------
//
// Strict on purpose (review 6 P1-2, self7 P2-1): a wrong lift writes wrong history and wrong next
// weights, a missing match only asks the person. A name matches a lift only when their words are
// the same once equipment and filler words are taken out, and the equipment agrees. Anything but
// the library's own name is a guess, shown in gold for the person to check.

/// Equipment words, Smith first: "Smith Machine" is a Smith lift, not a machine one.
const _equipWords = [
  ('smith machine', Equipment.smith),
  ('smith', Equipment.smith),
  ('plate loaded', Equipment.machine),
  ('barbell', Equipment.barbell),
  ('bb', Equipment.barbell),
  ('dumbbells', Equipment.dumbbell),
  ('dumbbell', Equipment.dumbbell),
  ('db', Equipment.dumbbell),
  ('machine', Equipment.machine),
  ('cable', Equipment.cable),
  ('kettlebell', Equipment.kettlebell),
  ('kb', Equipment.kettlebell),
  ('band', Equipment.band),
  ('bodyweight', Equipment.bodyweight),
];

/// Other apps' words for our lifts (the whole name, after the equipment is taken out).
const _synonyms = {
  'squat': 'back squat',
  'bench': 'bench press',
  'bent over row': 'row',
  'bent over barbell row': 'row',
  'military press': 'overhead press',
  'ohp': 'overhead press',
  'strict press': 'overhead press',
  'rdl': 'romanian deadlift',
  'bicep curl': 'curl',
  'biceps curl': 'curl',
  'lat pull down': 'lat pulldown',
  'pullup': 'pull up',
  'chinup': 'chin up',
  'pushup': 'push up',
  'press up': 'push up',
  'dip': 'dips',
  'chest dip': 'dips',
  'triceps dip': 'dips',
  'tricep pushdown': 'triceps pushdown',
  'skullcrusher': 'skull crusher',
  'conventional deadlift': 'deadlift',
};

/// Words that mean the same lift, used on both sides (the file's name and the library's), so a
/// match through them is still sure (review 7, P3-13).
const _same = [
  ('single arm', 'one arm'),
  ('shoulder press', 'overhead press'),
  ('reverse fly', 'rear delt fly'),
  ('standing calf raise', 'calf raise'), // only here: a standing leg curl is not just "leg curl"
];

/// Filler: these words say nothing about which lift it is.
const _stop = {'the', 'a', 'of', 'with', 'on', 'and', 'exercise', 'flat', 'regular', 'standard'};

/// The words of a name without its equipment and filler, the equipment it names, and whether a
/// synonym was used.
(Set<String>, Equipment?, bool) _words(String name) {
  var t = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  Equipment? eq;
  for (final (w, e) in _equipWords) {
    final rx = RegExp('\\b$w\\b');
    if (rx.hasMatch(t)) {
      eq ??= e;
      t = t.replaceAll(rx, ' ');
    }
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  var syn = false;
  if (_synonyms.containsKey(t)) {
    t = _synonyms[t]!;
    syn = true;
  }
  for (final (a, b) in _same) {
    t = t.replaceAll(RegExp('\\b$a\\b'), b);
  }
  final w = {for (final x in t.split(' ')) if (x.isNotEmpty && !_stop.contains(x)) x.endsWith('s') && x.length > 4 && x != 'press' && x != 'dips' ? x.substring(0, x.length - 1) : x};
  // "Incline Bench Press" is the incline press: "bench" adds nothing next to incline / decline
  if (w.contains('incline') || w.contains('decline')) w.remove('bench');
  // "Lat pulldown" and "Pulldown" are one lift: "lat" adds nothing next to pulldown
  if (w.contains('pulldown')) w.remove('lat');
  return (w, eq, syn);
}

/// Equipment words a library name may carry without the file saying it.
bool _plainName(Exercise e) {
  final n = e.name.toLowerCase();
  return !RegExp(r'\b(dumbbell|kettlebell|cable|band|smith|machine)\b').hasMatch(n) || n.contains('assisted');
}

/// The library exercise for a name another app wrote, and whether it is sure (the library's own
/// name, or the same words with the same equipment). Null: the person picks.
(Exercise?, bool sure) matchName(String name, Library lib) {
  final exact = lib.find(name);
  if (exact != null) return (exact, true);
  final (w, eq, syn) = _words(name);
  if (w.isEmpty) return (null, false);
  if (w.length == 1 && eq == null && !syn) return (null, false); // "Row", "Press", "Curl": ask
  final hits = <Exercise>[];
  for (final e in lib.all) {
    final (ew, eeq, _) = _words(e.name);
    if (ew.length != w.length || !ew.containsAll(w)) continue;
    if (eq != null && e.equipment != eq && eeq != eq) continue; // the file says the equipment
    if (eq == null && !_plainName(e)) continue; // no word in the file: not a dumbbell or cable lift
    hits.add(e);
  }
  if (hits.isEmpty) return (null, false);
  hits.sort((a, b) => _rank(a, eq).compareTo(_rank(b, eq)));
  final best = hits.first;
  final sure = !syn && hits.length == 1 && (eq == null || best.equipment == eq);
  return (best, sure);
}

int _rank(Exercise e, Equipment? eq) => e.equipment == eq ? 0 : (e.equipment == Equipment.barbell ? 1 : (e.equipment == Equipment.bodyweight ? 2 : 3));

/// The library exercise for a name another app wrote, or null (the person picks).
Exercise? matchExercise(String name, Library lib) => matchName(name, lib).$1;
