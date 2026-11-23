import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai.dart';
import '../ai/prompt.dart';
import '../data/backup.dart';
import '../services/crash_log.dart';
import 'recovery_screen.dart' show showDetails;
import '../domain/calendar_ics.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/units.dart';
import '../net/guarded_client.dart';
import '../services/sounds.dart';
import '../llm/model_store.dart';
import '../llm/native.dart';
import '../version.dart';
import 'app_state.dart';
import 'coaching_screen.dart';
import 'coach_screen.dart';
import 'gyms_screen.dart';
import '../services/handoff.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'export_screen.dart';
import 'import_screen.dart';
import '../data/webdav.dart';

const privacyText = 'No accounts. No tracking. No ads. Nothing about you is collected or sold.\n\n'
    'Your workouts are stored only on this phone (Android cloud backup is switched off for this app).\n\n'
    'The app goes online only when you tap something that needs it, or when you start it with an update or icon-pack check switched on:\n'
    '1. When you ask the AI something: the text shown to you before sending goes to the AI service you picked, with your own key.\n'
    '2. When you check for new icons or a new app version: the app asks GitHub. Like visiting any web page, GitHub sees your phone\'s internet address.\n'
    '3. When you download the on-phone AI model: the app fetches it from Hugging Face, once.\n'
    '4. When you send a backup to your own server: only to the address you typed, over https.\n\n'
    'Nothing else, ever. The code is open for anyone to check.';

/// Where the privacy promise is written down (F397), shown as text.
const privacyUrl = 'https://github.com/Balderding/FightMilk/blob/main/PRIVACY.md';

/// The release key's certificate fingerprint (F414): the same as tools/release_cert.sha256.
const signingFingerprint = 'f4f3906d08e2413d1c0175011d4ee29e7ebabce019df8a429eaa5f8e51c28989';

/// One section of Settings: a short list on the main page, its own page when tapped.
class _Section {
  final IconData icon;
  final String title, sub;
  final List<String> finds; // what the search box matches
  final List<Widget> Function(BuildContext) body;
  const _Section(this.icon, this.title, this.sub, this.finds, this.body);
}

class SettingsScreen extends StatefulWidget {
  final AppState s;
  const SettingsScreen({super.key, required this.s});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _q = TextEditingController();
  AppState get s => widget.s;

  List<_Section> get _sections {
    final st = s.settings;
    return [
      _Section(Icons.fitness_center, 'Workout', 'Screen, warm-ups, rest, sounds, weight steps',
          ['keep the screen on', 'warm-up help', 'rest between sets', 'smart rest', 'rest off', 'reward sounds', 'smallest weight steps', 'how was that set', 'effort chips'], _workout),
      _Section(Icons.notifications_none, 'Reminders', st.remindDays.isEmpty ? 'Off' : 'On ${st.remindDays.length} days', ['remind me to train', 'reminder time', 'notifications'], _reminders),
      _Section(Icons.trending_up, 'Progress', 'How weights go up, deloads, check-in', ['progression speed', 'drop the weight after', 'missed sessions', 'effort taps change the jump', 'deload week', 'how I feel', 'check-in', 'one-rep max formula', 'epley', 'brzycki'], _progress),
      _Section(Icons.store_mall_directory_outlined, 'Gyms & equipment', s.activeGym == null ? 'Set up your gym' : 'At ${s.activeGym!.name}', ['your gyms', 'machines', 'bar and plates', 'planet fitness', 'your setup', 'goal', 'days', 'units', 'kg', 'lb', 'sore joints', 'split'], _gyms),
      _Section(Icons.auto_awesome, 'Ask AI', st.aiOn ? 'On: ${aiKindLabel[st.ai.kind]}' : 'Off', ['ai', 'api key', 'on-phone model', 'lfm', 'claude', 'openai', 'gemini', 'own server', 'ask me first', 'auto'], (c) => [_AiCard(s: s)]),
      // F340: the status line is the section's subtitle, so it is seen without opening anything
      _Section(Icons.backup_outlined, 'Backup', s.backupStatus.line(DateTime.now(), hasWorkouts: s.finishedOnPlan > 0 || s.historyVersion > 0), ['backup', 'automatic backup', 'folder', 'password', 'restore', 'keep'], _backup),
      _Section(Icons.lock_outline, 'Data & privacy', 'Backup, CSV export, hide in recent apps', ['backup', 'export', 'import', 'csv', 'hide in recent apps', 'screenshots', 'delete all data', 'privacy'], _data),
      _Section(Icons.info_outline, 'About & updates', '$appName $appVersion', ['app updates', 'new version', 'exercise icons', 'icon pack', 'about', 'licence'], _about),
    ];
  }

  void _open(_Section x) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(x.title)),
            body: SafeArea(child: ListenableBuilder(listenable: s, builder: (c, _) => ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 32), children: x.body(c)))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = s.settings;
    final q = _q.text.trim().toLowerCase();
    final all = _sections;
    final hits = q.isEmpty ? all : [for (final x in all) if (x.title.toLowerCase().contains(q) || x.finds.any((f) => f.contains(q))) x];
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 32), children: [
        const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(
          enableIMEPersonalizedLearning: false,
          controller: _q,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Find a setting (rest, plates, backup…)',
            suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
          ),
        ),
        const SizedBox(height: 8),
        if (q.isEmpty)
          Card(
            child: SwitchListTile(
              value: st.simple,
              onChanged: (v) => s.saveSettings(st.copyWith(simple: v)),
              title: const Text('Simple mode (beginner)'),
              subtitle: const Dim(
                  'Hides the advanced tools: kinds of sets, RPE, training maxes, progression tuning, timers, tips, sore-joint and recovery cards, the extra Progress charts, Reports, Goals and badges, body numbers, tape, progress photos and strength scores. Everything still works the same. New to lifting? Try the Machine starter in Plan → Programs.',
                  size: 12),
            ),
          ),
        for (final x in hits)
          Card(
            child: ListTile(
              leading: Icon(x.icon, color: C.teal),
              title: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Dim(q.isEmpty ? x.sub : x.finds.where((f) => f.contains(q)).take(3).join(' · '), size: 12),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(x),
            ),
          ),
        if (hits.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Dim('Nothing matches. Try "rest", "gym", "AI" or "backup".')),
      ]),
    );
  }

  List<Widget> _workout(BuildContext context) {
    final st = s.settings;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.keepAwake,
        onChanged: (v) => s.saveSettings(st.copyWith(keepAwake: v)),
        title: const Text('Keep the screen on during a workout'),
        subtitle: const Dim('The rest timer buzzes even with the screen off.', size: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.leftHanded,
        onChanged: (v) => s.saveSettings(st.copyWith(leftHanded: v)),
        title: const Text('Left-handed'),
        subtitle: const Dim('Mirrors the − and + buttons and the Done row in a workout.', size: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.dimRest,
        onChanged: (v) => s.saveSettings(st.copyWith(dimRest: v)),
        title: const Text('Dark screen while resting'),
        subtitle: const Dim('Goes dark 8 seconds into a rest and shows only the timer. A touch wakes it and presses nothing, so a phone in your pocket stays put.', size: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.warmups,
        onChanged: (v) => s.saveSettings(st.copyWith(warmups: v)),
        title: const Text('Warm-up help'),
        subtitle: const Dim('A 5-minute warm-up before the first lift, warm-up sets worked out for each big lift, stretches at the end.', size: 12),
      ),
      const Q('Rest between sets'),
      Pills<int>(
        values: const [-1, 0, 60, 90, 120, 180, 240, -9],
        label: (v) => v == -9 ? 'Off' : v == -1 ? 'Smart' : v == 0 ? "Plan's own" : '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}',
        selected: {st.restOff ? -9 : (st.rest ?? (st.smartRest ? -1 : 0))},
        onTap: (v) => s.saveSettings(v == -9
            ? st.copyWith(restOff: true)
            : v <= 0
                ? st.copyWith(planRest: true, smartRest: v == -1, restOff: false)
                : st.copyWith(rest: v, restOff: false)),
      ),
      const Dim('Smart: heavy sets and big lifts rest longer, missed reps add time. Each exercise in your plan can also have its own rest (Plan → tap the exercise).', size: 12),
      if (!st.simple)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: st.effortChips,
          onChanged: (v) => s.saveSettings(st.copyWith(effortChips: v)),
          title: const Text('Ask "how was that set?" while I rest'),
          subtitle: const Dim('Easy / Good / Hard / All-out after each set. Changes the rest time and the next jump.', size: 12),
        ),
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
      Q('Smallest weight steps (${unitLabel(s.unit)})'),
      const Dim('How much the + and − buttons add. One exercise can have its own step in the plan.', size: 12),
      const SizedBox(height: 6),
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
    ];
  }

  List<Widget> _reminders(BuildContext context) {
    final st = s.settings;
    return [
      const Dim('A quiet "time to train" notification on the days you pick. It shows nothing on the lock screen.', size: 13),
      const Q('Remind me to train on'),
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
      // F357: the training days in the person's own calendar app, as a file they save
      const SizedBox(height: 8),
      OutlinedButton.icon(icon: const Icon(Icons.event_outlined), label: const Text('Put my training days in my calendar…'), onPressed: () => _calendar(context)),
      // F354, F356: links and NFC stickers only open a screen
      const SizedBox(height: 12),
      const Q('Links and NFC stickers'),
      const Dim('fightmilk://start opens today\'s workout, fightmilk://weight?kg=80 opens the weigh-in with 80 filled in, fightmilk://last the last workout. '
          'Write one onto an NFC sticker with any NFC writer app and tap the sticker with your phone. They only open the screen: nothing is saved until you tap Save.', size: 12),
    ];
  }

  Future<void> _calendar(BuildContext context) async {
    final st = s.settings;
    final wd = s.profile?.weekdays ?? const <int>[];
    if (wd.isEmpty && st.remindDays.isEmpty) return toast(context, 'Pick your training days above first.');
    final ics = planIcs(s.plan!, s.lib, weekdays: wd, days: wd.isNotEmpty ? wd : st.remindDays, at: st.remindAt, minutes: s.profile?.minutes ?? 60, now: DateTime.now());
    try {
      final uri = await FilePicker.saveFile(fileName: 'fightmilk-training-days.ics', bytes: Uint8List.fromList(utf8.encode(ics)), mimeType: 'text/calendar', dialogTitle: 'Save the calendar file');
      if (context.mounted) toast(context, uri == null ? 'Not saved.' : 'Saved. Open it in Files to add the days to your calendar.');
    } catch (_) {
      if (context.mounted) toast(context, 'The calendar file could not be saved.');
    }
  }

  List<Widget> _progress(BuildContext context) {
    final st = s.settings;
    return [
      const Dim('How the app moves your weights after each workout. The defaults suit most people.', size: 13),
      const Q('Speed'),
      Pills<String>(
        values: const ['slow', 'steady', 'fast'],
        label: (v) => {'slow': 'Slow (2 good sessions)', 'steady': 'Steady (1 step)', 'fast': 'Fast (2 steps)'}[v]!,
        selected: {st.progSpeed},
        onTap: (v) => s.saveSettings(st.copyWith(progSpeed: v)),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RulesScreen(s: s))), icon: const Icon(Icons.menu_book_outlined, size: 18), label: const Text('How the weights move')),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.tips,
        onChanged: (v) => s.saveSettings(st.copyWith(tips: v)),
        title: const Text('Tip of the day on Today'),
        subtitle: const Dim('One short tip about training, rest or food.', size: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.chartSmooth,
        onChanged: (v) => s.saveSettings(st.copyWith(chartSmooth: v)),
        title: const Text('Smooth chart lines'),
        subtitle: const Dim('Curves instead of straight lines between workouts on Progress.', size: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.chartDots,
        onChanged: (v) => s.saveSettings(st.copyWith(chartDots: v)),
        title: const Text('A dot on every workout'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.badges,
        onChanged: (v) => s.saveSettings(st.copyWith(badges: v)),
        title: const Text('Badges and levels'),
        subtitle: const Dim('Shown quietly in History → Reports; no pop-ups.', size: 12),
      ),
      const Q('Deload week'),
      const Dim('A lighter week (fewer sets at about 90%) so you come back fresh. Your progress does not move during it.', size: 12),
      const SizedBox(height: 4),
      Pills<int>(values: const [0, 4, 5, 6], label: (v) => v == 0 ? 'When I ask' : 'Every $v weeks', selected: {st.deloadEvery}, onTap: (v) => s.saveSettings(st.copyWith(deloadEvery: v))),
      Align(
        alignment: Alignment.centerLeft,
        child: s.inDeload
            ? TextButton(onPressed: () => s.setDeload(false), child: const Text('End the deload now'))
            : TextButton(onPressed: () => s.setDeload(true), child: const Text('Start a deload week now')),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.climb,
        onChanged: (v) => s.saveSettings(st.copyWith(climb: v)),
        title: const Text('Climb volume through each block'),
        subtitle: Dim(
            'The extra exercises start a block one set lighter and gain a set each week until the deload (${st.deloadEvery > 0 ? 'every ${st.deloadEvery} weeks' : 'blocks of 5 weeks'}). Main lifts and programs keep their sets.',
            size: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.checkin,
        onChanged: (v) => s.saveSettings(st.copyWith(checkin: v)),
        title: const Text('Ask how I feel before a workout'),
        subtitle: const Dim('Rough: one set fewer and a bit lighter. Optional every time.', size: 12),
      ),
      if (!st.simple) ...[
        const Q('Drop the weight after'),
        Pills<int>(values: const [1, 2, 3], label: (v) => '$v missed session${v == 1 ? '' : 's'}', selected: {st.missesToDrop}, onTap: (v) => s.saveSettings(st.copyWith(missesToDrop: v))),
        Pills<int>(values: const [5, 10, 15], label: (v) => 'by $v%', selected: {st.dropPct}, onTap: (v) => s.saveSettings(st.copyWith(dropPct: v))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: st.effortDrives,
          onChanged: (v) => s.saveSettings(st.copyWith(effortDrives: v)),
          title: const Text('Effort taps change the jump'),
          subtitle: const Dim('All "Easy" at the top of the range: a bigger jump. "All-out": one step only.', size: 12),
        ),
        const Q('One-rep max formula'),
        const Dim('How the best single lift is estimated from a set (for records and charts). Both are close below 10 reps.', size: 12),
        Pills<String>(values: const ['epley', 'brzycki'], label: (v) => v == 'epley' ? 'Epley' : 'Brzycki', selected: {st.formula}, onTap: (v) => s.saveSettings(st.copyWith(formula: v))),
      ],
    ];
  }

  List<Widget> _gyms(BuildContext context) {
    final pr = s.profile;
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.store_mall_directory_outlined, color: C.teal),
          title: const Text('Your gyms'),
          subtitle: Dim(s.activeGym == null ? 'The machines and equipment each gym has, its bar and plates' : 'At ${s.activeGym!.name} · ${s.gyms.length} gym${s.gyms.length == 1 ? '' : 's'} · machines, bar and plates', size: 12),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GymsScreen(s: s))),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline, color: C.teal),
          title: const Text('Your setup'),
          subtitle: Dim(pr == null ? '' : '${goalLabel[pr.goal]} · ${pr.days} days · ${pr.minutes} min · ${unitLabel(pr.unit)}', size: 12),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s: s))),
        ),
      ),
    ];
  }

  /// Settings → Backup (batch 22, F338-F340).
  List<Widget> _backup(BuildContext context) {
    final a = s.autoBackup, st = s.backupStatus, now = DateTime.now();
    return [
      Text(st.line(now, hasWorkouts: true), key: const Key('backupLine'), style: TextStyle(color: st.needsAttention || st.old(now) ? C.gold : C.text, fontSize: 14)),
      const SizedBox(height: 4),
      const Dim('A backup is one file with your workouts, plans, settings and goals. API keys and progress photos are never in it.', size: 12),
      const Q('Automatic backup'),
      Pills<String>(
        values: const ['off', 'workout', 'day'],
        label: (v) => switch (v) { 'workout' => 'After each workout', 'day' => 'Once a day', _ => 'Off' },
        selected: {a.when},
        onTap: (v) async {
          if (v != 'off' && a.tree == null && !await _pickFolder(context)) return;
          await s.saveAutoBackupChoice(s.autoBackup.copyWith(when: v));
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.folder_outlined),
        title: Text(a.tree == null ? 'No folder picked' : (a.folderName.isEmpty ? 'Your backup folder' : a.folderName)),
        subtitle: const Dim('A folder on this phone, or a cloud app\'s folder you choose. Only FightMilk\'s own backup files there are ever changed.', size: 12),
        trailing: TextButton(onPressed: () => _pickFolder(context), child: Text(a.tree == null ? 'Pick' : 'Change')),
      ),
      const Q('Keep the newest'),
      Pills<int>(values: const [3, 7, 14, 30], label: (v) => '$v', selected: {a.keep}, onTap: (v) => s.saveAutoBackupChoice(a.copyWith(keep: v))),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: a.body,
        onChanged: (v) => s.saveAutoBackupChoice(a.copyWith(body: v)),
        title: const Text('With body data'),
        subtitle: const Dim('Weigh-ins, body fat, tape, height and the body goal. Off: a restore keeps the phone\'s.', size: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: a.locked,
        onChanged: (v) async {
          if (v) {
            final pw = await askLock(context);
            if (pw == null || pw.isEmpty) return;
            await s.secrets.setBackupPassword(pw);
          } else {
            await s.secrets.setBackupPassword(null);
          }
          await s.saveAutoBackupChoice(s.autoBackup.copyWith(locked: v));
        },
        title: const Text('Lock with a password'),
        subtitle: const Dim('The password stays in this phone\'s secure storage. Keep it somewhere safe too: a new phone needs it.', size: 12),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: a.tree == null
              ? null
              : () async {
                  final ok = await s.backupNow();
                  if (context.mounted) toast(context, ok ? 'Backed up.' : s.backupStatus.line(DateTime.now(), hasWorkouts: true));
                },
          icon: const Icon(Icons.backup_outlined),
          label: const Text('Back up now'),
        ),
        OutlinedButton(onPressed: () => _export(context), child: const Text('Save a backup file…')),
        OutlinedButton(onPressed: () => _import(context), child: const Text('Restore a backup…')),
      ]),
      // F343: the person's own server, only when they tap Send
      const Q('Your own server (WebDAV, Nextcloud)'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.dns_outlined),
        title: Text(s.server == null ? 'Not set up' : Uri.parse(s.server!.url).host),
        subtitle: const Dim('Only when you tap Send: never by itself. https only. The password stays in this phone\'s secure storage.', size: 12),
        trailing: TextButton(onPressed: () => _serverSetup(context), child: Text(s.server == null ? 'Set up' : 'Change')),
      ),
      if (s.server != null) OutlinedButton.icon(key: const Key('sendServer'), onPressed: () => _sendToServer(context), icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Send a backup to my server…')),
    ];
  }

  Future<void> _serverSetup(BuildContext context) async {
    final url = TextEditingController(text: s.server?.url ?? ''), user = TextEditingController(text: s.server?.user ?? ''), pw = TextEditingController();
    String? err;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Your own server', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const Dim('The folder\'s WebDAV address, for example https://cloud.example.org/remote.php/dav/files/you/Backups', size: 12),
            TextField(enableIMEPersonalizedLearning: false, controller: url, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'Folder address (https://...)')),
            TextField(enableIMEPersonalizedLearning: false, controller: user, autocorrect: false, decoration: const InputDecoration(labelText: 'User name')),
            TextField(enableIMEPersonalizedLearning: false, controller: pw, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Password (an app password is best)')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: C.gold))),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                final bad = checkServerUrl(url.text);
                if (bad != null) return set(() => err = bad);
                if (user.text.trim().isEmpty) return set(() => err = 'Fill in the user name.');
                if (pw.text.isEmpty && s.server == null) return set(() => err = 'Fill in the password.');
                // a password belongs to one server and user: a new address or user needs its own (review 7, P1-3)
                if (pw.text.isEmpty && s.server != null && serverKey(ServerConfig(url.text, user.text)) != serverKey(s.server!)) {
                  return set(() => err = 'The server or user changed: type its password.');
                }
                Navigator.pop(c, true);
              },
              child: const Text('Save'),
            ),
            if (s.server != null) TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Remove this server')),
          ]),
        ),
      ),
    );
    if (ok == null) return;
    if (ok) {
      final c = ServerConfig(url.text.trim(), user.text.trim());
      await saveServer(s.repo, c);
      if (pw.text.isNotEmpty) await s.secrets.setServerPassword(pw.text, forServer: serverKey(c));
    } else {
      await saveServer(s.repo, null);
      await s.secrets.setServerPassword(null);
    }
    await s.reload();
  }

  Future<void> _sendToServer(BuildContext context) async {
    final body = await askBodyData(context, forYou: true);
    if (body == null || !context.mounted) return;
    // locked by default: the file leaves the phone (the person may still choose no password)
    final pw = await askLock(context);
    if (pw == null || !context.mounted) return;
    final c = s.server!;
    // exactly where it goes, before it goes
    final file = serverFileName(DateTime.now(), locked: pw.isNotEmpty); // the real name, shown and used (review 7, P3-6)
    if (!await confirm(context, 'Send this backup?', 'To: ${serverTarget(c, file)}\nAs: ${c.user}\n${pw.isEmpty ? 'Not locked: the server and anyone with access to it can read it.' : 'Locked with your password.'}${body ? '' : '\nWithout body data.'}', yes: 'Send')) return;
    try {
      final to = await busyWhile(context, pw.isEmpty ? 'Sending…' : 'Locking and sending…', () => s.sendBackupToServer(body: body, lockPassword: pw, name: file));
      if (context.mounted) toast(context, 'Sent to ${to.host}.');
    } on BackupError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  /// Android's own folder picker; true when one was picked.
  Future<bool> _pickFolder(BuildContext context) async {
    try {
      final tree = await AppState.backupFolder.pick();
      if (tree == null) return false;
      final name = Uri.decodeComponent(tree.split('/').last).split(':').last;
      await s.saveAutoBackupChoice(s.autoBackup.copyWith(tree: tree, folderName: name));
      return true;
    } catch (e) {
      if (context.mounted) toast(context, 'The folder could not be used: $e');
      return false;
    }
  }

  List<Widget> _data(BuildContext context) {
    final st = s.settings;
    return [
      const Dim('Stored only on this phone. A backup is one file you keep wherever you like (API keys and progress photos are never in it). '
          'Export makes a file of your sets, body data, plans or records in the format you pick (Strong, Hevy, FitNotes, a spreadsheet, text, Garmin), to save or share.'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(onPressed: () => _export(context), child: const Text('Export backup')),
        OutlinedButton(onPressed: () => _import(context), child: const Text('Import backup')),
        FilledButton.tonal(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExportScreen(s: s))), child: const Text('Export…')),
        FilledButton.tonal(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImportScreen(s: s))), child: const Text('Import from another app…')),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: st.hideRecents,
        onChanged: (v) => s.saveSettings(st.copyWith(hideRecents: v)),
        title: const Text('Hide the app in recent apps'),
        subtitle: const Dim('The app switcher shows a blank card, and screenshots of the app are blocked.', size: 12),
      ),
      const Q('Privacy, in plain words'),
      const Dim(privacyText),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () async {
          if (await confirm(context, 'Delete everything?', 'All workouts, plans, settings, progress photos, saved API keys, reminders and downloaded AI models are removed from this phone. This cannot be undone. Export a backup first if you want one.\n\nBackups already in your backup folder or on your server are not deleted; remove them there if you want them gone.', yes: 'Delete everything')) {
            await s.wipeEverything();
          }
        },
        child: const Text('Delete all data', style: TextStyle(color: C.gold)),
      ),
    ];
  }

  List<Widget> _about(BuildContext context) {
    final st = s.settings;
    return [
      _UpdateCard(s: s),
      // F397, F413, F414: the privacy promise, the licences, and the signing fingerprint, as text
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Privacy and licences', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Dim('The privacy promise in full:', size: 12),
            const SelectableText(privacyUrl, style: TextStyle(color: C.teal, fontSize: 12)),
            const SizedBox(height: 8),
            const Dim('Release APKs are signed with one key. Its certificate fingerprint (SHA-256):', size: 12),
            const SelectableText(signingFingerprint, style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 4),
            TextButton.icon(
              icon: const Icon(Icons.gavel_outlined, size: 18),
              label: const Text('Licences'),
              onPressed: () => showLicensePage(context: context, applicationName: appName, applicationVersion: appVersion, applicationLegalese: 'Code: GPL-3.0. Icons, texts and sounds: CC BY-SA 4.0. Made by balderding.'),
            ),
          ]),
        ),
      ),
      // F430: the last errors, kept on this phone; shown first, copied only on a tap
      Card(
        child: ListTile(
          leading: const Icon(Icons.description_outlined, color: C.teal),
          title: const Text('Debug info'),
          subtitle: const Dim('The last errors, if any: only their kind and where in the app. Nothing is sent.', size: 12),
          onTap: () async {
            final text = await (CrashLog.current?.text(header: '$appName $appVersion\n\n') ?? Future.value('No errors recorded.'));
            if (context.mounted) await showDetails(context, text);
          },
        ),
      ),
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
            const Text('About', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Dim('FightMilk is free and open source. Code: GPL-3.0. Exercise icons and sounds: CC BY-SA 4.0. Made by balderding. github.com/Balderding/FightMilk'),
            if (s.loadProblems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('These saved settings could not be read and were reset: ${s.loadProblems.join(', ')}.', key: const Key('loadProblems'), style: const TextStyle(color: C.gold, fontSize: 12)),
              ),
          ]),
        ),
      ),
    ];
  }

  Future<void> _export(BuildContext context) async {
    try {
      final body = await askBodyData(context, forYou: true); // asked once, plain words (batch 20)
      if (body == null) return;
      if (!context.mounted) return;
      final pw = await askLock(context); // F338
      if (pw == null) return;
      final plain = await exportBackup(s.repo, body: body);
      if (!context.mounted) return;
      final text = pw.isEmpty ? plain : await busyWhile(context, 'Locking…', () => lockBackup(plain, pw));
      final d = DateTime.now();
      final name = 'workout-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
      final uri = await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(text)), mimeType: 'application/json', dialogTitle: 'Save backup');
      if (uri != null) await s.noteManualBackup();
      if (context.mounted) toast(context, uri == null ? 'Not saved.' : 'Backup saved.');
    } catch (e) {
      if (context.mounted) toast(context, 'Could not save the backup: $e');
    }
  }

  Future<void> _import(BuildContext context) async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Pick a backup file');
    if (files.isEmpty || !context.mounted) return;
    // the size first: a file picked by mistake (a video, 500 MB) is never read whole (review 7, P2-4)
    const tooBig = 'That file is too big to be a backup from this app (over 64 MB).';
    if ((files.first.lengthSync() ?? 0) > backupMaxBytes) return toast(context, tooBig);
    final bytes = await readCapped(files.first.readAsByteStream());
    if (!context.mounted) return;
    if (bytes == null) return toast(context, tooBig);
    final text = utf8.decode(bytes, allowMalformed: true);
    final replace = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Import backup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (!backupHasBody(text)) const Padding(padding: EdgeInsets.only(top: 6), child: Dim('This backup has no body data; the weigh-ins, tape and height on this phone are kept.', size: 12)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Add to what is on this phone')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Replace everything on this phone')),
          ]),
        ),
      ),
    );
    if (replace == null) return;
    String? pw;
    String? problem;
    for (var tries = 0; tries < 5; tries++) {
      final took = Stopwatch()..start();
      try {
        await busyWhile(context, pw == null ? 'Restoring…' : 'Opening the locked backup…', () async {
          await importBackup(s.repo, text, replace: replace, password: pw);
          await s.reload();
        });
        if (context.mounted) toast(context, 'Backup imported.');
        return;
      } on BackupNeedsPassword {
        // asked below
      } on BackupError catch (e) {
        if (pw == null || !e.message.startsWith('Wrong password')) {
          if (context.mounted) toast(context, e.message);
          return;
        }
        // a file this slow to open is not offered again and again (review 7, P2-2)
        if (took.elapsed > const Duration(seconds: 15)) {
          if (context.mounted) toast(context, 'Wrong password. This locked backup takes very long to open on this phone, so it was not tried again.');
          return;
        }
        problem = e.message;
      }
      if (!context.mounted) return;
      pw = await askUnlock(context, problem: problem);
      if (pw == null) return;
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
                const Text('Ask AI', style: TextStyle(fontWeight: FontWeight.w600)),
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
            if (!a.isHandoff) ...[
              const Q('When the AI changes something in the app'),
              Pills<bool>(
                values: const [false, true],
                label: (v) => v ? 'Auto: just do it' : 'Ask me first',
                selected: {st.aiAuto},
                onTap: (v) => s.saveSettings(st.copyWith(aiAuto: v)),
              ),
              Dim(st.aiAuto
                  ? 'Ask AI makes the changes right away and tells you what it did. Every change can be undone (Ask AI → AI changes).'
                  : 'Ask AI shows what it wants to change and waits for you to tap Apply.', size: 12),
            ],
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
                  await copySensitive(projectInstructions(s.lib, s.profile!));
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
                icon: const Icon(Icons.auto_awesome, color: C.gold),
                label: const Text('Ask AI'),
              ),
              const SizedBox(height: 6),
              const Dim('This app sends nothing in this mode.', size: 12),
            ] else ...[
            if (a.kind == AiKind.local) ...[
              TextField(enableIMEPersonalizedLearning: false, controller: url, decoration: const InputDecoration(labelText: 'Server address', hintText: 'http://192.168.1.20:8081'), onChanged: (_) => setState(() {}), onSubmitted: (_) => _save()),
              const SizedBox(height: 4),
              const Dim('Any OpenAI-compatible server: llama-server, Ollama, LM Studio. Plain http works only on your home network.', size: 12),
              if (httpWarn && !badLocal) const Dim('Note: http is not encrypted. Fine at home, not on public Wi-Fi.', size: 12),
              if (badLocal) const Padding(padding: EdgeInsets.only(top: 6), child: Problem(['A server on the internet must use https.'])),
              const SizedBox(height: 8),
            ],
            TextField(enableIMEPersonalizedLearning: false, 
              controller: key,
              obscureText: true,
              decoration: InputDecoration(labelText: a.kind == AiKind.local ? 'API key (only if your server needs one)' : 'API key', hintText: hasKey ? 'saved ••••••• (type to replace)' : 'paste your key'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            TextField(enableIMEPersonalizedLearning: false, controller: model, decoration: const InputDecoration(labelText: 'Model'), onSubmitted: (_) => _save()),
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
              icon: const Icon(Icons.auto_awesome, color: C.gold),
              label: const Text('Ask AI'),
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
      Padding(padding: const EdgeInsets.only(top: 4), child: Dim(m.importOnly ? m.note : '${m.size} download. ${m.note}', size: 12)),
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
              icon: const Icon(Icons.auto_awesome, color: C.gold),
              label: const Text('Ask AI'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              if (await confirm(context, 'Delete the model?', m.importOnly ? 'Frees ${sizeText(s.models.sizeOf(m))}. You can import it again any time.' : 'Frees ${m.size}. You can download it again any time.', yes: 'Delete')) s.deleteModel();
            },
            child: const Text('Delete'),
          ),
        ]),
      ] else if (m.importOnly) ...[
        FilledButton.icon(
          onPressed: engine && !s.modelImporting ? s.importModel : null,
          icon: s.modelImporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_open_outlined),
          label: Text(s.modelImporting ? 'Copying… keep the app open' : 'Import model file (.gguf)'),
        ),
        const SizedBox(height: 4),
        const Dim('First save the file on this phone (for example in Google Drive: ⋮ → Download, it lands in Downloads), then pick it here. The app keeps its own copy; nothing is sent anywhere.', size: 12),
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
          const Dim('Updates are checked against their published fingerprint, and Android only installs them if they are signed by the same key as this app. Your workouts stay.', size: 12),
        ]),
      ),
    );
  }
}
