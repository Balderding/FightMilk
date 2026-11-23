import 'dart:convert';
import 'dart:math';

import 'library.dart';
import 'plan.dart';

/// Batch 23, F357: the training days as a calendar file (.ics, RFC 5545) the person saves and
/// opens in their own calendar app. Weekly repeating events: the day's name and its exercises;
/// never weights or body numbers. Nothing is sent anywhere.
///
/// [weekdays] (1 = Monday): when it has one weekday per plan day, each day gets its own event
/// on its weekday; otherwise one event "FightMilk workout" on [days] (the app picks the day in
/// line). [at] is minutes after midnight, [minutes] the length.
String planIcs(Plan plan, Library lib, {required List<int> weekdays, required List<int> days, required int at, int minutes = 60, required DateTime now}) {
  const by = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  final events = <(String title, String what, List<int> on)>[];
  if (weekdays.isNotEmpty && weekdays.length == plan.days.length) {
    for (var i = 0; i < plan.days.length; i++) {
      final d = plan.days[i];
      events.add(('FightMilk: ${d.name}', [for (final it in d.items) lib.byId(it.exerciseId)?.name ?? it.exerciseId].join(', '), [weekdays[i]]));
    }
  } else if (days.isNotEmpty) {
    events.add(('FightMilk workout', 'The app has your next workout ready (the next day in line).', ([...days.toSet()]..sort())));
  }
  final rnd = Random.secure();
  String id() => [for (var i = 0; i < 16; i++) rnd.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  String two(int v) => v.toString().padLeft(2, '0');
  String local(DateTime d) => '${d.year}${two(d.month)}${two(d.day)}T${two(d.hour)}${two(d.minute)}00';
  final u = now.toUtc();
  final stamp = '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  final out = <String>['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//FightMilk//Plan//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH'];
  for (final (title, what, on) in events) {
    // the first of these weekdays from today, at the chosen time
    var first = DateTime(now.year, now.month, now.day, at ~/ 60, at % 60);
    for (var k = 0; k < 7 && !on.contains(first.weekday); k++) {
      first = first.add(const Duration(days: 1));
    }
    out.addAll([
      'BEGIN:VEVENT',
      'UID:${id()}@fightmilk',
      'DTSTAMP:$stamp',
      'DTSTART:${local(first)}',
      'DURATION:PT${minutes.clamp(10, 300)}M',
      'RRULE:FREQ=WEEKLY;BYDAY=${[for (final d in on) by[d - 1]].join(',')}',
      'SUMMARY:${icsText(title)}',
      'DESCRIPTION:${icsText(what)}',
      'END:VEVENT',
    ]);
  }
  out.add('END:VCALENDAR');
  return '${out.map(icsFold).join('\r\n')}\r\n';
}

/// RFC 5545 text: backslash, semicolon, comma and new lines escaped.
String icsText(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll(RegExp(r'\r?\n'), '\\n');

/// Lines longer than 75 bytes are folded (CRLF and a space), never inside a UTF-8 character.
String icsFold(String line) {
  final b = StringBuffer();
  var n = 0;
  for (final r in line.runes) {
    final ch = String.fromCharCode(r);
    final len = utf8.encode(ch).length;
    if (n + len > 75) {
      b.write('\r\n ');
      n = 1;
    }
    b.write(ch);
    n += len;
  }
  return b.toString();
}
