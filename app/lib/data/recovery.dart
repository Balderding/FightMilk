import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'backup.dart';
import 'repo.dart';

/// F431: when the app cannot open or read its data at start. The original file is never written:
/// a copy is made in the app's own private folder, the copy is opened (with the normal upgrade),
/// and a normal backup is made from it, so the photo list and this phone's own rows stay out and
/// body data only goes in when the person says yes (the backup's allow-list does this).

/// Why the app could not start, in plain words, with where its data is.
class StartFailure implements Exception {
  final String path; // the database file
  final String stage; // 'data' or 'library'
  final Object error;
  StartFailure(this.path, this.error, {this.stage = 'data'});

  String get reason => stage == 'library' ? "The app's own exercise list could not be read. Installing the app again over itself keeps your data." : plainReason(error);

  @override
  String toString() => 'StartFailure($stage): ${error.runtimeType}';
}

/// What went wrong with the data file, in plain words (never the database's own text).
String plainReason(Object e) {
  final t = e.toString().toLowerCase();
  if (t.contains('enospc') || t.contains('no space') || t.contains('sqlite_full') || t.contains('disk is full') || t.contains('database or disk is full')) {
    return "The phone's storage is full. Free some space, then tap Try again.";
  }
  if (t.contains('malformed') || t.contains('not a database') || t.contains('corrupt')) return 'The data file is damaged.';
  if (t.contains('locked') || t.contains('busy')) return 'The data file is in use. Close the app fully, then open it again.';
  if (t.contains('readonly') || t.contains('permission') || t.contains('denied')) return 'The app was not allowed to read its data file.';
  return 'The data file could not be read.';
}

const _tmpName = 'recovery_tmp';

/// The private folder a recovery copy is made in.
Directory recoveryDir(Directory appSupport) => Directory(p.join(appSupport.path, _tmpName));

/// A copy left over from a recovery the app was killed in the middle of: removed at start.
void cleanRecoveryLeftovers(Directory appSupport) {
  try {
    final d = recoveryDir(appSupport);
    if (d.existsSync()) d.deleteSync(recursive: true);
  } catch (_) {}
}

/// The person's data as a normal backup, made from a private copy of [dbPath] (with its -wal,
/// -shm and -journal files, so the newest workouts come too). [body]: the person's answer.
/// Throws [StartFailure] (with the plain reason) when even the copy cannot be made or opened.
Future<String> recoveryBackup(String dbPath, Directory appSupport, {required bool body, DatabaseFactory? factory}) async {
  final tmp = recoveryDir(appSupport);
  try {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    final copy = p.join(tmp.path, 'workout.db');
    try {
      for (final ext in ['', '-wal', '-shm', '-journal']) {
        final f = File('$dbPath$ext');
        if (f.existsSync()) f.copySync('$copy$ext');
      }
    } catch (e) {
      throw StartFailure(dbPath, e);
    }
    Repo repo;
    try {
      repo = await Repo.open(copy, factory: factory); // the normal upgrade runs on the copy
    } catch (e) {
      throw StartFailure(dbPath, e);
    }
    try {
      return await exportBackup(repo, body: body);
    } catch (e) {
      throw StartFailure(dbPath, e);
    } finally {
      await repo.close();
    }
  } finally {
    cleanRecoveryLeftovers(appSupport);
  }
}
