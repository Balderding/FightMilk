// Live check of app updates against the real GitHub release (pretends to be an older version).
// Run: flutter test test_live/update_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/net/guarded_client.dart';
import 'package:workout/update/updater.dart';

void main() {
  HttpOverrides.global = null;
  test('finds the latest release, downloads the arm64 APK through the guard, fingerprint matches', () async {
    final c = GuardedClient(const NetGuard());
    final u = await checkUpdate(c, 'arm64-v8a', current: '0.0.1');
    expect(u, isNotNull);
    expect(u!.apkName, endsWith('-arm64.apk'));
    final dir = Directory.systemTemp.createTempSync('upl');
    final path = await downloadUpdate(u, c, dir.path);
    expect(File(path).lengthSync(), u.bytes);
    File('../work/update_live.txt').writeAsStringSync('${u.version} ${u.apkName} ${u.bytes} ${u.sha256}\n');
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
