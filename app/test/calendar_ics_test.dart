import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/domain/calendar_ics.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';

/// Batch 23, F357: the training days as a calendar file.
void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final plan = Plan(id: 'p', name: 'Mine', days: [
    PlanDay(name: 'Day A, legs; "heavy"', items: [PlanItem(exerciseId: 'back_squat', sets: 3, repLow: 5, repHigh: 5, restSec: 140)]),
    PlanDay(name: 'Day B', items: [PlanItem(exerciseId: 'bench_press', sets: 3, repLow: 5, repHigh: 5, restSec: 102)]),
  ]);
  final now = DateTime(2026, 11, 22, 20); // a Sunday

  test('one weekly event per plan day on its weekday, at the chosen time; never weights', () {
    final ics = planIcs(plan, lib, weekdays: [1, 4], days: [1, 4], at: 17 * 60 + 30, minutes: 60, now: now);
    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
    expect(ics, contains('DTSTART:20261123T173000\r\n'), reason: 'Monday the 23rd, 17:30');
    expect(ics, contains('DTSTART:20261126T173000\r\n'), reason: 'Thursday the 26th');
    expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=MO\r\n'));
    expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=TH\r\n'));
    expect(ics, contains('DURATION:PT60M'));
    expect(ics, contains(r'SUMMARY:FightMilk: Day A\, legs\; "heavy"'), reason: 'RFC 5545 escapes');
    expect(ics, contains('DESCRIPTION:Back squat'));
    // the words people see (not the random UID or the time stamps, which can hold any digits)
    final words = ics.split('\r\n').where((l) => l.startsWith('SUMMARY:') || l.startsWith('DESCRIPTION:') || l.startsWith(' ')).join('\n');
    for (final n in ['140', '102', 'kg', 'lb']) {
      expect(words, isNot(contains(n)), reason: 'no weights in a calendar');
    }
    for (final line in ics.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: line);
    }
    expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')), reason: 'CRLF line ends only');
  });

  test('days not tied to weekdays: one event on the reminder days', () {
    final ics = planIcs(plan, lib, weekdays: const [], days: [5, 1, 3, 3], at: 7 * 60, now: now);
    expect('BEGIN:VEVENT'.allMatches(ics).length, 1);
    expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR'));
    expect(ics, contains('SUMMARY:FightMilk workout'));
    expect(ics, contains('DTSTART:20261123T070000'));
  });

  test('no days: an empty calendar, still a valid file', () {
    final ics = planIcs(plan, lib, weekdays: const [], days: const [], at: 0, now: now);
    expect(ics, isNot(contains('VEVENT')));
    expect(ics, contains('END:VCALENDAR'));
  });

  test('folding never cuts a UTF-8 character, and unfolds back to the same text', () {
    final long = 'SUMMARY:${'Überzüge ' * 20}';
    final f = icsFold(long);
    for (final line in f.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }
    expect(f.replaceAll('\r\n ', ''), long);
  });
}
