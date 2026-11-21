import 'dart:convert';
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../ai/ai.dart';
import '../ai/grammar.dart';
import '../ai/plan_json.dart';
import '../ai/prompt.dart';
import '../ai/tools.dart';
import '../data/repo.dart';
import '../domain/exercise.dart';
import '../domain/gym.dart';
import '../domain/plates.dart';
import '../domain/progression.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/plan_maker.dart';
import '../domain/units.dart';
import '../llm/model_store.dart';
import '../llm/native.dart';
import '../net/guarded_client.dart';
import '../packs/pack.dart';
import '../services/notify.dart';
import '../services/secrets.dart';
import '../services/sounds.dart';
import '../update/updater.dart';

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
  final bool checkin; // 'How do you feel?' before a workout
  final int deloadEvery; // weeks; 0 = only when you ask or the app suggests
  final String formula; // 1RM: 'epley' | 'brzycki'
  final bool effortDrives; // Easy/Hard taps change the next weight
  final int dropPct; // percent
  final int missesToDrop;
  final String progSpeed; // 'slow' | 'steady' | 'fast'
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
    this.checkin = true,
    this.deloadEvery = 0,
    this.formula = 'epley',
    this.effortDrives = true,
    this.dropPct = 10,
    this.missesToDrop = 2,
    this.progSpeed = 'steady',
  });

  Settings copyWith({bool? aiOn, AiConfig? ai, bool? preview, bool? autoPacks, bool? keepAwake, int? rest, bool planRest = false, Map<String, double>? steps, bool? chatProject, bool? smartRest, String? sound, List<int>? remindDays, int? remindAt, bool? autoUpdate, bool? aiAuto, bool? hideRecents, bool? warmups, bool? restOff, bool? checkin, int? deloadEvery, String? formula, bool? effortDrives, int? dropPct, int? missesToDrop, String? progSpeed}) => Settings(
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
        deloadEvery: deloadEvery ?? this.deloadEvery,
        formula: formula ?? this.formula,
        effortDrives: effortDrives ?? this.effortDrives,
        dropPct: dropPct ?? this.dropPct,
        missesToDrop: missesToDrop ?? this.missesToDrop,
        progSpeed: progSpeed ?? this.progSpeed,
      );

  Map<String, dynamic> toJson() => {'aiOn': aiOn, 'ai': ai.toJson(), 'preview': preview, 'autoPacks': autoPacks, 'keepAwake': keepAwake, 'rest': rest, 'steps': steps, 'chatProject': chatProject, 'smartRest': smartRest, 'sound': sound, 'remindDays': remindDays, 'remindAt': remindAt, 'autoUpdate': autoUpdate, 'aiAuto': aiAuto, 'hideRecents': hideRecents, 'warmups': warmups, 'restOff': restOff, 'checkin': checkin, 'deloadEvery': deloadEvery, 'formula': formula, 'effortDrives': effortDrives, 'dropPct': dropPct, 'missesToDrop': missesToDrop, 'progSpeed': progSpeed};

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
        checkin: (j['checkin'] ?? true) as bool,
        deloadEvery: (j['deloadEvery'] ?? 0) as int,
        formula: (j['formula'] ?? 'epley') as String,
        effortDrives: (j['effortDrives'] ?? true) as bool,
        dropPct: (j['dropPct'] ?? 10) as int,
        missesToDrop: (j['missesToDrop'] ?? 2) as int,
        progSpeed: (j['progSpeed'] ?? 'steady') as String,
      );
}

/// What the screens show for one exercise today.
class Target {
  final double? kg; // null = no history yet; the user fills in the first set
  final int reps;
  final bool up; // weight (or reps) went up since last time
  final String? why; // a lighter target and why (deload, rough day, time off)
  const Target(this.kg, this.reps, this.up, {this.why});
}

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

  static Future<AppState> load() async {
    final dir = await getApplicationSupportDirectory();
    final repo = await Repo.open(p.join(await getDatabasesPath(), 'workout.db'));
    final packs = PackStore(dir.path);
    final base = await Library.load();
    final notifier = Notifier();
    await notifier.init();
    final s = AppState._(repo, packs, base, Secrets(), notifier);
    await s.rebuildLib();
    await s.reload();
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

  Future<void> reload() async {
    await rebuildLib();
    final st = await repo.kvGet('settings');
    settings = st == null ? const Settings() : Settings.fromJson(jsonDecode(st) as Map<String, dynamic>);
    applySteps();
    profile = await repo.profile();
    await _loadGyms();
    await _loadDeload();
    profile = _withGym(profile);
    plan = await repo.activePlan();
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
      final j = jsonDecode(pk) as Map<String, dynamic>;
      if (j['plan'] == plan!.id && j['last'] == lastDay && j['day'] is int && (j['day'] as int) < plan!.days.length) pickedDay = j['day'] as int;
    }
    override = null;
    final o = await repo.kvGet('override');
    if (o != null && plan != null) {
      final j = jsonDecode(o) as Map<String, dynamic>;
      if (j['plan'] == plan!.id && j['day'] == todayIndex) override = PlanDay.fromJson(j['data'] as Map<String, dynamic>);
    }
    await _loadChanges();
    notifyListeners();
  }

  Unit get unit => profile?.unit ?? Unit.lb;

  int get todayIndex {
    if (plan == null || plan!.days.isEmpty) return 0;
    if (pickedDay != null && pickedDay! < plan!.days.length) return pickedDay!;
    return nextDayIndex(plan!, lastDay);
  }

  PlanDay? get today {
    if (session != null) return session!.day;
    if (override != null) return _adjusted(override);
    if (plan == null || plan!.days.isEmpty) return null;
    return _adjusted(plan!.days[todayIndex]);
  }

  /// "Week 3": one pass through the rotation = one week.
  int get week => plan == null || plan!.days.isEmpty ? 1 : finishedOnPlan ~/ plan!.days.length + 1;

  String iconFor(Exercise e) => packs.iconPath(e.icon) ?? 'asset:assets/icons/${e.icon}.svg';

  // ---------- setup / plans ----------
  /// Puts the user's own weight steps into effect.
  /// Sound mode and reminders follow the settings.
  void applyPrefs() {
    sounds.mode = settings.sound;
    _sys.invokeMethod('secure', {'on': settings.hideRecents}).catchError((_) => null);
    final d = today;
    notifier.scheduleReminders(settings.remindDays.toSet(), settings.remindAt, d?.name ?? 'your workout').ignore();
  }

  void applySteps() {
    e1rmFormula = settings.formula;
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
  void pickDay(int i) {
    pickedDay = i;
    override = null;
    repo.kvSet('override', '{}');
    repo.kvSet('picked', jsonEncode({'plan': plan?.id, 'last': lastDay, 'day': i}));
    notifyListeners();
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

  /// Today's sets as they will be done: fewer in a deload week or on a rough day.
  PlanDay? _adjusted(PlanDay? d) {
    if (d == null) return null;
    final rough = feeling == 1;
    if (!inDeload && !rough) return d;
    return d.copyWith(items: [
      for (var i = 0; i < d.items.length; i++)
        d.items[i].copyWith(sets: inDeload ? (d.items[i].sets * 0.6).ceil().clamp(1, 10) : (i == 0 ? d.items[i].sets : (d.items[i].sets - 1).clamp(1, 10)))
    ]);
  }

  // ---------- targets ----------
  Future<Target> targetFor(PlanItem it) async {
    final e = lib.byId(it.exerciseId);
    if (e == null) return Target(null, it.repLow, false);
    final st = await repo.lift(e.id);
    final last = await repo.lastTime(e.id);
    final lastMax = last.isEmpty ? null : last.where((s) => s.counts).fold<double?>(null, (a, s) => a == null || s.kg > a ? s.kg : a);
    if (st == null) return Target(lastMax == null ? null : (e.bodyweight ? lastMax : roundToStep(lastMax, e.step, unit)), it.repLow, false);
    var f = 1.0;
    String? why;
    final away = st.updated == null ? 0 : DateTime.now().difference(st.updated!).inDays;
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
    }
    final kg = e.bodyweight ? st.workKg : roundToStep(st.workKg * f, e.step, unit);
    final reps = e.bodyweight ? (st.workReps ?? it.repLow).clamp(it.repLow, it.repHigh) : it.repLow;
    final up = lastMax != null && (kg > lastMax + 0.01 || (e.bodyweight && last.isNotEmpty && reps > (last.map((s) => s.reps).reduce((a, b) => a < b ? a : b))));
    return Target(kg, reps, up, why: why);
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
    notifier.askOnce().ignore();
    notifyListeners();
    return session!;
  }

  /// [excuse]: a bad day; misses don't count and weights don't drop. [rating]: 1-5 stars.
  Future<void> finishWorkout({bool excuse = false, int? rating}) async {
    if (session == null) return;
    restEnd = null;
    await notifier.cancel();
    final fk = 'flags:${session!.id}';
    final old = await repo.kvGet(fk);
    final flags = {...(old == null ? const <String, dynamic>{} : jsonDecode(old) as Map<String, dynamic>), if (excuse) 'excuse': true, if (rating != null) 'rating': rating};
    if (flags.isNotEmpty) await repo.kvSet(fk, jsonEncode(flags));
    await repo.finishSession(session!.id, lib, unit, excuse: excuse, deload: flags['deload'] == true);
    sessionDeload = false;
    pickedDay = null;
    await reload();
    applyPrefs(); // reminders now name the next day
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
    }
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
    aiChanges = [AiChange(DateTime.now(), asked, did, before), ...aiChanges].take(30).toList();
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
        k <= i ? AiChange(aiChanges[k].at, aiChanges[k].asked, aiChanges[k].did, aiChanges[k].before, undone: true) : aiChanges[k]
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
    if (!models.isReady(m)) throw AiError('Download the model first (Settings → AI coach).');
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
      final r = await _sys.invokeMethod<String>('install', {'path': path});
      updateNote = r == 'need_permission'
          ? 'Allow FightMilk to install updates on the screen that opened, then tap Install again.'
          : 'The installer is open. Confirm there to update; your workouts stay.';
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
  Future<void> wipeEverything() async {
    await notifier.cancelAll();
    await repo.wipe();
    models.deleteAll();
    try {
      final u = Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
      if (u.existsSync()) u.deleteSync(recursive: true);
    } catch (_) {}
    await secrets.wipe();
    packs.remove();
    lib = baseLib;
    pickedDay = null;
    await reload();
  }

  Future<List<LiftState>> lifts() => repo.allLifts();

  /// After a set or workout in history changed: work next time's weights out again.
  Future<void> historyChanged(Iterable<String> exerciseIds) async {
    await repo.rebuildLifts(exerciseIds, lib, unit);
    notifyListeners();
  }
}
