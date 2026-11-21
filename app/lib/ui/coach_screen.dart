import 'package:flutter/material.dart';

import '../ai/quick.dart';
import '../ai/tools.dart';
import '../services/handoff.dart';
import 'ai_sheet.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Chat models like markdown; this screen shows plain text.
String plainText(String a) => a
    .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r'^#{1,6}\s*', multiLine: true), (_) => '')
    .replaceAllMapped(RegExp(r'^\s*[*-]\s+', multiLine: true), (_) => '• ')
    .trim();

/// One question and what came back.
class _Turn {
  final String q;
  final String answer;
  List<AppAction> pending; // waiting for Apply (Ask me first)
  List<String> did = const []; // done
  final List<String> problems; // the AI tried a change the app refused
  int? change; // index into s.aiChanges when done (for Undo)
  _Turn(this.q, this.answer, {this.pending = const [], this.problems = const []});
}

/// Ask AI: questions about training, or tell it to set things up ("shoulders, arms and chest
/// today with drop sets"). It changes the app with the same tools the buttons use; with "Ask me
/// first" it waits for Apply, with "Auto" it just does it. Everything can be undone.
/// The conversation lives only on this screen; the list of changes is kept for Undo.
class CoachScreen extends StatefulWidget {
  final AppState s;
  const CoachScreen({super.key, required this.s});
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final q = TextEditingController();
  final turns = <_Turn>[];
  bool busy = false;

  static const ideas = [
    'Set me up a chest, shoulders and arms workout for today.',
    'I only have 30 minutes today.',
    'The bench is taken, swap it for something else.',
    'Remind me to train Monday, Wednesday and Friday at 6 pm.',
    'My bench has been stuck for 3 weeks. What should I change?',
    'What can I do instead of squats if my knees hurt?',
  ];

  Future<void> _send([String? text]) async {
    final t = (text ?? q.text).trim();
    if (t.isEmpty || busy) return;
    final s = widget.s;
    setState(() => busy = true);
    final earlier = [for (final x in turns) (x.q, x.answer)];
    // Everyday requests the app handles by itself (instant, no AI). An AI service with a key gets
    // the request instead, since it can follow extra wishes ("heavy", "no machines").
    final ai = s.settings;
    final quick = (!ai.aiOn || ai.ai.isOnDevice || ai.ai.isHandoff) ? quickCommand(t, s) : null;
    final _Turn turn;
    if (quick != null) {
      turn = _Turn(t, quick.say, pending: quick.actions);
    } else if (!ai.aiOn) {
      turn = _Turn(t, "The AI is off, so I only understand simple requests, like: 'set me up a chest and arms workout', "
          "'remind me Monday and Thursday at 6 pm', '2 minutes rest', 'I only have 30 minutes', 'the bench is taken'. "
          'Turn the AI on in Settings for anything else.');
    } else {
      // A chat app can only answer in words; the tools need a reply the app receives itself.
      final a = await runAsk(context, s, () => ai.ai.isHandoff ? s.aiAskRequest(t, earlier) : s.aiToolRequest(t, earlier));
      if (!mounted) return;
      if (a == null) {
        setState(() {
          busy = false;
          if (ai.ai.isHandoff) q.clear();
        });
        return;
      }
      turn = ai.ai.isHandoff ? _Turn(t, plainText(a)) : _fromReply(t, a);
    }
    if (turn.pending.isNotEmpty && s.settings.aiAuto) await _apply(turn);
    if (!mounted) return;
    setState(() {
      busy = false;
      turns.add(turn);
      q.clear();
    });
  }

  _Turn _fromReply(String asked, String a) {
    final r = parseToolReply(a, widget.s);
    final say = plainText(r.say.isEmpty && r.actions.isNotEmpty ? 'Done.' : r.say);
    if (r.errors.isNotEmpty) return _Turn(asked, say, problems: r.errors);
    return _Turn(asked, say, pending: widget.s.settings.ai.isOnDevice ? tidyActions(r.actions, asked) : r.actions);
  }

  Future<void> _apply(_Turn t) async {
    final s = widget.s;
    try {
      t.did = await s.runActions(t.q, t.pending);
      t.change = 0; // newest first
    } catch (e) {
      if (mounted) toast(context, 'That change could not be made: $e');
    }
    t.pending = const [];
  }

  Future<void> _undo(_Turn t) async {
    final s = widget.s;
    final i = s.aiChanges.indexWhere((c) => c.asked == t.q && !c.undone);
    if (i < 0) return;
    await s.undoChange(i);
    if (!mounted) return;
    setState(() => t.change = null);
    toast(context, 'Undone. The app is back to how it was.');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: const Text('Ask AI'), actions: [
        IconButton(
          tooltip: 'AI changes (undo)',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AiChangesScreen(s: s))),
        ),
      ]),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 8), children: [
              if (!s.settings.aiOn)
                const Dim('The AI is off. Simple requests still work (the app handles them itself); turn the AI on in Settings for anything else.', size: 12)
              else ...[
                Dim(s.settings.ai.isOnDevice
                    ? 'Runs on this phone with ${s.phoneModel.label}. Nothing leaves the phone; answers take a few seconds.'
                    : s.settings.ai.isHandoff
                    ? 'Opens your question in ${chatApps[s.settings.ai.model] ?? 'your chat app'} with your setup and the last 2 weeks of sets. The answer stays there, so it cannot change the app.'
                    : 'Goes to ${s.settings.ai.host ?? 'your server'} with your setup and the last 2 weeks of sets.', size: 12),
                if (!s.settings.ai.isHandoff)
                  Dim(s.settings.aiAuto ? 'Auto: it makes the changes you ask for right away (undo any time).' : 'It shows what it wants to change and waits for Apply.', size: 12),
                const SizedBox(height: 10),
              ],
              if (turns.isEmpty)
                for (final i in ideas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ActionChip(label: Text(i), onPressed: () => _send(i)),
                  ),
              for (final t in turns) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6, left: 40),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(14)),
                    child: Text(t.q),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(bottom: 14, right: 24),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (t.answer.isNotEmpty) SelectableText(t.answer, style: const TextStyle(height: 1.4)),
                    if (t.problems.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('It tried to change something, but the app said no, so nothing changed:', style: TextStyle(color: C.gold)),
                      for (final p in t.problems) Dim('• $p', size: 12),
                    ],
                    if (t.pending.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('It wants to:', style: TextStyle(fontWeight: FontWeight.w600)),
                      for (final a in t.pending) Text('• ${a.says}'),
                      const SizedBox(height: 6),
                      Row(children: [
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await _apply(t);
                                  if (mounted) setState(() {});
                                },
                          child: const Text('Apply'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: () => setState(() => t.pending = const []), child: const Text('No thanks')),
                      ]),
                    ],
                    if (t.did.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Done:', style: TextStyle(fontWeight: FontWeight.w600, color: C.green)),
                      for (final d in t.did) Text('• $d'),
                      if (t.change != null)
                        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _undo(t), icon: const Icon(Icons.undo), label: const Text('Undo'))),
                    ],
                  ]),
                ),
              ],
              if (busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(children: [
              Expanded(
                child: TextField(enableIMEPersonalizedLearning: false, 
                  controller: q,
                  enabled: !busy,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Ask, or tell it what to set up…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: !busy ? _send : null, icon: const Icon(Icons.send)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Everything the AI changed, newest first, each with Undo.
class AiChangesScreen extends StatefulWidget {
  final AppState s;
  const AiChangesScreen({super.key, required this.s});
  @override
  State<AiChangesScreen> createState() => _AiChangesScreenState();
}

class _AiChangesScreenState extends State<AiChangesScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final l = s.aiChanges;
    return Scaffold(
      appBar: AppBar(title: const Text('AI changes')),
      body: l.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Dim('Nothing yet. Changes the AI makes show up here, each with Undo.')))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: l.length,
              itemBuilder: (c, i) {
                final ch = l[i];
                final t = ch.at;
                final when = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Dim(when, size: 12),
                      Text('"${ch.asked}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                      const SizedBox(height: 4),
                      for (final d in ch.did) Text('• $d'),
                      const SizedBox(height: 4),
                      if (ch.undone)
                        const Dim('Undone', size: 12)
                      else
                        TextButton.icon(
                          onPressed: () async {
                            final later = l.take(i).where((x) => !x.undone).length;
                            if (later > 0 &&
                                !await confirm(context, 'Undo this?', 'This puts the app back to how it was before this change, so the $later newer AI change${later == 1 ? '' : 's'} above go too.', yes: 'Undo')) {
                              return;
                            }
                            await s.undoChange(i);
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.undo),
                          label: const Text('Undo'),
                        ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
