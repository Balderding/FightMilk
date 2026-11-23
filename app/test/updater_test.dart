import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workout/net/guarded_client.dart';
import 'package:workout/ui/app_state.dart' show AppState;
import 'package:workout/update/updater.dart';
import 'package:workout/version.dart';

void main() {
  test('versions compare like people expect', () {
    expect(isNewer('v0.7.1', '0.7.0'), isTrue);
    expect(isNewer('0.10.0', '0.9.9'), isTrue);
    expect(isNewer('v1.0.0', '0.99.0'), isTrue);
    expect(isNewer('v0.7.0', '0.7.0'), isFalse);
    expect(isNewer('v0.6.9', '0.7.0'), isFalse);
    expect(isNewer('nonsense', '0.7.0'), isFalse);
    expect(appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  test('picks the APK for this phone, else the universal one', () {
    final names = ['FightMilk-0.8.0-arm64.apk', 'FightMilk-0.8.0-armv7.apk', 'FightMilk-0.8.0-universal.apk', 'SHA256SUMS.txt'];
    expect(pickApk(names, 'arm64-v8a'), 'FightMilk-0.8.0-arm64.apk');
    expect(pickApk(names, 'armeabi-v7a'), 'FightMilk-0.8.0-armv7.apk');
    expect(pickApk(names, 'x86_64'), 'FightMilk-0.8.0-universal.apk');
    expect(pickApk(['notes.txt'], 'arm64-v8a'), isNull);
  });

  group('check and download', () {
    final apk = Uint8List.fromList(List.generate(4000, (i) => (i * 7) % 256));
    final sum = sha256.convert(apk).toString();

    http.Client gh({String tag = 'v9.0.0', bool badSum = false}) => MockClient((r) async {
          if (r.url.path.endsWith('/releases/latest')) {
            return http.Response(
                jsonEncode({
                  'tag_name': tag,
                  'name': 'FightMilk $tag',
                  'body': 'Better rest timer.',
                  'assets': [
                    {'name': 'FightMilk-9.0.0-arm64.apk', 'browser_download_url': 'https://github.com/Balderding/FightMilk/releases/download/$tag/FightMilk-9.0.0-arm64.apk', 'size': apk.length},
                    {'name': 'SHA256SUMS.txt', 'browser_download_url': 'https://github.com/Balderding/FightMilk/releases/download/$tag/SHA256SUMS.txt', 'size': 100},
                  ]
                }),
                200);
          }
          if (r.url.path.endsWith('SHA256SUMS.txt')) return http.Response('${badSum ? '0' * 64 : sum}  FightMilk-9.0.0-arm64.apk\n', 200);
          if (r.url.path.endsWith('.apk')) return http.Response.bytes(apk, 200);
          return http.Response('', 404);
        });

    test('finds a newer release and its notes', () async {
      final u = await checkUpdate(GuardedClient(const NetGuard(), gh()), 'arm64-v8a');
      expect(u, isNotNull);
      expect(u!.version, '9.0.0');
      expect(u.notes, contains('rest timer'));
      expect(u.sha256, sum);
    });
    test('same version: no update', () async {
      expect(await checkUpdate(GuardedClient(const NetGuard(), gh(tag: 'v$appVersion')), 'arm64-v8a'), isNull);
    });
    test('downloads and checks the fingerprint; a wrong file is thrown away', () async {
      final dir = Directory.systemTemp.createTempSync('up');
      final u = (await checkUpdate(GuardedClient(const NetGuard(), gh()), 'arm64-v8a'))!;
      final path = await downloadUpdate(u, GuardedClient(const NetGuard(), gh()), dir.path);
      expect(File(path).readAsBytesSync(), apk);
      final bad = (await checkUpdate(GuardedClient(const NetGuard(), gh(badSum: true)), 'arm64-v8a'))!;
      await expectLater(downloadUpdate(bad, GuardedClient(const NetGuard(), gh(badSum: true)), dir.path), throwsA(isA<UpdateError>()));
      expect(dir.listSync().whereType<File>().where((f) => f.path.endsWith('.apk')).length, 1);
      dir.deleteSync(recursive: true);
    });
    test('no fingerprint published: refuse', () async {
      final c = MockClient((r) async => http.Response(
          jsonEncode({
            'tag_name': 'v9.0.0',
            'assets': [
              {'name': 'FightMilk-9.0.0-arm64.apk', 'browser_download_url': 'https://github.com/x.apk', 'size': 1}
            ]
          }),
          200));
      await expectLater(checkUpdate(GuardedClient(const NetGuard(), c), 'arm64-v8a'), throwsA(isA<UpdateError>()));
    });
  });

  group('after the download: the installer step is never a silent nothing (0.9.1 lesson)', () {
    test('an update that is not newer is said, with both numbers, before Android is asked', () {
      final n = AppState.installNote('not_newer:13:2012');
      expect(n, contains('not newer than the app on your phone'));
      expect(n, contains('13'));
      expect(n, contains('2012'));
      expect(n, contains('Nothing was changed'));
    });

    test("the installer's refusal is said with its reason", () {
      expect(AppState.installNote('failed:-25'), contains('older than the app on your phone'));
      expect(AppState.installNote('failed:-7'), contains('different key'));
      expect(AppState.installNote('failed:-4'), contains('not enough free space'));
      expect(AppState.installNote('failed:-99'), contains('code -99'));
      expect(AppState.installNote('failed:x'), contains('Android did not install'));
      for (final r in ['failed:-25', 'failed:-7', 'failed:-4', 'not_apk', 'other_app', 'cancelled']) {
        expect(AppState.installNote(r), isNot(contains('The installer is open')), reason: '$r is not "it is opening"');
      }
    });

    test('the other answers', () {
      expect(AppState.installNote('cancelled'), contains('installer was closed'));
      expect(AppState.installNote('need_permission'), contains('Allow FightMilk'));
      expect(AppState.installNote('not_apk'), contains('not an app file'));
      expect(AppState.installNote('other_app'), contains('different app'));
      expect(AppState.installNote('installed'), 'Updated.');
      expect(AppState.installNote(null), contains('installer is open'));
    });
  });
}
