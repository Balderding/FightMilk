# Workout App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A free, private Flutter Android app that designs heavy-lifting workouts (built-in rules or the user's own AI), logs sets in one tap, shows progress, and lets the user edit their plan.

**Architecture:** Pure-Dart domain layer (library, plan maker, progression, rotation, AI JSON validation) with unit tests; a sqflite data layer behind repository classes; a thin Flutter UI using ChangeNotifier state (no state-management package). All network goes through one guarded HTTP client with a host allowlist.

**Tech Stack:** Flutter stable (Dart 3), sqflite, http, flutter_secure_storage, cryptography (Ed25519), crypto (SHA-256), archive (zip), file_picker, flutter_local_notifications, wakelock_plus, flutter_svg, path_provider. No Firebase, no Play Services, no analytics.

**Spec:** `docs/2026-11-20-workout-app-design.md`

## Global Constraints

- Android only; `minSdk` = Flutter's default floor; no iOS work.
- Tools under `O:\appsnotonc\` (flutter, android-sdk, gradle cache `GRADLE_USER_HOME`, `PUB_CACHE`); nothing installed on C:. JDK: existing Temurin 17 on the PC.
- Network: only (a) the user-configured AI host, (b) `github.com` / `api.github.com` / `objects.githubusercontent.com` for packs. Plain http only for localhost, 10.x, 172.16–31.x, 192.168.x.
- `android:allowBackup="false"`; no analytics/crash/ads packages; every new package checked for network code.
- AI off by default; "show what's sent" on by default; API keys only in secure storage, never in backups or logs.
- Colours: bg `#0f1418`, card `#182129`, teal `#2ec4b6`, gold `#f2c14e`, green `#7bd389`, navy `#1d3557`. **No red anywhere**; errors in gold/amber with an icon.
- Touch targets ≥ 48 dp; steppers 52 dp.
- Author name "balderding" only. Code GPL-3.0, icons CC BY-SA 4.0.
- Dumbbell weight per dumbbell (volume ×2); bodyweight lifts log added weight.

## Review Focus

1. App killed mid-workout → reopening resumes the same session with all logged sets (test in Task 4: session row + sets survive a fresh repository instance).
2. AI returns junk, partial JSON, unknown exercise ids, or a 50-set day → rejected, current plan kept, plain message (Task 7 validation tests).
3. User has very little equipment (dumbbells only) or many "go easy on" flags → plan maker still makes a full plan, never an empty day (Task 3 test).
4. kg ↔ lb switch after months of history → stored values unchanged (stored in kg internally), display converts, steps follow the unit (Task 2 test).
5. Backup from an older app version / import twice → merge doesn't duplicate (Task 9 test on ids).

---

### Task 0: Toolchain + project skeleton

**Files:** Create `app/` (flutter create), `app/android/app/src/main/AndroidManifest.xml` (allowBackup=false, INTERNET, VIBRATE, POST_NOTIFICATIONS, WAKE_LOCK), `tools/env.sh`.

- [ ] Download Flutter stable zip to `O:\appsnotonc\flutter`; Android cmdline-tools to `O:\appsnotonc\android-sdk`; install `platform-tools`, `platforms;android-36`, `build-tools;36.0.0` with sdkmanager; accept licences.
- [ ] `tools/env.sh` exports `FLUTTER_ROOT`, `ANDROID_HOME`, `PUB_CACHE=O:/appsnotonc/pub-cache`, `GRADLE_USER_HOME=O:/appsnotonc/gradle-home`, `JAVA_HOME` (Temurin 17), PATH.
- [ ] `flutter create --org org.balderding --project-name workout --platforms android app`; `flutter doctor` shows Android toolchain OK.
- [ ] `flutter build apk --debug` succeeds. `git init` in `O:\code.projects\workout-app`, commit.

### Task 1: Exercise library + icons

**Files:** `app/assets/exercises.json`, `app/assets/icons/*.svg`, `app/lib/domain/exercise.dart`, `app/lib/domain/library.dart`, test `app/test/library_test.dart`, tool `tools/gen_icons.py`.

**Produces:** `class Exercise {String id, name; Equipment equipment; List<Muscle> primary, secondary; Pattern pattern; String swapGroup; Set<Joint> joints; int repLow, repHigh; StepKind step; bool bodyweight; String icon;}`; `enum Equipment {barbell, dumbbell, machine, cable, smith, kettlebell, bodyweight}`; `enum Joint {shoulders, lowerBack, knees, wrists}`; `class Library {static Future<Library> load(); Exercise byId(String); List<Exercise> swapsFor(Exercise e, Set<Equipment> have, Set<Joint> avoid);}`.

- [ ] Tests: every exercise has an existing icon file; ids unique; every swapGroup has ≥2 members; `swapsFor(benchPress, {machine,dumbbell}, {})` contains `machine_chest_press` and `db_bench_press` and not `bench_press`.
- [ ] Write ~120 exercises across chest, back, shoulders, legs, arms, core, all equipment types.
- [ ] `tools/gen_icons.py` draws our own SVG icons: a stick-figure pose per movement pattern + equipment glyph, flat, coloured per equipment (teal barbell, gold dumbbell, green machine, light-blue cable). Run, tests pass, commit.

### Task 2: Units + progression + e1RM

**Files:** `app/lib/domain/units.dart`, `app/lib/domain/progression.dart`, test `app/test/progression_test.dart`.

**Produces:** weights stored as `double kg`. `String fmtWeight(double kg, Unit u)`; `double stepKg(StepKind k, Unit u)` (barbell 5 lb / 2.5 kg, dumbbell 5 lb / 2 kg, machine 10 lb / 5 kg, cable 5 lb / 2.5 kg); `double e1rm(double kg, int reps)` = Epley `kg*(1+reps/30)` (reps 1 → kg); `class LiftState {String exerciseId; double workKg; int misses;}`; `Target nextTarget(LiftState s, Exercise e, List<SetLog> lastSession, Unit u)`.

- [ ] Tests: all sets at repHigh → workKg + step; any set below repLow → misses+1; misses reaching 2 → workKg × 0.9 rounded to step, misses 0; in between → same weight; bodyweight exercise: reps up to repHigh then +step added weight; 100 kg in lb displays "220.5"→ rounded display "220"; e1rm(100,5)=116.67.
- [ ] Implement, pass, commit.

### Task 3: Plan model + built-in plan maker + rotation

**Files:** `app/lib/domain/plan.dart`, `app/lib/domain/plan_maker.dart`, test `app/test/plan_maker_test.dart`.

**Produces:** `class Profile {Goal goal; int days; int minutes; Set<Equipment> have; Set<Joint> avoid; Unit unit; String? split;}`; `class Plan {String id, name; List<PlanDay> days; bool userEdited;}`; `class PlanDay {String name; List<PlanItem> items;}`; `class PlanItem {String exerciseId; int sets, repLow, repHigh, restSec;}`; `Plan makePlan(Profile p, Library lib)`; `List<String> splitsFor(int days)`; `int nextDayIndex(Plan plan, int? lastDoneIndex)` = (last+1) % days.length.

- [ ] Tests: days 2/3/4/5/6 produce the split in the spec (2 full A/B, 3 full A/B/C, 4 upper/lower ×2, 5 UL+PPL, 6 PPL×2); a user-chosen split (`ppl`, `upper_lower`, `full_body`, `bro`) overrides; 45 min → ≤5 items/day, 60 → ≤6, 90 → ≤8; first item each day is a compound; dumbbells-only + avoid {shoulders,lowerBack,knees} → every day non-empty and no item stresses an avoided joint; goal strength → main lift repLow 3 repHigh 6, size 8–12, both 5–8 main / 8–12 accessories; rotation wraps.
- [ ] Implement, pass, commit.

### Task 4: Database + repositories

**Files:** `app/lib/data/db.dart`, `app/lib/data/repo.dart`, test `app/test/repo_test.dart` (sqflite_common_ffi for tests).

**Produces:** tables `profile`, `plan` (json blob + active flag, old plans kept), `lift_state`, `session (id, plan_id, day_index, started, finished)`, `set_log (id, session_id, exercise_id, kg, reps, ord, at)`, `note`. `class Repo {Future<Profile?> profile(); saveProfile; Future<Plan?> activePlan(); savePlan(Plan, {bool makeActive}); List<Plan> oldPlans(); Future<Session> startOrResume(); logSet(SetLog); deleteSet(id); finishSession(id); Future<List<Session>> history(); Future<List<SetLog>> setsFor(sessionId); Future<LiftState> lift(String exId); saveLift; Future<void> wipe();}` All ids are UUID strings.

- [ ] Tests: logged sets survive closing and reopening the db; `startOrResume` returns the unfinished session; finishing applies `nextTarget` to every exercise done; history newest first.
- [ ] Implement, pass, commit.

### Task 5: App shell, theme, setup + Today + Swap

**Files:** `app/lib/main.dart`, `app/lib/ui/theme.dart`, `app/lib/ui/app_state.dart` (ChangeNotifier holding repo/library/profile/plan), `app/lib/ui/setup_screen.dart`, `app/lib/ui/today_screen.dart`, `app/lib/ui/swap_sheet.dart`, `app/lib/ui/widgets.dart` (pill, card, exercise tile, svg icon).

- [ ] Bottom nav Today / Plan / History / Progress / Settings as in the mockups. First run → Setup (spec 8.1, plus "Split: let the app choose / pick one"), "Make my plan" → `makePlan` (or AI if on).
- [ ] Today lists the `nextDayIndex` day with target weights from `LiftState`, gold ↑ when raised; Swap sheet from `Library.swapsFor`, "today only" vs "use from now on".
- [ ] Widget test: first launch shows Setup; after Make my plan, Today shows a day name and ≥1 exercise. `flutter test` passes, commit.

### Task 6: Logging screen + rest timer

**Files:** `app/lib/ui/log_screen.dart`, `app/lib/ui/rest_timer.dart`.

- [ ] Steppers (52 dp) for weight (step by `stepKg`) and reps, pre-filled; Done set → `repo.logSet` immediately + rest timer (default from PlanItem, ±30 s, skip); timer end = vibration + scheduled local notification so it fires with the screen off; wakelock on during a workout. Set table green done / gold current. Note, Swap, Next/previous exercise, add extra set, long-press a set to edit/delete, Finish workout → summary.
- [ ] Widget test: tapping Done set adds a row and shows the timer. Commit.

### Task 7: AI providers + validation + send preview

**Files:** `app/lib/net/guarded_client.dart`, `app/lib/ai/ai.dart`, `app/lib/ai/providers.dart`, `app/lib/ai/prompt.dart`, `app/lib/ai/plan_json.dart`, `app/lib/ui/ai_preview_sheet.dart`, tests `app/test/net_guard_test.dart`, `app/test/plan_json_test.dart`.

**Produces:** `enum AiKind {claude, openai, gemini, local}`; `class AiConfig {AiKind kind; String model; String? baseUrl;}` (+ key in secure storage); `abstract class AiProvider {String get host; Future<String> complete(String system, String user);}` with Anthropic Messages, OpenAI Chat Completions, Gemini generateContent, and OpenAI-compatible local adapters; `String buildRequest(Profile, Plan?, List<SetLog> last14days, String ask)`; `PlanParse parsePlan(String text, Library lib)` → `Plan` or a list of plain-language errors.

- [ ] Guard tests: allows configured https host and github hosts; refuses any other host; refuses http to 8.8.8.8, allows http to 192.168.1.20:8080 and localhost.
- [ ] Validation tests: JSON inside ```json fences accepted; unknown exercise id → error; sets outside 1–10, reps outside 1–30, rest outside 30–600 s, >12 items/day, 0 days → error; non-JSON → error. Request text contains no device/name fields (assert keys).
- [ ] Settings → AI page: switch, provider, key, model, URL, test connection, preview-before-send. Buttons: "Make plan with AI" (setup/plan), "Ask AI to adjust today" (session only). Preview sheet shows host + exact text. Commit.

### Task 8: Plan editor (full editing)

**Files:** `app/lib/ui/plan_screen.dart`, `app/lib/ui/plan_editor.dart`, test `app/test/plan_edit_test.dart`.

- [ ] Plan tab: shows days; edit mode to add/rename/delete/reorder days, add (searchable library picker)/remove/reorder exercises, change sets/reps/rest; saving sets `userEdited=true`. "Remake plan" (built-in or AI) asks first when userEdited, keeps the old plan in history with Restore.
- [ ] Pure-Dart tests on the edit operations (`Plan.moveItem`, `addDay`, `removeDay` keep rotation index valid). Commit.

### Task 9: History, progress, backup

**Files:** `app/lib/ui/history_screen.dart`, `app/lib/ui/progress_screen.dart` (CustomPainter chart, no chart package), `app/lib/data/backup.dart`, test `app/test/backup_test.dart`.

- [ ] History list + session detail with edit/delete set. Progress: lift picker, e1RM chart over time, PBs (heaviest, most reps at weight, e1RM), weekly summary (workouts, volume, hard sets per primary muscle).
- [ ] Backup: export JSON `{format:1, profile, plans, lift_state, sessions, sets}` via file_picker save; import with merge (by id, no duplicates) or replace. Tests: round-trip equal; import twice → same counts; no key in export. Commit.

### Task 10: Signed icon/exercise packs

**Files:** `app/lib/packs/pack_manager.dart`, `tools/sign_pack.dart`, `tools/pack_key.pub` (private key kept in `O:\code.projects\workout-app\keys\`, git-ignored), test `app/test/pack_test.dart`.

- [ ] Pack = zip with `manifest.json {version, files:{path:sha256}, exercises?}` + `manifest.sig` (Ed25519 over manifest bytes). Fetch latest release from `api.github.com/repos/Balderding/<repo>/releases/latest` only on "Check now" or the auto switch; install to app dir only if version newer, signature valid, all hashes match; else keep built-in.
- [ ] Tests: good pack installs; tampered file → refused; wrong key → refused; older version → ignored. Settings shows the GitHub/IP note. Commit.

### Task 11: Settings, privacy page, release build

- [ ] Settings: units, rest defaults, steps, AI, packs, export/import, delete all data (confirm sheet), privacy text from spec 8.8, licence/about.
- [ ] Release keystore in `keys\` (git-ignored), `flutter build apk --release --split-per-abi` + universal APK; check the merged manifest has only the permissions listed in Task 0; `flutter test` all green (grep for failures, check exit code).
- [ ] Send the universal APK to the owner's phone; commit.
