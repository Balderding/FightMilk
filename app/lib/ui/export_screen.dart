import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dart:convert';
import 'dart:typed_data';

import '../data/backup.dart' show lockBackup;
import '../data/export.dart';
import '../domain/units.dart';
import '../services/handoff.dart';
import 'app_state.dart';
import 'history_screen.dart' show fmtDate;
import 'theme.dart';
import 'widgets.dart';

/// Settings → Export (batch 20, F313): what, format, unit and dates on one screen, then Save or
/// Share. Nothing is sent by the app; the person picks where the file goes.
class ExportScreen extends StatefulWidget {
  final AppState s;
  final ExportKind? kind;
  const ExportScreen({super.key, required this.s, this.kind});
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

enum _Range { all, year, days90, days30, pick }

class _ExportScreenState extends State<ExportScreen> {
  AppState get s => widget.s;
  late ExportKind kind = widget.kind ?? s.exportPreset ?? ExportKind.strong;
  late Unit unit = s.unit;
  _Range range = _Range.all;
  DateTimeRange? picked;
  bool busy = false;

  (DateTime?, DateTime?) get _dates {
    final now = DateTime.now();
    return switch (range) {
      _Range.all => (null, null),
      _Range.year => (DateTime(now.year), now),
      _Range.days90 => (now.subtract(const Duration(days: 90)), now),
      _Range.days30 => (now.subtract(const Duration(days: 30)), now),
      _Range.pick => (picked?.start, picked?.end),
    };
  }

  Future<ExportFile?> _build() async {
    // body data only when the person says so, asked once per export in plain words
    var body = false;
    if (bodyKinds.contains(kind)) {
      final a = await askBodyData(context, forYou: kind == ExportKind.backup);
      if (a == null) return null;
      body = a;
    }
    final (from, to) = datedKinds.contains(kind) ? _dates : (null, null);
    final f = await buildExport(kind, s.repo, s.lib, ExportOptions(unit: unit, from: from, to: to, body: body), tape: [for (final t in s.tape) t.toJson()]);
    if (kind != ExportKind.backup || !mounted) return f;
    final pw = await askLock(context); // a backup may be locked with a password (F338)
    if (pw == null) return null;
    if (pw.isEmpty || !mounted) return pw.isEmpty ? f : null;
    final locked = await busyWhile(context, 'Locking…', () => lockBackup(utf8.decode(f.bytes), pw));
    return ExportFile(f.name.replaceFirst('.json', '.locked.json'), f.mime, Uint8List.fromList(utf8.encode(locked)));
  }

  Future<void> _go(bool share) async {
    setState(() => busy = true);
    try {
      final f = await _build();
      if (f == null || !mounted) return;
      if (share) {
        final path = await writeForShare(f);
        final r = await shareFile(path, f.mime, title: 'Send ${f.name}');
        if (mounted && r != 'chooser') toast(context, 'Could not open the share menu.');
      } else {
        final uri = await FilePicker.saveFile(fileName: f.name, bytes: f.bytes, mimeType: f.mime, dialogTitle: 'Save ${f.name}');
        if (uri != null && kind == ExportKind.backup) await s.noteManualBackup();
        if (mounted) toast(context, uri == null ? 'Not saved.' : 'Saved ${f.name}.');
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not make the file: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dated = datedKinds.contains(kind);
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Dim('Made on this phone. It only goes where you save or send it. Progress photos are never in any file.', size: 12),
        const SizedBox(height: 8),
        const Q('What'),
        RadioGroup<ExportKind>(
          groupValue: kind,
          onChanged: (v) => setState(() => kind = v!),
          child: Column(children: [
            for (final k in ExportKind.values)
              RadioListTile<ExportKind>(dense: true, contentPadding: EdgeInsets.zero, value: k, title: Text(exportLabel[k]!), subtitle: _hint(k)),
          ]),
        ),
        const Q('Weights in'),
        Pills<Unit>(values: const [Unit.kg, Unit.lb], label: unitLabel, selected: {unit}, onTap: (u) => setState(() => unit = u)),
        if (dated) ...[
          const Q('Dates'),
          Pills<_Range>(
            values: _Range.values,
            label: (r) => switch (r) {
              _Range.all => 'All',
              _Range.year => 'This year',
              _Range.days90 => '90 days',
              _Range.days30 => '30 days',
              _Range.pick => picked == null ? 'Pick…' : '${fmtDate(picked!.start)} – ${fmtDate(picked!.end)}',
            },
            selected: {range},
            onTap: (r) async {
              if (r == _Range.pick) {
                final d = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now());
                if (d == null) return;
                picked = d;
              }
              setState(() => range = r);
            },
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: busy ? null : () => _go(false), icon: const Icon(Icons.save_alt), label: const Text('Save file'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => _go(true), icon: const Icon(Icons.share), label: const Text('Share'))),
        ]),
        const SizedBox(height: 8),
        const Dim('Share opens Android\'s share menu: you pick the app (email, Drive, a chat). Formats are described in the zip\'s README.', size: 12),
      ]),
    );
  }

  Widget? _hint(ExportKind k) => switch (k) {
        ExportKind.strong => const Dim('Strong, Hevy, Liftosaur and spreadsheets import this.', size: 12),
        ExportKind.everything => const Dim('One row per set with every detail, kg and lb.', size: 12),
        ExportKind.text => const Dim('For a notes app or your own AI.', size: 12),
        ExportKind.tcx => const Dim('Upload it yourself on Garmin Connect or Strava.', size: 12),
        ExportKind.sqlite => const Dim('The app\'s database as it is (no photos).', size: 12),
        ExportKind.backup => const Dim('Import it again in Settings → Your data.', size: 12),
        _ => null,
      };
}

/// Asks once whether body data goes in. Null: the person backed out. [forYou]: a backup (for
/// the person themself), where "Put it in" comes first; for files for others "Leave it out" does.
/// Both buttons look the same, so neither is "the obvious one" (review 5, P1-3).
Future<bool?> askBodyData(BuildContext context, {bool forYou = false}) => showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.card,
      builder: (c) {
        final no = OutlinedButton(key: const Key('bodyNo'), onPressed: () => Navigator.pop(c, false), child: const Text('Leave it out'));
        final yes = OutlinedButton(key: const Key('bodyYes'), onPressed: () => Navigator.pop(c, true), child: const Text('Put it in'));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Put your body data in this file?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Dim('Body data is your weigh-ins, body fat, tape measurements, height, body-weight goal and pregnancy answer. Anyone you give the file to can read it. Progress photos are never in any file.'),
              if (forYou) const Padding(padding: EdgeInsets.only(top: 6), child: Dim('A backup is for you: put it in, or a restore from this file brings no body data back (the phone keeps what it has).', size: 12)),
              const SizedBox(height: 12),
              forYou ? yes : no,
              const SizedBox(height: 6),
              forYou ? no : yes,
            ]),
          ),
        );
      },
    );

/// Lock a backup with a password? '' = no password, null = backed out (batch 22, F338).
Future<String?> askLock(BuildContext context) async {
  final a = TextEditingController(), b = TextEditingController();
  String? err;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Lock the backup with a password?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Dim('Then only someone with the password can read it. Keep the password safe: without it the backup cannot be opened, not even by the app.', size: 12),
          TextField(key: const Key('pw1'), enableIMEPersonalizedLearning: false, controller: a, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Password (8 or more characters)'), onChanged: (_) => set(() => err = null)),
          // a gentle hint, never a block (review 7, P3-7)
          if (a.text.length >= 8 && a.text.length < 12) const Padding(padding: EdgeInsets.only(top: 4), child: Dim('Longer is stronger: 12 or more characters is a good length.', size: 12)),
          TextField(key: const Key('pw2'), enableIMEPersonalizedLearning: false, controller: b, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'The same again')),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: C.gold))),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('lockYes'),
            onPressed: () {
              if (a.text.length < 8) return set(() => err = 'Use 8 or more characters.');
              if (!RegExp(r'\S').hasMatch(a.text)) return set(() => err = 'Use letters, numbers or signs, not only spaces.'); // review 7, P3-7
              if (a.text != b.text) return set(() => err = 'The two passwords are not the same.');
              Navigator.pop(c, a.text);
            },
            child: const Text('Lock it'),
          ),
          const SizedBox(height: 6),
          OutlinedButton(key: const Key('lockNo'), onPressed: () => Navigator.pop(c, ''), child: const Text('No password')),
        ]),
      ),
    ),
  );
}

/// The password of a locked backup, to restore it. Null = backed out.
Future<String?> askUnlock(BuildContext context, {String? problem}) async {
  final a = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('This backup is locked', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        if (problem != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(problem, style: const TextStyle(color: C.gold))),
        TextField(enableIMEPersonalizedLearning: false, controller: a, obscureText: true, autocorrect: false, enableSuggestions: false, autofocus: true, decoration: const InputDecoration(labelText: 'Password')),
        const SizedBox(height: 10),
        FilledButton(onPressed: () => Navigator.pop(c, a.text), child: const Text('Open it')),
      ]),
    ),
  );
}

/// Writes [f] into the cache's exports/ folder (the only place the share menu may read from),
/// after clearing what an earlier share left there.
Future<String> writeForShare(ExportFile f) async {
  final d = Directory(p.join((await getTemporaryDirectory()).path, 'exports'));
  if (d.existsSync()) d.deleteSync(recursive: true);
  d.createSync(recursive: true);
  final path = p.join(d.path, f.name);
  File(path).writeAsBytesSync(f.bytes, flush: true);
  return path;
}
