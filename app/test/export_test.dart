import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/export.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/export_screen.dart';
import 'package:workout/ui/share_card.dart';
import 'package:workout/domain/reports.dart';
import 'package:workout/domain/stats.dart';
import 'package:workout/ui/theme.dart';

/// Batch 20 (F310-F320) and the hard rule from review 4: no progress photo, photo file, photo path
/// or photo list in any export, share, backup or AI request, ever.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  // a byte run no export could make by chance: stands for the photo's pixels
  final marker = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...utf8.encode('FM-PHOTO-PIXELS-7731'), 0x00, 0x13]);

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('export20');
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full.copyWith(bodyKg: 82, heightCm: 183.7));
    await s.makeBuiltInPlan();
    final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
    await s.repo.logSet(ses.id, 'back_squat', 100, 5);
    await s.repo.logSet(ses.id, 'back_squat', 102.5, 5, note: 'felt good');
    await s.repo.logSet(ses.id, 'plank', 0, 60);
    await s.repo.finishSession(ses.id, s.lib, s.unit);
    await s.repo.logBody(81.7, fat: 17.3);
    await s.addTape('waist', 86.4);
    AppState.clearPicked = () async {};
    await s.addPhoto(marker);
    await s.reload();
    return s;
  }

  /// Every file inside an export: the export itself, or each member of a zip.
  List<Uint8List> parts(ExportFile f) {
    if (!f.name.endsWith('.zip') && !f.name.endsWith('.xlsx')) return [f.bytes]; // an .xlsx is a zip too
    return [for (final m in ZipDecoder().decodeBytes(f.bytes).files) if (m.isFile) Uint8List.fromList(m.content as List<int>)];
  }

  bool has(Uint8List hay, List<int> needle) {
    outer:
    for (var i = 0; i + needle.length <= hay.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  test('no export holds a progress photo, its file name, its path or the photo list', () async {
    final s = await app();
    final ph = s.photos.single;
    final id = ph['id'] as String;
    expect(File(s.photoPath(ph)).readAsBytesSync(), marker);
    for (final k in ExportKind.values) {
      for (final body in [true, false]) {
        final f = await buildExport(k, s.repo, lib, ExportOptions(unit: Unit.kg, body: body), tape: [for (final t in s.tape) t.toJson()], factory: databaseFactoryFfi);
        expect(f.bytes, isNotEmpty, reason: '$k');
        for (final p in parts(f)) {
          final why = '$k (body $body) in ${f.name}';
          expect(has(p, marker.sublist(4, 24)), isFalse, reason: '$why: photo pixels');
          expect(has(p, utf8.encode(id)), isFalse, reason: '$why: photo id');
          expect(has(p, utf8.encode('.img')), isFalse, reason: '$why: photo file name');
          expect(has(p, utf8.encode(s.photoDir)), isFalse, reason: '$why: photo folder');
          expect(has(p, utf8.encode('${Platform.pathSeparator}photos')), isFalse, reason: '$why: photo folder name');
          if (k == ExportKind.sqlite || k == ExportKind.backup) {
            expect(has(p, utf8.encode('photos')), isFalse, reason: '$why: the photo list row');
          }
        }
      }
    }
    // the photo is still on the phone, untouched
    expect(File(s.photoPath(ph)).readAsBytesSync(), marker);
  });

  test('the AI request never holds a photo', () async {
    final s = await app();
    final ctx = await s.bodyContext();
    expect(ctx, isNot(contains(s.photos.single['id'] as String)));
    expect(ctx.toLowerCase(), isNot(contains('photo')));
  });

  test('body data goes in only when asked for', () async {
    final s = await app();
    final tape = [for (final t in s.tape) t.toJson()];
    Future<String> text(ExportKind k, bool body) async {
      final f = await buildExport(k, s.repo, lib, ExportOptions(unit: Unit.kg, body: body), tape: tape, factory: databaseFactoryFfi);
      return parts(f).map((p) => latin1.decode(p)).join('\n');
    }

    for (final k in bodyKinds) {
      final no = await text(k, false);
      expect(no, isNot(contains('81.7')), reason: '$k weigh-in');
      expect(no, isNot(contains('17.3')), reason: '$k body fat');
      expect(no, isNot(contains('86.4')), reason: '$k tape');
      expect(no, isNot(contains('183.7')), reason: '$k height');
    }
    final yes = await text(ExportKind.bodyCsv, true);
    expect(yes, contains('"body weight","","","81.7","kg"'));
    expect(yes, contains('"body fat","","","17.3","%"'));
    expect(yes, contains('"tape","waist","","86.4","cm"'));
    expect(await text(ExportKind.bodyCsv, false), '"date","what","part","side","value","unit"\r\n');
    for (final k in ExportKind.values.where((k) => !bodyKinds.contains(k))) {
      expect(await text(k, true), isNot(contains('81.7')), reason: '$k needs no question: no body data in it');
    }
  });

  test('the set formats carry the sets, in the unit asked for', () async {
    final s = await app();
    Future<String> t(ExportKind k, {Unit u = Unit.kg}) async => utf8.decode((await buildExport(k, s.repo, lib, ExportOptions(unit: u))).bytes);
    expect(await t(ExportKind.strong), contains('"Back squat","2","102.5","5"'));
    final hevy = await t(ExportKind.hevy, u: Unit.lb);
    expect(hevy, startsWith('"title","start_time","end_time","description","exercise_title"'));
    expect(hevy, contains('"weight_lbs"'));
    expect(hevy, contains('"225.97"'));
    final fit = await t(ExportKind.fitnotes);
    expect(fit, contains('"Weight (kgs)"'));
    expect(fit, contains('"00:01:00"'), reason: 'the plank as a time');
    expect(await t(ExportKind.liftosaur), contains('"Completed Weight Value"'));
    final all = await t(ExportKind.everything);
    expect(all, contains('"felt good"'));
    expect(all, contains('"102.5","225.97"'));
    final md = await t(ExportKind.text);
    expect(md, contains('- Back squat: 100 kg × 5, 102.5 kg × 5'));
    expect(md, contains('- Plank: 60 s'));
    final tcx = await t(ExportKind.tcx);
    expect(tcx, contains('<Activity Sport="Other">'));
    expect(tcx, contains('Back squat: 100 kg × 5'));
    expect(await t(ExportKind.plansCsv), contains('"yes"'));
    expect(await t(ExportKind.recordsCsv), contains('"Back squat","Heaviest","102.5","kg"'));
  });

  test('dates limit the sets and the body rows', () async {
    final s = await app();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final f = await buildExport(ExportKind.strong, s.repo, lib, ExportOptions(unit: Unit.kg, from: tomorrow));
    expect(utf8.decode(f.bytes).trim().split('\r\n'), hasLength(1), reason: 'header only');
    final today = await buildExport(ExportKind.strong, s.repo, lib, ExportOptions(unit: Unit.kg, from: DateTime.now(), to: DateTime.now()));
    expect(utf8.decode(today.bytes), contains('Back squat'));
  });

  test('the SQLite copy opens and has the workouts', () async {
    final s = await app();
    final f = await buildExport(ExportKind.sqlite, s.repo, lib, const ExportOptions(unit: Unit.kg, body: true), factory: databaseFactoryFfi);
    final p = '${Directory.systemTemp.createTempSync('sq').path}/x.sqlite';
    File(p).writeAsBytesSync(f.bytes);
    final db = await databaseFactoryFfi.openDatabase(p);
    expect((await db.query('set_log')).length, 3);
    expect(await db.query('kv', where: 'k = ?', whereArgs: ['photos']), isEmpty);
    expect((await db.query('body')).length, 1);
    await db.close();
  });

  testWidgets('the Export screen asks about body data once, only when the format can hold it', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('exportui');
      final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(full);
      await s.makeBuiltInPlan();
      return s;
    });
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ExportScreen(s: s!)));
    await settle();
    expect(find.textContaining('Progress photos are never in any file'), findsOneWidget);
    // Strong CSV: no body data in it, so no question
    await tester.tap(find.text('Save file'));
    await settle();
    expect(find.text('Put your body data in this file?'), findsNothing);
    // the backup can hold it: asked, in plain words, once
    await tester.tap(find.text(exportLabel[ExportKind.backup]!));
    await settle();
    expect(find.text('Dates'), findsNothing, reason: 'a backup is the whole file');
    await tester.tap(find.text('Save file'));
    await settle();
    expect(find.text('Put your body data in this file?'), findsOneWidget);
    expect(find.textContaining('weigh-ins, body fat, tape measurements, height, body-weight goal'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('bodyYes'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('bodyNo'))).dy), reason: 'a backup is for you: Put it in first (review 5, P1-3)');
    await tester.tap(find.byKey(const Key('bodyNo')));
    await settle();
    expect(find.text('Put your body data in this file?'), findsNothing);
  });

  test('the AI export tool only picks what the screen shows', () async {
    final s = await app();
    final r = parseToolReply('SAY: ok\nDO: export hevy', s);
    expect(r.errors, isEmpty);
    await r.actions.single.run(s);
    expect(s.exportPreset, ExportKind.hevy);
    expect(parseToolReply('SAY: x\nDO: export photos', s).errors, isNotEmpty);
    expect(toolGrammar(s.lib, s.profile!, s.plan!.days.length), contains('"export " ("strong"'));
  });

  test('F316 the Excel file has its sheets, with numbers as numbers', () async {
    final s = await app();
    final f = await buildExport(ExportKind.xlsx, s.repo, lib, const ExportOptions(unit: Unit.kg, body: true), tape: [for (final t in s.tape) t.toJson()]);
    final z = ZipDecoder().decodeBytes(f.bytes);
    final names = [for (final m in z.files) m.name];
    expect(names, containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet5.xml']));
    final wb = utf8.decode(z.findFile('xl/workbook.xml')!.content as List<int>);
    expect(wb, contains('name="Workouts"'));
    expect(wb, contains('name="Body"'));
    final sets = utf8.decode(z.findFile('xl/worksheets/sheet2.xml')!.content as List<int>);
    expect(sets, contains('<v>102.5</v>'));
    expect(sets, contains('<t xml:space="preserve">Back squat</t>'));
    final noBody = await buildExport(ExportKind.xlsx, s.repo, lib, const ExportOptions(unit: Unit.kg));
    expect(utf8.decode(ZipDecoder().decodeBytes(noBody.bytes).findFile('xl/workbook.xml')!.content as List<int>), isNot(contains('Body')));
  });

  test('F317 and F328 the PDFs are whole files with the right pages', () async {
    final s = await app();
    void valid(Uint8List b) {
      final t = latin1.decode(b);
      expect(t, startsWith('%PDF-1.4'));
      expect(t.trimRight(), endsWith('%%EOF'));
      final xref = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(t)!.group(1)!);
      expect(t.substring(xref, xref + 4), 'xref');
      for (final m in RegExp(r'^(\d{10}) 00000 n $', multiLine: true).allMatches(t)) {
        expect(t.substring(int.parse(m.group(1)!)), matches(RegExp(r'^\d+ 0 obj')));
      }
    }

    final rep = await buildExport(ExportKind.pdf, s.repo, lib, const ExportOptions(unit: Unit.kg));
    valid(rep.bytes);
    final txt = latin1.decode(rep.bytes);
    expect(txt, contains('(FightMilk report)'));
    expect(txt, contains('(Back squat)'));
    expect(txt, isNot(contains('Body weight')), reason: 'no body data unless asked');
    final withBody = latin1.decode((await buildExport(ExportKind.pdf, s.repo, lib, const ExportOptions(unit: Unit.kg, body: true))).bytes);
    expect(withBody, contains('Est. 1-rep max'));
    final plan = planPdf(s.plan!, lib);
    valid(plan);
    expect(RegExp(r'/Type /Page ').allMatches(latin1.decode(plan)).length, 4, reason: 'a page per week');
    expect(latin1.decode(plan), contains('week 1'));
  });

  testWidgets('F322 share pictures: words and numbers only, never a photo, body numbers only when asked', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(app))!;
    final id = s.photos.single['id'] as String;
    final ses = (await tester.runAsync(() => s.repo.db.query('session')))!.first;
    final sets = (await tester.runAsync(() => s.repo.setsFor(ses['id'] as String)))!;
    final sq = lib.byId('back_squat')!;
    final squats = (await tester.runAsync(() => s.repo.setsOf('back_squat')))!;
    final rec = currentRecords(recordHistory(squats, sq))[RecordKind.heaviest]!;
    final report = Report(DateTime(2026, 11, 1), DateTime(2026, 12, 1), workouts: 3, sets: 30, volume: 9000, records: 2, bodyChange: -1.4);
    final cards = <String, CardData>{
      'workout': workoutCard('Upper A', DateTime(2026, 11, 20, 18), DateTime(2026, 11, 20, 19), sets, lib, Unit.kg, records: 1),
      'record': recordCard(sq, rec, Unit.kg),
      'recap': recapCard('November', report, Unit.kg),
      'recap+body': recapCard('November', report, Unit.kg, body: true),
      'chart': chartCard(sq, [Pt(DateTime(2026, 10, 1), 110, ''), Pt(DateTime(2026, 11, 1), 117.5, '')], Unit.kg),
    };
    expect(cards['workout']!.text, contains('Back squat: 2 × 102.5 kg × 5'));
    expect(cards['record']!.text, contains('102.5 kg'));
    expect(cards['recap']!.text, isNot(contains('Body weight')), reason: 'body numbers only when asked');
    expect(cards['recap+body']!.text, contains('Body weight −1.4 kg'));
    for (final c in cards.entries) {
      expect(c.value.text, isNot(contains('81.7')), reason: '${c.key}: no weigh-in');
      expect(c.value.text, isNot(contains('17.3')), reason: '${c.key}: no body fat');
      expect(c.value.text, isNot(contains(id)), reason: '${c.key}: no photo');
      for (final style in CardStyle.values) {
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(home: Center(child: RepaintBoundary(key: key, child: ShareCard(c.value, style: style)))));
        await tester.pump();
        expect(find.byType(Image), findsNothing, reason: '${c.key}: a card draws no picture of any kind');
        final png = (await tester.runAsync(() => cardPng(key, ratio: 1)))!;
        expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: '${c.key} ${style.name}: a PNG');
        expect(has(png, utf8.encode(id)), isFalse);
        expect(has(png, utf8.encode(s.photoDir)), isFalse);
        expect(has(png, marker.sublist(4, 24)), isFalse);
      }
    }
  });
}
