import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/domain/library.dart';

/// The exercise search: every word, any order, with the names gyms use (the user looked for
/// a machine chest fly and a machine reverse fly and found neither).
void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  List<String> ids(String q) => [for (final e in lib.search(q)) e.id];

  test('machine chest fly and machine reverse fly are found by what people call them', () {
    expect(ids('chest fly'), contains('pec_deck'));
    expect(ids('machine chest fly'), ['pec_deck']);
    expect(ids('machine fly'), containsAll(['pec_deck', 'reverse_pec_deck']));
    expect(ids('reverse fly'), contains('reverse_pec_deck'));
    expect(ids('machine reverse fly'), ['reverse_pec_deck']);
    expect(ids('rear delt fly machine'), ['reverse_pec_deck']);
    expect(ids('butterfly'), ['pec_deck']);
  });

  test('words in any order; names, muscles and equipment still found', () {
    expect(ids('press bench'), contains('bench_press'));
    expect(ids('Bench Press'), contains('bench_press'));
    expect(ids('dumbbell'), contains('db_fly'));
    expect(ids('  '), hasLength(lib.all.length));
    expect(ids('no such lift at all'), isEmpty);
  });
}
