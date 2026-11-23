import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/plan.dart';
import '../domain/progression.dart';
import '../domain/reports.dart';
import 'import_store.dart';
import 'repo.dart';

/// Backups (batch 22, F338, F341, F344, F345). A backup is one JSON file:
/// `{"format": 2, "app": "workout", "schema": 3, "exported": ..., "kv": [...], <tables>,
/// "sha256": <hash of everything else>}`. Format 1 (before batch 22, no hash) still restores.
/// It may be wrapped in a password envelope (AES-256-GCM, a key from PBKDF2-SHA256).
/// Never in it: API keys (they live in Android's encrypted storage, not the database) and
/// progress photos (they live in their own folder; the photo list is not an exportable row).
const backupFormat = 2;
const backupSchema = 3; // the database version the rows come from
const backupMaxBytes = 64 * 1024 * 1024; // larger files are refused before they are read (F345)

class BackupError implements Exception {
  final String message;
  BackupError(this.message);
  @override
  String toString() => message;
}

/// The file is locked with a password; ask for it and call again.
class BackupNeedsPassword extends BackupError {
  BackupNeedsPassword() : super('This backup is locked with a password.');
}

const _tables = ['plan', 'lift_state', 'session', 'set_log'];

/// Added in app 0.8 (database v2); older backups simply don't have them.
const _optional = ['body', 'ex_note'];

/// Only these settings travel in a backup. API keys live in secure storage and never do.
/// Goals, seen badges, 4-week swaps and the "that hurt" ramp travel with the backup too (review 3,
/// P1-3): without them a restore lost every goal and announced every badge again.
bool _exportable(String k) =>
    !deviceOnlyKeys.contains(k) &&
    (k == 'profile' || k == 'settings' || k == 'custom_ex' || k == 'ex_prefs' || k == 'gyms' || k == 'gym_active' || k.startsWith('last_day:') || k == 'aims' || k == 'badges_seen' || k == 'block_swaps' || k == 'ramp' || k == 'tape' || k == 'imports' || k == 'imports_undone'); // progress photos stay on the phone, not in the file; the import list goes, so Undo works after a restore

/// The settings rows that may leave the phone, by allow-list (review 5, P1-1): only the keys a
/// backup carries, never undo logs or day state (ai_changes, auto_changes, pain, override ...),
/// whose texts and snapshots can hold body numbers. Without [body]: no tape, no body weight,
/// height or pregnancy answer in the profile, and no body-weight goal. One helper for the backup
/// and the SQLite copy, so they can't drift apart.
List<Map<String, Object?>> exportKvRows(List<Map<String, Object?>> rows, {required bool body}) => [
      for (final row in rows)
        if (_exportable(row['k'] as String) && (body || !bodyOnlyKeys.contains(row['k'])))
          if (body) row else {...row, 'v': _stripBody(row['k'] as String, row['v'] as String)}
    ];

/// This phone's own rows: never in a backup, and kept when a backup replaces everything (review 7,
/// P2-1), so setting up a phone from a backup does not quietly turn its automatic backup off or
/// forget its server. Progress photos stay too (they are never in the file).
const deviceOnlyKeys = {'photos', 'auto_backup', 'webdav', 'backup_status'};

/// Settings rows that are body data only.
const bodyOnlyKeys = {'tape'};

/// Profile fields that are body data.
const bodyProfileFields = ['bodyKg', 'height', 'pregnancy'];

String _stripBody(String k, String v) {
  try {
    if (k == 'profile') return jsonEncode((jsonDecode(v) as Map)..removeWhere((f, _) => bodyProfileFields.contains(f)));
    if (k == 'aims') return jsonEncode([for (final a in jsonDecode(v) as List) if (a is! Map || a['kind'] != 'body') a]);
  } catch (_) {}
  return v;
}

/// Whether a backup file holds body data (a file without the mark is from before batch 20: yes).
bool backupHasBody(String text) {
  // the mark sits at the top of the file (exportBackup writes it right after the dates), so a
  // look at the start is enough: no second decode of a large file on the UI isolate (review 7, P2-4)
  final head = text.length > 4096 ? text.substring(0, 4096) : text;
  return !RegExp(r'"hasBody"\s*:\s*false').hasMatch(head);
}

/// Reads a picked file, but never more than [max] bytes: a file that is bigger is refused before
/// it is read whole (review 7, P2-4). Null = too big.
Future<Uint8List?> readCapped(Stream<List<int>> s, {int max = backupMaxBytes}) async {
  final b = BytesBuilder(copy: false);
  await for (final chunk in s) {
    if (b.length + chunk.length > max) return null;
    b.add(chunk);
  }
  return b.takeBytes();
}

/// Everything on the phone as one JSON file the user saves wherever they like.
/// [body]: weigh-ins, body fat, tape, height and the body goal go in (batch 20 asks the person
/// first). Progress photos never do (review 4). A file without body data says so, so a restore
/// keeps the phone's (review 5, P1-3).
Future<String> exportBackup(Repo r, {bool body = true}) async {
  final out = <String, dynamic>{'format': backupFormat, 'app': 'workout', 'schema': backupSchema, 'exported': DateTime.now().toIso8601String(), if (!body) 'hasBody': false};
  out['kv'] = exportKvRows(await r.db.query('kv'), body: body);
  for (final t in [..._tables, ..._optional]) {
    out[t] = !body && t == 'body' ? const [] : await r.db.query(t);
  }
  // a hash of all of it: a damaged or cut-short file is caught before anything changes (F341)
  out['sha256'] = await _hash(out);
  return const JsonEncoder.withIndent(' ').convert(out);
}

Future<String> _hash(Map<String, dynamic> j) async {
  final body = Map<String, dynamic>.from(j)..remove('sha256');
  final h = await Sha256().hash(utf8.encode(jsonEncode(body)));
  return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ---------- the password envelope (F338) ----------

const _iterations = 600000; // OWASP's advice for PBKDF2-HMAC-SHA256; stored in each file, so older locks still open

/// The round counts a locked file may state (review 7, P2-2): below, a file could not be one of
/// ours; above, one try would take minutes on a phone.
const lockMinIterations = 100000, lockMaxIterations = 2000000;

/// The key, worked out on a worker isolate: a few seconds of PBKDF2 never stall the screen
/// (review 7, P2-2).
Future<SecretKey> _key(String password, List<int> salt, int iterations) async {
  final bytes = await Isolate.run(() async {
    final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKeyFromPassword(password: password, nonce: salt);
    return k.extractBytes();
  });
  return SecretKey(bytes);
}

/// [plain] (a backup) locked with [password]: only someone with the password can read it.
Future<String> lockBackup(String plain, String password, {int iterations = _iterations}) async {
  if (iterations < lockMinIterations || iterations > lockMaxIterations) throw ArgumentError.value(iterations, 'iterations');
  final rnd = Random.secure();
  final salt = [for (var i = 0; i < 16; i++) rnd.nextInt(256)];
  final key = await _key(password, salt, iterations);
  final box = await AesGcm.with256bits().encrypt(utf8.encode(plain), secretKey: key);
  return jsonEncode({
    'fightmilk': 'backup-locked',
    'v': 1,
    'kdf': 'pbkdf2-sha256',
    'iter': iterations,
    'salt': base64.encode(salt),
    'nonce': base64.encode(box.nonce),
    'data': base64.encode(box.cipherText),
    'mac': base64.encode(box.mac.bytes),
  });
}

bool isLockedBackup(String text) {
  final t = text.trimLeft();
  return t.startsWith('{') && t.length < 300 * 1024 * 1024 && t.contains('"backup-locked"');
}

/// The backup inside a locked file. Wrong password or a damaged file: a plain BackupError.
Future<String> unlockBackup(String text, String password) async {
  Map j;
  try {
    j = jsonDecode(text) as Map;
  } catch (_) {
    throw BackupError('That file is damaged: it is not whole.');
  }
  if (j['fightmilk'] != 'backup-locked' || j['v'] != 1 || j['kdf'] != 'pbkdf2-sha256') throw BackupError('That is not a locked FightMilk backup (or it is from a newer version).');
  final iter = j['iter'];
  if (iter is! int || iter < lockMinIterations || iter > lockMaxIterations) throw BackupError('That locked backup is damaged.');
  try {
    final key = await _key(password, base64.decode(j['salt'] as String), iter);
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(base64.decode(j['data'] as String), nonce: base64.decode(j['nonce'] as String), mac: Mac(base64.decode(j['mac'] as String))),
      secretKey: key,
    );
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    throw BackupError('Wrong password, or the file is damaged.');
  } catch (_) {
    throw BackupError('That locked backup is damaged.');
  }
}

/// [replace] wipes the phone first. Otherwise merges: rows already on the phone (same id) are
/// kept, imported plans come in as old plans unless the phone has no plan yet.
///
/// Safe by design: the file is checked whole first (size, version, the hash, every row's
/// fields and contents), and only then written, in one database transaction, so a bad file
/// changes nothing. A large file is decoded, hashed and checked on a worker isolate, so the
/// screen keeps moving (review 7, P2-4). A locked file needs [password] (BackupNeedsPassword
/// without it).
Future<void> importBackup(Repo r, String text, {required bool replace, String? password}) async {
  if (text.length > backupMaxBytes) throw BackupError('That file is too big to be a backup from this app (over 64 MB).');
  if (isLockedBackup(text)) {
    if (password == null) throw BackupNeedsPassword();
    text = await unlockBackup(text, password);
  }
  final t = text;
  final res = t.length > 256 * 1024 ? await Isolate.run(() => _readChecked(t)) : await _readChecked(t);
  if (res is String) throw BackupError(res);
  try {
    await _apply(r, res as Map<String, dynamic>, replace);
  } on BackupError {
    rethrow;
  } catch (e) {
    throw BackupError('The backup could not be read, so nothing was changed.'); // no database text for the person (review 7, P2-5)
  }
}

/// The decoded, checked backup, or what is wrong with it in plain words (a String, so it can
/// come back from a worker isolate).
Future<Object> _readChecked(String text) async {
  Map<String, dynamic> j;
  try {
    j = jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    return 'That file is not a backup from this app, or it is cut short.';
  }
  if (j['app'] != 'workout' || j['format'] is! int) return 'That file is not a backup from this app.';
  final f = j['format'] as int;
  if (f > backupFormat || (j['schema'] is int && (j['schema'] as int) > backupSchema)) return 'This backup is from a newer FightMilk. Update the app, then restore it.';
  if (f < 1) return 'That file is not a backup from this app.';
  if (j['schema'] != null && j['schema'] is! int) return 'That file is not a backup from this app.';
  // the check is checked whenever it is there: a damaged file relabelled format 1 is still caught (review 7, P3-9)
  if (f >= 2 || j.containsKey('sha256')) {
    final want = j['sha256'];
    if (want is! String || want != await _hash(j)) return 'This backup is damaged (its check does not match), so nothing was changed.';
  }
  for (final t in [..._tables, 'kv']) {
    if (j[t] is! List) return 'The backup is missing its "$t" part.';
  }
  final bad = _checkRows(j);
  if (bad != null) return 'This backup is damaged ($bad), so nothing was changed.';
  return j;
}

/// The columns each table's rows must have, and their kinds (s text, i whole number, n number,
/// ? may be null).
const _columns = {
  'plan': {'id': 's', 'json': 's', 'active': 'i', 'created': 'i'},
  'lift_state': {'exercise_id': 's', 'json': 's'},
  'session': {'id': 's', 'plan_id': 's', 'day_index': 'i', 'day': 's', 'started': 'i', 'finished': 'i?'},
  'set_log': {'id': 's', 'session_id': 's', 'exercise_id': 's', 'kg': 'n', 'reps': 'i', 'ord': 'i', 'at': 'i'},
  'body': {'id': 's', 'at': 'i', 'kg': 'n?', 'fat': 'n?'},
  'ex_note': {'exercise_id': 's', 'note': 's'},
  'kv': {'k': 's', 'v': 's'},
};

/// The other columns a row may carry (newer fields, all with a default): '?' may be null,
/// '-' may be left out but never null (the column is NOT NULL).
const _more = {
  'session': {'note': 's-'},
  'set_log': {'type': 's-', 'effort': 'i?', 'rpe': 'n?', 'note': 's-', 'rest': 'i?', 'side': 's-', 'secs': 'i?', 'meters': 'n?', 'slot': 's?'},
  'body': {'json': 's-'},
};

/// Numbers that must make sense (review 7, P2-5): (low, high), inclusive.
const _ranges = {
  'set_log': {'kg': (0, 2000), 'reps': (0, 10000), 'rpe': (0, 10), 'secs': (0, 864000), 'meters': (0, 1000000), 'rest': (0, 864000)},
  'body': {'kg': (0, 700), 'fat': (0, 100)},
  'session': {'day_index': (0, 1000)},
};

/// Times in ms that must be between 1990 and a day from now.
const _times = {
  'session': ['started', 'finished'],
  'set_log': ['at'],
  'body': ['at'],
};

/// A JSON value that this app's own reader must take, else null.
bool _parses(String v, void Function(Object?) read) {
  try {
    read(jsonDecode(v));
    return true;
  } catch (_) {
    return false;
  }
}

Map<String, dynamic> _map(Object? x) => (x as Map).cast<String, dynamic>();

/// Null when every row has its fields and its contents make sense, else the first problem in
/// plain words. The contents are read the way the app reads them after a restore (review 7,
/// P2-5), so a file that passes here cannot break the app afterwards.
String? _checkRows(Map<String, dynamic> j) {
  final lo = DateTime(1990).millisecondsSinceEpoch, hi = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
  for (final e in _columns.entries) {
    final rows = j[e.key];
    if (rows == null && _optional.contains(e.key)) continue;
    if (rows is! List) return 'no "${e.key}" part';
    final more = _more[e.key] ?? const {};
    final ids = <Object?>{};
    final key = e.key == 'kv' ? 'k' : (e.value.containsKey('id') ? 'id' : 'exercise_id');
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final at = '${e.key} row ${i + 1}';
      if (row is! Map) return '$at is not a row';
      for (final f in row.keys) {
        if (!e.value.containsKey(f) && !more.containsKey(f)) return '$at has a field this app does not know ("$f")';
      }
      for (final c in [...e.value.entries, ...more.entries]) {
        final v = row[c.key];
        final kind = c.value;
        if (v == null) {
          if (kind.endsWith('?') || (kind.endsWith('-') && !row.containsKey(c.key))) continue;
          return '$at has no ${c.key}';
        }
        final ok = switch (kind.replaceAll(RegExp(r'[?-]'), '')) { 's' => v is String, 'i' => v is int, _ => v is num };
        if (!ok) return '$at: ${c.key} is the wrong kind';
        final r = _ranges[e.key]?[c.key];
        if (r != null && ((v as num) < r.$1 || v > r.$2 || v.isNaN)) return '$at: ${c.key} $v is not possible';
        if ((_times[e.key] ?? const []).contains(c.key) && ((v as int) < lo || v > hi)) return '$at: ${c.key} is not a real date';
      }
      if (!ids.add(row[key])) return 'two ${e.key} rows share one ${e.key == 'kv' ? 'name' : 'id'}';
      if (e.key == 'session' && row['finished'] is int && (row['finished'] as int) < (row['started'] as int) - 60000) return '$at ends before it starts';
      // what the app reads back after a restore must read
      final damaged = '$at is damaged';
      switch (e.key) {
        case 'plan':
          if (!_parses(row['json'] as String, (x) => Plan.fromJson(_map(x)))) return damaged;
        case 'lift_state':
          if (!_parses(row['json'] as String, (x) => LiftState.fromJson(_map(x)))) return damaged;
        case 'session':
          if (!_parses(row['day'] as String, (x) => PlanDay.fromJson(_map(x)))) return damaged;
        case 'body':
          if (row['json'] is String && !_parses(row['json'] as String, (x) => _map(x))) return damaged;
        case 'kv':
          final v = row['v'] as String;
          final ok = switch (row['k']) {
            'profile' => _parses(v, (x) => Profile.fromJson(_map(x))),
            'settings' || 'imports_undone' => _parses(v, (x) => _map(x)),
            'aims' => _parses(v, (x) => [for (final a in x as List) Aim.fromJson(_map(a))]),
            'imports' => _parses(v, (x) => [for (final a in x as List) ImportRecord.fromJson(_map(a))]),
            _ => true,
          };
          if (!ok) return 'the ${row['k']} setting is damaged';
      }
    }
  }
  return null;
}

Future<String?> _kv(DatabaseExecutor tx, String k) async {
  final v = await tx.query('kv', where: 'k = ?', whereArgs: [k]);
  return v.isEmpty ? null : v.first['v'] as String?;
}

String? _fileKv(Map<String, dynamic> j, String k) {
  for (final row in j['kv'] as List) {
    if (row is Map && row['k'] == k && row['v'] is String) return row['v'] as String;
  }
  return null;
}

List _list(String? v) {
  try {
    final x = v == null ? null : jsonDecode(v);
    return x is List ? x : const [];
  } catch (_) {
    return const [];
  }
}

/// The workouts and weigh-ins of imports the person undid (kv 'imports_undone').
({Set<String> s, Set<String> b}) _undone(String? v) {
  try {
    final x = v == null ? null : jsonDecode(v);
    if (x is! Map) return (s: <String>{}, b: <String>{});
    return (s: {for (final i in (x['s'] ?? const []) as List) if (i is String) i}, b: {for (final i in (x['b'] ?? const []) as List) if (i is String) i});
  } catch (_) {
    return (s: <String>{}, b: <String>{});
  }
}

/// The 'imports_undone' value; only the newest 20 000 of each are kept.
String undoneJson(Iterable<String> s, Iterable<String> b) {
  List<String> last(Iterable<String> l) => l.length > 20000 ? l.skip(l.length - 20000).toList() : l.toList();
  return jsonEncode({'s': last(s), 'b': last(b)});
}

/// Adds an undone import's workouts and weigh-ins to 'imports_undone', in [tx].
Future<void> noteUndone(DatabaseExecutor tx, Iterable<String> sessions, Iterable<String> body) async {
  final u = _undone(await _kv(tx, 'imports_undone'));
  await tx.insert('kv', {'k': 'imports_undone', 'v': undoneJson({...u.s, ...sessions}, {...u.b, ...body})}, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _apply(Repo r, Map<String, dynamic> j, bool replace) async {
  await r.db.transaction((tx) async {
    final hadPlan = (await tx.query('plan', where: 'active = 1', limit: 1)).isNotEmpty;
    // a backup made without body data keeps the phone's (review 5, P1-3)
    final keepBody = j['hasBody'] == false;
    Map? oldProfile;
    List oldBodyAims = const [];
    if (keepBody) {
      try {
        final p = await tx.query('kv', where: 'k = ?', whereArgs: ['profile']);
        if (p.isNotEmpty) oldProfile = jsonDecode(p.first['v'] as String) as Map;
        final a = await tx.query('kv', where: 'k = ?', whereArgs: ['aims']);
        if (a.isNotEmpty) oldBodyAims = [for (final x in jsonDecode(a.first['v'] as String) as List) if (x is Map && x['kind'] == 'body') x];
      } catch (_) {}
    }
    if (replace) {
      for (final t in [..._tables, ..._optional]) {
        if (keepBody && t == 'body') continue;
        await tx.delete(t);
      }
      // this phone's own rows stay: the photo list (review 4, P1-1), the automatic backup, the
      // server and the backup status (review 7, P2-1); so does the tape when the file has no body data
      final stay = [...deviceOnlyKeys, if (keepBody) 'tape'];
      await tx.delete('kv', where: 'k NOT IN (${List.filled(stay.length, '?').join(', ')})', whereArgs: stay);
    }
    final mode = replace ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore;
    final phoneHasOpen = !replace && (await tx.query('session', where: 'finished IS NULL', limit: 1)).isNotEmpty;
    final skip = <String>{
      if (phoneHasOpen)
        for (final row in (j['session'] as List).cast<Map<String, dynamic>>())
          if (row['finished'] == null) row['id'] as String
    };
    // a merge never brings a workout or weigh-in in twice: the same one under another id (a
    // backup from another phone, or of an import) is matched by its time, like the importer does
    final skipBody = <String>{};
    var mine = <String, int>{}, myBody = <String, int>{};
    final undone = (s: <String>{}, b: <String>{});
    if (!replace) {
      // an import the person undid never comes back with a merge (review 7, P2-3)
      for (final u in [_undone(await _kv(tx, 'imports_undone')), _undone(_fileKv(j, 'imports_undone'))]) {
        undone.s.addAll(u.s);
        undone.b.addAll(u.b);
      }
      skip.addAll(undone.s);
      skipBody.addAll(undone.b);
      mine = {for (final x in await tx.query('session', columns: ['id', 'started'])) x['id'] as String: x['started'] as int};
      for (final row in (j['session'] as List).cast<Map<String, dynamic>>()) {
        final id = row['id'] as String, st = row['started'] as int;
        if (!mine.containsKey(id) && mine.values.any((m) => (m - st).abs() <= 120000)) skip.add(id);
      }
      myBody = {for (final x in await tx.query('body', columns: ['id', 'at'])) x['id'] as String: x['at'] as int};
      for (final row in ((j['body'] ?? const []) as List).cast<Map<String, dynamic>>()) {
        final id = row['id'] as String, at = row['at'] as int;
        if (!myBody.containsKey(id) && myBody.values.any((m) => (m - at).abs() <= 600000)) skipBody.add(id);
      }
    }
    for (final row in (j['kv'] as List).cast<Map<String, dynamic>>()) {
      if (!replace && (row['k'] == 'imports' || row['k'] == 'imports_undone')) continue; // merged below
      if (_exportable(row['k'] as String)) await tx.insert('kv', row, conflictAlgorithm: mode);
    }
    // one batch for all rows: one trip to the database, not one per row (review 7, P2-4)
    final batch = tx.batch();
    for (final t in _tables) {
      for (final row in (j[t] as List).cast<Map<String, dynamic>>()) {
        final r2 = Map<String, dynamic>.from(row);
        if (t == 'plan' && !replace && hadPlan) r2['active'] = 0;
        if (t == 'session' && skip.contains(r2['id'])) continue;
        if (t == 'set_log' && skip.contains(r2['session_id'])) continue;
        batch.insert(t, r2, conflictAlgorithm: mode);
      }
    }
    for (final t in _optional) {
      if (j[t] is! List) continue;
      for (final row in (j[t] as List).cast<Map<String, dynamic>>()) {
        if (t == 'body' && skipBody.contains(row['id'])) continue;
        batch.insert(t, row, conflictAlgorithm: mode);
      }
    }
    await batch.commit(noResult: true);
    // one plan in use, at most (review 7, P2-5, checks9 B5): the newest one stays
    final active = await tx.query('plan', columns: ['id'], where: 'active = 1', orderBy: 'created DESC');
    for (final p in active.skip(1)) {
      await tx.update('plan', {'active': 0}, where: 'id = ?', whereArgs: [p['id']]);
    }
    if (!replace) {
      // the import list (review 7, P2-3): the phone's records, plus the file's records for what
      // actually came in, so those workouts can be undone here too; their saved lift states are
      // the other phone's, so an Undo here works the weights out from history instead
      final phone = _list(await _kv(tx, 'imports'));
      final known = {for (final x in phone) if (x is Map) x['id']};
      final added = <Map>[];
      for (final x in _list(_fileKv(j, 'imports'))) {
        if (x is! Map || known.contains(x['id'])) continue;
        final s = [for (final id in (x['s'] is List ? x['s'] as List : const [])) if (id is String && !mine.containsKey(id) && !skip.contains(id)) id];
        final b = [for (final id in (x['b'] is List ? x['b'] as List : const [])) if (id is String && !myBody.containsKey(id) && !skipBody.contains(id)) id];
        if (s.isEmpty && b.isEmpty) continue;
        added.add({...x, 's': s, 'b': b, 'l': const {}});
      }
      if (added.isNotEmpty) await tx.insert('kv', {'k': 'imports', 'v': jsonEncode([...phone, ...added])}, conflictAlgorithm: ConflictAlgorithm.replace);
      if (undone.s.isNotEmpty || undone.b.isNotEmpty) await tx.insert('kv', {'k': 'imports_undone', 'v': undoneJson(undone.s, undone.b)}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (keepBody) {
      // the file's profile and goals, with the phone's body fields and body goal back in
      final p = await tx.query('kv', where: 'k = ?', whereArgs: ['profile']);
      if (p.isNotEmpty && oldProfile != null) {
        final np = jsonDecode(p.first['v'] as String) as Map;
        for (final f in bodyProfileFields) {
          if (oldProfile[f] != null) np[f] = oldProfile[f];
        }
        await tx.update('kv', {'v': jsonEncode(np)}, where: 'k = ?', whereArgs: ['profile']);
      }
      if (oldBodyAims.isNotEmpty) {
        final a = await tx.query('kv', where: 'k = ?', whereArgs: ['aims']);
        final list = a.isEmpty ? [] : jsonDecode(a.first['v'] as String) as List;
        await tx.insert('kv', {'k': 'aims', 'v': jsonEncode([...list.where((x) => x is! Map || x['kind'] != 'body'), ...oldBodyAims])}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  });
}
