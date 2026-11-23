import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../data/export.dart';
import '../domain/plan.dart';
import '../domain/plan_share.dart';
import '../services/handoff.dart';
import 'app_state.dart';
import 'export_screen.dart' show writeForShare;
import 'theme.dart';
import 'widgets.dart';

/// Plan → Share plan (batch 20): every way to pass a plan on, with no server. Nothing about the
/// person is in it: only the plan's name, days, exercises, sets, reps and rules.
Future<void> planShareSheet(BuildContext context, AppState s, Plan plan, {int? onlyDay}) async {
  final what = onlyDay == null ? '"${plan.name}"' : '"${plan.days[onlyDay].name}"';
  final pick = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('Share $what'), subtitle: const Dim('Only the plan goes: days, exercises, sets, reps and rules. Nothing about you.', size: 12)),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('As a file'), subtitle: const Dim('A friend opens it with FightMilk.', size: 12), onTap: () => Navigator.pop(c, 'file')),
          ListTile(leading: const Icon(Icons.notes), title: const Text('As text'), subtitle: const Dim('Anyone can read it; FightMilk reads it back.', size: 12), onTap: () => Navigator.pop(c, 'text')),
          ListTile(leading: const Icon(Icons.link), title: const Text('As a link'), subtitle: const Dim('The whole plan is inside the link. No server.', size: 12), onTap: () => Navigator.pop(c, 'link')),
          ListTile(leading: const Icon(Icons.qr_code_2), title: const Text('As a QR code'), subtitle: const Dim('Scan it with the phone camera.', size: 12), onTap: () => Navigator.pop(c, 'qr')),
          ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Print it (PDF)'), subtitle: const Dim('A page per week with boxes for your weights.', size: 12), onTap: () => Navigator.pop(c, 'pdf')),
          if (onlyDay == null && plan.days.length > 1) ListTile(leading: const Icon(Icons.today_outlined), title: const Text('Just one day'), onTap: () => Navigator.pop(c, 'day')),
        ]),
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  switch (pick) {
    case 'file':
      final f = ExportFile('${_safe(onlyDay == null ? plan.name : plan.days[onlyDay].name)}.fightmilk.json', 'application/json', Uint8List.fromList(utf8.encode(sharePlanJson(plan, onlyDay: onlyDay))));
      if (await shareFile(await writeForShare(f), f.mime, title: 'Send the plan') != 'chooser' && context.mounted) toast(context, 'Could not open the share menu.');
    case 'text':
      await handOff(sharePlanText(plan, s.lib, onlyDay: onlyDay), '');
    case 'link':
      await handOff(sharePlanLink(plan, onlyDay: onlyDay), '');
    case 'qr':
      await showQr(context, sharePlanLink(plan, onlyDay: onlyDay), what);
    case 'pdf':
      await _pdf(context, s, onlyDay == null ? plan : plan.copyWith(days: [plan.days[onlyDay]]));
    case 'day':
      final d = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: C.card,
        builder: (c) => SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('Which day?')),
              for (var i = 0; i < plan.days.length; i++) ListTile(title: Text(plan.days[i].name), onTap: () => Navigator.pop(c, i)),
            ]),
          ),
        ),
      );
      if (d != null && context.mounted) await planShareSheet(context, s, plan, onlyDay: d);
  }
}

/// The QR code of [data] (a plan link), drawn on screen. Too big for one code: says so.
Future<void> showQr(BuildContext context, String data, String what) => showDialog<void>(
      context: context,
      builder: (d) {
        QrImage? img;
        try {
          img = QrImage(QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.low));
        } catch (_) {
          img = null;
        }
        return AlertDialog(
          backgroundColor: C.card,
          title: Text('QR code for $what'),
          content: img == null
              ? const Text('This plan is too big for one QR code. Send it as a file or a link instead.')
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    color: Colors.white, // a QR needs a light quiet zone around it
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(width: 260, height: 260, child: CustomPaint(key: const Key('qr'), painter: QrPainter(img))),
                  ),
                  const SizedBox(height: 8),
                  const Dim('Scan it with the phone camera; it opens in FightMilk. The plan is inside the code: nothing is fetched.', size: 12),
                ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Done'))],
        );
      },
    );

class QrPainter extends CustomPainter {
  final QrImage img;
  QrPainter(this.img);
  @override
  void paint(Canvas canvas, Size size) {
    final n = img.moduleCount;
    final m = size.shortestSide / n;
    final p = Paint()..color = Colors.black;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (img.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(c * m, r * m, m + 0.3, m + 0.3), p);
      }
    }
  }

  @override
  bool shouldRepaint(QrPainter old) => old.img != img;
}

Future<void> _pdf(BuildContext context, AppState s, Plan plan) async {
  final bytes = planPdf(plan, s.lib);
  final f = ExportFile('${_safe(plan.name)}.pdf', 'application/pdf', bytes);
  final how = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.save_alt), title: const Text('Save the PDF'), onTap: () => Navigator.pop(c, 'save')),
        ListTile(leading: const Icon(Icons.share), title: const Text('Share or print it'), subtitle: const Dim('Pick a print app or a printer from the share menu.', size: 12), onTap: () => Navigator.pop(c, 'share')),
      ]),
    ),
  );
  if (how == null) return;
  try {
    if (how == 'share') {
      await shareFile(await writeForShare(f), f.mime, title: 'Print or send ${f.name}');
    } else {
      final uri = await FilePicker.saveFile(fileName: f.name, bytes: f.bytes, mimeType: f.mime, dialogTitle: 'Save ${f.name}');
      if (context.mounted) toast(context, uri == null ? 'Not saved.' : 'Saved ${f.name}.');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Could not make the PDF: $e');
  }
}

String _safe(String n) {
  final s = n.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(' ', '-');
  return s.isEmpty ? 'plan' : s;
}
