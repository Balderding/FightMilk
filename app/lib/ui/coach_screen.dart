import 'package:flutter/material.dart';

import '../services/handoff.dart';
import 'ai_sheet.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ask the AI coach anything about training. The conversation lives only on this screen:
/// nothing is saved, and it is gone when you leave.
/// Chat models like markdown; this screen shows plain text.
String plainText(String a) => a
    .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r'^#{1,6}\s*', multiLine: true), (_) => '')
    .replaceAllMapped(RegExp(r'^\s*[*-]\s+', multiLine: true), (_) => '• ')
    .trim();

class CoachScreen extends StatefulWidget {
  final AppState s;
  const CoachScreen({super.key, required this.s});
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final q = TextEditingController();
  final turns = <(String, String)>[];
  bool busy = false;

  static const ideas = [
    'My bench has been stuck for 3 weeks. What should I change?',
    'How long should I rest between heavy sets?',
    'What can I do instead of squats if my knees hurt?',
    'Is my weekly volume for chest enough?',
  ];

  Future<void> _send([String? text]) async {
    final t = (text ?? q.text).trim();
    if (t.isEmpty || busy) return;
    setState(() => busy = true);
    final a = await runAsk(context, widget.s, () => widget.s.aiAskRequest(t, turns));
    if (!mounted) return;
    setState(() {
      busy = false;
      if (a != null) {
        turns.add((t, plainText(a)));
        q.clear();
      } else if (widget.s.settings.ai.isHandoff) {
        q.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: const Text('Ask the coach')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 8), children: [
              if (!s.settings.aiOn)
                const Problem(['The AI coach is off. Turn it on in Settings and add your key (or your own server).'])
              else ...[
                Dim(s.settings.ai.isOnDevice
                    ? 'Runs on this phone with ${s.phoneModel.label}. Nothing leaves the phone; answers take a few seconds.'
                    : s.settings.ai.isHandoff
                    ? 'Opens your question in ${chatApps[s.settings.ai.model] ?? 'your chat app'} with your setup and the last 2 weeks of sets. The answer stays there.'
                    : 'Goes to ${s.settings.ai.host ?? 'your server'} with your setup and the last 2 weeks of sets. Nothing here is saved.', size: 12),
                const SizedBox(height: 10),
              ],
              if (turns.isEmpty && s.settings.aiOn)
                for (final i in ideas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ActionChip(label: Text(i), onPressed: () => _send(i)),
                  ),
              for (final (question, answer) in turns) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6, left: 40),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(14)),
                    child: Text(question),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(bottom: 14, right: 24),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14)),
                  child: SelectableText(answer, style: const TextStyle(height: 1.4)),
                ),
              ],
              if (busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: q,
                  enabled: s.settings.aiOn && !busy,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Ask about your training…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: s.settings.aiOn && !busy ? _send : null, icon: const Icon(Icons.send)),
            ]),
          ),
        ]),
      ),
    );
  }
}
