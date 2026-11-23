import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'backup.dart';
import 'repo.dart';

/// Automatic backups to a folder the person picked once (batch 22, F339) and the backup status
/// (F340). Only the picked folder is touched, through Android's own document access, and only
/// files this app wrote there (named fightmilk-auto-...). Nothing leaves the phone by itself: the
/// folder is on the phone (or a cloud app's folder the person chose). Progress photos and API
/// keys are never in a backup; a locked backup's password stays in Android's secure storage.

/// The folder, as an interface so tests can use a fake one.
abstract class BackupFolder {
  Future<String?> pick(); // the folder's id (a tree URI), null = backed out
  Future<bool> ok(String tree); // still allowed to write there
  /// Our files (name, modified, size in bytes, -1 = not known); null = not reachable.
  Future<List<(String id, String name, int at, int size)>?> list(String tree);

  /// Writes the file and answers the name the folder gave it (it may add " (1)"). A failed
  /// write leaves nothing behind (review 7, P1-2).
  Future<String> write(String tree, String name, Uint8List bytes);
  Future<void> delete(String tree, String id, String name);

  /// The first [n] bytes of one of our files; null = it could not be read.
  Future<Uint8List?> head(String tree, String id, int n);

  /// Gives the folder's access back to Android (another folder picked, or all data deleted):
  /// Android keeps only so many, and drops the oldest without a word (review 7, P3-8).
  Future<void> release(String tree);
}

class AndroidBackupFolder implements BackupFolder {
  static const _ch = MethodChannel('workout/system');
  @override
  Future<String?> pick() => _ch.invokeMethod<String>('pickFolder');
  @override
  Future<bool> ok(String tree) async => (await _ch.invokeMethod<bool>('folder', {'op': 'ok', 'tree': tree})) ?? false;
  @override
  Future<List<(String, String, int, int)>?> list(String tree) async {
    final l = await _ch.invokeListMethod<Map>('folder', {'op': 'list', 'tree': tree});
    return l == null ? null : [for (final x in l) (x['id'] as String, x['name'] as String, (x['at'] as num).toInt(), ((x['size'] ?? -1) as num).toInt())];
  }

  @override
  Future<String> write(String tree, String name, Uint8List bytes) async {
    final r = await _ch.invokeMethod<Object?>('folder', {'op': 'write', 'tree': tree, 'name': name, 'bytes': bytes});
    if (r is! String) throw BackupError('The backup folder can no longer be written. Pick it again.');
    return r;
  }

  @override
  Future<void> delete(String tree, String id, String name) => _ch.invokeMethod('folder', {'op': 'delete', 'tree': tree, 'id': id, 'name': name});

  @override
  Future<Uint8List?> head(String tree, String id, int n) => _ch.invokeMethod<Uint8List>('folder', {'op': 'head', 'tree': tree, 'id': id, 'n': n});

  @override
  Future<void> release(String tree) => _ch.invokeMethod('folder', {'op': 'release', 'tree': tree});
}

/// What the person chose (kv 'auto_backup'; it stays on this phone, never in a backup).
class AutoBackup {
  final String when; // off | workout | day
  final String? tree; // the picked folder
  final String folderName; // what to show for it
  final int keep; // the newest N of our files are kept
  final bool body; // with body data
  final bool locked; // locked with the password in secure storage
  const AutoBackup({this.when = 'off', this.tree, this.folderName = '', this.keep = 7, this.body = true, this.locked = false});
  AutoBackup copyWith({String? when, String? tree, String? folderName, int? keep, bool? body, bool? locked}) =>
      AutoBackup(when: when ?? this.when, tree: tree ?? this.tree, folderName: folderName ?? this.folderName, keep: keep ?? this.keep, body: body ?? this.body, locked: locked ?? this.locked);
  Map<String, dynamic> toJson() => {'when': when, 'tree': tree, 'name': folderName, 'keep': keep, 'body': body, 'locked': locked};
  factory AutoBackup.fromJson(Map<String, dynamic> j) => AutoBackup(
      when: (j['when'] ?? 'off') as String,
      tree: j['tree'] as String?,
      folderName: (j['name'] ?? '') as String,
      keep: ((j['keep'] ?? 7) as num).toInt().clamp(1, 60),
      body: (j['body'] ?? true) as bool,
      locked: (j['locked'] ?? false) as bool);
}

/// The last backup and the last problem (kv 'backup_status'), for the status line.
class BackupStatus {
  final DateTime? last; // the last backup that worked (by hand or automatic)
  final String where; // "a file you saved", "your backup folder"
  final String? problem; // the last automatic backup that failed, in plain words
  final DateTime? lastTry; // when that failed one was tried: the daily one waits an hour (review 7, P1-2)
  const BackupStatus({this.last, this.where = '', this.problem, this.lastTry});
  Map<String, dynamic> toJson() => {
        if (last != null) 'last': last!.millisecondsSinceEpoch,
        'where': where,
        if (problem != null) 'problem': problem,
        if (lastTry != null) 'lastTry': lastTry!.millisecondsSinceEpoch,
      };
  factory BackupStatus.fromJson(Map<String, dynamic> j) => BackupStatus(
      last: j['last'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['last'] as int),
      where: (j['where'] ?? '') as String,
      problem: j['problem'] as String?,
      lastTry: j['lastTry'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['lastTry'] as int));

  /// The status line: when, where, or what went wrong; a gentle nudge when it is old.
  String line(DateTime now, {required bool hasWorkouts}) {
    // a problem, and still when the last good one was (review 7, P3-11)
    if (problem != null) {
      if (last == null) return problem!;
      final d = now.difference(last!).inDays;
      return '${problem!} Last good backup ${d == 0 ? 'today' : (d == 1 ? 'yesterday' : '$d days ago')}.';
    }
    if (last == null) return hasWorkouts ? 'No backup yet. One file keeps your history safe.' : 'No backup yet.';
    final d = now.difference(last!).inDays;
    final ago = d == 0 ? 'today' : (d == 1 ? 'yesterday' : '$d days ago');
    return 'Last backup $ago${where.isEmpty ? '' : ', $where'}.${d >= 14 && hasWorkouts ? ' Time for a new one.' : ''}';
  }

  bool get needsAttention => problem != null;
  bool old(DateTime now) => last == null || now.difference(last!).inDays >= 14;
}

Future<AutoBackup> loadAutoBackup(Repo r) async {
  try {
    final v = await r.kvGet('auto_backup');
    return v == null ? const AutoBackup() : AutoBackup.fromJson(jsonDecode(v) as Map<String, dynamic>);
  } catch (_) {
    return const AutoBackup();
  }
}

Future<void> saveAutoBackup(Repo r, AutoBackup a) => r.kvSet('auto_backup', jsonEncode(a.toJson()));

Future<BackupStatus> loadBackupStatus(Repo r) async {
  try {
    final v = await r.kvGet('backup_status');
    return v == null ? const BackupStatus() : BackupStatus.fromJson(jsonDecode(v) as Map<String, dynamic>);
  } catch (_) {
    return const BackupStatus();
  }
}

/// A backup that worked (by hand: [where] "a file you saved").
Future<void> noteBackup(Repo r, String where, {DateTime? at}) => r.kvSet('backup_status', jsonEncode(BackupStatus(last: at ?? DateTime.now(), where: where).toJson()));

/// The only names the app ever touches in the backup folder, the same rule as AUTO_NAME in
/// MainActivity.kt (review 7, P1-1): nothing that merely starts with "fightmilk-auto-".
final autoNamePattern = RegExp(r'^fightmilk-auto-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})(\.locked)?( \((\d+)\))?\.json$');

/// A real backup is at least this big; an empty or cut-short file is never counted as one.
const autoMinBytes = 1024;

/// The first bytes are those of one of our backups: the plain file or the lock envelope.
bool autoHeadOk(Uint8List? b) {
  if (b == null || b.isEmpty) return false;
  final s = utf8.decode(b, allowMalformed: true).replaceAll(RegExp(r'\s'), '');
  return (s.startsWith('{"format":') && s.contains('"app":"workout"')) || s.startsWith('{"fightmilk":"backup-locked"');
}

/// The time in one of our names, and the folder's " (n)" for two in the same second; null = not ours.
(DateTime, int)? autoNameTime(String name) {
  final m = autoNamePattern.firstMatch(name);
  if (m == null) return null;
  final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  final d = DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  if (d.year != v[0] || d.month != v[1] || d.day != v[2] || d.hour != v[3] || d.minute != v[4] || d.second != v[5]) return null;
  return (d, m.group(9) == null ? 0 : int.parse(m.group(9)!));
}

String autoName(DateTime d, {bool locked = false}) {
  String p(int v) => v.toString().padLeft(2, '0');
  return 'fightmilk-auto-${d.year}-${p(d.month)}-${p(d.day)}-${p(d.hour)}${p(d.minute)}${p(d.second)}${locked ? '.locked' : ''}.json';
}

/// Writes one automatic backup into the folder and keeps the newest [AutoBackup.keep] of ours.
/// Never throws: a problem is kept in the status for the status line.
Future<Uint8List?> _head(BackupFolder f, String tree, String id) async {
  try {
    return await f.head(tree, id, 64);
  } catch (_) {
    return null;
  }
}

const _folderFull = 'The backup folder is full or would not take the file. Free some space, or pick another folder in Settings → Backup.';
const _folderTrouble = 'The backup folder would not take the file. Try "Back up now", or pick the folder again in Settings → Backup.';

Future<bool> runAutoBackup(Repo r, BackupFolder f, AutoBackup a, {String? password, DateTime? now}) async {
  final t = now ?? DateTime.now();
  final prev = await loadBackupStatus(r);
  Future<bool> fail(String why) async {
    await r.kvSet('backup_status', jsonEncode(BackupStatus(last: prev.last, where: prev.where, problem: why, lastTry: t).toJson()));
    return false;
  }

  if (a.tree == null) return fail('No backup folder is picked. Pick one in Settings → Backup.');
  try {
    if (!await f.ok(a.tree!)) return await fail('The backup folder can no longer be reached. Pick it again in Settings → Backup.');
    if (a.locked && (password == null || password.isEmpty)) return await fail('The backup password is missing. Set it again in Settings → Backup.');
    final plain = await exportBackup(r, body: a.body);
    final text = a.locked ? await lockBackup(plain, password!) : plain;
    final bytes = Uint8List.fromList(utf8.encode(text));
    final written = await f.write(a.tree!, autoName(t, locked: a.locked), bytes);
    // the file must be there, whole, before anything older goes (review 7, P1-2)
    final mine = (await f.list(a.tree!)) ?? const [];
    final it = mine.where((x) => x.$2 == written).firstOrNull;
    if (it == null || (it.$4 >= 0 && it.$4 != bytes.length)) return await fail(_folderTrouble);
    // keep the newest N real backups of ours; nothing else in the folder is ever touched (review 7, P1-1)
    // a real backup: our exact name, and at least 1 kB; where the folder does not say the size,
    // its first bytes must be ours (it is then neither counted nor ever deleted otherwise)
    final good = <(String, String, int, int)>[];
    for (final x in mine) {
      if (autoNameTime(x.$2) == null) continue;
      if (x.$2 == written || x.$4 >= autoMinBytes || (x.$4 < 0 && autoHeadOk(await _head(f, a.tree!, x.$1)))) good.add(x);
    }
    good.sort((x, y) {
        final (tx, nx) = autoNameTime(x.$2)!;
        final (ty, ny) = autoNameTime(y.$2)!;
        final c = ty.compareTo(tx); // the date in the name, newest first
        if (c != 0) return c;
        return nx != ny ? ny.compareTo(nx) : y.$3.compareTo(x.$3);
      });
    if (good.length > a.keep) {
      for (final old in good.skip(a.keep)) {
        if (old.$2 != written) await f.delete(a.tree!, old.$1, old.$2);
      }
    }
    await noteBackup(r, 'your backup folder${a.folderName.isEmpty ? '' : ' (${a.folderName})'}', at: t);
    return true;
  } on BackupError catch (e) {
    return fail(e.message);
  } on PlatformException catch (e) {
    return fail(e.code == 'full' || '${e.message}'.contains('ENOSPC') || '${e.message}'.contains('No space') ? _folderFull : _folderTrouble);
  } catch (_) {
    return fail(_folderTrouble);
  }
}
