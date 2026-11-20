import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'repo.dart';

class BackupError implements Exception {
  final String message;
  BackupError(this.message);
  @override
  String toString() => message;
}

const _tables = ['plan', 'lift_state', 'session', 'set_log'];

/// Only these settings travel in a backup. API keys live in secure storage and never do.
bool _exportable(String k) => k == 'profile' || k == 'settings' || k.startsWith('last_day:');

/// Everything on the phone as one JSON file the user saves wherever they like.
Future<String> exportBackup(Repo r) async {
  final out = <String, dynamic>{'format': 1, 'app': 'workout', 'exported': DateTime.now().toIso8601String()};
  out['kv'] = [for (final row in await r.db.query('kv')) if (_exportable(row['k'] as String)) row];
  for (final t in _tables) {
    out[t] = await r.db.query(t);
  }
  return const JsonEncoder.withIndent(' ').convert(out);
}

/// [replace] wipes the phone first. Otherwise merges: rows already on the phone (same id) are
/// kept, imported plans come in as old plans unless the phone has no plan yet.
Future<void> importBackup(Repo r, String text, {required bool replace}) async {
  Map<String, dynamic> j;
  try {
    j = jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    throw BackupError('That file is not a backup from this app.');
  }
  if (j['format'] != 1 || j['app'] != 'workout') throw BackupError('That file is not a backup from this app (or is from a newer version).');
  for (final t in [..._tables, 'kv']) {
    if (j[t] is! List) throw BackupError('The backup is missing its "$t" part.');
  }
  try {
    await _apply(r, j, replace);
  } on BackupError {
    rethrow;
  } catch (e) {
    throw BackupError('The backup could not be read, so nothing was changed. ($e)');
  }
}

Future<void> _apply(Repo r, Map<String, dynamic> j, bool replace) async {
  await r.db.transaction((tx) async {
    final hadPlan = (await tx.query('plan', where: 'active = 1', limit: 1)).isNotEmpty;
    if (replace) {
      for (final t in [..._tables, 'kv']) {
        await tx.delete(t);
      }
    }
    final mode = replace ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore;
    final phoneHasOpen = !replace && (await tx.query('session', where: 'finished IS NULL', limit: 1)).isNotEmpty;
    final skip = <String>{
      if (phoneHasOpen)
        for (final row in (j['session'] as List).cast<Map<String, dynamic>>())
          if (row['finished'] == null) row['id'] as String
    };
    for (final row in (j['kv'] as List).cast<Map<String, dynamic>>()) {
      if (_exportable(row['k'] as String)) await tx.insert('kv', row, conflictAlgorithm: mode);
    }
    for (final t in _tables) {
      for (final row in (j[t] as List).cast<Map<String, dynamic>>()) {
        final r2 = Map<String, dynamic>.from(row);
        if (t == 'plan' && !replace && hadPlan) r2['active'] = 0;
        if (t == 'session' && skip.contains(r2['id'])) continue;
        if (t == 'set_log' && skip.contains(r2['session_id'])) continue;
        await tx.insert(t, r2, conflictAlgorithm: mode);
      }
    }
  });
}
