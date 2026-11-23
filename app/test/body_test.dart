import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/body.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/stats.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/body_screen.dart';
import 'package:workout/ui/theme.dart';

/// Batch 19 (F299-F309): body weight, body fat, tape, photos, weigh-in reminder, strength scores.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<AppState> app({DatabaseFactory? f}) async {
    final dir = Directory.systemTemp.createTempSync('body19');
    final r = await Repo.open('${dir.path}/t.db', factory: f ?? databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  group('numbers', () {
    test('the 7-day average smooths daily swings', () {
      final d = DateTime(2026, 11, 1);
      final l = [for (var i = 0; i < 10; i++) Pt(d.add(Duration(days: i)), i.isEven ? 80 : 82, '')];
      final a = sevenDayAverage(l);
      expect(a.first, 80);
      expect(a.last, closeTo(81, 0.2));
    });

    test('review 4 P2-4: no rate from a few days of water; a steady loss reads right', () {
      final d = DateTime(2026, 11, 1, 7);
      final water = [Pt(d, 80, ''), Pt(d.add(const Duration(days: 1)), 80.8, ''), Pt(d.add(const Duration(days: 2)), 81.2, '')];
      expect(ratePerWeek(water), isNull);
      final four = [for (var i = 0; i < 4; i++) Pt(d.add(Duration(days: i)), 80 + i * 0.3, '')];
      expect(ratePerWeek(four), isNull, reason: 'under 14 days');
      final steady = [for (var i = 0; i < 28; i++) Pt(d.add(Duration(days: i)), 90 - i * 0.5 / 7 + (i.isEven ? 0.6 : -0.6), '')];
      expect(ratePerWeek(steady), closeTo(-0.5, 0.05));
      expect(showSevenDay([Pt(d, 80, '')], d), isFalse);
      expect(showSevenDay([Pt(d, 80, ''), Pt(d.add(const Duration(days: 2)), 80, '')], d.add(const Duration(days: 3))), isTrue);
    });

    test('BMI, lean mass and FFMI', () {
      expect(bmi(80, 180), closeTo(24.7, 0.05));
      expect(leanMass(80, 20), 64);
      expect(ffmi(80, 20, 180), closeTo(19.75, 0.05));
    });

    test('DOTS, Wilks and IPF GL land near the published values', () {
      // 600 kg at 90 kg (men), worked by hand from the formulas: DOTS 388.0, Wilks 383.0, IPF GL 79.8
      expect(dots(600, 90, female: false), closeTo(388.0, 0.5));
      expect(wilks(600, 90, female: false), closeTo(383.0, 0.5));
      expect(ipfGl(600, 90, female: false), closeTo(79.8, 0.3));
      expect(dots(400, 60, female: true), greaterThan(dots(400, 60, female: false)));
    });

    test('levels, the next level and the 0-100 score', () {
      final (lvl, next, part) = strengthLevelOf('back_squat', 120, 80, female: false);
      expect(levelNames5[lvl], 'Intermediate'); // 1.5x = intermediate
      expect(next, 160);
      expect(part, 0);
      expect(strengthLevelOf('deadlift', 300, 80, female: false).$2, isNull); // past Elite
      expect(strengthLevelOf('back_squat', 30, 80, female: false).$1, -1);
      expect(strengthScore({'back_squat': 120}, 80, female: false), 60);
      expect(strengthScore({'deadlift': 300}, 80, female: false), 100);
    });

    test('a lagging lift is named, a balanced pair is not', () {
      final lag = laggingLifts({'back_squat': 150, 'bench_press': 80});
      expect(lag.single.$1, 'bench_press');
      expect(laggingLifts({'back_squat': 150, 'bench_press': 112}), isEmpty);
      // a weak squat next to a big bench: squat is the one named
      expect(laggingLifts({'back_squat': 100, 'bench_press': 120}).single.$1, 'back_squat');
    });

    test('the total by month carries a lift forward and starts when all three are there', () {
      final pts = {
        'back_squat': [Pt(DateTime(2026, 1, 5), 100, ''), Pt(DateTime(2026, 3, 5), 120, '')],
        'bench_press': [Pt(DateTime(2026, 2, 5), 80, '')],
        'deadlift': [Pt(DateTime(2026, 2, 6), 140, '')],
      };
      final t = totalByMonth(pts);
      expect(t.map((x) => x.$2), [320, 340]);
      expect(t.first.$1, DateTime(2026, 2));
      expect(totalByMonth({'back_squat': pts['back_squat']!}), isEmpty);
    });
  });

  group('state', () {
    test('tape is kept, survives a reload and is in the backup; photos are not', () async {
      final s = await app();
      await s.addTape('waist', 84);
      await s.addTape('arm', 38, side: 'R');
      await s.addPhoto([1, 2, 3]);
      await s.reload();
      expect(s.tape.map((t) => t.label), ['Waist', 'Arm right']);
      expect(s.photos, hasLength(1));
      expect(File(s.photoPath(s.photos.first)).existsSync(), isTrue);
      final b = await exportBackup(s.repo);
      expect(b, contains('"tape"'));
      expect(b, isNot(contains('"photos"')));
      final id = s.photos.first['id'] as String;
      final path = s.photoPath(s.photos.first);
      await s.removePhoto(id);
      expect(s.photos, isEmpty);
      expect(File(path).existsSync(), isFalse);
    });

    test('the strength line for the AI; a ratio hint only after 3 workouts of each lift (review 4, P2-7)', () async {
      final s = await app();
      await s.saveProfile(s.profile!.copyWith(bodyKg: 80));
      Future<void> workout() async {
        final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
        await s.repo.logSet(ses.id, 'back_squat', 120, 1);
        await s.repo.logSet(ses.id, 'bench_press', 60, 1);
        await s.repo.finishSession(ses.id, s.lib, s.unit);
      }

      await workout();
      await s.reload();
      final m = await s.mainMaxes();
      expect(m['back_squat'], closeTo(120, 5));
      var line = await s.strengthLine();
      expect(line, contains('Strength score'));
      expect(line, isNot(contains('low next to')), reason: 'one workout says nothing');
      await workout();
      await workout();
      line = await s.strengthLine();
      expect(line, contains('bench press low next to back squat (ratio 0.50, usual 0.75)'));
      expect(line, isNot(contains('behind')));
      expect(laggingLifts({'back_squat': 150, 'bench_press': 80}, workouts: {'back_squat': 5, 'bench_press': 2}), isEmpty);
    });
  });

  group('review 4 P1-1 and P2-2: photos really go', () {
    test('Delete all data removes every photo file', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
      final s = await app();
      var cleared = 0;
      AppState.clearPicked = () async => cleared++;
      await s.addPhoto([1, 2, 3]);
      await s.addPhoto([4, 5]);
      expect(cleared, 2, reason: 'the picker copy goes after each add');
      final dir = Directory(s.photoDir);
      expect(dir.listSync(), hasLength(2));
      await s.wipeEverything();
      expect(dir.existsSync() ? dir.listSync() : const [], isEmpty);
      expect(s.photos, isEmpty);
      expect(cleared, 3);
    });

    test('a replace-restore keeps the photo list and the files', () async {
      final s = await app();
      AppState.clearPicked = () async {};
      await s.addPhoto([1, 2, 3]);
      final b = await exportBackup(s.repo);
      await importBackup(s.repo, b, replace: true);
      await s.reload();
      expect(s.photos, hasLength(1));
      expect(File(s.photoPath(s.photos.first)).existsSync(), isTrue);
    });

    test('an orphan photo file is removed on reload; a listed one stays', () async {
      final s = await app();
      AppState.clearPicked = () async {};
      await s.addPhoto([1, 2, 3]);
      final orphan = File('${s.photoDir}/123.img')..writeAsBytesSync([9]);
      await s.reload();
      expect(orphan.existsSync(), isFalse);
      expect(File(s.photoPath(s.photos.single)).existsSync(), isTrue);
    });

    test('removing a photo clears the picker copy too', () async {
      final s = await app();
      var cleared = 0;
      AppState.clearPicked = () async => cleared++;
      await s.addPhoto([1]);
      await s.removePhoto(s.photos.single['id'] as String);
      expect(cleared, 2);
    });
  });

  group('review 4 P2-1: inches and feet for lb users', () {
    test('heights typed every common way', () {
      expect(parseHeight('178'), 178);
      expect(parseHeight('178 cm'), 178);
      expect(parseHeight("5'10"), closeTo(177.8, 0.01));
      expect(parseHeight('5\'10"'), closeTo(177.8, 0.01));
      expect(parseHeight('5 ft 10'), closeTo(177.8, 0.01));
      expect(parseHeight('70 in'), closeTo(177.8, 0.01));
      expect(parseHeight('70'), closeTo(177.8, 0.01));
      expect(parseHeight("5'13"), isNull);
      expect(parseHeight('300'), isNull);
      expect(fmtHeight(180, Unit.lb), '5 ft 11 in');
      expect(fmtLen(86, Unit.lb), '33.9 in');
      expect(fmtLen(86, Unit.kg), '86 cm');
    });

    test('the AI tape and height tools use the person unit', () async {
      final s = await app();
      await s.saveProfile(s.profile!.copyWith(unit: Unit.lb));
      var r = parseToolReply('SAY: ok\nDO: tape waist 34\nDO: tape chest 100 cm\nDO: tape arm 15in right', s);
      expect(r.errors, isEmpty);
      expect(r.actions.first.says, 'Tape: Waist 34 in');
      for (final a in r.actions) {
        await a.run(s);
      }
      expect(s.tape.map((x) => x.cm), [closeTo(86.36, 0.01), 100, closeTo(38.1, 0.01)]);
      r = parseToolReply("SAY: ok\nDO: profile height 5'11", s);
      expect(r.errors, isEmpty);
      expect(r.actions.single.says, contains('5 ft 11 in'));
      await r.actions.single.run(s);
      expect(s.profile!.heightCm, closeTo(180.34, 0.01));
      final g = toolGrammar(s.lib, s.profile!, s.plan!.days.length);
      expect(g, contains('(" cm" | " in")?'));
      expect(g, contains('"sex " ("m" | "f" | "none")'));
    });

    testWidgets('an lb user sees feet and inches', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final s = await tester.runAsync(() async {
        final s = await app(f: databaseFactoryFfiNoIsolate);
        await s.saveProfile(s.profile!.copyWith(unit: Unit.lb, heightCm: 180));
        await s.repo.logBody(85);
        await s.addTape('waist', 86);
        await s.reload();
        return s;
      });
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: BodyScreen(s: s!)));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      expect(find.text('Height 5 ft 11 in'), findsOneWidget);
      expect(find.text('33.9 in'), findsOneWidget);
      expect(find.textContaining(' cm'), findsNothing);
    });
  });

  group('AI tools', () {
    test('weigh-in with body fat, tape, weigh reminder and height', () async {
      final s = await app();
      var r = parseToolReply('SAY: ok\nDO: body 81.5 kg fat 18', s);
      expect(r.errors, isEmpty);
      expect(r.actions.single.says, contains('body fat 18.0%'));
      await r.actions.single.run(s);
      final log = await s.repo.bodyLog();
      expect(log.first.$3, closeTo(81.5, 0.01));
      expect(log.first.$4, 18);

      r = parseToolReply('SAY: ok\nDO: tape arm 38 left\nDO: tape lower waist 80', s);
      expect(r.errors, isEmpty);
      for (final a in r.actions) {
        await a.run(s);
      }
      expect(s.tape.map((t) => t.label), ['Arm left', 'Lower waist']);
      expect(parseToolReply('SAY: x\nDO: tape waist', s).errors, isNotEmpty);
      expect(parseToolReply('SAY: x\nDO: body 80 fat 99', s).errors, isNotEmpty);

      r = parseToolReply('SAY: ok\nDO: setting weigh_reminder 07:15', s);
      await r.actions.single.run(s);
      expect(s.settings.weighAt, 7 * 60 + 15);
      r = parseToolReply('SAY: ok\nDO: setting weigh_reminder off', s);
      await r.actions.single.run(s);
      expect(s.settings.weighAt, -1);

      r = parseToolReply('SAY: ok\nDO: profile height 178', s);
      await r.actions.single.run(s);
      expect(s.profile!.heightCm, 178);
      expect(parseToolReply('SAY: x\nDO: profile height 30', s).errors, isNotEmpty); // 30 in is not a height
    });
  });

  testWidgets('review 4 P2-3: one weigh-in check, with plain messages', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = await tester.runAsync(() async {
      final s = await app(f: databaseFactoryFfiNoIsolate);
      await s.saveProfile(s.profile!.copyWith(unit: Unit.lb));
      return s;
    });
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100)); // lets the sheet finish sliding up
      }
    }

    Future<int> rows() async => (await tester.runAsync(() => s!.repo.bodyLog()))!.length;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: BodyScreen(s: s!)));
    await settle();
    await tester.tap(find.text('Weigh in').last);
    await settle();
    await tester.enterText(find.widgetWithText(TextField, 'Body weight'), '5000');
    await tester.tap(find.text('Save'));
    await settle();
    expect(find.textContaining('That looks off. Body weight between 44'), findsOneWidget);
    expect(await rows(), 0);
    await tester.enterText(find.widgetWithText(TextField, 'Body weight'), '180');
    await tester.enterText(find.widgetWithText(TextField, 'Body fat (optional)'), '0');
    await tester.tap(find.text('Save'));
    await settle();
    expect(find.text('Body fat is a percent between 3 and 60.'), findsOneWidget);
    expect(await rows(), 0);
    await tester.enterText(find.widgetWithText(TextField, 'Body fat (optional)'), '18');
    await tester.tap(find.text('Save'));
    await settle();
    final log = (await tester.runAsync(() => s.repo.bodyLog()))!;
    expect(log.single.$3, closeTo(lbToKg(180), 0.01));
    expect(log.single.$4, 18);
    expect(s.bodyKgNow, closeTo(lbToKg(180), 0.01), reason: 'saved and reloaded at once');
  });

  test('review 4 P2-3: the AI and quick phrases use the same range', () async {
    final s = await app();
    expect(parseToolReply('SAY: x\nDO: body 500 kg', s).errors, isNotEmpty);
    expect(parseToolReply('SAY: x\nDO: body 80 kg fat 2', s).errors.join(), contains('between 3 and 60'));
    expect(parseToolReply('SAY: x\nDO: body 80 kg fat 25', s).errors, isEmpty);
  });

  testWidgets('review 4 P2-5: estimates are labelled, one neutral sex line with a one-tap change', (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = await tester.runAsync(() async {
      final s = await app(f: databaseFactoryFfiNoIsolate);
      await s.saveProfile(s.profile!.copyWith(heightCm: 180));
      await s.repo.logBody(80, fat: 18);
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      for (final (id, kg) in const [('back_squat', 140.0), ('bench_press', 100.0), ('deadlift', 180.0)]) {
        await s.repo.logSet(ses.id, id, kg, 1);
      }
      await s.repo.finishSession(ses.id, s.lib, s.unit);
      await s.reload();
      return s;
    });
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: BodyScreen(s: s!)));
    await settle();
    expect(find.textContaining('lean mass about'), findsOneWidget);
    expect(find.textContaining('FFMI about'), findsOneWidget);
    expect(find.textContaining('are estimates'), findsOneWidget);
    expect(find.textContaining('Estimated total'), findsOneWidget);
    expect(find.textContaining('not a meet total'), findsOneWidget);
    expect(find.textContaining('Wilks (original)'), findsOneWidget);
    expect(find.textContaining('(estimates)'), findsOneWidget);
    expect(find.textContaining("men's tables"), findsOneWidget);
    await tester.tap(find.byKey(const Key('setSex')));
    await settle();
    await tester.tap(find.text('Female'));
    await settle();
    expect(s.profile!.sex, 'f');
    expect(find.textContaining("men's tables"), findsNothing);
  });

  test('review 4 N19: the Wilks (original) women clamp and the IPF GL floor', () async {
    expect(wilks(300, 20, female: true), closeTo(wilks(300, 26.51, female: true), 1e-9));
    expect(wilks(300, 160, female: true), closeTo(wilks(300, 154.53, female: true), 1e-9));
    expect(ipfGl(300, 10, female: false), closeTo(ipfGl(300, 40, female: false), 1e-9));
  });

  testWidgets('review 4 P2-6: Simple keeps the weight card and hides the extras', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = await tester.runAsync(() async {
      final s = await app(f: databaseFactoryFfiNoIsolate);
      await s.saveProfile(s.profile!.copyWith(heightCm: 180));
      await s.saveSettings(s.settings.copyWith(simple: true));
      await s.repo.logBody(80, fat: 18);
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      await s.repo.logSet(ses.id, 'back_squat', 120, 1);
      await s.repo.finishSession(ses.id, s.lib, s.unit);
      await s.addTape('waist', 84);
      await s.reload();
      return s;
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: BodyScreen(s: s!)));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Body weight'), findsOneWidget);
    expect(find.text('Weigh in'), findsOneWidget);
    for (final gone in ['Strength score', 'DOTS', 'Progress photos', 'Tape', 'FFMI', 'BMI']) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }
  });

  testWidgets('review 4 P2-8: a tape row is deleted with a swipe and comes back with Undo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = await tester.runAsync(() async {
      final s = await app(f: databaseFactoryFfiNoIsolate);
      await s.addTape('waist', 86);
      await s.addTape('waist', 68); // the typo
      await s.addTape('neck', 40);
      return s;
    });
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: TapeHistoryScreen(s: s!, label: 'Waist')));
    await settle();
    expect(find.text('68 cm'), findsOneWidget);
    await tester.drag(find.text('68 cm'), const Offset(-600, 0));
    await settle();
    expect(s.tape.map((x) => x.cm), [86, 40]);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle();
    expect(s.tape.map((x) => x.cm), [86, 68, 40], reason: 'back at its own place');
  });

  testWidgets('review 4 P2-8: an arm measurement needs a side before Save', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = await tester.runAsync(() => app(f: databaseFactoryFfiNoIsolate));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: BodyScreen(s: s!)));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Measure'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the sheet is up
    await tester.tap(find.text('Arm'));
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text('Pick left or right.'), findsOneWidget);
    await tester.tap(find.text('Right'));
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(parseToolReply('SAY: x\nDO: tape arm 38', s).errors.join(), contains('left or right'));
  });

  testWidgets('the Body screen shows weight, goal, numbers and strength', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final s = await tester.runAsync(() async {
      final s = await app(f: databaseFactoryFfiNoIsolate);
      await s.saveProfile(s.profile!.copyWith(heightCm: 180));
      for (var i = 0; i < 5; i++) {
        await s.repo.logBody(82.0 - i * 0.2, fat: i == 4 ? 18 : null, at: DateTime.now().subtract(Duration(days: 4 - i)));
      }
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      await s.repo.logSet(ses.id, 'back_squat', 120, 1);
      await s.repo.finishSession(ses.id, s.lib, s.unit);
      await s.addTape('waist', 84);
      await s.reload();
      return s;
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: BodyScreen(s: s!)));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Body weight'), findsOneWidget);
    expect(find.textContaining('7-day average'), findsWidgets);
    expect(find.textContaining('BMI'), findsWidgets);
    expect(find.textContaining('FFMI'), findsWidgets);
    expect(find.textContaining('Strength score'), findsOneWidget);
    expect(find.text('Waist'), findsOneWidget);
    expect(find.text('Morning weigh-in reminder'), findsOneWidget);
  });
}
