import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../data/import_store.dart';
import '../domain/exercise.dart';
import '../domain/import.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'history_screen.dart' show fmtDate;
import 'pickers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Settings → Your data → Import (batch 21, F330-F337): history from other apps. The file is read
/// and shown first: what it holds, what was guessed (the unit, the date order, the exercise
/// names) and what was left out. Nothing is saved until "Import"; an import only adds, and it can
/// be undone whole.
class ImportScreen extends StatefulWidget {
  final AppState s;
  final String? text; // a file opened with FightMilk (F337)
  const ImportScreen({super.key, required this.s, this.text});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  AppState get s => widget.s;
  String? text, fileName;
  ImportRead? read;
  Unit? unit; // the person's choice, once seen
  bool? dayFirst;
  Map<String, String?> names = {}; // file name -> our id, null = leave out
  Set<String> guessed = {}; // matched, but not sure: shown in gold to check (review 6 P1-2)
  Set<int> dup = {}, dupBody = {};
  bool keepDup = false, busy = false, reading = false;
  List<ImportRecord> done = [];

  @override
  void initState() {
    super.initState();
    _loadDone();
    if (widget.text != null) _read(widget.text!, 'the shared file');
  }

  Future<void> _loadDone() async {
    final l = await importRecords(s.repo);
    if (mounted) setState(() => done = l.reversed.toList());
  }

  Future<void> _read(String t, String from) async {
    setState(() => reading = true);
    ImportRead r;
    try {
      // off the UI thread: an 8 MB file takes seconds (review 6 P2-7, self7 P2-9)
      r = await compute(_readIsolate, (t, s.unit, unit, dayFirst));
    } catch (_) {
      r = readImport(t, appUnit: s.unit, unit: unit, dayFirst: dayFirst); // no isolate here: read in place
    }
    if (!mounted) return;
    final m = <String, String?>{};
    for (final n in r.names) {
      if (names.containsKey(n)) {
        m[n] = names[n];
      } else {
        final (e, sure) = matchName(n, s.lib);
        m[n] = e?.id;
        if (e != null && !sure) guessed.add(n);
      }
    }
    final d = r.ok ? await duplicates(s.repo, r) : <int>{};
    final db = r.ok ? await bodyDuplicates(s.repo, r) : <int>{};
    if (!mounted) return;
    setState(() {
      reading = false;
      text = t;
      fileName = from;
      read = r;
      names = m;
      dup = d;
      dupBody = db;
    });
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFiles(dialogTitle: 'Pick a history file (.csv)');
    if (f.isEmpty) return;
    if ((f.first.lengthSync() ?? await f.first.length() ?? 0) > importMaxBytes) { // checked before it is read (review 5, P3-N30)
      if (mounted) toast(context, 'That file is too big to import (over 8 MB).');
      return;
    }
    final bytes = await f.first.readAsBytes();
    await AppState.clearPicked(); // the picker's copy goes at once
    String t;
    try {
      t = utf8.decode(bytes);
    } on FormatException {
      t = latin1.decode(bytes); // older exports; the reader still checks it
    }
    await _read(t, f.first.name);
  }

  Future<void> _paste() async {
    final c = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (b) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(b).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Paste a CSV', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          TextField(enableIMEPersonalizedLearning: false, controller: c, minLines: 6, maxLines: 10, decoration: const InputDecoration(hintText: 'Date,Exercise,Weight,Reps\n2026-11-05,Squat,100,5')),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(b, true), child: const Text('Read it')),
        ]),
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) await _read(c.text, 'pasted text');
  }

  Future<void> _import() async {
    final r = read!;
    setState(() => busy = true);
    try {
      final rec = await saveImport(s.repo, r, names, skip: keepDup ? const {} : dup, skipBody: keepDup ? const {} : dupBody, label: '${importFormatName[r.format]} (${fileName ?? 'file'})');
      await s.historyChanged(rec.exercises); // progression from the imported history (F336)
      await s.reload();
      if (!mounted) return;
      toast(context, 'Imported ${rec.sessions.length} workout${rec.sessions.length == 1 ? '' : 's'}${rec.body.isEmpty ? '' : ' and ${rec.body.length} weigh-ins'}. Undo it below if it looks wrong.');
      setState(() {
        read = null;
        text = null;
        names = {};
      });
      await _loadDone();
    } catch (e) {
      if (mounted) toast(context, 'The import could not be saved, so nothing was added. ($e)');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _undo(ImportRecord rec) async {
    if (!await confirm(context, 'Undo this import?',
        'The ${rec.sessions.length} workouts and ${rec.body.length} weigh-ins it brought in are taken out again, with anything you added to those workouts since. Your own workouts stay, and your lifts go back to their weights from before.',
        yes: 'Undo it')) return;
    final ex = await undoImport(s.repo, rec.id);
    await s.historyChanged(ex);
    await s.reload();
    await _loadDone();
    if (mounted) toast(context, 'Import undone.');
  }

  @override
  Widget build(BuildContext context) {
    final r = read;
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Dim('Bring in your history from Strong, Hevy, FitNotes, Liftosaur, Fitbod, FightMilk, or any CSV with a date, exercise, weight and reps (or a date and body weight). '
            'It is read on this phone and shown to you first; nothing is saved until you tap Import, and an import can be undone.', size: 12),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.file_open_outlined), label: const Text('Pick a file')),
          OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text('Paste')),
        ]),
        if (reading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (r != null && !r.ok && !reading) ...[
          const SizedBox(height: 12),
          Problem([r.problem ?? 'Nothing in the file could be read.', ...r.skipped.take(3)]),
        ],
        if (r != null && r.ok && !reading) ..._preview(r),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Your imports', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final d in done)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(d.label),
              subtitle: Dim('${d.sessions.length} workouts${d.body.isEmpty ? '' : ', ${d.body.length} weigh-ins'}${d.from == null ? '' : ' from ${fmtDate(d.from!)} to ${fmtDate(d.to!)}'} · imported ${fmtDate(d.at)}', size: 12),
              trailing: TextButton(onPressed: () => _undo(d), child: const Text('Undo')),
            ),
        ],
      ]),
    );
  }

  List<Widget> _preview(ImportRead r) {
    final workouts = r.workouts.length - (keepDup ? 0 : dup.length);
    final left = [for (final e in names.entries) if (e.value == null) e.key];
    final dates = r.workouts.isEmpty ? (r.body.isEmpty ? null : (r.body.first.$1, r.body.last.$1)) : (r.workouts.first.start, r.workouts.last.start);
    return [
      const SizedBox(height: 14),
      Text(importFormatName[r.format]!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      Dim([
        if (r.workouts.isNotEmpty) '${r.workouts.length} workouts${dup.isEmpty ? '' : ' (${dup.length} already here)'}, ${r.sets} sets',
        if (r.body.isNotEmpty) '${r.body.length} weigh-ins',
        if (dates != null) '${fmtDate(dates.$1)} to ${fmtDate(dates.$2)}',
      ].join(' · ')),
      if (r.capped) const Text('The file has more than 200 000 rows; only the first ones were read.', style: TextStyle(color: C.gold, fontSize: 13)),
      // the unit: said where it came from; gold when it is only a guess
      const Q('Weights in the file'),
      Text(r.unitWhy, key: const Key('unitWhy'), style: TextStyle(fontSize: 13, color: r.unitGuessed ? C.gold : C.text)),
      if (!r.unitWhy.startsWith('each row'))
      Pills<Unit>(
        values: const [Unit.kg, Unit.lb],
        label: unitLabel,
        selected: {r.unit},
        onTap: (u) async {
          unit = u;
          await _read(text!, fileName!);
        },
      ),
      if (r.dateAmbiguous) ...[
        const Q('Dates like 05/06'),
        const Text('These dates read both ways. Which comes first?', style: TextStyle(fontSize: 13, color: C.gold)),
        Pills<bool>(
          values: const [true, false],
          label: (v) => v ? 'Day first (5 June)' : 'Month first (May 6)',
          selected: {r.dayFirst},
          onTap: (v) async {
            dayFirst = v;
            await _read(text!, fileName!);
          },
        ),
      ],
      if (names.isNotEmpty) ...[
        const Q('Exercises'),
        Dim('${names.length - left.length} of ${names.length} found in the app${guessed.isEmpty ? '' : ', ${guessed.length} guessed'}. Tap one to change it.', size: 12),
        for (final e in names.entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(e.key),
            subtitle: e.value == null
                ? const Text('Not found: pick one, or it is left out', style: TextStyle(color: C.gold, fontSize: 12))
                : guessed.contains(e.key)
                    ? Text('Guessed: ${s.lib.byId(e.value!)?.name ?? e.value}. Check it', key: const Key('guessed'), style: const TextStyle(color: C.gold, fontSize: 12))
                    : Dim('→ ${s.lib.byId(e.value!)?.name ?? e.value}', size: 12),
            trailing: e.value == null ? const Icon(Icons.search, color: C.gold) : const Icon(Icons.edit_outlined, size: 18, color: C.dim),
            onTap: () async {
              final ex = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => ExercisePicker(s: s, title: 'Which is "${e.key}"?')));
              if (ex != null) {
                setState(() {
                  names[e.key] = ex.id;
                  guessed.remove(e.key); // the person chose it
                });
              }
            },
            onLongPress: () => setState(() {
              names[e.key] = null;
              guessed.remove(e.key);
            }),
          ),
        if (names.values.any((v) => v != null)) const Dim('Long-press one to leave it out.', size: 12),
      ],
      if (dup.isNotEmpty || dupBody.isNotEmpty)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: keepDup,
          onChanged: (v) => setState(() => keepDup = v),
          title: Text([
            if (dup.isNotEmpty) '${dup.length} workout${dup.length == 1 ? '' : 's'}',
            if (dupBody.isNotEmpty) '${dupBody.length} weigh-in${dupBody.length == 1 ? '' : 's'}',
          ].join(' and ') + ' already on this phone'),
          subtitle: Dim(keepDup ? 'They are imported again (twice in your history).' : 'They are left out.', size: 12),
        ),
      if (r.skippedCount > 0)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('${r.skippedCount} row${r.skippedCount == 1 ? '' : 's'} left out', style: const TextStyle(fontSize: 14)),
          children: [for (final x in r.skipped) Align(alignment: Alignment.centerLeft, child: Dim(x, size: 12)), if (r.skippedCount > r.skipped.length) Dim('… and ${r.skippedCount - r.skipped.length} more', size: 12)],
        ),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('doImport'),
        onPressed: busy || (workouts <= 0 && r.body.length - (keepDup ? 0 : dupBody.length) <= 0) || (r.workouts.isNotEmpty && names.values.every((v) => v == null)) ? null : _import,
        child: Text(r.workouts.isEmpty ? 'Import ${r.body.length - (keepDup ? 0 : dupBody.length)} weigh-ins' : 'Import $workouts workout${workouts == 1 ? '' : 's'}'),
      ),
      const Dim('Only adds: your own workouts stay as they are.', size: 12),
    ];
  }
}

/// [readImport] for [compute]: the file, the app unit, the chosen unit and date order.
ImportRead _readIsolate((String, Unit, Unit?, bool?) a) => readImport(a.$1, appUnit: a.$2, unit: a.$3, dayFirst: a.$4);
