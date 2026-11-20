import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/exercise.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/progression.dart';
import '../domain/units.dart';

/// One workout. [day] is the day as actually worked (today-only swaps and AI tweaks live here,
/// not in the plan).
class Session {
  final String id;
  final String planId;
  final int dayIndex;
  final PlanDay day;
  final DateTime started;
  final DateTime? finished;
  final String note;

  const Session({required this.id, required this.planId, required this.dayIndex, required this.day, required this.started, this.finished, this.note = ''});

  Map<String, dynamic> toRow() => {
        'id': id,
        'plan_id': planId,
        'day_index': dayIndex,
        'day': jsonEncode(day.toJson()),
        'started': started.millisecondsSinceEpoch,
        'finished': finished?.millisecondsSinceEpoch,
        'note': note,
      };

  factory Session.fromRow(Map<String, Object?> r) => Session(
        id: r['id'] as String,
        planId: r['plan_id'] as String,
        dayIndex: r['day_index'] as int,
        day: PlanDay.fromJson(jsonDecode(r['day'] as String) as Map<String, dynamic>),
        started: DateTime.fromMillisecondsSinceEpoch(r['started'] as int),
        finished: r['finished'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['finished'] as int),
        note: (r['note'] ?? '') as String,
      );
}

/// Everything the app stores, on the phone only. One SQLite file.
class Repo {
  final Database db;
  static const _uuid = Uuid();

  Repo._(this.db);

  static Future<Repo> open(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            await db.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
            await db.execute('CREATE TABLE plan (id TEXT PRIMARY KEY, json TEXT NOT NULL, active INTEGER NOT NULL, created INTEGER NOT NULL)');
            await db.execute('CREATE TABLE lift_state (exercise_id TEXT PRIMARY KEY, json TEXT NOT NULL)');
            await db.execute('CREATE TABLE session (id TEXT PRIMARY KEY, plan_id TEXT NOT NULL, day_index INTEGER NOT NULL, day TEXT NOT NULL, '
                'started INTEGER NOT NULL, finished INTEGER, note TEXT NOT NULL DEFAULT "")');
            await db.execute('CREATE TABLE set_log (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, exercise_id TEXT NOT NULL, kg REAL NOT NULL, '
                'reps INTEGER NOT NULL, ord INTEGER NOT NULL, at INTEGER NOT NULL)');
            await db.execute('CREATE INDEX set_by_session ON set_log(session_id)');
            await db.execute('CREATE INDEX set_by_ex ON set_log(exercise_id)');
          },
        ));
    return Repo._(db);
  }

  Future<void> close() => db.close();

  // ---- key/value ----
  Future<String?> kvGet(String k) async {
    final r = await db.query('kv', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String;
  }

  Future<void> kvSet(String k, String v) => db.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- profile ----
  Future<Profile?> profile() async {
    final s = await kvGet('profile');
    return s == null ? null : Profile.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> saveProfile(Profile p) => kvSet('profile', jsonEncode(p.toJson()));

  // ---- plans ----
  Future<Plan?> activePlan() async {
    final r = await db.query('plan', where: 'active = 1', limit: 1);
    return r.isEmpty ? null : Plan.fromJson(jsonDecode(r.first['json'] as String) as Map<String, dynamic>);
  }

  /// Saves (insert or replace). With [makeActive] the previous active plan is kept as an old plan.
  Future<void> savePlan(Plan p, {bool makeActive = true}) async {
    await db.transaction((t) async {
      if (makeActive) await t.update('plan', {'active': 0});
      final existing = await t.query('plan', columns: ['active'], where: 'id = ?', whereArgs: [p.id]);
      final active = makeActive ? 1 : (existing.isEmpty ? 0 : existing.first['active'] as int);
      await t.insert('plan', {'id': p.id, 'json': jsonEncode(p.toJson()), 'active': active, 'created': p.created.millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Plan>> oldPlans() async {
    final r = await db.query('plan', where: 'active = 0', orderBy: 'created DESC');
    return [for (final x in r) Plan.fromJson(jsonDecode(x['json'] as String) as Map<String, dynamic>)];
  }

  Future<void> restorePlan(String id) => db.transaction((t) async {
        await t.update('plan', {'active': 0});
        await t.update('plan', {'active': 1}, where: 'id = ?', whereArgs: [id]);
      });

  Future<void> deletePlan(String id) => db.delete('plan', where: 'id = ? AND active = 0', whereArgs: [id]);

  Future<int?> lastDayIndex(String planId) async {
    final s = await kvGet('last_day:$planId');
    return s == null ? null : int.parse(s);
  }

  Future<void> setLastDayIndex(String planId, int i) => kvSet('last_day:$planId', '$i');

  // ---- sessions ----
  Future<Session?> openSession() async {
    final r = await db.query('session', where: 'finished IS NULL', orderBy: 'started DESC', limit: 1);
    return r.isEmpty ? null : Session.fromRow(r.first);
  }

  Future<Session> startSession(Plan plan, int dayIndex, PlanDay day) async {
    final s = Session(id: _uuid.v4(), planId: plan.id, dayIndex: dayIndex, day: day, started: DateTime.now());
    await db.insert('session', s.toRow());
    return s;
  }

  Future<void> updateSessionDay(String id, PlanDay day) => db.update('session', {'day': jsonEncode(day.toJson())}, where: 'id = ?', whereArgs: [id]);

  Future<void> setSessionNote(String id, String note) => db.update('session', {'note': note}, where: 'id = ?', whereArgs: [id]);

  Future<Session?> session(String id) async {
    final r = await db.query('session', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Session.fromRow(r.first);
  }

  Future<void> discardSession(String id) => db.transaction((t) async {
        await t.delete('set_log', where: 'session_id = ?', whereArgs: [id]);
        await t.delete('session', where: 'id = ?', whereArgs: [id]);
      });

  /// Ends a workout: applies progression to each exercise done and moves the rotation on.
  /// A workout with no sets is thrown away and the rotation stays where it was.
  Future<void> finishSession(String id, Library lib, Unit unit) async {
    final s = await session(id);
    if (s == null || s.finished != null) return; // finishing twice changes nothing
    final sets = await setsFor(id);
    if (sets.isEmpty) {
      await discardSession(id);
      return;
    }
    final byEx = <String, List<SetLog>>{};
    for (final x in sets) {
      (byEx[x.exerciseId] ??= []).add(x);
    }
    final updates = <LiftState>[];
    for (final entry in byEx.entries) {
      final e = lib.byId(entry.key);
      if (e == null) continue;
      final item = s.day.items.where((i) => i.exerciseId == e.id).firstOrNull;
      final prev = await lift(e.id) ??
          LiftState(exerciseId: e.id, workKg: entry.value.map((x) => x.kg).reduce((a, b) => a > b ? a : b), workReps: e.bodyweight ? (item?.repLow ?? e.repLow) : null);
      updates.add(nextLift(prev, e, entry.value, unit, repLow: item?.repLow, repHigh: item?.repHigh));
    }
    // all or nothing: a kill half-way can't progress some lifts and leave the workout open
    await db.transaction((t) async {
      for (final u in updates) {
        await t.insert('lift_state', {'exercise_id': u.exerciseId, 'json': jsonEncode(u.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await t.update('session', {'finished': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
      await t.insert('kv', {'k': 'last_day:${s.planId}', 'v': '${s.dayIndex}'}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Session>> history({int limit = 500}) async {
    final r = await db.query('session', where: 'finished IS NOT NULL', orderBy: 'started DESC', limit: limit);
    return [for (final x in r) Session.fromRow(x)];
  }

  Future<void> deleteSession(String id) => discardSession(id);

  // ---- sets ----
  Future<SetLog> logSet(String sessionId, String exerciseId, double kg, int reps) async {
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(MAX(ord), -1) + 1 FROM set_log WHERE session_id = ?', [sessionId])) ?? 0;
    final s = SetLog(id: _uuid.v4(), sessionId: sessionId, exerciseId: exerciseId, kg: kg, reps: reps, ord: n, at: DateTime.now());
    await db.insert('set_log', {...s.toJson(), 'at': s.at!.millisecondsSinceEpoch});
    return s;
  }

  Future<void> updateSet(String id, double kg, int reps) => db.update('set_log', {'kg': kg, 'reps': reps}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteSet(String id) => db.delete('set_log', where: 'id = ?', whereArgs: [id]);

  Future<List<SetLog>> setsFor(String sessionId) async {
    final r = await db.query('set_log', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'ord');
    return [for (final x in r) SetLog.fromJson(x)];
  }

  /// All finished sets of one exercise, oldest first.
  Future<List<SetLog>> setsOf(String exerciseId) async {
    final r = await db.rawQuery(
        'SELECT s.* FROM set_log s JOIN session w ON w.id = s.session_id WHERE s.exercise_id = ? AND w.finished IS NOT NULL ORDER BY s.at',
        [exerciseId]);
    return [for (final x in r) SetLog.fromJson(x)];
  }

  /// Finished sets since [since], oldest first (for weekly totals and the AI's "last 2 weeks").
  Future<List<SetLog>> setsSince(DateTime since) async {
    final r = await db.rawQuery(
        'SELECT s.* FROM set_log s JOIN session w ON w.id = s.session_id WHERE s.at >= ? AND w.finished IS NOT NULL ORDER BY s.at',
        [since.millisecondsSinceEpoch]);
    return [for (final x in r) SetLog.fromJson(x)];
  }

  /// Exercise ids that have any finished sets.
  Future<List<String>> loggedExercises() async {
    final r = await db.rawQuery('SELECT s.exercise_id, COUNT(*) n FROM set_log s JOIN session w ON w.id = s.session_id '
        'WHERE w.finished IS NOT NULL GROUP BY s.exercise_id ORDER BY n DESC');
    return [for (final x in r) x['exercise_id'] as String];
  }

  /// The previous finished session's sets of an exercise ("last time").
  Future<List<SetLog>> lastTime(String exerciseId, {String? notSession}) async {
    final r = await db.rawQuery(
        'SELECT s.session_id FROM set_log s JOIN session w ON w.id = s.session_id WHERE s.exercise_id = ? AND w.finished IS NOT NULL '
        'AND s.session_id != ? ORDER BY s.at DESC LIMIT 1',
        [exerciseId, notSession ?? '']);
    if (r.isEmpty) return [];
    final sid = r.first['session_id'] as String;
    return [for (final x in await setsFor(sid)) if (x.exerciseId == exerciseId) x];
  }

  /// Works the lift state out again from all finished workouts (after a set or workout in
  /// history was changed or deleted).
  Future<void> rebuildLifts(Iterable<String> exerciseIds, Library lib, Unit unit) async {
    for (final id in exerciseIds.toSet()) {
      final e = lib.byId(id);
      await db.delete('lift_state', where: 'exercise_id = ?', whereArgs: [id]);
      if (e == null) continue;
      final rows = await db.rawQuery(
          'SELECT DISTINCT w.* FROM session w JOIN set_log s ON s.session_id = w.id WHERE s.exercise_id = ? AND w.finished IS NOT NULL ORDER BY w.started',
          [id]);
      LiftState? st;
      for (final row in rows) {
        final ses = Session.fromRow(row);
        final sets = [for (final x in await setsFor(ses.id)) if (x.exerciseId == id) x];
        if (sets.isEmpty) continue;
        final item = ses.day.items.where((i) => i.exerciseId == id).firstOrNull;
        st ??= LiftState(exerciseId: id, workKg: sets.map((x) => x.kg).reduce((a, b) => a > b ? a : b), workReps: e.bodyweight ? (item?.repLow ?? e.repLow) : null);
        st = nextLift(st, e, sets, unit, repLow: item?.repLow, repHigh: item?.repHigh);
      }
      if (st != null) await saveLift(st);
    }
  }

  Future<void> setSessionDayIndex(String id, int i) => db.update('session', {'day_index': i}, where: 'id = ?', whereArgs: [id]);

  // ---- lift state ----
  Future<LiftState?> lift(String exerciseId) async {
    final r = await db.query('lift_state', where: 'exercise_id = ?', whereArgs: [exerciseId]);
    return r.isEmpty ? null : LiftState.fromJson(jsonDecode(r.first['json'] as String) as Map<String, dynamic>);
  }

  Future<void> saveLift(LiftState s) =>
      db.insert('lift_state', {'exercise_id': s.exerciseId, 'json': jsonEncode(s.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<LiftState>> allLifts() async => [
        for (final x in await db.query('lift_state')) LiftState.fromJson(jsonDecode(x['json'] as String) as Map<String, dynamic>)
      ];

  // ---- everything ----
  Future<void> wipe() => db.transaction((t) async {
        for (final tb in ['kv', 'plan', 'lift_state', 'session', 'set_log']) {
          await t.delete(tb);
        }
      });
}
