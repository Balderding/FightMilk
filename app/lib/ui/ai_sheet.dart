import 'package:flutter/material.dart';

import '../ai/ai.dart';
import '../services/handoff.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ask the coach a free question. Returns the answer text, or null (cancelled / failed, with a message shown).
Future<String?> runAsk(BuildContext context, AppState s, Future<AiRequest> Function() build) async {
  if (!await s.aiReady()) {
    if (context.mounted) toast(context, 'Set up the Ask AI in Settings first (service, model and key, or your server address).');
    return null;
  }
  final r = await build();
  if (!context.mounted) return null;
  if (s.settings.ai.isHandoff) {
    final app = chatApps[s.settings.ai.model] ?? 'your chat app';
    final res = await handOff(handoffText(r, project: s.settings.chatProject), s.settings.ai.model);
    if (context.mounted) {
      toast(context, switch (res) {
        'app' => 'Opened in $app. Tap send there; the answer stays in $app.',
        'missing' => '$app is not installed, so the share menu opened instead. (Also copied.)',
        'failed' => 'Could not open an app. The question is copied: paste it into your chat app.',
        _ => 'Pick your chat app. (Also copied.)',
      });
    }
    return null;
  }
  if (s.settings.preview && !s.settings.ai.isOnDevice) {
    final go = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: C.card, builder: (c) => _Preview(r));
    if (go != true) return null;
  }
  try {
    return await s.aiSend(r);
  } on AiError catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (e) {
    if (context.mounted) toast(context, 'Something went wrong: $e');
  }
  return null;
}

/// Shows exactly what will be sent (when the preview setting is on), sends it, checks the answer.
/// Returns true when the AI's plan/day was used.
Future<bool> runAi(BuildContext context, AppState s, Future<AiRequest> Function() build) async {
  if (!await s.aiReady()) {
    if (context.mounted) toast(context, 'Set up the Ask AI in Settings first (service, model and key, or your server address).');
    return false;
  }
  final r = await build();
  if (!context.mounted) return false;
  if (s.settings.ai.isHandoff) {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: C.card, builder: (c) => _Handoff(s: s, r: r));
    if (ok == true && context.mounted) {
      toast(context, r.wholePlan ? 'New plan is in. Your old plan is kept under Plan → Old plans.' : 'Today adjusted.');
    }
    return ok == true;
  }
  if (s.settings.preview && !s.settings.ai.isOnDevice) {
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (c) => _Preview(r),
    );
    if (go != true || !context.mounted) return false;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      backgroundColor: C.card,
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(child: Text(s.settings.ai.isOnDevice ? 'Thinking on your phone… a plan can take a minute or two. Nothing leaves the phone.' : 'Asking the AI… this can take a minute.')),
      ]),
    ),
  );
  List<String>? errors;
  try {
    errors = await s.aiApply(r);
  } catch (e) {
    errors = ['Something went wrong: $e'];
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (!context.mounted) return false;
  if (errors == null) {
    toast(context, r.wholePlan ? 'New plan from the AI is in. Your old plan is kept under Plan → Old plans.' : 'Today adjusted by the AI.');
    return true;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('The AI answer was not used', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Dim('Nothing changed. Your current plan stays as it is.', size: 14),
          const SizedBox(height: 12),
          Problem(errors!),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ]),
      ),
    ),
  );
  return false;
}

/// Step 1: open the chat app with the request. Step 2: paste its answer back; it gets checked.
class _Handoff extends StatefulWidget {
  final AppState s;
  final AiRequest r;
  const _Handoff({required this.s, required this.r});
  @override
  State<_Handoff> createState() => _HandoffState();
}

class _HandoffState extends State<_Handoff> {
  String? note;
  List<String>? problems;
  bool opened = false, busy = false;

  String get app => chatApps[widget.s.settings.ai.model] ?? 'your chat app';

  Future<void> _open() async {
    final res = await handOff(handoffText(widget.r, project: widget.s.settings.chatProject), widget.s.settings.ai.model);
    setState(() {
      opened = true;
      note = switch (res) {
        'app' => 'Opened in $app with the request filled in. Tap send there. If the box is empty, paste: it is copied too.',
        'missing' => '$app is not installed, so the share menu opened. The request is also copied.',
        'failed' => 'Could not open an app. The request is copied: open your chat app and paste it.',
        _ => 'Pick your chat app from the menu. The request is also copied.',
      };
    });
  }

  Future<void> _paste() async {
    setState(() {
      busy = true;
      problems = null;
    });
    final t = await pasteText();
    if (t == null || t.trim().isEmpty) {
      setState(() {
        busy = false;
        problems = ['Nothing to paste. In $app, copy the answer (long-press it, or the copy button under it), then come back and tap Paste.'];
      });
      return;
    }
    final err = await widget.s.aiApplyText(widget.r, t);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      busy = false;
      problems = [...err, 'Nothing changed. You can ask $app to fix it and paste again.'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final what = widget.r.wholePlan ? 'a new plan' : 'today\'s workout';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ask $app for $what', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Dim('Uses your own $app account. This app sends nothing itself: you see the request in $app before it goes.', size: 13),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _open, icon: const Icon(Icons.open_in_new), label: Text('1. Open $app')),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Dim(note!, size: 13)),
          const SizedBox(height: 10),
          (opened ? FilledButton.icon : OutlinedButton.icon)(
            onPressed: busy ? null : _paste,
            icon: const Icon(Icons.content_paste),
            label: Text('2. Paste $app\'s answer'),
          ),
          const SizedBox(height: 6),
          const Dim('Copy the whole answer in the chat app, then tap Paste. The app checks it before using it.', size: 12),
          if (problems != null) ...[const SizedBox(height: 10), Problem(problems!)],
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ]),
      ),
    );
  }
}

class _Preview extends StatefulWidget {
  final AiRequest r;
  const _Preview(this.r);
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool showSystem = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final lines = r.system.split('\n').length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (c, sc) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('This is exactly what will be sent', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Dim('To: ${r.host} · No name, no phone ID, no location', size: 13),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(controller: sc, children: [
                _box(r.user),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => showSystem = !showSystem),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Icon(showSystem ? Icons.expand_less : Icons.expand_more, color: C.dim),
                      const SizedBox(width: 6),
                      Expanded(child: Dim('Also sent: the app\'s instructions${(r.task == AiTask.ask || r.task == AiTask.guide) ? '' : ' and exercise list'} ($lines lines). Tap to ${showSystem ? 'hide' : 'show'}.')),
                    ]),
                  ),
                ),
                if (showSystem) _box(r.system),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _box(String t) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF0B1115), borderRadius: BorderRadius.circular(10)),
        child: SelectableText(t, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFB9E6E0))),
      );
}
