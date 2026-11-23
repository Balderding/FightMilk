import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout/ui/settings_screen.dart' show privacyText, privacyUrl, signingFingerprint;

/// Batch B3 (release 0.9.0): the privacy promise, the licences and the signing fingerprint
/// (F397, F413, F414) say the same thing everywhere.
void main() {
  test('F414: the fingerprint in the app is the release certificate\'s, in the repo and the README', () {
    final want = File('../tools/release_cert.sha256').readAsStringSync().trim();
    expect(signingFingerprint, want);
    expect(File('../README.md').readAsStringSync(), contains(want));
    expect(File('../PRIVACY.md').readAsStringSync(), contains(want));
  });

  test('F397: PRIVACY.md and the in-app text name the same ways online, and the photo rule', () {
    final doc = File('../PRIVACY.md').readAsStringSync();
    for (final w in ['Ask AI', 'GitHub', 'Hugging Face', 'your own server', 'never in a backup']) {
      expect(doc.toLowerCase(), contains(w.toLowerCase()), reason: w);
    }
    for (final w in ['AI', 'GitHub', 'Hugging Face', 'your own server', 'https']) {
      expect(privacyText, contains(w), reason: w);
    }
    expect(privacyUrl, endsWith('/PRIVACY.md'));
    expect(doc, isNot(contains('@gmail')));
  });

  test('F413: llama.cpp\'s licence is bundled (native code is not listed by Flutter itself)', () {
    final t = File('assets/licenses/llama.cpp.txt').readAsStringSync();
    expect(t, startsWith('MIT License'));
    expect(t, contains('ggml authors'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/licenses/'));
    expect(File('lib/main.dart').readAsStringSync(), contains("LicenseRegistry.addLicense"));
    expect(LicenseEntryWithLineBreaks(const ['x'], 'y').packages, ['x']);
  });
}
