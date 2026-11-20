import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/llm/model_store.dart';
import 'package:workout/net/guarded_client.dart';

void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {Joint.knees}, unit: Unit.lb);

  group('grammar', () {
    test('plan grammar: the split day names in order, each day only its own muscles, compound first', () {
      final g = planGrammar(lib, profile); // 4 days -> Upper A, Lower A, Upper B, Lower B
      final lines = g.split('\n');
      expect(lines.first, 'root ::= "PLAN: " name "\\n" d0 d1 d2 d3');
      expect(g, contains('d0 ::= "DAY: " "Upper A"'));
      expect(g, contains('d1 ::= "DAY: " "Lower A"'));
      final upper = lines.firstWhere((l) => l.startsWith('d0i ::='));
      final lower = lines.firstWhere((l) => l.startsWith('d1i ::='));
      final lowerFirst = lines.firstWhere((l) => l.startsWith('d1f ::='));
      expect(upper, contains('"bench_press"'));
      expect(upper, isNot(contains('"romanian_deadlift"')));
      expect(lower, contains('"romanian_deadlift"'));
      expect(lower, isNot(contains('"bench_press"')));
      expect(lowerFirst, isNot(contains('"lying_leg_curl"'))); // isolation can't lead the day
      expect(g, isNot(contains('"goblet_squat"'))); // knees
    });
    test('day grammar keeps the day name and muscles', () {
      final g = dayGrammar(lib, profile, 'Push A');
      expect(g, startsWith('root ::= d0'));
      expect(g, contains('"DAY: " "Push A"'));
      expect(g.split('\n').firstWhere((l) => l.startsWith('d0i ::=')), isNot(contains('"barbell_row"')));
    });
    test('compact list groups ids by muscle and is much shorter than the full list', () {
      final c = compactExerciseList(lib, profile);
      expect(c, contains('chest: '));
      expect(c, contains('bench_press'));
      expect(c.length, lessThan(8000));
    });
  });

  group('model download', () {
    final data = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final good = ModelInfo(id: 't', label: 'Test', file: 'm.gguf', url: 'https://huggingface.co/x/resolve/abc/m.gguf', sha256: sha256.convert(data).toString(), bytes: data.length, note: '');

    http.Client server({bool corrupt = false}) => MockClient.streaming((req, body) async {
          if (req.url.host == 'huggingface.co') {
            return http.StreamedResponse(const Stream.empty(), 302, headers: {'location': 'https://us.aws.cdn.hf.co/blob'});
          }
          final range = req.headers['range'];
          var start = 0;
          if (range != null) start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          final bytes = corrupt ? Uint8List.fromList(data.map((b) => b ^ 1).toList()) : data;
          return http.StreamedResponse(Stream.value(bytes.sublist(start)), range != null ? 206 : 200, contentLength: bytes.length - start);
        });

    test('downloads through the Hugging Face redirect, checks the fingerprint, reports progress', () async {
      final dir = Directory.systemTemp.createTempSync('ms');
      final store = ModelStore(dir.path);
      final seen = <double>[];
      await store.download(good, GuardedClient(const NetGuard(models: true), server()), onProgress: seen.add);
      expect(store.isReady(good), isTrue);
      expect(File(store.pathOf(good)).lengthSync(), data.length);
      expect(seen.last, 1.0);
      dir.deleteSync(recursive: true);
    });
    test('resumes a half download', () async {
      final dir = Directory.systemTemp.createTempSync('ms');
      final store = ModelStore(dir.path);
      File('${store.pathOf(good)}.part')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data.sublist(0, 2000));
      await store.download(good, GuardedClient(const NetGuard(models: true), server()));
      expect(store.isReady(good), isTrue);
      expect(sha256.convert(File(store.pathOf(good)).readAsBytesSync()).toString(), good.sha256);
      dir.deleteSync(recursive: true);
    });
    test('a wrong file is thrown away, not installed', () async {
      final dir = Directory.systemTemp.createTempSync('ms');
      final store = ModelStore(dir.path);
      await expectLater(store.download(good, GuardedClient(const NetGuard(models: true), server(corrupt: true))), throwsA(isA<ModelError>()));
      expect(store.isReady(good), isFalse);
      expect(File('${store.pathOf(good)}.part').existsSync(), isFalse);
      dir.deleteSync(recursive: true);
    });
    test('model hosts are allowed only for model downloads', () {
      expect(const NetGuard().allows(Uri.parse('https://huggingface.co/x')), isFalse);
      expect(const NetGuard(models: true).allows(Uri.parse('https://huggingface.co/x')), isTrue);
      expect(const NetGuard(models: true).allows(Uri.parse('https://us.aws.cdn.hf.co/x')), isTrue);
      expect(const NetGuard(models: true).allows(Uri.parse('https://evilhf.co/x')), isFalse);
      expect(const NetGuard(models: true).allows(Uri.parse('http://huggingface.co/x')), isFalse);
    });
    test('the built-in catalog is pinned and fingerprinted', () {
      for (final m in modelCatalog) {
        expect(m.url, contains('/resolve/'));
        expect(m.url, isNot(contains('/resolve/main/')));
        expect(m.sha256.length, 64);
        expect(m.bytes, greaterThan(100000000));
      }
      expect(modelCatalog.first.id, 'lfm2.5-1.2b-instruct');
    });
  });
}
