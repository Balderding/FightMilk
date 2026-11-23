import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/backup.dart';
import '../data/recovery.dart';
import '../services/crash_log.dart';
import 'export_screen.dart' show askBodyData, askLock;
import 'theme.dart';
import 'widgets.dart';

/// F431: shown only when the app cannot open or read its data at start. It never resets
/// anything: it can save a copy of the data as a normal backup, try again, or show the details.
class RecoveryScreen extends StatefulWidget {
  final StartFailure failure;
  final VoidCallback onRetry;
  const RecoveryScreen({super.key, required this.failure, required this.onRetry});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  String? copyProblem; // even the copy could not be made or opened

  StartFailure get f => widget.failure;

  Future<void> _saveCopy() async {
    final body = await askBodyData(context, forYou: true);
    if (body == null || !mounted) return;
    try {
      final dir = await getApplicationSupportDirectory();
      if (!mounted) return;
      final plain = await busyWhile(context, 'Making a copy of your data…', () => recoveryBackup(f.path, dir, body: body));
      if (!mounted) return;
      final pw = await askLock(context);
      if (pw == null || !mounted) return;
      final text = pw.isEmpty ? plain : await busyWhile(context, 'Locking…', () => lockBackup(plain, pw));
      final d = DateTime.now();
      final name = 'fightmilk-rescue-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}${pw.isEmpty ? '' : '.locked'}.json';
      final uri = await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(text)), mimeType: 'application/json', dialogTitle: 'Save a copy of your data');
      if (mounted) toast(context, uri == null ? 'Not saved.' : 'Saved. It restores like any backup, in Settings → Backup.');
    } on StartFailure catch (e) {
      setState(() => copyProblem = 'Even a copy could not be opened: ${e.reason}');
    } catch (_) {
      setState(() => copyProblem = 'The copy could not be saved.');
    }
  }

  Future<void> _details() async {
    final head = 'FightMilk could not start.\nWhere: ${f.path}\nWhy: ${f.reason}\n\n';
    final text = await (CrashLog.current?.text(header: head) ?? Future.value(head));
    if (!mounted) return;
    await showDetails(context, text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('FightMilk could not open your data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Dim('Nothing was deleted or changed.'),
            const SizedBox(height: 12),
            Problem([f.reason, 'Where: ${f.path}']),
            const SizedBox(height: 16),
            if (copyProblem == null) ...[
              FilledButton.icon(icon: const Icon(Icons.save_alt), label: const Text('Save a copy of my data'), onPressed: _saveCopy),
              const SizedBox(height: 4),
              const Dim('A normal backup file, made from a copy: your progress photos are never in it, and body data only if you say so.', size: 12),
            ] else
              Problem([copyProblem!]),
            const SizedBox(height: 10),
            OutlinedButton.icon(icon: const Icon(Icons.refresh), label: const Text('Try again'), onPressed: widget.onRetry),
            const SizedBox(height: 6),
            TextButton.icon(icon: const Icon(Icons.description_outlined), label: const Text('Copy the details'), onPressed: _details),
          ]),
        ),
      );
}

/// The details as text, shown first; copied only on the person's tap (a keyboard may sync the
/// clipboard).
Future<void> showDetails(BuildContext context, String text) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const Dim('Only the kind of each error and where in the app it happened: no workouts, notes or numbers.', size: 12),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.5),
              child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Copy'),
            ),
          ]),
        ),
      ),
    );

/// The crash log file in the app's private folder.
Future<File> crashLogFile() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}crash_log.json');
