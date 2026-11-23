// Run by hand before publishing a pack: checks a signed pack.zip the way the app does.
//   flutter test test_live/pack_verify_test.dart --dart-define=PACK=../release/v0.9.2/pack.zip
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/packs/pack.dart';

void main() {
  const path = String.fromEnvironment('PACK');
  test('the pack verifies with the app\'s public key and its exercise list reads', () async {
    expect(path, isNotEmpty, reason: 'give --dart-define=PACK=<pack.zip>');
    final pack = await verifyPack(File(path).readAsBytesSync(), base64Decode(packPublicKeyB64));
    // ignore: avoid_print
    print('pack version ${pack.version}, files ${pack.files.keys.toList()}, exercises ${pack.exercises.length}');
    expect(pack.exercises.length, greaterThan(200));
    expect(pack.exercises.firstWhere((e) => e.id == 'pec_deck').name, 'Machine chest fly (pec deck)');
  });
}
