import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workout/ai/ai.dart';
import 'package:workout/ai/plan_json.dart';
import 'package:workout/ai/prompt.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/net/guarded_client.dart';

void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 3, minutes: 60, have: Equipment.values.toSet(), avoid: {Joint.knees}, unit: Unit.lb);

  group('network guard', () {
    test('private hosts', () {
      expect(isPrivateHost('localhost'), isTrue);
      expect(isPrivateHost('127.0.0.1'), isTrue);
      expect(isPrivateHost('10.1.2.3'), isTrue);
      expect(isPrivateHost('172.16.0.9'), isTrue);
      expect(isPrivateHost('172.31.255.1'), isTrue);
      expect(isPrivateHost('172.32.0.1'), isFalse);
      expect(isPrivateHost('192.168.1.20'), isTrue);
      expect(isPrivateHost('8.8.8.8'), isFalse);
      expect(isPrivateHost('api.openai.com'), isFalse);
    });
    test('allow list', () {
      final g = NetGuard(aiHost: 'api.anthropic.com');
      expect(g.allows(Uri.parse('https://api.anthropic.com/v1/messages')), isTrue);
      expect(g.allows(Uri.parse('https://api.github.com/repos/x/y/releases/latest')), isTrue);
      expect(g.allows(Uri.parse('https://objects.githubusercontent.com/a')), isTrue);
      expect(g.allows(Uri.parse('https://example.com/')), isFalse);
      expect(g.allows(Uri.parse('http://api.anthropic.com/v1/messages')), isFalse);
      final local = NetGuard(aiHost: '192.168.1.20');
      expect(local.allows(Uri.parse('http://192.168.1.20:8080/v1/chat/completions')), isTrue);
      expect(NetGuard(aiHost: '8.8.8.8').allows(Uri.parse('http://8.8.8.8/')), isFalse);
      expect(NetGuard().allows(Uri.parse('https://api.anthropic.com/')), isFalse); // AI not set up
    });
    test('guarded client refuses blocked hosts and redirects to them', () async {
      final inner = MockClient((r) async {
        if (r.url.path == '/hop') return http.Response('', 302, headers: {'location': 'https://evil.example/x'});
        return http.Response('ok', 200);
      });
      final c = GuardedClient(NetGuard(aiHost: 'api.anthropic.com'), inner);
      expect((await c.get(Uri.parse('https://api.github.com/ok'))).body, 'ok');
      await expectLater(c.get(Uri.parse('https://example.com/')), throwsA(isA<NetBlocked>()));
      await expectLater(c.get(Uri.parse('https://api.github.com/hop')), throwsA(isA<NetBlocked>()));
    });
  });

  group('request text', () {
    test('contains only setup, plan and sets - nothing about the person or phone', () {
      final text = buildRequest(profile, null, [SetLog(exerciseId: 'bench_press', kg: 100, reps: 8, at: DateTime(2026, 11, 17))], lib, 'Make me a plan.');
      expect(text, contains('Goal: both'));
      expect(text, contains('Bench press'));
      expect(text, contains('220.5 lb x 8'));
      expect(text, contains('Go easy on: knees'));
      for (final bad in ['device', 'android', 'name:', 'email', 'location', 'id:']) {
        expect(text.toLowerCase(), isNot(contains(bad)), reason: bad);
      }
    });
  });

  group('AI plan validation', () {
    String day(String name, List<Map<String, dynamic>> items) => jsonEncode({'name': name, 'items': items});
    Map<String, dynamic> it(String id, {int sets = 3, int lo = 8, int hi = 12, int rest = 90}) =>
        {'exercise': id, 'sets': sets, 'repLow': lo, 'repHigh': hi, 'rest': rest};
    String plan(List<String> days) => '{"name":"AI plan","days":[${days.join(',')}]}';

    test('good plan inside a ```json fence is accepted', () {
      final text = 'Here you go:\n```json\n${plan([day('Push', [it('bench_press'), it('db_lateral_raise')]), day('Pull', [it('lat_pulldown')])])}\n```\nEnjoy';
      final r = parsePlan(text, lib);
      expect(r.errors, isEmpty);
      expect(r.plan!.days.map((d) => d.name), ['Push', 'Pull']);
      expect(r.plan!.source, 'ai');
    });
    test('unknown exercise id is rejected with its name', () {
      final r = parsePlan(plan([day('Push', [it('laser_press')])]), lib);
      expect(r.plan, isNull);
      expect(r.errors.join(), contains('laser_press'));
    });
    test('silly numbers are rejected', () {
      for (final bad in [it('bench_press', sets: 0), it('bench_press', sets: 11), it('bench_press', lo: 0), it('bench_press', hi: 31),
        it('bench_press', lo: 12, hi: 8), it('bench_press', rest: 10), it('bench_press', rest: 601)]) {
        expect(parsePlan(plan([day('X', [bad])]), lib).plan, isNull, reason: '$bad');
      }
    });
    test('too many items, no days, not JSON', () {
      expect(parsePlan(plan([day('X', List.generate(13, (_) => it('bench_press')))]), lib).plan, isNull);
      expect(parsePlan(plan([]), lib).plan, isNull);
      expect(parsePlan('{"name":"x","days":[{"name":"A","items":[]}]}', lib).plan, isNull);
      expect(parsePlan('I am sorry, I cannot do that.', lib).plan, isNull);
      expect(parsePlan('{"days": "nope"}', lib).plan, isNull);
    });
    test('day (adjust today) parse', () {
      final r = parseDay(day('Upper A', [it('bench_press', sets: 4, lo: 5, hi: 8, rest: 150)]), lib);
      expect(r.errors, isEmpty);
      expect(r.day!.items.single.sets, 4);
    });
  });

  group('providers', () {
    test('claude request shape and reply', () async {
      late http.Request seen;
      final inner = MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode({'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'hi'}]}), 200);
      });
      final p = providerFor(const AiConfig(kind: AiKind.claude, model: 'claude-opus-5-5'), 'k', GuardedClient(NetGuard(aiHost: 'api.anthropic.com'), inner));
      expect(await p.complete('sys', 'user'), 'hi');
      expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(seen.headers['x-api-key'], 'k');
      expect(seen.headers['anthropic-version'], '2026-10-21');
      final body = jsonDecode(seen.body) as Map;
      expect(body['model'], 'claude-opus-5-5');
      expect(body['system'], 'sys');
      expect(body.containsKey('temperature'), isFalse);
    });
    test('claude refusal and http errors become plain AiError', () async {
      final refuse = MockClient((r) async => http.Response(jsonEncode({'stop_reason': 'refusal', 'content': []}), 200));
      final p = providerFor(const AiConfig(kind: AiKind.claude, model: 'm'), 'k', GuardedClient(NetGuard(aiHost: 'api.anthropic.com'), refuse));
      await expectLater(p.complete('s', 'u'), throwsA(isA<AiError>()));
      final bad = MockClient((r) async => http.Response('{"error":{"message":"invalid x-api-key"}}', 401));
      final p2 = providerFor(const AiConfig(kind: AiKind.claude, model: 'm'), 'k', GuardedClient(NetGuard(aiHost: 'api.anthropic.com'), bad));
      await expectLater(p2.complete('s', 'u'), throwsA(isA<AiError>().having((e) => e.message, 'message', contains('key'))));
    });
    test('openai, gemini, local shapes', () async {
      final seen = <http.Request>[];
      final inner = MockClient((r) async {
        seen.add(r);
        if (r.url.host.contains('googleapis')) {
          return http.Response(jsonEncode({'candidates': [{'content': {'parts': [{'text': 'g'}]}}]}), 200);
        }
        return http.Response(jsonEncode({'choices': [{'message': {'content': 'o'}}]}), 200);
      });
      expect(await providerFor(const AiConfig(kind: AiKind.openai, model: 'gpt-x'), 'k', GuardedClient(NetGuard(aiHost: 'api.openai.com'), inner)).complete('s', 'u'), 'o');
      expect(seen.last.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(seen.last.headers['authorization'], 'Bearer k');
      expect(await providerFor(const AiConfig(kind: AiKind.gemini, model: 'gem'), 'k', GuardedClient(NetGuard(aiHost: 'generativelanguage.googleapis.com'), inner)).complete('s', 'u'), 'g');
      expect(seen.last.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/gem:generateContent');
      expect(seen.last.headers['x-goog-api-key'], 'k');
      expect(await providerFor(const AiConfig(kind: AiKind.local, model: 'qwen', baseUrl: 'http://192.168.1.20:8081'), '', GuardedClient(NetGuard(aiHost: '192.168.1.20'), inner)).complete('s', 'u'), 'o');
      expect(seen.last.url.toString(), 'http://192.168.1.20:8081/v1/chat/completions');
      expect(seen.last.headers.containsKey('authorization'), isFalse);
    });
  });

  group('claude extras', () {
    test('a schema makes Claude answer in that exact shape', () async {
      late http.Request seen;
      final inner = MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode({'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': '{}'}]}), 200);
      });
      final p = providerFor(const AiConfig(kind: AiKind.claude, model: 'claude-opus-5-5'), 'k', GuardedClient(NetGuard(aiHost: 'api.anthropic.com'), inner));
      final schema = planSchema(lib, profile);
      await p.complete('s', 'u', schema: schema);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final fmt = (body['output_config'] as Map)['format'] as Map;
      expect(fmt['type'], 'json_schema');
      expect(fmt['schema'], schema);
      final ids = (((((schema['properties'] as Map)['days'] as Map)['items'] as Map)['properties'] as Map)['items'] as Map)['items'] as Map;
      final en = ((ids['properties'] as Map)['exercise'] as Map)['enum'] as List;
      expect(en, contains('bench_press'));
      expect(en, isNot(contains('goblet_squat'))); // knees are sore in this profile
    });
    test('ask the coach: plain text answer, no schema', () async {
      late http.Request seen;
      final inner = MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode({'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'Rest 2-3 minutes.'}]}), 200);
      });
      final p = providerFor(const AiConfig(kind: AiKind.claude, model: 'claude-opus-5-5'), 'k', GuardedClient(NetGuard(aiHost: 'api.anthropic.com'), inner));
      expect(await p.complete(coachPrompt(), 'How long should I rest?'), 'Rest 2-3 minutes.');
      expect(((jsonDecode(seen.body) as Map)['output_config'] as Map).containsKey('format'), isFalse);
    });
  });
}
