import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../ai/ai.dart';
import '../ai/grammar.dart';
import '../ai/plan_json.dart';
import '../ai/prompt.dart';
import '../ai/tools.dart';
import '../data/recovery.dart';
import '../data/repo.dart';
import '../domain/exercise.dart';
import '../domain/explain.dart';
import '../domain/gym.dart';
import '../domain/plates.dart';
import '../domain/progression.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/programs.dart';
import '../domain/program.dart';
import '../domain/plan_maker.dart';
import '../data/export.dart' show ExportKind;
import '../domain/body.dart';
import '../domain/reports.dart';
import '../domain/stats.dart';
import '../domain/units.dart';
import '../domain/volume.dart';
import '../llm/model_store.dart';
import '../llm/native.dart';
import '../net/guarded_client.dart';
import '../packs/pack.dart';
import '../services/notify.dart';
import '../services/secrets.dart';
import '../services/sounds.dart';
import '../update/updater.dart';
import 'widgets.dart' show leftHandedLayout;
import '../data/import_store.dart';
import '../data/auto_backup.dart';
import '../data/webdav.dart';
import '../data/backup.dart' show BackupError, exportBackup, lockBackup;

class Settings {
  final bool aiOn;
  final AiConfig ai;
  final bool preview; // show what's sent before every AI request
  final bool autoPacks; // check GitHub for icons when the app starts
  final bool keepAwake; // screen stays on during a workout
  final int? rest; // rest between sets in seconds; null = each exercise's own rest from the plan
  final Map<String, double> steps; // "barbell_lb" -> 2.5 : the user's own smallest weight steps
  final bool chatProject; // the instructions are saved in a Claude Project: hand-offs send only the request
  final bool smartRest; // rest worked out from how hard the set was (default)
  final String sound; // reward sounds: 'cute' (uwu), 'simple', 'off'
  final List<int> remindDays; // weekdays 1-7 (Monday = 1) to get a "time to train" reminder
  final int remindAt; // minutes after midnight
  final bool autoUpdate; // check GitHub for a new app version when the app opens
  final bool restOff; // no rest timer at all
  final bool checkin; // 'How do you feel?' before a workout (off unless turned on)
  final bool effortChips; // 'How was that set?' chips while resting (off unless turned on)
  final bool simple; // Simple mode: the advanced tools are hidden
  final int deloadEvery; // weeks; 0 = only when you ask or the app suggests
  final String formula; // 1RM: 'epley' | 'brzycki'
  final bool effortDrives; // Easy/Hard taps change the next weight
  final int dropPct; // percent
  final int missesToDrop;
  final String progSpeed; // 'slow' | 'steady' | 'fast'
  final bool climb; // F228: fewer extra sets early in a block, one more each week
  final bool tips; // F246: a tip of the day on Today
  final bool chartSmooth; // F267: smooth curves on charts
  final bool chartDots; // F267: a dot on every workout
  final bool badges; // F297/F298: badges and levels in Reports (quiet: no pop-ups)
  final bool dimRest; // F086: dark screen while resting; touches only wake it (pocket lock)
  final bool leftHanded; // F085: steppers and the workout buttons mirrored
  final int weighAt; // F303: morning weigh-in reminder, minutes after midnight; -1 = off
  final bool warmups; // warm-up rows worked out for the first big lift of each muscle
  final bool hideRecents; // blank thumbnail in recent apps, no screenshots
  final bool aiAuto; // Ask AI: true = the AI just makes the changes (undo stays), false = ask first

  const Settings({
    this.aiOn = false,
    this.ai = const AiConfig(kind: AiKind.claude, model: 'claude-opus-5-5'),
    this.preview = true,
    this.autoPacks = false,
    this.keepAwake = true,
    this.rest,
    this.steps = const {},
    this.chatProject = false,
    this.smartRest = true,
    this.sound = 'cute',
    this.remindDays = const [],
    this.remindAt = 17 * 60 + 30,
    this.autoUpdate = false,
    this.aiAuto = false,
    this.hideRecents = false,
    this.warmups = true,
    this.restOff = false,
    this.checkin = false,
    this.effortChips = false,
    this.simple = false,
    this.deloadEvery = 0,
    this.formula = 'epley',
    this.effortDrives = true,
    this.dropPct = 10,
    this.missesToDrop = 2,
    this.progSpeed = 'steady',
    this.climb = false,
    this.tips = true,
    this.chartSmooth = false,
    this.chartDots = true,
    this.badges = true,
    this.weighAt = -1,
    this.leftHanded = false,
    this.dimRest = false,
  });

  Settings copyWith({bool? aiOn, AiConfig? ai, bool? preview, bool? autoPacks, bool? keepAwake, int? rest, bool planRest = false, Map<String, double>? steps, bool? chatProject, bool? smartRest, String? sound, List<int>? remindDays, int? remindAt, bool? autoUpdate, bool? aiAuto, bool? hideRecents, bool? warmups, bool? restOff, bool? checkin, bool? effortChips, bool? simple, int? deloadEvery, String? formula, bool? effortDrives, int? dropPct, int? missesToDrop, String? progSpeed, bool? climb, bool? tips, bool? chartSmooth, bool? chartDots, bool? badges, int? weighAt, bool? leftHanded, bool? dimRest}) => Settings(
        aiOn: aiOn ?? this.aiOn,
        ai: ai ?? this.ai,
        preview: preview ?? this.preview,
        autoPacks: autoPacks ?? this.autoPacks,
        keepAwake: keepAwake ?? this.keepAwake,
        rest: planRest ? null : (rest ?? this.rest),
        steps: steps ?? this.steps,
        chatProject: chatProject ?? this.chatProject,
        smartRest: smartRest ?? this.smartRest,
        sound: sound ?? this.sound,
        remindDays: remindDays ?? this.remindDays,
        remindAt: remindAt ?? this.remindAt,
        autoUpdate: autoUpdate ?? this.autoUpdate,
        aiAuto: aiAuto ?? this.aiAuto,
        hideRecents: hideRecents ?? this.hideRecents,
        warmups: warmups ?? this.warmups,
        restOff: restOff ?? this.restOff,
        checkin: checkin ?? this.checkin,
        effortChips: effortChips ?? this.effortChips,
        simple: simple ?? this.simple,
        deloadEvery: deloadEvery ?? this.deloadEvery,
        formula: formula ?? this.formula,
        effortDrives: effortDrives ?? this.effortDrives,
        dropPct: dropPct ?? this.dropPct,
        missesToDrop: missesToDrop ?? this.missesToDrop,
        progSpeed: progSpeed ?? this.progSpeed,
        climb: climb ?? this.climb,
        tips: tips ?? this.tips,
        chartSmooth: chartSmooth ?? this.chartSmooth,
        chartDots: chartDots ?? this.chartDots,
        badges: badges ?? this.badges,
        weighAt: weighAt ?? this.weighAt,
        leftHanded: leftHanded ?? this.leftHanded,
        dimRest: dimRest ?? this.dimRest,
      );

  Map<String, dynamic> toJson() => {'aiOn': aiOn, 'ai': ai.toJson(), 'preview': preview, 'autoPacks': autoPacks, 'keepAwake': keepAwake, 'rest': rest, 'steps': steps, 'chatProject': chatProject, 'smartRest': smartRest, 'sound': sound, 'remindDays': remindDays, 'remindAt': remindAt, 'autoUpdate': autoUpdate, 'aiAuto': aiAuto, 'hideRecents': hideRecents, 'warmups': warmups, 'restOff': restOff, 'checkIn': checkin, 'effortChips': effortChips, 'simple': simple, 'deloadEvery': deloadEvery, 'formula': formula, 'effortDrives': effortDrives, 'dropPct': dropPct, 'missesToDrop': missesToDrop, 'progSpeed': progSpeed, 'climb': climb, 'tips': tips, 'chartSmooth': chartSmooth, 'chartDots': chartDots, 'badges': badges, 'weighAt': weighAt, 'leftHanded': leftHanded, 'dimRest': dimRest};

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        aiOn: (j['aiOn'] ?? false) as bool,
        ai: j['ai'] == null ? const AiConfig(kind: AiKind.claude, model: 'claude-opus-5-5') : AiConfig.fromJson(j['ai'] as Map<String, dynamic>),
        preview: (j['preview'] ?? true) as bool,
        autoPacks: (j['autoPacks'] ?? false) as bool,
        keepAwake: (j['keepAwake'] ?? true) as bool,
        rest: j['rest'] as int?,
        steps: {for (final e in ((j['steps'] ?? const {}) as Map).entries) e.key as String: (e.value as num).toDouble()},
        chatProject: (j['chatProject'] ?? false) as bool,
        smartRest: (j['smartRest'] ?? true) as bool,
        sound: (j['sound'] ?? 'cute') as String,
        remindDays: [for (final d in (j['remindDays'] ?? const []) as List) d as int],
        remindAt: (j['remindAt'] ?? 17 * 60 + 30) as int,
        autoUpdate: (j['autoUpdate'] ?? false) as bool,
        aiAuto: (j['aiAuto'] ?? false) as bool,
        hideRecents: (j['hideRecents'] ?? false) as bool,
        warmups: (j['warmups'] ?? true) as bool,
        restOff: (j['restOff'] ?? false) as bool,
        checkin: (j['checkIn'] ?? false) as bool,
        effortChips: (j['effortChips'] ?? false) as bool,
        simple: (j['simple'] ?? false) as bool,
        deloadEvery: (j['deloadEvery'] ?? 0) as int,
        formula: (j['formula'] ?? 'epley') as String,
        effortDrives: (j['effortDrives'] ?? true) as bool,
        dropPct: (j['dropPct'] ?? 10) as int,
        missesToDrop: (j['missesToDrop'] ?? 2) as int,
        progSpeed: (j['progSpeed'] ?? 'steady') as String,
        climb: (j['climb'] ?? false) as bool,
        tips: (j['tips'] ?? true) as bool,
        chartSmooth: (j['chartSmooth'] ?? false) as bool,
        chartDots: (j['chartDots'] ?? true) as bool,
        badges: (j['badges'] ?? true) as bool,
        weighAt: (j['weighAt'] ?? -1) as int,
        leftHanded: (j['leftHanded'] ?? false) as bool,
        dimRest: (j['dimRest'] ?? false) as bool,
      );
}

/// What the screens show for one exercise today.
class Target {
  final double? kg; // null = no history yet; the user fills in the first set
  final int reps;
  final bool up; // weight (or reps) went up since last time
  final String? why; // a lighter target and why (deload, rough day, time off)
  final List<double?>? perSet; // programs: the weight of each planned set (null = you pick)
  final double? tm; // programs: the training max the % sets come from
  final String? reason; // F238: why this weight, from the last workout ("+2.5 kg: every set hit 8")
  const Target(this.kg, this.reps, this.up, {this.why, this.perSet, this.tm, this.reason});
}

/// A weak point and the exercise that works it (F209): lift -> point -> exercise ids, best first.
const weakPoints = <String, Map<String, List<String>>>{
  'bench_press': {'Off the chest': ['db_bench_press', 'deficit_push_up', 'cable_fly'], 'Lockout': ['close_grip_bench', 'jm_press', 'dips'], 'Shoulders give out': ['seated_db_press', 'face_pull']},
  'back_squat': {'Out of the hole': ['pause_squat', 'box_squat', 'front_squat'], 'Knees cave in': ['hip_abduction', 'db_split_squat'], 'Leaning forward': ['front_squat', 'good_morning']},
  'deadlift': {'Off the floor': ['deficit_deadlift', 'pendlay_row'], 'Lockout': ['rack_pull', 'hip_thrust'], 'Back rounds': ['romanian_deadlift', 'back_extension']},
  'overhead_press': {'Off the shoulders': ['seated_db_press', 'z_press'], 'Lockout': ['close_grip_bench', 'triceps_pushdown']},
};

/// A rough first weight from body weight (F199): fraction of body weight for someone new.
const _startRatio = {'back_squat': 0.5, 'front_squat': 0.4, 'bench_press': 0.4, 'deadlift': 0.6, 'overhead_press': 0.25, 'barbell_row': 0.35, 'leg_press': 0.9, 'hip_thrust': 0.5, 'romanian_deadlift': 0.4, 'lat_pulldown': 0.4, 'seated_cable_row': 0.4, 'machine_chest_press': 0.35};

/// An AI request ready to send: the exact texts and where they go.
enum AiTask { plan, today, ask, guide, tools }

class AiRequest {
  final String host;
  final String system;
  final String user;
  final AiTask task;
  final Map<String, dynamic>? schema;
  final String? grammar; // on-phone model: the output is locked to this
  const AiRequest(this.host, this.system, this.user, this.task, {this.schema, this.grammar});
  bool get wholePlan => task == AiTask.plan;
}

/// One message for a chat app: the instructions and the request together, plus how to reply.
/// With [project] the instructions already live in a Claude Project, so only the request goes.
String handoffText(AiRequest r, {bool project = false}) {
  final b = StringBuffer();
  if (!project) {
    b
      ..writeln(r.system.trim())
      ..writeln()
      ..writeln('---');
  }
  b.writeln(r.user.trim());
  if (r.task == AiTask.plan || r.task == AiTask.today) {
    b
      ..writeln()
      ..writeln(project
          ? 'Reply in the workout list format from the project instructions (PLAN: / DAY: lines) so I can paste it back into my app.'
          : 'Reply in the workout list format above (PLAN: / DAY: lines) so I can paste it back into my workout app.');
  }
  return b.toString();
}

class AppState extends ChangeNotifier {
  final Repo repo;
  final PackStore packs;
  final Library baseLib;
  final Secrets secrets;
  final Notifier notifier;
  final Sounds sounds = Sounds();
  final ModelStore models;
  double? modelProgress; // 0..1 while a model downloads
  String? modelNote; // last download message
  bool _stopDownload = false;
  Library lib;
  Profile? profile;
  Plan? plan;
  Session? session;
  Settings settings = const Settings();
  int? lastDay;
  PlanDay? override; // today-only swaps made before starting
  int? pickedDay; // "do a different day today"
  Map<String, LiftState> programLifts = {}; // program plans: the state of each lift with a rule
  List<String> programNotes = []; // what the last program workout changed (shown on Today once)
  int finishedOnPlan = 0;

  // ---------- rest timer ----------
  DateTime? restEnd;
  bool _background = false;

  Duration? get restLeft {
    if (restEnd == null) return null;
    final d = restEnd!.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// In the app: the screen counts down and beeps. Locked or in the background: a scheduled
  /// notification buzzes instead. Never both.
  /// How long ago the rest ran out (the timer counts up after zero), or null.
  Duration? get restOver {
    if (restEnd == null) return null;
    final d = DateTime.now().difference(restEnd!);
    return d.isNegative ? null : d;
  }

  /// Name of the next exercise, for the rest notice.
  String restNext = '';

  void startRest(Duration d) {
    if (settings.restOff) return;
    restEnd = DateTime.now().add(d);
    if (_background) {
      notifier.restDone(d);
      notifier.restOngoing(restEnd!, restNext);
    }
    notifyListeners();
  }

  void stopRest() {
    restEnd = null;
    notifier.cancel();
    notifier.cancelOngoing();
    notifyListeners();
  }

  void appPaused() {
    _background = true;
    updateHomeWidget().ignore(); // the home-screen widget shows what is next when the app is left (F351)
    final left = restLeft;
    if (left != null && left > Duration.zero) {
      notifier.restDone(left);
      notifier.restOngoing(restEnd!, restNext);
    }
  }

  void appResumed() {
    _background = false;
    notifier.cancel();
    notifier.cancelOngoing();
    notifyListeners();
  }

  AppState._(this.repo, this.packs, this.baseLib, this.secrets, this.notifier) : lib = baseLib, models = ModelStore(packs.dir);

  @visibleForTesting
  static Future<AppState> forTest(Repo repo, PackStore packs, Library lib) async {
    final s = AppState._(repo, packs, lib, Secrets(), Notifier());
    s.sounds.muted = true;
    await s.reload();
    return s;
  }

  /// Opens the app's data. A failure becomes a [StartFailure] with the file and a plain reason,
  /// and any half-opened database is closed again, so the recovery screen can copy the files and
  /// "Try again" starts clean (F431). Notifications that fail to start do not stop the app.
  static Future<AppState> load() async {
    final dir = await getApplicationSupportDirectory();
    cleanRecoveryLeftovers(dir); // a recovery copy the app was killed in the middle of
    final path = p.join(await getDatabasesPath(), 'workout.db');
    final Library base;
    try {
      base = await Library.load();
    } catch (e) {
      throw StartFailure(path, e, stage: 'library');
    }
    Repo? repo;
    final AppState s;
    try {
      repo = await Repo.open(path);
      final packs = PackStore(dir.path);
      final notifier = Notifier();
      await notifier.init(); // never throws: without it, reminders and rest alerts are just off
      s = AppState._(repo, packs, base, Secrets(), notifier);
      await s.rebuildLib();
      await s.reload();
    } catch (e) {
      try {
        await repo?.close();
      } catch (_) {}
      throw StartFailure(path, e);
    }
    if (s.settings.autoPacks) {
      s.checkPacks().ignore();
    }
    s.applyPrefs();
    if (s.settings.autoUpdate) {
      s.checkForUpdate().ignore();
    }
    return s;
  }

  // ---------- your exercises ----------
  List<Exercise> customExercises = [];
  Map<String, String> renames = {};
  /// A new user's short "what's here" card on Today (shown once after the first setup).
  bool showTour = false;
  void hideTour() {
    showTour = false;
    notifyListeners();
  }

  Map<String, String> exScheme = {}; // per-exercise progression: 'linear'
  Map<String, double> exStep = {}; // per-exercise weight step (kg)

  /// 'double' (default) or 'linear' for one exercise.
  Future<void> setScheme(String id, String scheme) async {
    scheme == 'double' ? exScheme.remove(id) : exScheme[id] = scheme;
    await _savePrefs();
    applySteps();
  }

  /// This lift's own weight step (kg); null = the usual for its equipment.
  Future<void> setExStep(String id, double? kg) async {
    kg == null ? exStep.remove(id) : exStep[id] = kg;
    await _savePrefs();
    applySteps();
  }

  /// The library: built in + icon packs + your own, with your names, favourites and hidden ones.
  Future<void> rebuildLib() async {
    final c = await repo.kvGet('custom_ex');
    customExercises = [];
    customNeeds.clear();
    if (c != null) {
      for (final j in (jsonDecode(c) as List).cast<Map<String, dynamic>>()) {
        try {
          customExercises.add(Exercise.fromJson(j['ex'] as Map<String, dynamic>));
          final needs = [for (final n in (j['needs'] ?? const []) as List) (n as List).cast<String>().toSet()];
          customNeeds[j['ex']['id'] as String] = needs;
        } catch (_) {}
      }
    }
    final pj = await repo.kvGet('ex_prefs');
    final prefs = pj == null ? const <String, dynamic>{} : jsonDecode(pj) as Map<String, dynamic>;
    renames = {for (final e in ((prefs['names'] ?? const {}) as Map).entries) e.key as String: e.value as String};
    exScheme = {for (final e in ((prefs['scheme'] ?? const {}) as Map).entries) e.key as String: e.value as String};
    exStep = {for (final e in ((prefs['step'] ?? const {}) as Map).entries) e.key as String: (e.value as num).toDouble()};
    final base = baseLib.merged([...packs.exercises(), ...customExercises]);
    final l = base.merged([for (final e in renames.entries) if (base.byId(e.key) != null) base.byId(e.key)!.copyWith(name: e.value)]);
    l.hidden.addAll([for (final x in (prefs['hide'] ?? const []) as List) x as String]);
    l.favs.addAll([for (final x in (prefs['fav'] ?? const []) as List) x as String]);
    lib = l;
  }

  Future<void> _savePrefs() async {
    await repo.kvSet('ex_prefs', jsonEncode({'fav': lib.favs.toList(), 'hide': lib.hidden.toList(), 'names': renames, 'scheme': exScheme, 'step': exStep}));
    await rebuildLib();
    notifyListeners();
  }

  Future<void> setFavourite(String id, bool on) async {
    on ? lib.favs.add(id) : lib.favs.remove(id);
    await _savePrefs();
  }

  Future<void> setHidden(String id, bool on) async {
    on ? lib.hidden.add(id) : lib.hidden.remove(id);
    await _savePrefs();
  }

  /// Your own name for an exercise ('' = back to the library name).
  Future<void> renameExercise(String id, String name) async {
    name.trim().isEmpty ? renames.remove(id) : renames[id] = name.trim();
    await _savePrefs();
  }

  /// Save one of your own exercises ([needs]: gym items, any one set of them is enough).
  Future<void> saveCustomExercise(Exercise e, List<Set<String>> needs) async {
    final l = [for (final x in customExercises) if (x.id != e.id) {'ex': x.toJson(), 'needs': [for (final n in customNeeds[x.id] ?? const <Set<String>>[]) n.toList()]}];
    l.add({'ex': e.toJson(), 'needs': [for (final n in needs) n.toList()]});
    await repo.kvSet('custom_ex', jsonEncode(l));
    await rebuildLib();
    notifyListeners();
  }

  Future<void> deleteCustomExercise(String id) async {
    final l = [for (final x in customExercises) if (x.id != id) {'ex': x.toJson(), 'needs': [for (final n in customNeeds[x.id] ?? const <Set<String>>[]) n.toList()]}];
    await repo.kvSet('custom_ex', jsonEncode(l));
    await rebuildLib();
    notifyListeners();
  }

  /// Goes up whenever the history may have changed; cached Progress look-ups reload on it (P2-8).
  int historyVersion = 0;

  /// Saved values that could not be read at the last load (each kept its empty default).
  List<String> loadProblems = [];

  void _loadFailed(String what, Object e) {
    loadProblems = [...loadProblems, what];
    debugPrint('FightMilk: could not read the saved $what ($e); using the default');
  }

  Future<void> _safeLoad(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      _loadFailed(what, e);
    }
  }

  Future<void> reload() async {
    historyVersion++;
    await rebuildLib();
    loadProblems = [];
    final st = await repo.kvGet('settings');
    try {
      settings = st == null ? const Settings() : Settings.fromJson(jsonDecode(st) as Map<String, dynamic>);
    } catch (e) {
      settings = const Settings();
      _loadFailed('settings', e);
    }
    applySteps();
    profile = await repo.profile();
    // a broken or edited saved value never stops the whole load (review 4, P3-N22)
    await _safeLoad('gyms', _loadGyms);
    await _safeLoad('deload', _loadDeload);
    await _safeLoad('body notes', _loadBodyNotes);
    await _safeLoad('coaching', _loadCoaching);
    await _safeLoad('dashboard', _loadDash);
    await _safeLoad('goals', _loadAims);
    await _safeLoad('body', _loadBody19);
    await _safeLoad('imports', () async => lastImport = (await importRecords(repo)).lastOrNull);
    await _safeLoad('backup', () async {
      server = await loadServer(repo);
      autoBackup = await loadAutoBackup(repo);
      backupStatus = await loadBackupStatus(repo);
    });
    final bl = await repo.bodyLog();
    latestBodyKg = bl.map((b) => b.$3).whereType<double>().firstOrNull;
    final today0 = DateTime.now();
    weighedToday = bl.any((b) => b.$3 != null && b.$2.year == today0.year && b.$2.month == today0.month && b.$2.day == today0.day);
    profile = _withGym(profile);
    plan = await repo.activePlan();
    await _endBlockSwaps(); // a swap for a block ends on its own plan, by date (P1-3)
    session = await repo.openSession();
    if (session != null && session!.day.items.any((it) => lib.byId(it.exerciseId) == null)) {
      await repo.updateSessionDay(session!.id, session!.day.copyWith(items: [for (final it in session!.day.items) if (lib.byId(it.exerciseId) != null) it]));
      session = await repo.session(session!.id);
    }
    lastDay = plan == null ? null : await repo.lastDayIndex(plan!.id);
    finishedOnPlan = plan == null ? 0 : (await repo.history()).where((h) => h.planId == plan!.id).length;
    pickedDay = null;
    final pk = await repo.kvGet('picked');
    if (pk != null && plan != null) {
      try {
        final j = jsonDecode(pk) as Map<String, dynamic>;
        if (j['plan'] == plan!.id && j['last'] == lastDay && j['day'] is int && (j['day'] as int) < plan!.days.length) pickedDay = j['day'] as int;
      } catch (e) {
        _loadFailed('picked day', e);
      }
    }
    override = null;
    final o = await repo.kvGet('override');
    if (o != null && plan != null) {
      try {
        final j = jsonDecode(o) as Map<String, dynamic>;
        if (j['plan'] == plan!.id && j['day'] == todayIndex) override = PlanDay.fromJson(j['data'] as Map<String, dynamic>);
      } catch (e) {
        override = null;
        _loadFailed("today's changes", e);
      }
    }
    programLifts = {};
    if (plan?.program != null) {
      for (final k in plan!.program!.rules.keys) {
        final st = await repo.lift(k);
        if (st != null) programLifts[k] = st;
      }
    }
    await _loadChanges();
    notifyListeners();
  }

  Unit get unit => profile?.unit ?? Unit.lb;

  int get todayIndex {
    if (plan == null || plan!.days.isEmpty) return 0;
    if (pickedDay != null && pickedDay! < plan!.days.length) return pickedDay!;
    // days tied to weekdays (F197): Monday's day on Mondays, even after a missed week
    final wd = profile?.weekdays ?? const [];
    if (wd.isNotEmpty && wd.length == plan!.days.length) {
      final now = DateTime.now().weekday;
      for (var k = 0; k < 7; k++) {
        final i = wd.indexOf((now - 1 + k) % 7 + 1);
        if (i >= 0) return i;
      }
    }
    return nextDayIndex(plan!, lastDay);
  }

  /// Training days are set (F197) and today is not one of them.
  bool get restDay {
    final wd = profile?.weekdays ?? const [];
    return wd.isNotEmpty && !wd.contains(DateTime.now().weekday) && pickedDay == null && session == null && override == null;
  }

  /// The next training weekday after today ("Wed"), or null without set days.
  String? get nextTrainingDay {
    final wd = profile?.weekdays ?? const [];
    if (wd.isEmpty) return null;
    final now = DateTime.now().weekday;
    for (var k = 1; k <= 7; k++) {
      final d = (now - 1 + k) % 7 + 1;
      if (wd.contains(d)) return weekdayShort[d - 1];
    }
    return null;
  }

  /// A sport or long-run day today or tomorrow (F202): legs get one set fewer.
  bool get sportNear {
    final sd = profile?.sportDays ?? const {};
    if (sd.isEmpty) return false;
    final now = DateTime.now().weekday;
    return sd.contains(now) || sd.contains(now % 7 + 1);
  }

  static const _legs = {'quads', 'hamstrings', 'glutes', 'calves'};

  PlanDay? get today {
    if (session != null) return session!.day;
    if (override != null) return override;
    if (plan == null || plan!.days.isEmpty) return null;
    return _adjusted(plan!.days[todayIndex]);
  }

  /// "Week 3": one pass through a week's days = one week (programs have several weeks per rotation).
  int get week => plan == null || plan!.days.isEmpty ? 1 : finishedOnPlan ~/ plan!.daysPerWeek + 1;

  /// Programs: the week of the cycle the next day is in (1-based) and the cycle number.
  (int, int) get programWeek {
    final p = plan;
    if (p == null || p.weeksPerCycle <= 1) return (1, finishedOnPlan ~/ (p == null || p.days.isEmpty ? 1 : p.days.length) + 1);
    return (todayIndex ~/ p.daysPerWeek + 1, finishedOnPlan ~/ p.days.length + 1);
  }

  String iconFor(Exercise e) => packs.iconPath(e.icon) ?? 'asset:assets/icons/${e.icon}.svg';

  // ---------- setup / plans ----------
  /// Puts the user's own weight steps into effect.
  /// Sound mode and reminders follow the settings.
  void applyPrefs() {
    sounds.mode = settings.sound;
    _sys.invokeMethod('secure', {'on': settings.hideRecents}).catchError((_) => null);
    final d = today;
    notifier.scheduleReminders(settings.remindDays.toSet(), settings.remindAt, d?.name ?? 'your workout').ignore();
    notifier.scheduleWeighIn(settings.weighAt, skipToday: weighedToday).ignore();
  }

  void applySteps() {
    e1rmFormula = settings.formula;
    leftHandedLayout = settings.leftHanded;
    progressRules = ProgressRules(
      speed: settings.progSpeed,
      missesToDrop: settings.missesToDrop,
      dropPct: settings.dropPct / 100,
      effort: settings.effortDrives,
      scheme: exScheme,
      stepKg: exStep,
    );
    stepOverrides.clear();
    settings.steps.forEach((k, v) {
      final p = k.split('_');
      if (p.length == 2 && v > 0) {
        stepOverrides[(StepKind.values.byName(p[0]), Unit.values.byName(p[1]))] = v;
      }
    });
  }

  Future<void> saveSettings(Settings s) async {
    if (s.remindDays.isNotEmpty && settings.remindDays.isEmpty) notifier.askOnce().ignore();
    if (s.weighAt >= 0 && settings.weighAt < 0) notifier.askOnce().ignore(); // the weigh-in reminder needs it too (P3-N23)
    settings = s;
    applySteps();
    applyPrefs();
    await repo.kvSet('settings', jsonEncode(s.toJson()));
    notifyListeners();
  }

  Future<void> saveProfile(Profile pr) async {
    profile = _withGym(pr);
    await repo.saveProfile(pr);
    notifyListeners();
  }

  Future<void> usePlan(Plan pl) async {
    await repo.savePlan(pl);
    await repo.kvSet('override', '{}');
    await repo.kvSet('picked', '{}');
    pickedDay = null;
    await reload();
  }

  Future<void> makeBuiltInPlan() => usePlan(makePlan(profile!, lib));

  /// Saves a hand edit. The rotation, a picked day and an open workout keep pointing at the
  /// same days even when days were moved or deleted; today-only swaps are dropped.
  Future<void> savePlanEdits(Plan pl) async {
    final old = plan;
    await repo.savePlan(pl);
    if (old != null && old.id == pl.id) {
      final m = dayMap(old, pl);
      int? follow(int? i) {
        if (i == null || i < 0 || i >= m.length) return null;
        // a deleted day: carry on from the nearest earlier day that is still there
        for (var k = i; k >= 0; k--) {
          if (m[k] != null) return m[k];
        }
        return null;
      }
      if (lastDay != null) await repo.setLastDayIndex(pl.id, follow(lastDay) ?? -1);
      if (pickedDay != null) {
        final np = (pickedDay! < m.length) ? m[pickedDay!] : null;
        final nl = follow(lastDay);
        await repo.kvSet('picked', np == null ? '{}' : jsonEncode({'plan': pl.id, 'last': nl, 'day': np}));
      }
      if (session != null && session!.planId == pl.id) {
        await repo.setSessionDayIndex(session!.id, (session!.dayIndex >= 0 && session!.dayIndex < m.length ? m[session!.dayIndex] : null) ?? -1);
      }
    }
    await repo.kvSet('override', '{}');
    await reload();
  }

  Future<void> restorePlan(String id) async {
    await repo.restorePlan(id);
    pickedDay = null;
    await reload();
  }

  /// Move the rotation on without training (e.g. skip a day).
  Future<void> skipToday() async {
    if (plan == null) return;
    await repo.setLastDayIndex(plan!.id, todayIndex);
    await repo.kvSet('picked', '{}');
    pickedDay = null;
    await repo.kvSet('override', '{}');
    await reload();
  }

  /// "Do a different day today". Kept across restarts until that workout is done.
  Future<void> pickDay(int i) async {
    pickedDay = i;
    override = null;
    notifyListeners();
    await repo.kvSet('override', '{}');
    await repo.kvSet('picked', jsonEncode({'plan': plan?.id, 'last': lastDay, 'day': i}));
  }

  // ---------- deloads and how you feel ----------
  DateTime? deloadUntil; // "Deload this week"
  int? feeling; // today's check-in: 1 rough, 2 ok, 3 great

  /// A lighter week: asked for, or every N weeks of the plan (Settings → Progression).
  bool get inDeload {
    if (session != null) return sessionDeload;
    if (deloadUntil != null && DateTime.now().isBefore(deloadUntil!)) return true;
    final n = settings.deloadEvery;
    return n > 0 && plan != null && week % n == 0;
  }

  bool sessionDeload = false; // the workout going was started in a deload week

  Future<void> setDeload(bool on) async {
    deloadUntil = on ? DateTime.now().add(const Duration(days: 7)) : DateTime.now().subtract(const Duration(seconds: 1));
    await repo.kvSet('deload_until', '${deloadUntil!.millisecondsSinceEpoch}');
    notifyListeners();
  }

  Future<void> setFeeling(int? f) async {
    feeling = f;
    await repo.kvSet('feeling', f == null ? '{}' : jsonEncode({'date': _day(DateTime.now()), 'f': f}));
    notifyListeners();
  }

  Future<void> _loadDeload() async {
    final d = await repo.kvGet('deload_until');
    deloadUntil = d == null ? null : DateTime.fromMillisecondsSinceEpoch(int.tryParse(d) ?? 0);
    final f = await repo.kvGet('feeling');
    feeling = null;
    if (f != null && f.startsWith('{')) {
      final j = jsonDecode(f) as Map<String, dynamic>;
      if (j['date'] == _day(DateTime.now())) feeling = j['f'] as int?;
    }
    final sd = session == null ? null : await repo.kvGet('flags:${session!.id}');
    sessionDeload = sd != null && (jsonDecode(sd) as Map<String, dynamic>)['deload'] == true;
  }

  /// Lifts that missed reps last time: 3 or more and the app suggests a deload.
  Future<int> stalling() async => (await repo.allLifts()).where((l) => l.misses > 0).length;

  /// Today's sets as they will be done: a program lift's current stage; fewer in a deload week, on
  /// a rough day, or for legs next to a sport day.
  PlanDay? _adjusted(PlanDay? d) {
    if (d == null) return null;
    d = _staged(d);
    d = _careful(d);
    d = _climbed(d);
    if (sportNear) {
      d = d.copyWith(items: [
        for (final it in d.items)
          (_legs.contains(lib.byId(it.exerciseId)?.primary.first) && it.sets > 2 && it.perSet == null) ? it.copyWith(sets: it.sets - 1) : it
      ]);
    }
    final rough = feeling == 1;
    if (!inDeload && !rough) return d;
    return d.copyWith(items: [
      for (var i = 0; i < d.items.length; i++)
        d.items[i].copyWith(sets: inDeload ? (d.items[i].sets * 0.6).ceil().clamp(1, 10) : (i == 0 ? d.items[i].sets : (d.items[i].sets - 1).clamp(1, 10)))
    ]);
  }

  /// Pregnant or after a birth (F237): left-out exercises swapped for a safer one of the same kind
  /// (or dropped), and no all-out last sets or + sets.
  PlanDay _careful(PlanDay d) {
    careSwapped = 0;
    careDropped = 0;
    if (profile?.pregnancy == null) return d;
    final pr = profile!;
    final ids = {for (final it in d.items) it.exerciseId};
    final items = <PlanItem>[];
    for (final it in d.items) {
      var x = it;
      final e = lib.byId(it.exerciseId);
      if (e != null && lib.caution.contains(e.id)) {
        final alt = lib.swapsFor(e, pr.have, pr.avoid, items: pr.items).where((a) => !ids.contains(a.id)).firstOrNull;
        if (alt == null) {
          careDropped++;
          continue;
        }
        careSwapped++;
        ids.add(alt.id);
        x = x.copyWith(exerciseId: alt.id);
      }
      if (x.style.isNotEmpty) x = x.copyWith(style: '');
      if (x.perSet != null && x.perSet!.any((s) => s.amrap)) x = x.copyWith(perSet: [for (final s in x.perSet!) SetSpec(s.reps, hi: s.hi, pct: s.pct)]);
      items.add(x);
    }
    return d.copyWith(items: items); // nothing fits: an empty day, never a left-out exercise (P2-8)
  }

  int careSwapped = 0, careDropped = 0; // what careful mode did to the day shown (P2-8)

  /// "Careful mode: 2 swapped, 1 left out" for Today, or null.
  String? get carefulNote {
    if (profile?.pregnancy == null || session != null || override != null) return null;
    today; // works the counts out for the day shown
    if (careSwapped == 0 && careDropped == 0) return null;
    return 'Careful mode: ${[if (careSwapped > 0) '$careSwapped swapped', if (careDropped > 0) '$careDropped left out'].join(', ')} (Setup → More choices)';
  }

  /// Volume climb (F228): the extra exercises start a block one set lighter and gain a set each
  /// week until the deload. Main lifts and programs keep their sets.
  PlanDay _climbed(PlanDay d) {
    final c = climbStep;
    if (c == null || c == 0) return d;
    return d.copyWith(items: [
      for (var i = 0; i < d.items.length; i++)
        i == 0 || d.items[i].perSet != null ? d.items[i] : d.items[i].copyWith(sets: (d.items[i].sets + c).clamp(2, d.items[i].sets + 2))
    ]);
  }

  /// Sets added to each extra exercise this week of the block (-1 first week), or null when the
  /// climb is off.
  int? get climbStep {
    if (!settings.climb || inDeload || plan == null || plan!.weeksPerCycle > 1) return null;
    final len = settings.deloadEvery > 0 ? settings.deloadEvery : 5;
    return ((week - 1) % len - 1).clamp(-1, 2);
  }

  /// Stage rule lifts (GZCLP): the sets of the stage the lift is on.
  PlanDay _staged(PlanDay d) {
    final pr = plan?.program;
    if (pr == null) return d;
    var changed = false;
    final items = [
      for (final it in d.items)
        () {
          final r = pr.rules[liftKey(it)];
          if (r == null || r.kind != 'stage') return it;
          final sets = stageSets(r, programLifts[liftKey(it)]?.stage ?? 0);
          if (sets == null) return it;
          changed = true;
          final n = PlanItem.of(it.exerciseId, sets, rest: it.restSec, tier: it.tier, tmOf: it.tmOf, bump: it.bump, group: it.group);
          return n;
        }()
    ];
    return changed ? d.copyWith(items: items) : d;
  }

  /// A rough first weight from body weight, age and sex (F199). Null without a body weight.
  double? startGuess(Exercise e) {
    final r = _startRatio[e.id];
    final bw = profile?.bodyKg ?? latestBodyKg;
    if (r == null || bw == null || bw <= 0) return null;
    var f = r * (profile?.sex == 'f' ? 0.7 : 1.0) * ((profile?.age ?? 30) >= 50 ? 0.85 : 1.0);
    if (profile?.experience == 'years') f *= 1.6;
    if (profile?.experience == 'some') f *= 1.25;
    return roundToStep(bw * f, e.step, unit);
  }

  double? latestBodyKg; // newest weigh-in, for the start guess
  bool weighedToday = false; // today's weigh-in reminder is skipped (P3-N23)

  // ---------- targets ----------
  Future<Target> targetFor(PlanItem it) async {
    final e = lib.byId(it.exerciseId);
    if (e == null) return Target(null, it.repLow, false);
    // programs: % sets come from the training max, one weight per set
    if (it.perSet != null && it.perSet!.any((x) => x.pct != null)) {
      final tmSt = await repo.lift(tmKey(it));
      var tm = tmSt?.tm;
      final own = await repo.lift(liftKey(it));
      // no max yet: the first set you pick today sets one for the rest of the day (P2-5)
      String? from;
      if (tm == null && session != null) {
        final first = (await repo.setsFor(session!.id)).where((x) => x.key == liftKey(it) && x.counts && x.kg > 0).firstOrNull;
        final p0 = it.perSet!.first.pct;
        if (first != null && p0 != null && p0 > 0) {
          tm = first.kg / p0;
          from = 'Worked out from your first set; the workout sets your training max';
        }
      }
      // the same "lighter today" reasons as any lift (P1-9): every set of the day moves together
      final (f, why) = await _lighter(e, own ?? tmSt);
      final w = [
        for (final x in it.perSet!)
          x.pct != null ? (tm == null ? null : roundToStep(tm * x.pct! * f, e.step, unit)) : (own == null ? null : roundToStep(own.workKg * f, e.step, unit))
      ];
      return Target(w.firstWhere((x) => x != null, orElse: () => null), it.perSet!.first.reps, false,
          perSet: w, tm: tm, why: tm == null ? 'No training max yet: pick the first weight; the rest follow from it' : (from ?? why), reason: tmSt?.why);
    }
    var st = await repo.lift(liftKey(it));
    if (st == null && it.tier.isNotEmpty) {
      // a second slot of a lift (T2) starts at about 65% of the main slot's weight
      final base = await repo.lift(it.exerciseId);
      if (base != null && !e.bodyweight) st = LiftState(exerciseId: liftKey(it), workKg: roundToStep(base.workKg * 0.65, e.step, unit));
    }
    final last = await repo.lastTime(e.id);
    final lastMax = last.isEmpty ? null : last.where((s) => s.counts).fold<double?>(null, (a, s) => a == null || s.kg > a ? s.kg : a);
    if (st == null) {
      if (lastMax == null && !e.bodyweight) {
        final g = startGuess(e);
        if (g != null) return Target(g, it.repLow, false, why: 'A first guess from your body weight: change it if it feels wrong');
      }
      return Target(lastMax == null ? null : (e.bodyweight ? lastMax : roundToStep(lastMax, e.step, unit)), it.repLow, false);
    }
    final (f, why) = await _lighter(e, st);
    final kg = e.bodyweight ? st.workKg : roundToStep(st.workKg * f, e.step, unit);
    final reps = e.bodyweight ? (st.workReps ?? it.repLow).clamp(it.repLow, it.repHigh) : it.repLow;
    final up = lastMax != null && (kg > lastMax + 0.01 || (e.bodyweight && last.isNotEmpty && reps > (last.map((s) => s.reps).reduce((a, b) => a < b ? a : b))));
    return Target(kg, reps, up, why: why, reason: st.why);
  }

  /// Why today's weight is lighter than the lift's own, as one factor (1 = not lighter) and the
  /// reason: back after a break, a deload week, a rough day, "that hurt", tiredness earlier in
  /// the workout. Programs and plain lifts both use it.
  Future<(double, String?)> _lighter(Exercise e, LiftState? st) async {
    var f = 1.0;
    String? why;
    final away = st?.updated == null ? 0 : DateTime.now().difference(st!.updated!).inDays;
    if (away >= 28) {
      f = 0.8;
      why = 'Back after $away days: 20% lighter to start';
    } else if (away >= 14) {
      f = 0.9;
      why = 'Back after $away days: 10% lighter to start';
    }
    if (inDeload) {
      f *= 0.9;
      why = 'Deload week: lighter and fewer sets';
    } else if (feeling == 1) {
      f *= 0.95;
      why = 'Rough day: a bit lighter, one set fewer';
    } else if (sportNear && _legs.contains(e.primary.first)) {
      why = 'Sport day near: one leg set fewer';
    }
    final rp = (ramp[e.id]?['n'] as int?) ?? 0;
    if (rp > 0) {
      f *= rp >= 2 ? 0.8 : 0.9;
      why = 'Easing back in after it hurt: ${rp >= 2 ? 20 : 10}% lighter';
    }
    if (session != null && !e.bodyweight) {
      final s = session!;
      final planned = plan != null && plan!.id == s.planId && s.dayIndex >= 0 && s.dayIndex < plan!.days.length ? plan!.days[s.dayIndex].items : s.day.items;
      final extra = extraSetsBefore(e, await repo.setsFor(s.id), planned, lib);
      final ff = fatigueFactor(extra);
      if (ff < 1) {
        f *= ff;
        why ??= '${muscleName(muscleOf(e.primary.first))} already did ${extra.round()} more sets than usual before this: ${((1 - ff) * 100).round()}% lighter';
      }
    }
    return (f, why);
  }

  // ---------- today / workout ----------
  Future<void> setToday(PlanDay d) async {
    if (session != null) {
      await repo.updateSessionDay(session!.id, d);
      session = await repo.session(session!.id);
    } else {
      override = d;
      await repo.kvSet('override', jsonEncode({'plan': plan!.id, 'day': todayIndex, 'data': d.toJson()}));
    }
    notifyListeners();
  }

  /// Takes exercise [i] out of today (and out of the plan's day when [forever]). In a workout,
  /// the sets already logged for it are deleted too. Returns what [undoRemoveToday] needs.
  Future<({PlanDay day, List<SetLog> sets, Plan? plan, PlanDay? keep})> removeFromToday(int i, {bool forever = false}) async {
    final d = today!;
    final it = d.items[i];
    final sets = session == null ? <SetLog>[] : [for (final x in await repo.setsFor(session!.id)) if (x.exerciseId == it.exerciseId && (x.slot == null || x.slot == liftKey(it))) x];
    for (final x in sets) {
      await repo.deleteSet(x.id);
    }
    await setToday(d.copyWith(items: [...d.items]..removeAt(i)));
    Plan? before;
    PlanDay? keep;
    if (forever && plan != null) {
      final di = session?.dayIndex ?? todayIndex;
      if (di >= 0 && di < plan!.days.length) {
        final items = plan!.days[di].items;
        var pi = items.indexWhere((x) => x.exerciseId == it.exerciseId);
        if (pi < 0 && items.length == d.items.length) pi = i;
        if (pi >= 0) {
          before = plan;
          keep = session == null ? override : null;
          await savePlanEdits(plan!.removeItem(di, pi));
          if (keep != null) await setToday(keep); // today's other changes stay
        }
      }
    }
    if (sets.isNotEmpty) historyVersion++;
    notifyListeners();
    return (day: d, sets: sets, plan: before, keep: keep);
  }

  /// Undo of [removeFromToday]: the plan, today's list and the deleted sets, as they were.
  Future<void> undoRemoveToday(({PlanDay day, List<SetLog> sets, Plan? plan, PlanDay? keep}) r) async {
    if (r.plan != null) await savePlanEdits(r.plan!);
    await setToday(r.day);
    for (final x in r.sets) {
      await repo.restoreSet(x);
    }
    if (r.sets.isNotEmpty) historyVersion++;
    notifyListeners();
  }

  /// Adds [e] to the end of today (and to the plan's day when [forever]).
  Future<void> addToToday(Exercise e, {bool forever = false}) async {
    final d = today!;
    final it = PlanItem(exerciseId: e.id, sets: 3, repLow: e.repLow, repHigh: e.repHigh, restSec: e.compound ? 120 : 75);
    final nd = d.copyWith(items: [...d.items, it]);
    await setToday(nd);
    if (forever && plan != null) {
      final di = session?.dayIndex ?? todayIndex;
      if (di >= 0 && di < plan!.days.length) {
        await savePlanEdits(plan!.addItem(di, it));
        if (session == null) await setToday(nd); // keep today's other changes too
      }
    }
  }

  /// Swap exercise [i] of today. [forever] also writes it into the plan.
  /// Returns false when "from now on" could not be written into the plan.
  Future<bool> swap(int i, Exercise to, {required bool forever}) async {
    final d = today!;
    final old = d.items[i];
    final it = old.copyWith(exerciseId: to.id);
    final nd = d.copyWith(items: [...d.items]..[i] = it);
    await setToday(nd);
    if (!forever || plan == null) return true;
    final di = session?.dayIndex ?? todayIndex;
    if (di < 0 || di >= plan!.days.length) return false;
    final items = plan!.days[di].items;
    var pi = items.indexWhere((x) => x.exerciseId == old.exerciseId);
    if (pi < 0 && items.length == d.items.length) pi = i; // same slot
    if (pi < 0) return false;
    final keep = session == null ? override : null;
    await savePlanEdits(plan!.updateItem(di, pi, items[pi].copyWith(exerciseId: to.id)));
    if (keep != null) await setToday(keep); // keep today's other swaps
    return true;
  }

  Future<Session> startWorkout() async {
    if (session != null) return session!;
    final d = today!;
    final deload = inDeload;
    session = await repo.startSession(plan!, todayIndex, d.copyWith(items: [for (final it in d.items) if (lib.byId(it.exerciseId) != null) it]));
    sessionDeload = deload;
    if (deload) await repo.kvSet('flags:${session!.id}', jsonEncode({'deload': true}));
    override = null;
    await repo.kvSet('override', '{}');
    notifyListeners();
    return session!;
  }

  /// [excuse]: a bad day; misses don't count and weights don't drop. [rating]: 1-5 stars.
  Future<void> finishWorkout({bool excuse = false, int? rating}) async {
    if (session == null) return;
    _blockDone = []; // a block that ended before this workout was already shown (review 4, P3-N11)
    restEnd = null;
    await notifier.cancel();
    final fk = 'flags:${session!.id}';
    final old = await repo.kvGet(fk);
    final flags = {...(old == null ? const <String, dynamic>{} : jsonDecode(old) as Map<String, dynamic>), if (excuse) 'excuse': true, if (rating != null) 'rating': rating};
    if (flags.isNotEmpty) await repo.kvSet(fk, jsonEncode(flags));
    final weekBefore = week;
    final sid = session!.id;
    final did = {for (final x in await repo.setsFor(sid)) if (x.counts) x.exerciseId};
    final keys = {for (final it in session!.day.items) ...{liftKey(it), tmKey(it), it.exerciseId}};
    final before = {for (final k in keys) k: await repo.lift(k)};
    final res = await repo.finishSession(session!.id, lib, unit, excuse: excuse, deload: flags['deload'] == true, program: plan?.id == session!.planId ? plan?.program : null);
    sessionDeload = false;
    pickedDay = null;
    await reload();
    // ladders: the plan moves on to the harder (or easier) exercise
    if (res.climbs.isNotEmpty && plan?.program != null) {
      var pl = plan!;
      for (final (from, to) in res.climbs) {
        pl = pl.copyWith(days: [
          for (final d in pl.days) d.copyWith(items: [for (final it in d.items) it.exerciseId == from && it.tier.isEmpty ? it.copyWith(exerciseId: to) : it])
        ]);
        final rules = {...pl.program!.rules};
        final r = rules.remove(from);
        if (r != null) rules[to] = r;
        pl = pl.copyWith(program: pl.program!.copyWith(rules: rules));
      }
      await repo.savePlan(pl);
      await reload();
    }
    // new block: accessories change (F205)
    if (plan != null && plan!.rotateWeeks > 0 && week > weekBefore && (week - 1) % plan!.rotateWeeks == 0 && profile != null) {
      await repo.savePlan(rotateAccessories(plan!, profile!, lib));
      await reload();
      res.notes.add('New block: accessory exercises changed (Plan → Variety)');
    }
    await _logAutoChanges(before, sid);
    if (ramp.keys.any(did.contains)) {
      final r = {...ramp};
      for (final k in did) {
        final v = r[k];
        if (v == null || v['from'] == sid) continue;
        final n = (v['n'] as int) - 1;
        n <= 0 ? r.remove(k) : r[k] = {...v, 'n': n};
      }
      ramp = r;
      await repo.kvSet('ramp', jsonEncode(ramp));
    }
    final newBadges = await _newBadges();
    if (newBadges.isNotEmpty && settings.badges && !settings.simple) {
      // one quiet line; more than two at once is a count, not a list (review 3, P2-1)
      res.notes.add(newBadges.length <= 2 ? 'New badge${newBadges.length == 1 ? '' : 's'}: ${newBadges.map((b) => b.name).join(', ')} (History → Reports)' : '${newBadges.length} new badges in History → Reports');
      if (settings.sound != 'off') sounds.play(Reward.exercise);
    }
    programNotes = [...res.notes, ..._blockDone];
    _blockDone = [];
    applyPrefs(); // reminders now name the next day
    if (autoBackup.when == 'workout') backupNow().ignore(); // after each workout (F339); a problem shows in the status line
    notifyListeners();
  }

  // ---------- programs (F210-F223) ----------
  void clearProgramNotes() {
    programNotes = [];
    notifyListeners();
  }

  /// Starts a program plan. [maxes]: training max per lift key (kg); null = set from the first workout.
  Future<void> startProgram(Plan pl, Map<String, double?> maxes) async {
    for (final e in maxes.entries) {
      if (e.value == null) continue;
      final old = await repo.lift(e.key);
      await repo.saveLift((old ?? LiftState(exerciseId: e.key, workKg: e.value! * 0.8)).copyWith(tm: e.value));
    }
    // stages start at the first one
    for (final e in (pl.program?.rules ?? const <String, LiftRule>{}).entries) {
      if (e.value.kind != 'stage') continue;
      final old = await repo.lift(e.key);
      if (old != null && old.stage != 0) await repo.saveLift(old.copyWith(stage: 0));
    }
    await usePlan(pl);
  }

  /// A best guess at a lift's training max from history: 90% of the best estimated max in 90 days.
  /// A training max guess from the last 90 days, on the program's [basis] (P1-5).
  Future<double?> guessMax(String key, {String basis = 'tm90'}) async {
    final id = key.split('#').first;
    final e = lib.byId(id);
    if (e == null) return null;
    final st = await repo.lift(key);
    if (st?.tm != null) return st!.tm;
    final since = DateTime.now().subtract(const Duration(days: 90));
    var best = 0.0;
    for (final x in await repo.setsOf(id)) {
      if (!x.counts || (x.at != null && x.at!.isBefore(since))) continue;
      final v = e1rm(x.kg, x.reps);
      if (v > best) best = v;
    }
    return best <= 0 ? null : roundToStep(maxOnBasis(best, basis), e.step, unit);
  }

  Future<void> setTm(String key, double? kg) async {
    final old = await repo.lift(key);
    if (kg == null) {
      if (old != null) await repo.saveLift(old.copyWith(clearTm: true));
    } else {
      await repo.saveLift((old ?? LiftState(exerciseId: key, workKg: kg * 0.8)).copyWith(tm: kg));
    }
    await reload();
  }

  Future<void> setStage(String key, int stage) async {
    final old = await repo.lift(key);
    await repo.saveLift((old ?? LiftState(exerciseId: key, workKg: 0)).copyWith(stage: stage));
    await reload();
  }

  /// Changes one lift's rule in the program (F221); null takes the rule away (back to double progression).
  Future<void> setRule(String key, LiftRule? r) async {
    final pl = plan;
    if (pl == null) return;
    final rules = {...pl.program?.rules ?? const <String, LiftRule>{}};
    r == null ? rules.remove(key) : rules[key] = r;
    await savePlanEdits(pl.copyWith(program: ProgramInfo(id: pl.program?.id ?? 'mine', rules: rules), userEdited: true));
  }

  /// "Time to graduate" (F223): a beginner program run for 12+ weeks, or main lifts reset twice.
  Future<String?> graduateHint() async {
    final pl = plan;
    final t = pl?.program == null ? null : templateById(pl!.program!.id);
    if (t == null || t.level != 0 || t.group != 'Beginner') return null;
    if (week >= 13) return 'You have run ${t.name} for ${week - 1} weeks. Time to look at an intermediate program (Plan → Programs).';
    var resets = 0;
    for (final k in pl!.program!.rules.keys) {
      final st = await repo.lift(k);
      if (st != null && st.misses >= 2) resets++;
    }
    return resets >= 2 ? 'Several lifts are stalling. A program with weekly progress may suit you now (Plan → Programs).' : null;
  }

  // ---------- several plans (F206-F208) ----------
  Future<List<Plan>> savedPlans() => repo.oldPlans();

  /// Copies the current plan (or [id]) as a saved plan, not active.
  Future<void> duplicatePlan({String? id, String? name}) async {
    final src = id == null || id == plan?.id ? plan : (await repo.oldPlans()).where((p) => p.id == id).firstOrNull;
    if (src == null) return;
    await repo.savePlan(src.duplicate(name ?? '${src.name} (copy)'), makeActive: false);
    notifyListeners();
  }

  Future<void> setPlanFolder(String id, String folder) async {
    if (plan?.id == id) {
      await repo.savePlan(plan!.copyWith(folder: folder), makeActive: false);
      await reload();
      return;
    }
    final p = (await repo.oldPlans()).where((p) => p.id == id).firstOrNull;
    if (p != null) await repo.savePlan(p.copyWith(folder: folder), makeActive: false);
    notifyListeners();
  }

  Future<void> setRotation(int weeks) async {
    if (plan == null) return;
    await repo.savePlan(plan!.copyWith(rotateWeeks: weeks), makeActive: false);
    await reload();
  }

  /// Adds a weak-point exercise after [lift] on every day that has it (F209). Returns the name, or null.
  Future<String?> addWeakPoint(String lift, String point) async {
    final pl = plan;
    final p = profile;
    if (pl == null || p == null) return null;
    final opts = weakPoints[lift]?[point] ?? const [];
    final id = opts.map((o) => resolveFor(o, p, lib)).whereType<String>().firstOrNull;
    if (id == null) return null;
    final e = lib.byId(id)!;
    var any = false;
    final days = [
      for (final d in pl.days)
        () {
          final at = d.items.indexWhere((it) => it.exerciseId == lift);
          if (at < 0 || d.items.any((it) => it.exerciseId == id)) return d;
          any = true;
          return d.copyWith(items: [...d.items]..insert(at + 1, itemFor(e, p.goal, main: false, experience: p.experience)));
        }()
    ];
    if (!any) return null;
    await savePlanEdits(pl.copyWith(days: days, userEdited: true));
    return e.name;
  }

  Future<void> throwAwayWorkout() async {
    if (session == null) return;
    restEnd = null;
    await notifier.cancel();
    await repo.discardSession(session!.id);
    await reload();
  }

  // ---------- AI ----------
  GuardedClient get client => GuardedClient(NetGuard(aiHost: settings.aiOn ? settings.ai.host : null));

  Future<bool> aiReady() async {
    if (!settings.aiOn) return false;
    if (settings.ai.isHandoff) return true;
    if (settings.ai.isOnDevice) return models.isReady(phoneModel) && engineAvailable();
    if (settings.ai.host == null || settings.ai.model.trim().isEmpty) return false;
    if (!settings.ai.needsKey) return true;
    return (await secrets.key(settings.ai.kind))?.isNotEmpty == true;
  }

  String get _where => settings.ai.isOnDevice ? 'this phone' : (settings.ai.host ?? 'your chat app');

  ModelInfo get phoneModel => modelById(settings.ai.isOnDevice ? settings.ai.model : modelCatalog.first.id);

  Future<AiRequest> aiPlanRequest(Profile pr) async {
    final recent = await repo.setsSince(DateTime.now().subtract(const Duration(days: 14)));
    if (settings.ai.isOnDevice) {
      // a small model does best improving a sound starting plan inside a strict grammar
      return AiRequest(_where, localSystemPrompt(lib, pr, wholePlan: true),
          buildRequest(pr, makePlan(pr, lib), recent, lib, 'Improve this starting plan for my goal, equipment and session length. Keep the day names.'), AiTask.plan,
          grammar: planGrammar(lib, pr));
    }
    final ask = 'Make me a ${pr.days}-day rotation${pr.split != null ? " using a ${splitLabel[pr.split]} split" : ""} for my goal, equipment and session length.';
    return AiRequest(_where, systemPrompt(lib, pr, wholePlan: true, plainText: settings.ai.isHandoff), buildRequest(pr, plan, recent, lib, ask), AiTask.plan, schema: planSchema(lib, pr));
  }

  /// [note]: how today is going, in the person's words (optional).
  Future<AiRequest> aiTodayRequest({String note = ''}) async {
    final recent = await repo.setsSince(DateTime.now().subtract(const Duration(days: 14)));
    final extra = note.trim().isEmpty ? '' : ' ${note.trim()}';
    if (settings.ai.isOnDevice) {
      return AiRequest(_where, localSystemPrompt(lib, profile!, wholePlan: false),
          buildRequest(profile!, today, recent, lib, "Adjust today's workout (${today!.name}) based on my recent training.$extra"), AiTask.today,
          grammar: dayGrammar(lib, profile!, today!.name));
    }
    return AiRequest(_where, systemPrompt(lib, profile!, wholePlan: false, plainText: settings.ai.isHandoff),
        buildRequest(profile!, today, recent, lib, 'Adjust today\'s workout (${today!.name}) based on my recent training. Keep it the same kind of day.$extra'), AiTask.today,
        schema: daySchema(lib, profile!));
  }

  /// "Today's guide": a short brief for the session ahead (plain text).
  Future<AiRequest> aiGuideRequest() async {
    final recent = await repo.setsSince(DateTime.now().subtract(const Duration(days: 14)));
    return AiRequest(_where, guidePrompt(), buildRequest(profile!, today, recent, lib, guideAsk(today!.name)), AiTask.guide);
  }

  /// A free question for the coach. Earlier questions and answers on screen go along so it can follow up.
  Future<AiRequest> aiAskRequest(String question, List<(String, String)> earlier) async {
    final recent = await repo.setsSince(DateTime.now().subtract(const Duration(days: 14)));
    final b = StringBuffer();
    for (final (q, a) in earlier.reversed.take(4).toList().reversed) {
      b.writeln('Earlier question: $q');
      b.writeln('Your earlier answer: $a\n');
    }
    b.write(question.trim());
    return AiRequest(_where, coachPrompt(), buildRequest(profile!, plan, recent, lib, b.toString()), AiTask.ask);
  }

  /// "Ask AI": a question or a request to change something. The AI may answer with app tools.
  Future<AiRequest> aiToolRequest(String question, List<(String, String)> earlier) async {
    final recent = await repo.setsSince(DateTime.now().subtract(const Duration(days: 14)));
    final b = StringBuffer();
    for (final (q, a) in earlier.reversed.take(4).toList().reversed) {
      b.writeln('Earlier question: $q');
      b.writeln('Your earlier answer: $a');
      b.writeln();
    }
    if (plan != null) {
      b.writeln('Days of the plan: ${[for (var i = 0; i < plan!.days.length; i++) '${i + 1} ${plan!.days[i].name}'].join(', ')}. Today is day ${(session?.dayIndex ?? todayIndex) + 1}${session != null ? ' (workout already started)' : ''}.');
      final pr = plan!.program;
      if (pr != null) {
        // the program's rules and training maxes, so the AI can talk about them and change them with the program tools
        final lines = <String>[];
        for (final e in pr.rules.entries) {
          final ex = lib.byId(e.key.split('#').first);
          final st = await repo.lift(e.key);
          lines.add('${e.key}: ${ex == null ? e.value.kind : e.value.describe(unit, ex.step)}${st?.tm == null ? '' : ', training max ${fmtWeight(st!.tm!, unit)} ${unitLabel(unit)}'}${e.value.kind == 'stage' ? ', stage ${(st?.stage ?? 0) + 1}' : ''}');
        }
        b.writeln('Program: ${templateById(pr.id)?.name ?? 'own rules'}${plan!.weeksPerCycle > 1 ? ', week ${programWeek.$1} of ${plan!.weeksPerCycle}, cycle ${programWeek.$2}' : ''}. Lift rules: ${lines.join('; ')}.');
      }
    }
    b.write(await bodyContext());
    b.write(question.trim());
    final phone = settings.ai.isOnDevice;
    final sys = [
      phone ? 'You are a strength coach inside a workout app. Answer briefly in plain words.' : coachPrompt(),
      phone ? toolHelpShort() : toolHelp(lib),
      'Exercise ids you may use, by muscle:',
      compactExerciseList(lib, profile!),
      '',
    ].join('\n');
    return AiRequest(_where, sys, buildRequest(profile!, today, recent, lib, b.toString()), AiTask.tools,
        grammar: phone ? toolGrammar(lib, profile!, plan?.days.length ?? 0, mustAct: looksLikeChange(question)) : null);
  }

  // ---------- volume, recovery, pain and sore joints (batch 15) ----------
  Set<Joint> soreToday = {}; // F236: sore today only (cleared tomorrow)
  Map<String, Map<String, dynamic>> ramp = {}; // F235: exercise -> {n: workouts left lighter, from: session id}
  List<Map<String, dynamic>> pains = []; // F235: {ex, joint?, at}
  String? restHintOff; // the day the rest suggestion was put away

  Future<void> _loadBodyNotes() async {
    final today = _day(DateTime.now());
    final so = await repo.kvGet('sore');
    soreToday = {};
    if (so != null && so.startsWith('{')) {
      final j = jsonDecode(so) as Map<String, dynamic>;
      if (j['date'] == today) soreToday = {for (final n in j['joints'] as List) ...Joint.values.where((x) => x.name == n)};
    }
    final r = await repo.kvGet('ramp');
    ramp = r == null ? {} : {for (final e in (jsonDecode(r) as Map<String, dynamic>).entries) e.key: (e.value as Map).cast<String, dynamic>()};
    final pa = await repo.kvGet('pain');
    pains = pa == null ? [] : [for (final x in jsonDecode(pa) as List) (x as Map).cast<String, dynamic>()];
    restHintOff = await repo.kvGet('rest_hint_off');
  }

  Future<void> setSore(Set<Joint> j) async {
    soreToday = {...j};
    await repo.kvSet('sore', jsonEncode({'date': _day(DateTime.now()), 'joints': [for (final x in j) x.name]}));
    notifyListeners();
  }

  /// "That hurt" (F235): noted with the joint, the joint counts as sore today, and the next two
  /// workouts of that exercise start 20% and then 10% lighter.
  Future<void> flagPain(String exId, Joint? joint) async {
    pains = [
      ...pains.where((x) => DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(x['at'] as int)).inDays < 180),
      {'ex': exId, if (joint != null) 'joint': joint.name, 'at': DateTime.now().millisecondsSinceEpoch},
    ];
    await repo.kvSet('pain', jsonEncode(pains));
    ramp = {...ramp, exId: {'n': 2, 'from': session?.id ?? ''}};
    await repo.kvSet('ramp', jsonEncode(ramp));
    if (joint != null && !soreToday.contains(joint)) {
      await setSore({...soreToday, joint});
    } else {
      notifyListeners();
    }
  }

  /// Back to the normal weights for an exercise after a pain flag.
  Future<void> clearRamp(String exId) async {
    ramp = {...ramp}..remove(exId);
    await repo.kvSet('ramp', jsonEncode(ramp));
    notifyListeners();
  }

  /// Today's exercises that are hard on a joint that is sore today.
  List<int> get soreItems {
    final d = today;
    if (d == null || soreToday.isEmpty) return const [];
    return [for (var i = 0; i < d.items.length; i++) if (lib.byId(d.items[i].exerciseId)?.joints.intersection(soreToday).isNotEmpty ?? false) i];
  }

  /// Swaps today's exercises that are hard on a sore joint for ones that are not (today only).
  /// Returns how many were swapped; the rest have nothing that fits.
  Future<int> swapSore() async {
    final pr = profile;
    if (pr == null) return 0;
    var n = 0;
    for (final i in soreItems) {
      final d = today!;
      final e = lib.byId(d.items[i].exerciseId)!;
      final ids = {for (final it in d.items) it.exerciseId};
      final alt = lib.swapsFor(e, pr.have, {...pr.avoid, ...soreToday}, items: pr.items).where((a) => !ids.contains(a.id)).firstOrNull;
      if (alt == null) continue;
      await swap(i, alt, forever: false);
      n++;
    }
    return n;
  }

  /// How rested each muscle is now (F232), from the last four days of sets.
  Future<Map<String, MuscleRecovery>> recoveryNow() async {
    final now = DateTime.now();
    return recovery(await repo.setsSince(now.subtract(const Duration(days: 4))), lib, now);
  }

  /// Today's recovery hints (F232, F234): a muscle trained too recently, a more rested day of the
  /// plan to do instead, or a day off.
  Future<RecoveryHint?> recoveryHint() async {
    final d = today, pl = plan;
    if (d == null || pl == null || session != null || restDay) return null;
    final now = DateTime.now();
    final recent = await repo.setsSince(now.subtract(const Duration(days: 10)));
    if (recent.isEmpty) return null;
    // sets done today never warn: you know you just trained (P2-2)
    final r = recovery([for (final x in recent) if (x.at == null || _day(x.at!) != _day(now)) x], lib, now);
    final ready = dayReadiness(d, r, lib);
    final low = leastRested(d, r, lib);
    String? warn;
    // Simple mode skips it (P2-1)
    if (!settings.simple && low != null && low.$2.pct < 60) {
      warn = '${muscleName(low.$1)} ${low.$1.endsWith('s') ? 'are' : 'is'} still recovering (${low.$2.pct}%, trained ${agoText(low.$2.last, now)}).';
    }
    int? better;
    if (!settings.simple && ready < 60 && (profile?.weekdays ?? const []).isEmpty && pl.weeksPerCycle <= 1 && pickedDay == null && override == null) {
      var best = ready;
      for (var j = 0; j < pl.days.length; j++) {
        if (j == todayIndex) continue;
        final x = dayReadiness(pl.days[j], r, lib);
        if (x > best) {
          best = x;
          better = j;
        }
      }
      if (best < ready + 25 || best < 70) better = null;
    }
    String? rest;
    // Simple mode: the day-off card at most once a week (P2-1)
    final seen = await repo.kvGet('rest_hint_seen');
    final weekAgo = seen != null && now.difference(DateTime.fromMillisecondsSinceEpoch(int.tryParse(seen) ?? 0)).inDays < 7 && _day(DateTime.fromMillisecondsSinceEpoch(int.tryParse(seen) ?? 0)) != _day(now);
    if (restHintOff != _day(now) && !(settings.simple && weekAgo)) {
      final streak = trainingStreak(recent.map((x) => x.at).whereType<DateTime>(), now);
      // a plan that trains 5-6 days running is not a reason to nag (P2-2): only past the plan's own days
      final perWeek = (profile?.weekdays ?? const []).isNotEmpty ? profile!.weekdays.length : (pl.weeksPerCycle > 1 ? pl.daysPerWeek : (profile?.days ?? pl.daysPerWeek));
      if (streak >= 4 && (streak > perWeek || streak >= 7)) {
        rest = 'You trained $streak days in a row. A day off now helps you come back stronger.';
      } else if (ready < 35 && better == null && !settings.simple) {
        rest = 'Most of what today trains is still tired ($ready% recovered). A day off or a light day may be better.';
      }
      if (rest != null && (seen == null || _day(DateTime.fromMillisecondsSinceEpoch(int.tryParse(seen) ?? 0)) != _day(now))) {
        await repo.kvSet('rest_hint_seen', '${now.millisecondsSinceEpoch}');
      }
    }
    if (warn == null && better == null && rest == null) return null;
    return RecoveryHint(warn: warn, betterDay: better, ready: ready, rest: rest);
  }

  Future<void> hideRestHint() async {
    restHintOff = _day(DateTime.now());
    await repo.kvSet('rest_hint_off', restHintOff!);
    notifyListeners();
  }

  /// Applies the weekly set targets to the current plan (F227). Returns the plan's sets changed.
  Future<int> fitPlanVolume() async {
    if (plan == null || profile == null) return 0;
    final n = fitVolume(plan!, profile!, lib);
    var changed = 0;
    for (var d = 0; d < n.days.length; d++) {
      for (var i = 0; i < n.days[d].items.length; i++) {
        changed += (n.days[d].items[i].sets - plan!.days[d].items[i].sets).abs();
      }
    }
    if (changed > 0) await savePlanEdits(n.copyWith(userEdited: true));
    return changed;
  }

  /// What the AI should know about volume, recovery and sore spots (plain lines, ends with a blank).
  Future<String> bodyContext() async {
    final b = StringBuffer();
    final now = DateTime.now();
    final week = weeklyMuscles(await repo.setsSince(now.subtract(const Duration(days: 8))), lib, now, 1).sets;
    final had = [for (final m in volumeMuscles) if ((week[m]?.first ?? 0) > 0) '$m ${volumeText(week[m]!.first, muscleTarget(m, profile))}'];
    if (had.isNotEmpty) b.writeln('Sets per muscle in the last 7 days (helpers count half, against the weekly range): ${had.join(', ')}.');
    final r = await recoveryNow();
    final tired = [for (final m in volumeMuscles) if (r[m]!.pct < 70) '$m ${r[m]!.pct}%'];
    if (tired.isNotEmpty) b.writeln('Still recovering: ${tired.join(', ')}.');
    if (soreToday.isNotEmpty) b.writeln('Sore today: ${soreToday.map((j) => jointLabel[j]!.toLowerCase()).join(', ')}.');
    final hurt = [
      for (final x in pains)
        if (now.difference(DateTime.fromMillisecondsSinceEpoch(x['at'] as int)).inDays <= 30)
          '${lib.byId(x['ex'] as String)?.name ?? x['ex']}${x['joint'] == null ? '' : ' (${jointLabel[Joint.values.where((j) => j.name == x['joint']).firstOrNull] ?? x['joint']})'}'
    ];
    if (hurt.isNotEmpty) b.writeln('Marked "that hurt" in the last 30 days: ${hurt.join(', ')}. Go easy there.');
    final rec = await recordsLine();
    if (rec.isNotEmpty) b.writeln(rec);
    b.writeln(await weekLine());
    final st = await strengthLine();
    if (st.isNotEmpty) b.writeln(st);
    final moved = [for (final c in autoChanges.take(6)) if (c['undone'] != true) autoChangeText(c)];
    if (moved.isNotEmpty) b.writeln('Weights the app moved lately: ${moved.join('; ')}.');
    final mine = [for (final x in blockSwaps.values) if (x['plan'] == plan?.id) x];
    if (mine.isNotEmpty) {
      b.writeln('Swapped for a block: ${mine.map((x) {
        final u = DateTime.fromMillisecondsSinceEpoch(x['until'] as int);
        return '${lib.byId(x['orig'] as String)?.name} -> ${lib.byId(x['var'] as String)?.name} until ${u.year}-${u.month}-${u.day}';
      }).join('; ')}.');
    }
    if (lib.caution.isNotEmpty) b.writeln('Some exercises are left out for health reasons: do not add crunches, sit-ups, jumps or Olympic lifts, and no all-out sets.');
    if (b.isNotEmpty) b.writeln();
    return b.toString();
  }

  // ---------- coaching (batch 16) ----------
  List<Map<String, dynamic>> autoChanges = []; // F242: newest first {at, key, from, to, why, undone?}
  /// F244 swaps for a block (review 2, P1-3): key "<planId>:<variation id>" ->
  /// {plan, orig, var, pos: [[day, item], ...], until: ms}. Ended by date, only on that plan.
  Map<String, Map<String, dynamic>> blockSwaps = {};
  List<String> _blockDone = []; // notes from swaps that ended at the last reload
  String? tipOff; // the day the tip was put away

  Future<void> _loadCoaching() async {
    final a = await repo.kvGet('auto_changes');
    autoChanges = a == null ? [] : [for (final x in jsonDecode(a) as List) (x as Map).cast<String, dynamic>()];
    final b = await repo.kvGet('block_swaps');
    blockSwaps = b == null ? {} : {for (final e in (jsonDecode(b) as Map<String, dynamic>).entries) e.key: (e.value as Map).cast<String, dynamic>()};
    tipOff = await repo.kvGet('tip_off');
  }

  /// Every lift the workout moved, with the reason, for the change log (F242).
  Future<void> _logAutoChanges(Map<String, LiftState?> before, String sessionId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final add = <Map<String, dynamic>>[];
    final done = await repo.setsFor(sessionId);
    for (final e in before.entries) {
      final b = await repo.lift(e.key);
      if (b == null) continue;
      // a lift's first workout: it moved from the weight just lifted
      final mine = [for (final x in done) if (x.key == e.key && x.counts) x.kg];
      final a = e.value ?? (mine.isEmpty ? null : LiftState(exerciseId: e.key, workKg: mine.reduce((x, y) => x > y ? x : y), workReps: b.workReps));
      final moved = a != null && ((a.workKg - b.workKg).abs() > 0.01 || (a.tm ?? 0) != (b.tm ?? 0) || a.stage != b.stage || a.workReps != b.workReps);
      if (!moved) continue;
      add.add({'at': now, 'key': e.key, 'from': a.toJson(), 'to': b.toJson(), if (b.why != null) 'why': b.why});
    }
    if (add.isEmpty) return;
    autoChanges = [...add, ...autoChanges].take(100).toList();
    await repo.kvSet('auto_changes', jsonEncode(autoChanges));
  }

  /// "Squat 100 → 90 kg: -10%: 2 workouts in a row short of 5 reps".
  String autoChangeText(Map<String, dynamic> c) {
    final a = LiftState.fromJson((c['from'] as Map).cast<String, dynamic>()), b = LiftState.fromJson((c['to'] as Map).cast<String, dynamic>());
    final name = lib.byId((c['key'] as String).split('#').first)?.name ?? c['key'];
    String w(double kg) => '${fmtWeight(kg, unit)} ${unitLabel(unit)}';
    final what = [
      if ((a.workKg - b.workKg).abs() > 0.01) '${w(a.workKg)} → ${w(b.workKg)}',
      if ((a.tm ?? 0) != (b.tm ?? 0)) 'training max ${a.tm == null ? '-' : w(a.tm!)} → ${b.tm == null ? '-' : w(b.tm!)}',
      if (a.stage != b.stage) 'stage ${a.stage + 1} → ${b.stage + 1}',
      if (a.workReps != b.workReps) 'reps ${a.workReps ?? '-'} → ${b.workReps ?? '-'}',
    ].join(', ');
    return '$name: $what${c['why'] == null ? '' : '. ${c['why']}'}';
  }

  /// Puts a lift back to how it was before change [i], if nothing moved it since. False otherwise.
  Future<bool> undoAutoChange(int i) async {
    if (i < 0 || i >= autoChanges.length || autoChanges[i]['undone'] == true) return false;
    final c = autoChanges[i];
    final cur = await repo.lift(c['key'] as String);
    final to = LiftState.fromJson((c['to'] as Map).cast<String, dynamic>());
    if (cur == null || (cur.workKg - to.workKg).abs() > 0.01 || cur.tm != to.tm || cur.stage != to.stage) return false;
    await repo.saveLift(LiftState.fromJson((c['from'] as Map).cast<String, dynamic>()).copyWith(why: 'Put back by hand (Plan → Changes)'));
    autoChanges = [...autoChanges]..[i] = {...c, 'undone': true};
    await repo.kvSet('auto_changes', jsonEncode(autoChanges));
    if (programLifts.containsKey(c['key'])) programLifts[c['key'] as String] = (await repo.lift(c['key'] as String))!;
    notifyListeners();
    return true;
  }

  /// Lifts in the plan with no new best in 4+ weeks (F243).
  Future<List<(Exercise, Stall)>> stalls() async {
    final now = DateTime.now();
    final out = <(Exercise, Stall)>[];
    final ids = {for (final d in plan?.days ?? const <PlanDay>[]) for (final it in d.items) it.exerciseId};
    for (final id in ids) {
      final e = lib.byId(id);
      if (e == null || e.timed) continue;
      final st = stallOf(await repo.setsOf(id), e.bodyweight, now);
      if (st != null) out.add((e, st));
    }
    return out;
  }

  Future<Stall?> stallFor(Exercise e) async => stallOf(await repo.setsOf(e.id), e.bodyweight, DateTime.now());

  /// The closest variation for a stuck lift, ranked (F244/F245).
  Exercise? variationFor(Exercise e) {
    final pr = profile;
    if (pr == null) return null;
    final used = {for (final d in plan?.days ?? const <PlanDay>[]) for (final it in d.items) it.exerciseId};
    final c = rankSwaps(e, lib.swapsFor(e, pr.have, pr.avoid, items: pr.items).where((x) => !used.contains(x.id)), avoid: {...pr.avoid, ...soreToday}, favs: lib.favs);
    return c.isEmpty ? null : c.first.$1;
  }

  /// A stuck lift is swapped for a variation for [weeks] weeks, then comes back (F244).
  /// The places in the current plan a block swap may change: plain items of that lift. A
  /// program's % sets keep their own lift (its training max and rule belong to it).
  List<List<int>> blockSwapPlaces(String id) {
    final pl = plan;
    if (pl == null) return const [];
    return [
      for (var d = 0; d < pl.days.length; d++)
        for (var i = 0; i < pl.days[d].items.length; i++)
          if (pl.days[d].items[i].exerciseId == id && pl.days[d].items[i].tier.isEmpty && !(pl.days[d].items[i].perSet?.any((x) => x.pct != null) ?? false)) [d, i]
    ];
  }

  /// A swap for a block of this lift in the current plan, if any.
  Map<String, dynamic>? blockSwapOf(String origId) => blockSwaps.values.where((x) => x['plan'] == plan?.id && x['orig'] == origId).firstOrNull;

  Future<Exercise?> swapForBlock(String id, {int weeks = 4}) async {
    final e = lib.byId(id), pl = plan;
    if (e == null || pl == null) return null;
    final pos = blockSwapPlaces(id);
    if (pos.isEmpty) return null; // only program % sets: nothing to swap
    final v = variationFor(e);
    if (v == null) return null;
    final days = [for (final d in pl.days) [...d.items]];
    for (final p in pos) {
      days[p[0]][p[1]] = days[p[0]][p[1]].copyWith(exerciseId: v.id);
    }
    await savePlanEdits(pl.copyWith(days: [for (var d = 0; d < pl.days.length; d++) pl.days[d].copyWith(items: days[d])]));
    blockSwaps = {
      ...blockSwaps,
      '${pl.id}:${v.id}': {'plan': pl.id, 'orig': id, 'var': v.id, 'pos': pos, 'until': DateTime.now().add(Duration(days: 7 * weeks)).millisecondsSinceEpoch},
    };
    await repo.kvSet('block_swaps', jsonEncode(blockSwaps));
    notifyListeners();
    return v;
  }

  /// Swaps of the plan in use whose time is up go back, at their own places only. Swaps of other
  /// plans wait until that plan is in use again.
  Future<void> _endBlockSwaps() async {
    final pl0 = plan;
    if (pl0 == null) return;
    // swaps saved before P1-3 had no plan. Never rewrite from them (review 4, P1-2): even one plan
    // with the variation may have it on purpose. The entry is dropped with a plain note.
    if (blockSwaps.values.any((x) => x['plan'] == null)) {
      final plans = [pl0, ...await repo.oldPlans()];
      final kept = <String, Map<String, dynamic>>{};
      for (final e in blockSwaps.entries) {
        if (e.value['plan'] != null) {
          kept[e.key] = e.value;
          continue;
        }
        final v = e.key, orig = e.value['orig'] as String;
        bool has(Plan p, String id) => p.days.any((d) => d.items.any((it) => it.exerciseId == id && it.tier.isEmpty));
        final match = [for (final p in plans) if (has(p, v) && !has(p, orig)) p];
        if (match.length == 1) {
          programNotes = [
            ...programNotes,
            'An earlier 4-week swap (${lib.byId(orig)?.name ?? orig} → ${lib.byId(v)?.name ?? v}) may still be in your plan "${match.single.name}". Change it back there if you want.',
          ];
        } else {
          programNotes = [
            ...programNotes,
            'An earlier 4-week swap (${lib.byId(orig)?.name ?? orig} → ${lib.byId(v)?.name ?? v}) could not be matched to a plan; change it back in Plan if you want.',
          ];
        }
      }
      blockSwaps = kept;
      await repo.kvSet('block_swaps', jsonEncode(blockSwaps));
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = [for (final e in blockSwaps.entries) if (e.value['plan'] == pl0.id && now >= (e.value['until'] as int)) e];
    if (due.isEmpty) return;
    final days = [for (final d in pl0.days) [...d.items]];
    for (final e in due) {
      final orig = e.value['orig'] as String, v = e.value['var'] as String;
      for (final p in (e.value['pos'] as List).cast<List>()) {
        final d = p[0] as int, i = p[1] as int;
        if (d < days.length && i < days[d].length && days[d][i].exerciseId == v) days[d][i] = days[d][i].copyWith(exerciseId: orig);
      }
      _blockDone.add('Block done: back to ${lib.byId(orig)?.name ?? orig} after ${lib.byId(v)?.name ?? v}');
    }
    blockSwaps = {...blockSwaps}..removeWhere((k, _) => due.any((d) => d.key == k));
    await repo.kvSet('block_swaps', jsonEncode(blockSwaps));
    plan = pl0.copyWith(days: [for (var d = 0; d < pl0.days.length; d++) pl0.days[d].copyWith(items: days[d])]);
    await repo.savePlan(plan!);
    programNotes = [...programNotes, ..._blockDone];
  }

  /// What the workout going will do to each lift when finished (F247), without saving anything.
  /// Each line says if the lift goes up (1), stays (0) or comes down (-1). In a deload nothing
  /// moves, so it is one line (review 2, P2-5).
  Future<List<NextLine>> previewNext() async {
    final ses = session;
    if (ses == null) return const [];
    if (sessionDeload) return const [NextLine('Deload week: weights stay where they are.', 0)];
    final done = await repo.setsFor(ses.id);
    final out = <NextLine>[];
    for (final it in ses.day.items) {
      final e = lib.byId(it.exerciseId);
      final sets = [for (final x in done) if (x.key == liftKey(it) && x.counts) x];
      if (e == null || sets.isEmpty || ruleFor(plan?.program, it) != null) continue;
      final prev = await repo.lift(liftKey(it)) ?? LiftState(exerciseId: liftKey(it), workKg: sets.map((x) => x.kg).reduce((a, b) => a > b ? a : b), workReps: e.bodyweight ? it.repLow : null);
      final nx = nextLift(prev, e, sets, unit, repLow: it.repLow, repHigh: it.repHigh);
      final ch = nx.workKg > prev.workKg + 0.01 || (nx.workReps ?? 0) > (prev.workReps ?? 0) ? 1 : (nx.workKg < prev.workKg - 0.01 ? -1 : 0);
      if (nx.why != null) out.add(NextLine('${e.name}: ${nx.why}', ch));
    }
    return out;
  }

  /// One change for next week (F248), worked out without the AI: a stuck lift, a muscle far from
  /// its range, or fewer workouts than planned. Null when all is on track.
  /// [shown]: the lift whose Stuck card is on screen (that advice is not said twice, P3-N3).
  Future<String?> weeklySuggestion({String? shown}) async {
    if (plan == null) return null;
    final st = [for (final x in await stalls()) if (x.$1.id != shown) x];
    if (st.isNotEmpty) {
      final (e, s) = st.first;
      return '${e.name} has had no new best in ${s.weeks} weeks. Swap it for a variation for 4 weeks (Progress → ${e.name}).';
    }
    final now = DateTime.now();
    final log = await repo.setsSince(now.subtract(const Duration(days: 8)));
    final days = {for (final x in log) if (x.at != null) DateTime(x.at!.year, x.at!.month, x.at!.day)}.length;
    final want = profile?.weekdays.isNotEmpty ?? false ? profile!.weekdays.length : (profile?.days ?? plan!.daysPerWeek);
    final older = (await repo.setsSince(now.subtract(const Duration(days: 30)))).any((x) => x.at != null && now.difference(x.at!).inDays > 8);
    if (older && days > 0 && days < want - 1) return 'You trained $days of $want days in the last 8 days. A ${days + 1}-day plan may fit your week better (Plan → Make my plan).';
    final w = weeklyMuscles(log, lib, now, 1).sets;
    for (final m in priorityMuscles) {
      final v = w[m]?.first ?? 0;
      final t = muscleTarget(m, profile);
      if (days >= 2 && v + 2 < t.lo) return '${muscleName(m)} got ${fmtSets(v)} sets against a range of ${t.lo}-${t.hi}. Add an exercise or a set or two for it.';
      if (v > t.mrv) return '${muscleName(m)} got ${fmtSets(v)} sets, more than most people recover from (${t.mrv}). Take a few sets off.';
    }
    return null;
  }

  /// Sets that broke a record when they were done (History medals, F269).
  Future<Set<String>> medalsFor(Iterable<String> exerciseIds) async {
    final out = <String>{};
    for (final id in exerciseIds) {
      final e = lib.byId(id);
      if (e != null) out.addAll(medalSets(recordHistory(await repo.setsOf(id), e)));
    }
    return out;
  }

  /// The top records of the most-done lifts, for the AI (one line).
  Future<String> recordsLine() async {
    final parts = <String>[];
    for (final id in (await repo.loggedExercises()).take(6)) {
      final e = lib.byId(id);
      if (e == null) continue;
      final cur = currentRecords(recordHistory(await repo.setsOf(id), e));
      final k = recordKinds(e, const []).first;
      final r = cur[k];
      if (r != null) parts.add('${e.name} ${recordLabel[k]!.toLowerCase()} ${recordText(r, unit, bodyweight: e.bodyweight)} (${r.at.year}-${r.at.month}-${r.at.day})');
    }
    return parts.isEmpty ? '' : 'Records: ${parts.join('; ')}.';
  }

  // ---------- reports, streaks, goals, badges (batch 18) ----------

  /// Workouts a week the plan asks for (the weekly goal ring and the week streak, F292/F293).
  /// Weekdays set, else a program's own days a week, else the setup's days (review 3, P2-8).
  int get perWeekGoal {
    if ((profile?.weekdays ?? const []).isNotEmpty) return profile!.weekdays.length;
    final pl = plan;
    if (pl != null && pl.program != null) return pl.weeksPerCycle > 1 ? pl.daysPerWeek : (templateById(pl.program!.id)?.days ?? pl.daysPerWeek);
    return profile?.days ?? 3;
  }

  /// Every finished workout, oldest first, with its length and planned sets.
  Future<List<Workout>> workouts() async => [
        for (final h in (await repo.history(limit: 100000)).reversed)
          Workout(h.id, h.started, h.finished == null ? 0 : h.finished!.difference(h.started).inMinutes, plannedSets: h.day.items.fold(0, (a, it) => a + it.sets))
      ];

  Future<List<SetLog>> allSets() => repo.setsSince(DateTime(2000));

  Future<List<(DateTime, double)>> bodySeries() async => [for (final b in await repo.bodyLog()) if (b.$3 != null) (b.$2, b.$3!)];

  // personal goals (F294-F296), kv 'aims'
  List<Aim> aims = [];

  Future<void> _loadAims() async {
    final a = await repo.kvGet('aims');
    aims = a == null ? [] : [for (final x in jsonDecode(a) as List) Aim.fromJson((x as Map).cast<String, dynamic>())];
  }

  Future<void> addAim(String kind, double target, {String exercise = '', DateTime? by}) async {
    final start = (await aimSeries(Aim(id: '', kind: kind, exercise: exercise, target: target, start: 0, created: DateTime.now()))).lastOrNull?.v ?? 0;
    aims = [...aims, Aim(id: '${DateTime.now().microsecondsSinceEpoch}', kind: kind, exercise: exercise, target: target, start: start, created: DateTime.now(), by: by)];
    await repo.kvSet('aims', jsonEncode([for (final a in aims) a.toJson()]));
    notifyListeners();
  }

  /// Removes a goal; returns it and its place, so Undo can put it back (review 3, P3-N14).
  Future<(int, Aim)?> removeAim(String id) async {
    final i = aims.indexWhere((a) => a.id == id);
    if (i < 0) return null;
    final gone = aims[i];
    aims = [for (final a in aims) if (a.id != id) a];
    await repo.kvSet('aims', jsonEncode([for (final a in aims) a.toJson()]));
    notifyListeners();
    return (i, gone);
  }

  /// Undo of [removeAim]: the goal back at its place, as it was (start and dates kept).
  Future<void> restoreAim(int i, Aim a) async {
    aims = [...aims]..insert(i.clamp(0, aims.length), a);
    await repo.kvSet('aims', jsonEncode([for (final x in aims) x.toJson()]));
    notifyListeners();
  }

  /// A goal's value over time: e1RM per workout, body weight, best reps, or this month's volume.
  Future<List<Pt>> aimSeries(Aim a) async {
    switch (a.kind) {
      case 'lift':
        return seriesOf(await repo.setsOf(a.exercise), ChartKind.e1rm);
      case 'reps':
        return seriesOf(await repo.setsOf(a.exercise), ChartKind.e1rm, bodyweight: true);
      case 'body':
        final b = await bodySeries()
          ..sort((x, y) => x.$1.compareTo(y.$1));
        return [for (final x in b) Pt(x.$1, x.$2, '')];
      case 'volume':
        final now = DateTime.now();
        final from = DateTime(now.year, now.month);
        final v = (await repo.setsSince(from)).where((x) => x.counts).fold<double>(0, (s, x) => s + x.kg * x.reps);
        return [Pt(now, v / 1000, '')];
    }
    return const [];
  }

  /// Badges not seen before; marks them seen (F297).
  Future<List<Award>> _newBadges() async {
    final all = badgesEarned(await workouts(), await allSets(), lib, perWeek: perWeekGoal);
    final seenRaw = await repo.kvGet('badges_seen');
    final seen = seenRaw == null ? <String>{} : {for (final x in jsonDecode(seenRaw) as List) x as String};
    // the first look with older history: what was earned before counts as seen, silently
    if (seenRaw == null && (await workouts()).length > 1) {
      await repo.kvSet('badges_seen', jsonEncode([for (final b in all) b.id]));
      return const [];
    }
    final fresh = [for (final b in all) if (!seen.contains(b.id)) b];
    if (fresh.isNotEmpty) await repo.kvSet('badges_seen', jsonEncode([...seen, ...fresh.map((b) => b.id)]));
    return fresh;
  }

  /// This week for the AI (one line): workouts, sets and volume against last week.
  Future<String> weekLine() async {
    final (a, b, _) = weekReports(DateTime.now(), await workouts(), await allSets(), lib);
    return 'This week: ${a.workouts} of $perWeekGoal workouts, ${a.sets} sets (last week ${b.workouts} workouts, ${b.sets} sets); week streak ${weekStreak(await workouts(), DateTime.now(), perWeek: perWeekGoal)}.'
        '${aims.isEmpty ? '' : ' Goals: ${(await Future.wait([for (final g in aims) _aimWords(g)])).join('; ')}.'}';
  }

  /// A goal for the AI: what, with its unit, how far along, and by when (review 3, P3-N17).
  Future<String> _aimWords(Aim g) async {
    final st = aimState(g, await aimSeries(g), DateTime.now());
    final what = switch (g.kind) {
      'reps' => '${lib.byId(g.exercise)?.name ?? g.exercise} ${fmtNum(g.target)} reps',
      'volume' => '${fmtNum(g.target)} t lifted a month',
      'body' => 'body weight ${fmtWeight(g.target, unit)} ${unitLabel(unit)}',
      _ => '${lib.byId(g.exercise)?.name ?? g.exercise} ${fmtWeight(g.target, unit)} ${unitLabel(unit)} est. 1-rep max',
    };
    final by = g.by == null ? '' : ', by ${g.by!.year}-${g.by!.month.toString().padLeft(2, '0')}-${g.by!.day.toString().padLeft(2, '0')}';
    return '$what (${st.reached ? 'reached' : '${(st.done * 100).round()}% there'}$by)';
  }

  /// What the Export screen opens on, when the AI picked it (batch 20). Only a choice on screen:
  /// the AI can never save or send a file.
  ExportKind? exportPreset;

  // ---------- body and strength scores (batch 19) ----------
  List<Tape> tape = []; // F301, kv 'tape'
  List<Map<String, dynamic>> photos = []; // F302, kv 'photos': {id, at}; files in the app's own folder

  Future<void> _loadBody19() async {
    final t0 = await repo.kvGet('tape');
    tape = t0 == null ? [] : [for (final x in jsonDecode(t0) as List) Tape.fromJson((x as Map).cast<String, dynamic>())];
    final ph = await repo.kvGet('photos');
    photos = ph == null ? [] : [for (final x in jsonDecode(ph) as List) (x as Map).cast<String, dynamic>()];
    _sweepPhotos();
  }

  /// Photo files no list entry points at are deleted (review 4, P1-1: older restores left them).
  void _sweepPhotos() {
    try {
      final d = Directory(photoDir);
      if (!d.existsSync()) return;
      final listed = {for (final x in photos) '${x['id']}.img'};
      for (final f in d.listSync().whereType<File>()) {
        if (!listed.contains(p.basename(f.path))) f.deleteSync();
      }
    } catch (_) {}
  }

  /// The picker's own copies of picked files (review 4, P2-2). Tests swap it out.
  static Future<void> Function() clearPicked = FilePicker.clearTemporaryFiles;

  Future<void> _clearPicked() async {
    try {
      await clearPicked();
    } catch (_) {}
  }

  Future<void> addTape(String part, double cm, {String side = ''}) async {
    tape = [...tape, Tape(DateTime.now(), part, side, cm)];
    await repo.kvSet('tape', jsonEncode([for (final x in tape) x.toJson()]));
    notifyListeners();
  }

  /// Puts a removed measurement back at its place (Undo, review 4 P2-8).
  Future<void> insertTape(int i, Tape t) async {
    tape = [...tape]..insert(i.clamp(0, tape.length), t);
    await repo.kvSet('tape', jsonEncode([for (final x in tape) x.toJson()]));
    notifyListeners();
  }

  Future<void> removeTape(int i) async {
    tape = [...tape]..removeAt(i);
    await repo.kvSet('tape', jsonEncode([for (final x in tape) x.toJson()]));
    notifyListeners();
  }

  /// Progress photos live only in the app's own folder: never the gallery, never the AI (F302).
  String get photoDir => p.join(packs.dir, 'photos');

  String photoPath(Map<String, dynamic> ph) => p.join(photoDir, '${ph['id']}.img');

  Future<void> addPhoto(List<int> bytes, {DateTime? at}) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    await Directory(photoDir).create(recursive: true);
    final f = File(p.join(photoDir, '$id.img'));
    await f.writeAsBytes(bytes, flush: true);
    photos = [...photos, {'id': id, 'at': (at ?? DateTime.now()).millisecondsSinceEpoch}];
    await repo.kvSet('photos', jsonEncode(photos));
    await _clearPicked();
    notifyListeners();
  }

  Future<void> removePhoto(String id) async {
    final ph = photos.where((x) => x['id'] == id).firstOrNull;
    if (ph == null) return;
    try {
      await File(photoPath(ph)).delete();
    } catch (_) {}
    photos = [for (final x in photos) if (x['id'] != id) x];
    await repo.kvSet('photos', jsonEncode(photos));
    await _clearPicked();
    notifyListeners();
  }

  /// The body weight now: the newest weigh-in, else the setup answer.
  double? get bodyKgNow => latestBodyKg ?? profile?.bodyKg;
  bool get female => profile?.sex == 'f';

  /// Best est. 1-rep max per main lift in the last 90 days (current strength, F305-F309).
  Future<Map<String, double>> mainMaxes() async => (await mainLifts()).$1;

  /// The 90-day best est. 1-rep max per main lift, and how many workouts it is from (P2-7).
  Future<(Map<String, double>, Map<String, int>)> mainLifts() async {
    final since = DateTime.now().subtract(const Duration(days: 90));
    final out = <String, double>{};
    final n = <String, int>{};
    for (final id in levelLifts) {
      final s = [for (final x in await repo.setsOf(id)) if (x.at != null && x.at!.isAfter(since)) x];
      final pts = seriesOf(s, ChartKind.e1rm);
      if (pts.isNotEmpty) out[id] = pts.map((x) => x.v).reduce((a, b) => a > b ? a : b);
      n[id] = {for (final x in s) if (x.counts) x.sessionId}.length;
    }
    return (out, n);
  }

  /// "deadlift low next to back squat (ratio 0.85, usual 1.2)" for the AI (P2-7).
  String ratioWords((String, String, double, double) x) =>
      '${(lib.byId(x.$1)?.name ?? x.$1).toLowerCase()} low next to ${(lib.byId(x.$2)?.name ?? x.$2).toLowerCase()} (ratio ${x.$3.toStringAsFixed(2)}, usual ${x.$4.toStringAsFixed(2)})';

  /// One line for the AI: the strength score, levels and a lagging lift.
  Future<String> strengthLine() async {
    final bw = bodyKgNow;
    if (bw == null) return '';
    final (m, nw) = await mainLifts();
    if (m.isEmpty) return '';
    final lv = [
      for (final e in m.entries)
        () {
          final (l, _, _) = strengthLevelOf(e.key, e.value, bw, female: female);
          return '${lib.byId(e.key)?.name} ${l < 0 ? 'below beginner' : levelNames5[l].toLowerCase()}';
        }()
    ];
    final lag = laggingLifts(m, workouts: nw);
    return 'Strength score ${strengthScore(m, bw, female: female)}/100 (${lv.join(', ')})${lag.isEmpty ? '' : '; ${ratioWords(lag.first)}'}.';
  }

  // ---------- Progress dashboard (F264) ----------
  List<String> dash = const ['week_workouts', 'week_volume', 'records_month'];

  Future<void> _loadDash() async {
    final d = await repo.kvGet('dash');
    if (d != null) dash = [for (final x in jsonDecode(d) as List) if (dashTiles.containsKey(x)) x as String];
  }

  Future<void> setDash(List<String> tiles) async {
    dash = [for (final x in tiles) if (dashTiles.containsKey(x)) x];
    await repo.kvSet('dash', jsonEncode(dash));
    notifyListeners();
  }

  Future<void> hideTip() async {
    tipOff = _day(DateTime.now());
    await repo.kvSet('tip_off', tipOff!);
    notifyListeners();
  }

  // ---------- gyms ----------
  List<Gym> gyms = [];
  String? gymId;
  Set<String> takenToday = {};

  Gym? get activeGym => gyms.where((g) => g.id == gymId).firstOrNull;

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  Future<void> _loadGyms() async {
    final g = await repo.kvGet('gyms');
    gyms = g == null ? [] : [for (final x in jsonDecode(g) as List) Gym.fromJson(x as Map<String, dynamic>)];
    gymId = await repo.kvGet('gym_active');
    if (activeGym == null) gymId = null;
    final t = await repo.kvGet('taken');
    takenToday = {};
    if (t != null) {
      final j = jsonDecode(t) as Map<String, dynamic>;
      if (j['date'] == _day(DateTime.now())) takenToday = {for (final i in j['items'] as List) i as String};
    }
  }

  /// The setup answers with the active gym's real equipment (minus anything taken today).
  Profile? _withGym(Profile? pr) {
    lib.caution = cautionIds(pr?.pregnancy, lib);
    if (pr == null) return null;
    final g = activeGym;
    if (g == null) return pr.copyWith(clearItems: true);
    final items = g.items.difference(takenToday);
    return pr.copyWith(have: kindsOf(items), items: items);
  }

  Future<void> _saveGyms() async {
    await repo.kvSet('gyms', jsonEncode([for (final g in gyms) g.toJson()]));
    await repo.kvSet('gym_active', gymId ?? '');
    profile = _withGym(profile);
    if (profile != null) await repo.saveProfile(profile!);
    notifyListeners();
  }

  /// Adds or updates [g]. The first gym (or [use]) becomes the one you are at.
  Future<void> saveGym(Gym g, {bool use = false}) async {
    final i = gyms.indexWhere((x) => x.id == g.id);
    if (i >= 0) {
      gyms[i] = g;
    } else {
      gyms.add(g);
    }
    if (use || gymId == null) gymId = g.id;
    await _saveGyms();
  }

  /// Switch gyms (null = none: the setup's equipment kinds decide again).
  Future<void> useGym(String? id) async {
    gymId = id;
    await _saveGyms();
  }

  Future<void> deleteGym(String id) async {
    gyms.removeWhere((g) => g.id == id);
    if (gymId == id) gymId = gyms.isEmpty ? null : gyms.first.id;
    await _saveGyms();
  }

  /// Bar, Smith bar and plates for plate maths: the gym's, or the standard set for the unit.
  ({double bar, double smith, List<double> plates}) get plateSetup {
    final g = activeGym;
    final u = unit;
    final std = u == Unit.lb ? defaultPlatesLb : defaultPlatesKg;
    List<double> pl = std;
    if (g?.plates != null && g!.plates!.isNotEmpty) {
      final from = g.platesUnit == 'kg' ? Unit.kg : Unit.lb;
      pl = [for (final x in g.plates!) toUnit(fromUnit(x, from), u)];
    }
    return (bar: g?.barKg ?? defaultBarKg(u), smith: g?.smithKg ?? 0, plates: pl);
  }

  bool get warmupsOn => settings.warmups;

  /// "Taken today": that item is left out until tomorrow.
  Future<void> setTaken(String item, bool taken) async {
    taken ? takenToday.add(item) : takenToday.remove(item);
    await repo.kvSet('taken', jsonEncode({'date': _day(DateTime.now()), 'items': takenToday.toList()}));
    profile = _withGym(profile);
    notifyListeners();
  }

  // ---------- AI changes (undo) ----------
  List<AiChange> aiChanges = [];

  Future<void> _loadChanges() async => aiChanges = decodeChanges(await repo.kvGet('ai_changes'));

  /// Runs checked tool actions. Everything they touch is saved first, so it can be put back.
  Future<List<String>> runActions(String asked, List<AppAction> acts) async {
    if (acts.isEmpty) return const [];
    final before = await snapshot(repo.db);
    final did = <String>[];
    for (final a in acts) {
      await a.run(this);
      did.add(a.says);
    }
    await _loadChanges();
    aiChanges = [AiChange(DateTime.now(), asked, did, before, partial: acts.any((a) => !a.undoable)), ...aiChanges].take(30).toList();
    await repo.kvSet('ai_changes', encodeChanges(aiChanges));
    notifyListeners();
    return did;
  }

  /// Puts the app back to how it was before change [i] (and so also undoes every later change).
  Future<void> undoChange(int i) async {
    await _loadChanges();
    if (i < 0 || i >= aiChanges.length || aiChanges[i].undone) return;
    await restoreSnapshot(repo.db, aiChanges[i].before);
    aiChanges = [
      for (var k = 0; k < aiChanges.length; k++)
        k <= i ? AiChange(aiChanges[k].at, aiChanges[k].asked, aiChanges[k].did, aiChanges[k].before, undone: true, partial: aiChanges[k].partial) : aiChanges[k]
    ];
    await repo.kvSet('ai_changes', encodeChanges(aiChanges));
    await reload();
    applyPrefs();
  }

  Future<String> aiSend(AiRequest r, {int seed = 0}) async {
    if (settings.ai.isOnDevice) return _onPhone(r, seed);
    final key = await secrets.key(settings.ai.kind) ?? '';
    final c = client;
    try {
      return await providerFor(settings.ai, key, c).complete(r.system, r.user, schema: r.schema);
    } finally {
      c.close();
    }
  }

  Future<String> _onPhone(AiRequest r, int seed) async {
    final m = phoneModel;
    if (!models.isReady(m)) throw AiError('Download the model first (Settings → Ask AI).');
    final res = await runLocal(
      modelPath: models.pathOf(m),
      system: r.system,
      user: r.user,
      grammar: r.grammar,
      maxTokens: switch (r.task) { AiTask.plan => 900, AiTask.today => 400, AiTask.ask => 800, AiTask.guide => 400, AiTask.tools => 700 },
      temperature: (r.task == AiTask.ask || r.task == AiTask.guide) ? 0.7 : (r.task == AiTask.tools ? 0.5 : 0.4),
      seed: 42 + seed,
    );
    return switch (res.status) {
      0 || 4 => res.text,
      1 => throw AiError('That request is too long for the on-phone model.'),
      9 => throw AiError(res.error.isEmpty ? 'The on-phone model could not start.' : 'The on-phone model could not start: ${res.error}.'),
      _ => throw AiError('The on-phone model stopped with an error (${res.status}). Try again.'),
    };
  }

  /// Sends and checks. Returns null on success, else the reasons in plain words.
  Future<List<String>?> aiApply(AiRequest r) async {
    final String text;
    try {
      text = await aiSend(r);
    } on AiError catch (e) {
      return [e.message];
    } catch (e) {
      return ['Something went wrong talking to the AI: $e'];
    }
    final first = await aiApplyText(r, text);
    if (first == null || !settings.ai.isOnDevice) return first;
    // a small model sometimes repeats an exercise: one more go with a different seed
    try {
      return await aiApplyText(r, await aiSend(r, seed: 1));
    } on AiError catch (e) {
      return [e.message];
    }
  }

  /// Checks an answer (from a service, or pasted back from a chat app) and uses it if it is good.
  /// Returns null on success, else the reasons in plain words; nothing changes then.
  Future<List<String>?> aiApplyText(AiRequest r, String text) async {
    if (r.wholePlan) {
      final res = parsePlan(text, lib, profile: profile);
      if (res.plan == null) return res.errors;
      await usePlan(res.plan!);
    } else {
      final res = parseDay(text, lib, profile: profile);
      if (res.day == null) return res.errors;
      await setToday(res.day!);
    }
    return null;
  }

  // ---------- on-phone model ----------
  Future<void> downloadModel() async {
    if (modelProgress != null) return;
    final m = phoneModel;
    _stopDownload = false;
    modelProgress = models.have(m) / m.bytes;
    modelNote = null;
    notifyListeners();
    final c = GuardedClient(const NetGuard(models: true));
    var last = 0;
    try {
      await models.download(m, c, stop: () => _stopDownload, onProgress: (p) {
        modelProgress = p;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - last > 250) {
          last = now;
          notifyListeners();
        }
      });
      modelNote = 'Ready. ${m.label} is on this phone.';
    } on ModelError catch (e) {
      modelNote = e.message;
    } finally {
      c.close();
      modelProgress = null;
      notifyListeners();
    }
  }

  void stopModelDownload() => _stopDownload = true;

  bool modelImporting = false;

  /// "My own model file": the person picks a .gguf (e.g. from Downloads); it is copied into the app.
  Future<void> importModel() async {
    if (modelImporting || modelProgress != null) return;
    final m = phoneModel;
    modelImporting = true;
    modelNote = null;
    notifyListeners();
    try {
      final n = await _sys.invokeMethod<int>('pickFile', {'dest': '${models.pathOf(m)}.part'}) ?? -1;
      if (n < 0) {
        modelNote = 'No file picked.';
      } else {
        models.finishImport(m);
        modelNote = 'Ready. Your model (${sizeText(n)}) is on this phone. You can delete the copy in Downloads now.';
      }
    } on ModelError catch (e) {
      modelNote = e.message;
    } on PlatformException catch (e) {
      modelNote = 'Could not copy the file: ${e.message ?? e.code}.';
    } finally {
      modelImporting = false;
      notifyListeners();
    }
  }

  void deleteModel() {
    models.delete(phoneModel);
    modelNote = 'Deleted from this phone.';
    notifyListeners();
  }

  // ---------- app updates ----------
  static const _sys = MethodChannel('workout/system');
  Update? update; // a newer version found on GitHub
  String? updateNote;
  double? updateProgress;

  Future<String> _abi() async {
    try {
      return await _sys.invokeMethod<String>('abi') ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> checkForUpdate() async {
    updateNote = 'Checking GitHub…';
    notifyListeners();
    final c = GuardedClient(const NetGuard());
    try {
      update = await checkUpdate(c, await _abi());
      updateNote = update == null ? "You have the newest version." : 'Version ${update!.version} is available.';
    } on UpdateError catch (e) {
      updateNote = e.message;
    } catch (_) {
      updateNote = 'Could not check for updates right now.';
    } finally {
      c.close();
      notifyListeners();
    }
  }

  /// What the installer step said, in plain words: never a silent nothing (0.9.1 lesson).
  static String installNote(String? r) {
    final v = r ?? '';
    if (v == 'need_permission') return 'Allow FightMilk to install updates on the screen that opened, then tap Install again.';
    if (v == 'installed') return 'Updated.';
    if (v == 'cancelled') return 'The update was not installed: the installer was closed. Tap Install to try again; your workouts stay.';
    if (v == 'busy') return 'The installer is already open.';
    if (v == 'not_apk') return 'The downloaded file is not an app file, so it was not installed. Nothing was changed.';
    if (v == 'other_app') return 'The downloaded file is a different app, so it was not installed. Nothing was changed.';
    if (v.startsWith('not_newer:')) {
      final p = v.split(':');
      return 'This update is not newer than the app on your phone (its version code ${p.length > 1 ? p[1] : '?'}, yours ${p.length > 2 ? p[2] : '?'}), so Android would refuse it. Nothing was changed. Please tell the app\'s maker.';
    }
    if (v.startsWith('failed:')) {
      final code = int.tryParse(v.substring(7)) ?? 0;
      final why = switch (code) {
        -25 => 'it is older than the app on your phone',
        -7 => 'it is signed with a different key than the app on your phone (a test build installed earlier?)',
        -4 => 'there is not enough free space on the phone',
        -2 || -3 => 'the file is damaged',
        _ => 'Android said no (code $code)',
      };
      return 'Android did not install the update: $why. Nothing was changed; your workouts stay.';
    }
    return 'The installer is open. Confirm there to update; your workouts stay.';
  }

  /// Downloads the update, checks its fingerprint and opens Android's installer.
  Future<void> installUpdate() async {
    final u = update;
    if (u == null || updateProgress != null) return;
    updateProgress = 0;
    updateNote = null;
    notifyListeners();
    final c = GuardedClient(const NetGuard());
    try {
      final dir = p.join((await getTemporaryDirectory()).path, 'updates');
      final path = await downloadUpdate(u, c, dir, onProgress: (x) {
        updateProgress = x;
        notifyListeners();
      });
      updateNote = 'The installer is open. Confirm there to update; your workouts stay.';
      notifyListeners();
      updateNote = installNote(await _sys.invokeMethod<String>('install', {'path': path}));
    } on UpdateError catch (e) {
      updateNote = e.message;
    } catch (e) {
      updateNote = 'The update could not be opened: $e';
    } finally {
      c.close();
      updateProgress = null;
      notifyListeners();
    }
  }

  // ---------- packs ----------
  Future<String> checkPacks() async {
    final c = client;
    try {
      final msg = await checkForPack(c, packs);
      await rebuildLib();
      notifyListeners();
      return msg;
    } finally {
      c.close();
    }
  }

  // ---------- data ----------
  /// Files made for the share menu live in cache/exports only while it reads them; they go at the
  /// next start and with Delete all data (review 5, P1-2).
  static Future<void> clearShared({Duration? olderThan}) async {
    try {
      final d = Directory(p.join((await getTemporaryDirectory()).path, 'exports'));
      if (!d.existsSync()) return;
      if (olderThan == null) {
        d.deleteSync(recursive: true);
        return;
      }
      // at start: an app that reads a share late (a cloud upload) still finds a fresh file (S7 P3-8)
      final cut = DateTime.now().subtract(olderThan);
      for (final f in d.listSync().whereType<File>()) {
        if (f.lastModifiedSync().isBefore(cut)) f.deleteSync();
      }
    } catch (_) {}
  }

  Future<void> _releaseFolder(String tree) async {
    try {
      await backupFolder.release(tree);
    } catch (_) {}
  }

  Future<void> wipeEverything() async {
    await notifier.cancelAll();
    // the backup folder's access goes back to Android; the files already there stay (review 7, P3-8)
    final tree = autoBackup.tree;
    if (tree != null) await _releaseFolder(tree);
    await repo.wipe();
    models.deleteAll();
    try {
      final u = Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
      if (u.existsSync()) u.deleteSync(recursive: true);
    } catch (_) {}
    await secrets.wipe();
    try {
      final ph = Directory(photoDir); // progress photos (review 4, P1-1)
      if (ph.existsSync()) ph.deleteSync(recursive: true);
    } catch (_) {}
    await clearShared(); // the last file sent through the share menu (review 5, P1-2)
    photos = [];
    await _clearPicked();
    packs.remove();
    lib = baseLib;
    pickedDay = null;
    await reload();
  }

  Future<List<LiftState>> lifts() => repo.allLifts();

  /// After a set or workout in history changed: work next time's weights out again.
  /// The newest import, for the AI tool's words (loaded with the rest).
  ImportRecord? lastImport;

  // ---------- backups (batch 22, F339, F340) ----------
  /// Where automatic backups go; tests swap in a fake folder.
  static BackupFolder backupFolder = AndroidBackupFolder();
  AutoBackup autoBackup = const AutoBackup();
  BackupStatus backupStatus = const BackupStatus();
  bool _backingUp = false;

  Future<void> saveAutoBackupChoice(AutoBackup a) async {
    final old = autoBackup.tree;
    if (old != null && old != a.tree) await _releaseFolder(old); // another folder: give the old one back
    autoBackup = a;
    await saveAutoBackup(repo, a);
    notifyListeners();
  }

  /// One automatic backup now (after a workout, once a day, or "Back up now").
  Future<bool> backupNow({DateTime? now}) async {
    if (_backingUp || autoBackup.tree == null) return false;
    _backingUp = true;
    try {
      final ok = await runAutoBackup(repo, backupFolder, autoBackup, password: autoBackup.locked ? await secrets.backupPassword() : null, now: now);
      backupStatus = await loadBackupStatus(repo);
      notifyListeners();
      return ok;
    } finally {
      _backingUp = false;
    }
  }

  /// The home-screen widget's two lines (batch 23, F351): the next workout and this week. No
  /// body numbers, no weights: it sits on the home screen.
  Future<({String next, String week})> widgetLines({DateTime? now}) async {
    final t = now ?? DateTime.now();
    if (plan == null || plan!.days.isEmpty) return (next: 'Open FightMilk to set up your plan.', week: '');
    final ses = session;
    final day = plan!.days[todayIndex.clamp(0, plan!.days.length - 1)];
    final names = [for (final it in day.items.take(3)) lib.byId(it.exerciseId)?.name ?? it.exerciseId].join(', ');
    final next = ses != null ? 'In progress: ${ses.day.name}' : '${restDay ? 'Rest day. Next' : 'Today'}: ${day.name}${names.isEmpty ? '' : ' · $names'}';
    final (a, _, _) = weekReports(t, await workouts(), await allSets(), lib);
    final streak = weekStreak(await workouts(), t, perWeek: perWeekGoal);
    return (next: next, week: '${a.workouts} of $perWeekGoal this week${streak > 0 ? ' · $streak-week streak' : ''}');
  }

  /// Gives the home-screen widget its lines; nothing happens when none is placed.
  Future<void> updateHomeWidget() async {
    try {
      final l = await widgetLines();
      await _sys.invokeMethod('widget', {'next': l.next, 'week': l.week});
    } catch (_) {
      // no widget support (tests, desktop)
    }
  }

  /// The daily automatic backup, when the last one is a day old (at start and on return).
  Future<void> dailyBackup({DateTime? now}) async {
    if (autoBackup.when != 'day' || autoBackup.tree == null) return;
    final t = now ?? DateTime.now();
    final last = backupStatus.last;
    if (last != null && t.difference(last).inHours < 24) return;
    // after a failed try, wait an hour, not every return to the app (review 7, P1-2)
    final tried = backupStatus.lastTry;
    if (backupStatus.problem != null && tried != null && t.difference(tried).inMinutes.abs() < 60) return;
    await backupNow(now: t);
  }

  /// The person's own server (F343), if set up; the password is in secure storage.
  ServerConfig? server;

  /// Sends a backup to the person's own server, when they tap it (never by itself). Returns where
  /// it went. A plain BackupError on any problem.
  Future<Uri> sendBackupToServer({required bool body, String? lockPassword, http.Client? via, String? name}) async {
    final c = server;
    if (c == null) throw BackupError('No server is set up.');
    final pw = await secrets.serverPassword(serverKey(c)); // only the password typed for this very server (review 7, P1-3)
    if (pw == null) throw BackupError('The server password is missing. Set the server up again.');
    final plain = await exportBackup(repo, body: body);
    final text = lockPassword == null || lockPassword.isEmpty ? plain : await lockBackup(plain, lockPassword);
    final locked = !(lockPassword == null || lockPassword.isEmpty);
    // the name shown in the confirm, when given; it must fit the lock
    final file = name != null && name.endsWith(locked ? '.locked.json' : '.json') && (locked || !name.endsWith('.locked.json')) ? name : serverFileName(DateTime.now(), locked: locked);
    final client = via ?? GuardedClient(NetGuard(backupHost: Uri.parse(c.url.trim()).host));
    try {
      await sendToServer(client, c, pw, file, Uint8List.fromList(utf8.encode(text)));
    } finally {
      if (via == null) client.close();
    }
    await noteBackup(repo, 'your server');
    backupStatus = await loadBackupStatus(repo);
    notifyListeners();
    return serverTarget(c, file);
  }

  /// A backup saved by hand counts too (the status line).
  Future<void> noteManualBackup() async {
    await noteBackup(repo, 'a file you saved');
    backupStatus = await loadBackupStatus(repo);
    notifyListeners();
  }

  /// Takes the newest import out again (batch 21; the AI tool "import undo").
  Future<void> undoLastImport() async {
    final l = await importRecords(repo);
    if (l.isEmpty) return;
    final ex = await undoImport(repo, l.last.id);
    await historyChanged(ex);
    await reload();
  }

  Future<void> historyChanged(Iterable<String> exerciseIds) async {
    historyVersion++;
    await repo.rebuildLifts(exerciseIds, lib, unit);
    notifyListeners();
  }
}

/// Today's recovery hints (F232, F234).
class RecoveryHint {
  final String? warn; // a muscle trained too recently
  final int? betterDay; // a more rested plan day to do instead
  final int ready; // how rested today's muscles are, 0-100
  final String? rest; // a day off may be better
  const RecoveryHint({this.warn, this.betterDay, required this.ready, this.rest});
}

/// Tiles for the top of Progress (F264).
const dashTiles = {
  'week_workouts': 'Workouts this week',
  'week_volume': 'Lifted this week',
  'week_sets': 'Sets this week',
  'streak': 'Week streak (on plan)',
  'records_month': 'Days with a record this month',
  'body': 'Body weight',
  'top_lift': 'Top lift, est. 1-rep max',
};

/// One "Next time" line on the finish sheet: [change] 1 up, 0 the same, -1 down.
class NextLine {
  final String text;
  final int change;
  const NextLine(this.text, this.change);
}

/// "1 lift up, 5 the same" (the folded "Next time" line).
String nextSummary(List<NextLine> l) {
  final up = l.where((x) => x.change > 0).length, down = l.where((x) => x.change < 0).length, same = l.length - up - down;
  return [if (up > 0) '$up up', if (same > 0) '$same the same', if (down > 0) '$down down'].join(', ');
}
