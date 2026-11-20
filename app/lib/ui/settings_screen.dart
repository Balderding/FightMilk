import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai.dart';
import '../ai/prompt.dart';
import '../data/backup.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/units.dart';
import '../net/guarded_client.dart';
import '../services/sounds.dart';
import '../llm/model_store.dart';
import '../llm/native.dart';
import '../version.dart';
import 'app_state.dart';
import 'coach_screen.dart';
import '../services/handoff.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'widgets.dart';

const privacyText = 'No accounts. No tracking. No ads. Nothing about you is collected or sold.\n\n'
    'Your workouts are stored only on this phone (Android cloud backup is switched off for this app).\n\n'
    'The app goes online for three things only, and only when you choose:\n'
    '1. When you ask the AI something: the text shown to you before sending goes to the AI service you picked, with your own key.\n'
    '2. When you check for new icons or a new app version: the app asks GitHub. Like visiting any web page, GitHub sees your phone\'s internet address.\n'
    '3. When you download the on-phone AI model: the app fetches it from Hugging Face, once.\n\n'
    'Nothing else, ever. The code is open for anyone to check.';

class SettingsScreen extends StatelessWidget {
  final AppState s;
  const SettingsScreen({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final st = s.settings;
    final pr = s.profile;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 32), children: [
        const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            title: const Text('Your setup', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Dim(pr == null ? '' : '${goalLabel[pr.goal]} · ${pr.days} days · ${pr.minutes} min · ${unitLabel(pr.unit)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s: s))),
          ),
        ),
        _AiCard(s: s),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Exercise icons', style: TextStyle(fontWeight: FontWeight.w600)),
              Dim(s.packs.installedVersion() == 0 ? 'Built-in set · ${s.lib.all.length} exercises' : 'Icon pack v${s.packs.installedVersion()} · ${s.lib.all.length} exercises'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.autoPacks,
                onChanged: (v) => s.saveSettings(st.copyWith(autoPacks: v)),
                title: const Text('Check GitHub for new icons when the app opens'),
              ),
              OutlinedButton(
                onPressed: () async {
                  toast(context, 'Checking GitHub…');
                  final m = await s.checkPacks();
                  if (context.mounted) toast(context, m);
                },
                child: const Text('Check now'),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Workout', style: TextStyle(fontWeight: FontWeight.w600)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.keepAwake,
                onChanged: (v) => s.saveSettings(st.copyWith(keepAwake: v)),
                title: const Text('Keep the screen on during a workout'),
              ),
              const Dim('The rest timer buzzes even with the screen off.'),
              const Q('Rest between sets'),
              Pills<int>(
                values: const [-1, 0, 60, 90, 120, 180, 240],
                label: (v) => v == -1 ? 'Smart (by effort)' : v == 0 ? "Plan's own" : '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}',
                selected: {st.rest ?? (st.smartRest ? -1 : 0)},
                onTap: (v) => s.saveSettings(v <= 0 ? st.copyWith(planRest: true, smartRest: v == -1) : st.copyWith(rest: v)),
              ),
              const Dim('Smart: heavy sets and big lifts rest longer, missed reps add time, and you can tap how hard a set felt.', size: 12),
              const Q('Reward sounds'),
              Row(children: [
                Expanded(
                  child: Pills<String>(
                    values: const ['cute', 'simple', 'off'],
                    label: (v) => switch (v) { 'cute' => 'Cute (uwu)', 'simple' => 'Simple', _ => 'Off' },
                    selected: {st.sound},
                    onTap: (v) => s.saveSettings(st.copyWith(sound: v)),
                  ),
                ),
                IconButton(tooltip: 'Play', icon: const Icon(Icons.play_circle_outline, color: C.teal), onPressed: () => s.sounds.play(Reward.exercise)),
              ]),
              const Q('Remind me to train'),
              Pills<int>(
                values: const [1, 2, 3, 4, 5, 6, 7],
                label: (d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1],
                selected: st.remindDays.toSet(),
                onTap: (d) => s.saveSettings(st.copyWith(remindDays: st.remindDays.contains(d) ? (st.remindDays.toList()..remove(d)) : [...st.remindDays, d])),
              ),
              if (st.remindDays.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text('at ${TimeOfDay(hour: st.remindAt ~/ 60, minute: st.remindAt % 60).format(context)}'),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: st.remindAt ~/ 60, minute: st.remindAt % 60));
                    if (t != null) await s.saveSettings(s.settings.copyWith(remindAt: t.hour * 60 + t.minute));
                  },
                ),
              Q('Smallest weight steps (${unitLabel(s.unit)})'),
              for (final k in [StepKind.barbell, StepKind.dumbbell, StepKind.machine, StepKind.cable])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(width: 84, child: Text(switch (k) { StepKind.barbell => 'Barbell', StepKind.dumbbell => 'Dumbbell', StepKind.machine => 'Machine', _ => 'Cable' })),
                    Expanded(
                      child: Pills<double>(
                        values: s.unit == Unit.lb ? const [2.5, 5, 10] : const [1, 1.25, 2, 2.5, 5],
                        label: (v) => fmtNum(v),
                        selected: {stepIn(k, s.unit)},
                        onTap: (v) => s.saveSettings(st.copyWith(steps: {...st.steps, '${k.name}_${s.unit.name}': v})),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
        _UpdateCard(s: s),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your data', style: TextStyle(fontWeight: FontWeight.w600)),
              const Dim('Stored only on this phone. A backup is one file you keep wherever you like (API keys are never in it).'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(onPressed: () => _export(context), child: const Text('Export backup')),
                OutlinedButton(onPressed: () => _import(context), child: const Text('Import backup')),
                OutlinedButton(
                  onPressed: () async {
                    if (await confirm(context, 'Delete everything?', 'All workouts, plans, settings and saved API keys are removed from this phone. This cannot be undone. Export a backup first if you want one.', yes: 'Delete everything')) {
                      await s.wipeEverything();
                    }
                  },
                  child: const Text('Delete all data', style: TextStyle(color: C.gold)),
                ),
              ]),
            ]),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Privacy, in plain words', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Dim(privacyText),
            ]),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('About', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Dim('FightMilk is free and open source. Code: GPL-3.0. Exercise icons and sounds: CC BY-SA 4.0. Made by balderding. github.com/Balderding/FightMilk'),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _export(BuildContext context) async {
    try {
      final text = await exportBackup(s.repo);
      final d = DateTime.now();
      final name = 'workout-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
      final uri = await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(text)), mimeType: 'application/json', dialogTitle: 'Save backup');
      if (context.mounted) toast(context, uri == null ? 'Not saved.' : 'Backup saved.');
    } catch (e) {
      if (context.mounted) toast(context, 'Could not save the backup: $e');
    }
  }

  Future<void> _import(BuildContext context) async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Pick a backup file');
    if (files.isEmpty || !context.mounted) return;
    final text = utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
    if (!context.mounted) return;
    final replace = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Import backup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Add to what is on this phone')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Replace everything on this phone')),
          ]),
        ),
      ),
    );
    if (replace == null) return;
    try {
      await importBackup(s.repo, text, replace: replace);
      await s.reload();
      if (context.mounted) toast(context, 'Backup imported.');
    } on BackupError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }
}

class _AiCard extends StatefulWidget {
  final AppState s;
  const _AiCard({required this.s});
  @override
  State<_AiCard> createState() => _AiCardState();
}

class _AiCardState extends State<_AiCard> {
  final key = TextEditingController();
  final model = TextEditingController();
  final url = TextEditingController();
  bool hasKey = false;
  bool testing = false;

  AppState get s => widget.s;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  Future<void> _fill() async {
    final a = s.settings.ai;
    model.text = a.model;
    url.text = a.baseUrl ?? '';
    hasKey = (await s.secrets.key(a.kind))?.isNotEmpty == true;
    key.clear();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final a = s.settings.ai.copyWith(model: model.text.trim(), baseUrl: url.text.trim());
    await s.saveSettings(s.settings.copyWith(ai: a));
    if (key.text.trim().isNotEmpty) await s.secrets.setKey(a.kind, key.text);
    await _fill();
  }

  Future<void> _test() async {
    await _save();
    setState(() => testing = true);
    String msg;
    if (!await s.aiReady()) {
      msg = 'Fill in ${s.settings.ai.needsKey ? 'the key, ' : 'the server address, '}and the model first.';
    } else {
      try {
        final r = await s.aiSend(AiRequest(s.settings.ai.host!, 'Reply with the single word OK.', 'Connection test.', AiTask.ask));
        msg = 'Connected. The AI said: ${r.trim().split('\n').first}';
      } on AiError catch (e) {
        msg = e.message;
      }
    }
    if (!mounted) return;
    setState(() => testing = false);
    toast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final st = s.settings;
    final a = st.ai;
    final host = a.host;
    final httpWarn = a.kind == AiKind.local && url.text.startsWith('http://');
    final badLocal = a.kind == AiKind.local && host != null && url.text.startsWith('http://') && !isPrivateHost(host);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AI coach', style: TextStyle(fontWeight: FontWeight.w600)),
                Dim(st.aiOn ? 'On: ${aiKindLabel[a.kind]}' : 'Off: the built-in plan maker is used'),
              ]),
            ),
            Switch(value: st.aiOn, onChanged: (v) => s.saveSettings(st.copyWith(aiOn: v))),
          ]),
          if (st.aiOn) ...[
            const Q('Use'),
            Pills(
              values: AiKind.values,
              label: (k) => aiKindLabel[k]!,
              selected: {a.kind},
              onTap: (k) async {
                await s.saveSettings(st.copyWith(ai: AiConfig(kind: k, model: defaultModel[k]!, baseUrl: a.baseUrl)));
                await _fill();
              },
            ),
            const SizedBox(height: 10),
            if (a.isOnDevice) ...[
              _PhoneModel(s: s),
            ] else if (a.isHandoff) ...[
              const Dim('No key and no cost here: the request opens in a chat app on this phone, using your own subscription there. For plans, you copy the answer back and the app checks it.', size: 13),
              const Q('Open in'),
              Pills<String>(
                values: chatApps.keys.toList(),
                label: (k) => chatApps[k]!,
                selected: {a.model},
                onTap: (k) => s.saveSettings(st.copyWith(ai: a.copyWith(model: k))),
              ),
              const Q('Save the rules once (recommended)'),
              const Dim('In the Claude app: Projects → New project, name it "Workout app", open its instructions and paste. Then start your chats inside that project. Each hand-off is then short, and Claude keeps the workout list format even after back-and-forth.', size: 12),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: projectInstructions(s.lib, s.profile!)));
                  if (context.mounted) toast(context, 'Project instructions copied. Paste them into the project in the Claude app.');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Project instructions'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.chatProject,
                onChanged: (v) => s.saveSettings(st.copyWith(chatProject: v)),
                title: const Text("I've set up the project: send only the request"),
                subtitle: const Dim('Copy the instructions again if you change your equipment or sore joints.', size: 12),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s))),
                icon: const Icon(Icons.chat_bubble_outline, color: C.gold),
                label: const Text('Ask the coach'),
              ),
              const SizedBox(height: 6),
              const Dim('This app sends nothing in this mode.', size: 12),
            ] else ...[
            if (a.kind == AiKind.local) ...[
              TextField(controller: url, decoration: const InputDecoration(labelText: 'Server address', hintText: 'http://192.168.1.20:8081'), onChanged: (_) => setState(() {}), onSubmitted: (_) => _save()),
              const SizedBox(height: 4),
              const Dim('Any OpenAI-compatible server: llama-server, Ollama, LM Studio. Plain http works only on your home network.', size: 12),
              if (httpWarn && !badLocal) const Dim('Note: http is not encrypted. Fine at home, not on public Wi-Fi.', size: 12),
              if (badLocal) const Padding(padding: EdgeInsets.only(top: 6), child: Problem(['A server on the internet must use https.'])),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: key,
              obscureText: true,
              decoration: InputDecoration(labelText: a.kind == AiKind.local ? 'API key (only if your server needs one)' : 'API key', hintText: hasKey ? 'saved ••••••• (type to replace)' : 'paste your key'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            TextField(controller: model, decoration: const InputDecoration(labelText: 'Model'), onSubmitted: (_) => _save()),
            const SizedBox(height: 4),
            Dim(a.kind == AiKind.local ? 'The model name your server uses.' : 'Change it to any model your account has.', size: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: st.preview,
              onChanged: (v) => s.saveSettings(st.copyWith(preview: v)),
              title: const Text("Show me what's sent before every request"),
            ),
            Row(children: [
              Expanded(child: FilledButton.tonal(onPressed: _save, child: const Text('Save'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: testing ? null : _test, child: Text(testing ? 'Testing…' : 'Test connection'))),
            ]),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s))),
              icon: const Icon(Icons.chat_bubble_outline, color: C.gold),
              label: const Text('Ask the coach'),
            ),
            const SizedBox(height: 6),
            Dim('Requests go only to ${host ?? 'your server'}. Your key stays in this phone\'s secure storage.', size: 12),
            ],
          ],
        ]),
      ),
    );
  }
}


/// On-phone model: pick, download (resumable, fingerprint-checked), test, delete.
class _PhoneModel extends StatelessWidget {
  final AppState s;
  const _PhoneModel({required this.s});

  @override
  Widget build(BuildContext context) {
    final a = s.settings.ai;
    final m = s.phoneModel;
    final ready = s.models.isReady(m);
    final have = s.models.have(m);
    final p = s.modelProgress;
    final engine = engineAvailable();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Dim('The AI runs inside the app, on this phone: free, offline once downloaded, and nothing ever leaves the phone. Plans are locked to your split and your gym\'s exercises.', size: 13),
      if (!engine) const Padding(padding: EdgeInsets.only(top: 8), child: Problem(['This phone\'s processor is not supported by the on-phone engine in this build.'])),
      const Q('Model'),
      Pills<String>(
        values: [for (final x in modelCatalog) x.id],
        label: (id) => modelById(id).label,
        selected: {a.model},
        onTap: (id) => s.saveSettings(s.settings.copyWith(ai: a.copyWith(model: id))),
      ),
      Padding(padding: const EdgeInsets.only(top: 4), child: Dim('${m.size} download. ${m.note}', size: 12)),
      const SizedBox(height: 10),
      if (p != null) ...[
        LinearProgressIndicator(value: p, color: C.teal, backgroundColor: C.card2),
        const SizedBox(height: 4),
        Dim('Downloading ${(p * 100).toStringAsFixed(0)}% of ${m.size}. Keep the app open.', size: 12),
        const SizedBox(height: 6),
        OutlinedButton(onPressed: s.stopModelDownload, child: const Text('Pause')),
      ] else if (ready) ...[
        Row(children: [
          const Icon(Icons.check_circle_outline, color: C.green),
          const SizedBox(width: 8),
          Expanded(child: Text('Ready on this phone', style: const TextStyle(color: C.green, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoachScreen(s: s))),
              icon: const Icon(Icons.chat_bubble_outline, color: C.gold),
              label: const Text('Ask the coach'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              if (await confirm(context, 'Delete the model?', 'Frees ${m.size}. You can download it again any time.', yes: 'Delete')) s.deleteModel();
            },
            child: const Text('Delete'),
          ),
        ]),
      ] else ...[
        FilledButton.icon(
          onPressed: engine ? s.downloadModel : null,
          icon: const Icon(Icons.download),
          label: Text(have > 0 ? 'Continue download (${(have * 100 / m.bytes).toStringAsFixed(0)}%)' : 'Download model (${m.size})'),
        ),
        const SizedBox(height: 4),
        const Dim('Comes from Hugging Face, the only time the app contacts it. Use Wi-Fi.', size: 12),
      ],
      if (s.modelNote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Dim(s.modelNote!, size: 12)),
    ]);
  }
}


/// App updates from the project's GitHub releases.
class _UpdateCard extends StatelessWidget {
  final AppState s;
  const _UpdateCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final st = s.settings;
    final u = s.update;
    final p = s.updateProgress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('App updates', style: TextStyle(fontWeight: FontWeight.w600)),
          Dim('$appName $appVersion · from github.com/$appRepo', size: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: st.autoUpdate,
            onChanged: (v) => s.saveSettings(st.copyWith(autoUpdate: v)),
            title: const Text('Check for a new version when the app opens'),
          ),
          if (p != null) ...[
            LinearProgressIndicator(value: p, color: C.teal, backgroundColor: C.card2),
            const SizedBox(height: 4),
            Dim('Downloading ${(p * 100).toStringAsFixed(0)}%…', size: 12),
          ] else if (u != null) ...[
            FilledButton.icon(onPressed: s.installUpdate, icon: const Icon(Icons.system_update), label: Text('Install version ${u.version}')),
            if (u.notes.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Dim(u.notes.trim(), size: 12)),
          ] else
            OutlinedButton(onPressed: s.checkForUpdate, child: const Text('Check for updates')),
          if (s.updateNote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Dim(s.updateNote!, size: 12)),
          const SizedBox(height: 4),
          const Dim('Updates are checked against their published fingerprint, and Android only installs them if they are signed by the same key as this app. Your workouts stay.', size: 11),
        ]),
      ),
    );
  }
}
