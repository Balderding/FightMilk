import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/export.dart';
import '../domain/exercise.dart';
import '../domain/library.dart';
import '../domain/reports.dart';
import '../domain/stats.dart';
import '../domain/units.dart';
import '../services/handoff.dart';
import 'export_screen.dart' show writeForShare;
import 'history_screen.dart' show fmtDate;
import 'lift_chart.dart';
import 'theme.dart';
import 'widgets.dart';

/// Share images (batch 20, F322): a workout, a record, a recap or a lift chart as a picture, in
/// dark, light or clear (see-through, to lay over your own picture). A card is drawn from words
/// and numbers only: **never a progress photo**, and body numbers only when [CardData] was made
/// with them asked for (MCP guardrail 4). Nothing is sent: the person picks the app.
class CardData {
  final String kicker, title;
  final List<(String, String)> stats; // big numbers: (label, value)
  final List<String> lines;
  final List<Pt> chart; // optional line (already in the person's unit)
  final String file; // file name without .png
  const CardData({required this.kicker, required this.title, this.stats = const [], this.lines = const [], this.chart = const [], required this.file});

  /// Every word on the card, for checks.
  String get text => [kicker, title, for (final (a, b) in stats) '$a $b', ...lines].join('\n');
}

String _day(DateTime d) => fmtDate(d);
String _f(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

CardData workoutCard(String name, DateTime start, DateTime? end, List<SetLog> sets, Library lib, Unit u, {int records = 0}) {
  final work = [for (final x in sets) if (x.counts) x];
  final vol = work.fold<double>(0, (a, x) => a + x.kg * x.reps);
  final by = <String, List<SetLog>>{};
  for (final x in work) {
    by.putIfAbsent(x.exerciseId, () => []).add(x);
  }
  return CardData(
    kicker: _day(start),
    title: name,
    stats: [
      if (end != null) ('Minutes', '${end.difference(start).inMinutes}'),
      ('Sets', '${work.length}'),
      ('Lifted', '${fmtNum(toUnit(vol, u).roundToDouble())} ${unitLabel(u)}'),
      if (records > 0) ('Records', '$records'),
    ],
    lines: [
      for (final e in by.entries.take(7))
        () {
          final ex = lib.byId(e.key);
          final best = e.value.reduce((a, b) => a.kg * (1 + a.reps / 30) >= b.kg * (1 + b.reps / 30) ? a : b);
          return '${ex?.name ?? e.key}: ${e.value.length} × ${ex?.timed == true ? '${best.secs ?? best.reps} s' : '${best.kg > 0 ? '${fmtWeight(best.kg, u)} ${unitLabel(u)} × ' : ''}${best.reps}'}';
        }(),
      if (by.length > 7) '+ ${by.length - 7} more',
    ],
    file: 'fightmilk-${_f(name)}-${start.year}-${start.month}-${start.day}',
  );
}

CardData recordCard(Exercise e, Rec r, Unit u) => CardData(
      kicker: 'New record · ${_day(r.at)}',
      title: e.name,
      stats: [(recordLabel[r.kind]!, recordText(r, u, bodyweight: e.bodyweight))],
      lines: [if (r.beforeSet != null || r.before != null) 'Was ${r.beforeSet != null ? '${fmtWeight(r.beforeSet!.kg, u)} ${unitLabel(u)} × ${r.beforeSet!.reps}' : fmtNum(r.before!)}'],
      file: 'fightmilk-record-${_f(e.name)}',
    );

/// [body]: the body weight change goes on the card only when the person turned it on.
CardData recapCard(String title, Report r, Unit u, {bool body = false}) => CardData(
      kicker: 'Recap',
      title: title,
      stats: [('Workouts', '${r.workouts}'), ('Lifted', bigWeight(r.volume, u)), ('Records', '${r.records}')],
      lines: [
        if (r.minutes > 0) '${r.minutes ~/ 60} h ${r.minutes % 60} min of training',
        if (r.mostDone.isNotEmpty) 'Most done: ${r.mostDone.first.$1.name}',
        if (r.mostImproved.isNotEmpty) 'Most improved: ${r.mostImproved.first.$1.name} +${fmtWeight(r.mostImproved.first.$2, u)} ${unitLabel(u)}',
        if (body && r.bodyChange != null) 'Body weight ${r.bodyChange! >= 0 ? '+' : '−'}${fmtWeight(r.bodyChange!.abs(), u)} ${unitLabel(u)}',
      ],
      file: 'fightmilk-recap-${_f(title)}',
    );

/// A lift's est. 1-rep max over time (no body weight on it).
CardData chartCard(Exercise e, List<Pt> e1rm, Unit u) => CardData(
      kicker: 'Est. 1-rep max',
      title: e.name,
      stats: [if (e1rm.isNotEmpty) ('Best', '${fmtNum(e1rm.map((p) => p.v).reduce((a, b) => a > b ? a : b))} ${unitLabel(u)}')],
      lines: [if (e1rm.length > 1) '${_day(e1rm.first.at)} to ${_day(e1rm.last.at)}'],
      chart: e1rm,
      file: 'fightmilk-chart-${_f(e.name)}',
    );

enum CardStyle { dark, light, clear }

/// The card, 360 × 450 (rendered at 3x: 1080 × 1350). Words and numbers only.
class ShareCard extends StatelessWidget {
  final CardData d;
  final CardStyle style;
  const ShareCard(this.d, {super.key, this.style = CardStyle.dark});

  @override
  Widget build(BuildContext context) {
    final bg = switch (style) { CardStyle.dark => C.bg, CardStyle.light => const Color(0xFFF4F6F7), CardStyle.clear => Colors.transparent };
    final fg = style == CardStyle.light ? const Color(0xFF10171C) : Colors.white;
    final dim = style == CardStyle.light ? const Color(0xFF55636B) : const Color(0xFFB8C4CA);
    final accent = style == CardStyle.light ? const Color(0xFF0B7A5A) : C.teal; // green on light, never red
    final shadow = style == CardStyle.clear ? const [Shadow(blurRadius: 6, color: Color(0xAA000000))] : null;
    TextStyle t(double size, Color c, {FontWeight w = FontWeight.w400}) => TextStyle(fontSize: size, color: c, fontWeight: w, shadows: shadow, decoration: TextDecoration.none);
    return SizedBox(
      width: 360,
      height: 450,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: style == CardStyle.clear ? null : BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.kicker, style: t(13, dim)),
            const SizedBox(height: 4),
            Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t(26, fg, w: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(spacing: 18, runSpacing: 10, children: [
              for (final (a, b) in d.stats)
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(b, style: t(24, accent, w: FontWeight.w800)),
                  Text(a, style: t(11.5, dim)),
                ]),
            ]),
            const SizedBox(height: 12),
            if (d.chart.length > 1)
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: ChartPainter(pts: d.chart, label: t(9, dim)),
                ),
              )
            else
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final l in d.lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(13.5, fg))),
                ]),
              ),
            if (d.chart.length > 1)
              for (final l in d.lines) Text(l, style: t(11.5, dim)),
            const SizedBox(height: 6),
            Text('FightMilk', style: t(11, dim, w: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// The PNG of a card drawn under [key].
Future<Uint8List> cardPng(GlobalKey key, {double ratio = 3}) async {
  final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final img = await b.toImage(pixelRatio: ratio);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// A preview with the style to pick, then Share or Save (1 tap from where it opens).
Future<void> shareCardSheet(BuildContext context, CardData d, {CardData? withBody}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (c) => _CardSheet(d, withBody),
    );

class _CardSheet extends StatefulWidget {
  final CardData d;
  final CardData? withBody;
  const _CardSheet(this.d, this.withBody);
  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  final key = GlobalKey();
  var style = CardStyle.dark;
  var body = false; // body numbers only when turned on

  CardData get d => body && widget.withBody != null ? widget.withBody! : widget.d;

  Future<void> _go(bool share) async {
    try {
      final f = ExportFile('${d.file}-${style.name}.png', 'image/png', await cardPng(key));
      if (share) {
        if (await shareFile(await writeForShare(f), f.mime, title: 'Share the picture') != 'chooser' && mounted) toast(context, 'Could not open the share menu.');
      } else {
        final uri = await FilePicker.saveFile(fileName: f.name, bytes: f.bytes, mimeType: f.mime, dialogTitle: 'Save the picture');
        if (mounted) toast(context, uri == null ? 'Not saved.' : 'Saved ${f.name}.');
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not make the picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              color: style == CardStyle.clear ? const Color(0xFF6B7C85) : null, // shows the see-through card on a grey
              child: FittedBox(child: RepaintBoundary(key: key, child: ShareCard(d, style: style))),
            ),
            const SizedBox(height: 10),
            Pills<CardStyle>(values: CardStyle.values, label: (v) => switch (v) { CardStyle.dark => 'Dark', CardStyle.light => 'Light', CardStyle.clear => 'Clear' }, selected: {style}, onTap: (v) => setState(() => style = v)),
            if (widget.withBody != null)
              SwitchListTile(contentPadding: EdgeInsets.zero, value: body, onChanged: (v) => setState(() => body = v), title: const Text('Show my body weight change'), subtitle: const Dim('Off unless you turn it on.', size: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => _go(true), icon: const Icon(Icons.share), label: const Text('Share'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: () => _go(false), icon: const Icon(Icons.save_alt), label: const Text('Save'))),
            ]),
            const SizedBox(height: 6),
            const Dim('Only what you see on the card is in the picture. Never your progress photos.', size: 12),
          ]),
        ),
      );
}
