# Workout app — design (2026-11-20)

Working name: **workout app** (final name not chosen yet).
Owner: balderding. Mockups: `mockups/mockups.html` (five screens: setup, today, logging, progress, settings).

## 1. Intent and the why

A free Android app for people who lift heavy with machines, barbells and dumbbells, and who
**don't know what to do when they walk into the gym**. The app designs the workout, then makes
logging it faster than keeping it in your head (the owner currently tracks from memory).

Why it exists:
- The owner wants to build it, and wants one that **collects no data about the user and sells
  nothing to anyone**.
- It is given away freely, so anyone can use it on the same terms.

The privacy rule, in the owner's words: the app may use the internet, but must never do anything
bad with it. **Bad = sending any data a feature doesn't need, or collecting any information about
the user or their use of the app.**

## 2. Goals

1. Design a workout for today, with or without AI.
2. Log a set in one tap in the common case (weight and reps pre-filled from the plan / last time).
3. Show progress per lift over time.
4. Optional AI coach, off by default, using the user's own key or own server.
5. Our own exercise icons, built in, with optional user-triggered updates from GitHub.
6. Works on as many Android phones as possible.

## 3. Non-goals (not in version 1)

- iPhone (decided: Android only; Apple's build/distribution needs a Mac and $99/yr).
- Accounts, sign-in, cloud sync, social features, sharing, leaderboards.
- Nutrition, body-weight/diet tracking, wearables, heart rate.
- Cardio programming (a free-form "cardio" log entry is fine, nothing more).
- Ads, payments, in-app purchases, "pro" tiers.

## 4. Anti-goals (failure even if it works)

- Any analytics, telemetry, crash-reporting service, ad SDK, or Google/Firebase service.
- Any network call the user didn't trigger or switch on.
- Logging that is slower or more fiddly than remembering.
- An app that is only useful with AI. The built-in plan maker must be good on its own.

## 5. Constraints

- **Platform:** Flutter (Dart), **Android only**. Minimum Android version = the lowest Flutter's
  current stable release supports. No iOS folder work, no iOS testing.
- **Owner's PC:** Windows 11. All SDKs/tools (Flutter SDK, Android SDK, JDK, Gradle cache, pub
  cache) install under `O:\appsnotonc\`, **never on C:** (set `PUB_CACHE`, `GRADLE_USER_HOME`,
  `ANDROID_HOME`/`ANDROID_SDK_ROOT` to O:).
- **Project folder:** `O:\code.projects\workout-app\`.
- **No Google Play Services** dependency (needed for F-Droid, and a privacy point).
- **Network:** the app has the INTERNET permission (one version only — decided). It may contact
  only: (a) the AI endpoint the user configured, (b) GitHub, for icon/exercise pack updates. All
  HTTP goes through one network module with a host allowlist; nothing else may open a socket.
  Every dependency gets checked for hidden network/analytics code before it's added.
- **No real names** in the code, commits or releases; author is "balderding".
- **No red text** in the UI (a design rule: problems are shown calmly). Use navy/teal/green/gold. Errors use
  gold/amber with an icon.

## 6. Approaches considered (for how it's built)

| Approach | Trade-off | Outcome |
|---|---|---|
| Native Kotlin + Jetpack Compose | Smallest/fastest APK, best F-Droid fit; Android only, no path to iPhone | Considered first |
| **Flutter** | One codebase, iPhone possible later if ever wanted; slightly bigger APK, F-Droid build a bit fussier | **Chosen by the owner** |
| Web app (PWA) | No store needed; phone can wipe its data, weak offline/privacy guarantees | Dropped |

AI approaches: (1) no AI, (2) **bring-your-own AI, off by default — chosen**, (3) on-phone model
(dropped: huge downloads, slow on most phones).

## 7. What the owner decided

- Android only, Flutter.
- One version with internet, used only for the AI and icon updates (no separate offline build).
- AI = option 2: user's own key or own server, **off by default**. Providers: local server,
  Claude, OpenAI, Gemini.
- The app designs the workout ("I don't know what I'm going to do").
- Own exercise icons, published on GitHub, downloadable as updates **only if the user chooses**.
- Free, given away.
- The flow in sections 8–9 below (setup → plan → today → log → progress) was played back and
  accepted ("nothing so far" missing).

- **Today = next in line (rotation).** The days rotate in order; a missed gym day just waits. The
  days come from whatever split the person sets up: they pick a split (push/pull/legs,
  upper/lower, full body, bro split…), build their own, or let the built-in maker / the AI arrange
  it. The week number in the header is only a counter (one pass through the rotation = one week);
  deloads come from the progression rule, not the calendar.
- **Everything in one go, including full plan editing** (add/remove/reorder days and exercises,
  change sets/reps/weight/rest). The owner tests the APK on their own Android phone; it is
  built on the home PC and sent to them.

### Calls made after the builder check (balderding may overrule)
- Progression is stored **per exercise**, not per plan slot: remaking the plan, editing it, or
  swapping keeps working weights and miss counts.
- Swap = today only by default, with "use this from now on" (writes the plan).
- "Ask AI to adjust today" changes only that session; "Remake plan with AI" replaces the plan
  (the old plan is kept in history and can be restored).
- A user-edited plan is the user's: the plan maker never overwrites it without asking.
- Dumbbell weight is logged per dumbbell; volume counts both. Bodyweight lifts (pull-ups, dips,
  push-ups) log added weight (0 = bodyweight) + reps; they progress on reps, then added weight.
- Icon/exercise packs are **signed** (Ed25519 key, public half built into the app); unsigned or
  wrongly signed packs are refused. SHA-256 per file too.
- Own-server AI may use plain http only on home-network addresses (see 8.6).

## 8. How it works

### 8.1 First-time setup (one screen, no account)
Goal (strength / size / both), days per week (2–6), time per session (45/60/90 min),
equipment available (barbells, dumbbells, machines, cables, Smith, kettlebells), "go easy on"
(shoulders, lower back, knees, wrists), units (lb/kg). "Make my plan" runs the built-in plan maker,
or the AI if enabled. All of it can be changed later in Settings.

### 8.2 The plan
A weekly plan of named days (e.g. Upper A, Lower A, Upper B, Lower B). Each day = ordered
exercises, each with target sets × reps × weight and rest time.

**Built-in plan maker (AI off — the default):**
- Split by days/week: 2 = full body A/B; 3 = full body A/B/C; 4 = upper/lower ×2;
  5 = upper/lower + push/pull/legs mix; 6 = push/pull/legs ×2.
- Exercise picks from the bundled library filtered by the user's equipment and "go easy on" flags;
  compound lift first, then accessories; exercise count trimmed to fit the session time.
- Rep ranges by goal: strength 3–6 on main lifts; size 8–12; both = 5–8 main, 8–12 accessories.
- **Progression (double progression):** hit the top of the rep range on all sets → next time add the
  smallest step (barbell 5 lb / 2.5 kg, dumbbell to next pair, machine to next pin step). Miss the
  bottom of the range twice in a row → drop ~10 % and build back.
- Starting weights: on first use of an exercise the app asks "what can you do for about N reps?"
  (or the user leaves it blank and fills in the first set).

**With AI on:** the same inputs go to the AI, which returns a plan as structured JSON (exercise ids
from our library only, sets, reps, weights, rest). Before each session "Ask AI to adjust today" can
tweak the day from recent logs. The app **validates** every AI answer (known exercise ids, sane
numbers); anything invalid is rejected and the built-in plan stays. AI never blocks using the app.

### 8.3 Today screen
Today's day from the plan, all exercises pre-filled. Gold ↑ marks lifts whose weight went up.
**Swap** on any exercise opens alternatives that hit the same muscles with the user's equipment
(e.g. barbell bench → machine chest press / DB bench / Smith bench), with a weight suggestion.
"Start workout" goes to logging.

### 8.4 Logging (the screen that matters most)
- Big − / + steppers for weight and reps, pre-filled from the target (or last time).
- **Done set** = one tap logs it and starts the rest timer automatically (vibrates/beeps when done,
  works with the screen off via a foreground notification; ±30 s, skip).
- Set table shows done (green ✓), current (gold), remaining.
- Note, Swap, Next exercise. Extra sets allowed; skipping an exercise allowed.
- Workout survives the app being killed (every set written to the database immediately).
- The user can always log what they actually did, whatever the plan said.

### 8.5 History and progress
History: list of past workouts, tap to view/edit. Progress: per-lift chart of best set's
estimated 1-rep max (Epley), personal bests (heaviest, most reps at a weight, e1RM), weekly
summary (workouts done, total weight lifted, hard sets per muscle group). All computed on the phone.

### 8.6 Settings
- **AI coach** switch (off by default). Provider (owner decided: these four):
  - **Claude** (Anthropic API, user's key) + model;
  - **OpenAI** (user's key) + model;
  - **Gemini** (Google AI API, user's key) + model;
  - **Local / my own server** — an OpenAI-compatible URL (llama-server, Ollama, LM Studio) +
    model name. Plain http allowed only for home-network addresses (localhost, 10.x, 172.16–31.x,
    192.168.x), with a warning; https anywhere.
  Each provider is one small adapter behind a common interface (same prompt, same JSON schema,
  same validation), so adding another later is cheap.
  "Show me what's sent before every request" (on by default). Test-connection button.
- **Exercise icons**: built-in version + count; "Check GitHub automatically" switch (off by
  default); "Check now" button.
- **Your data**: export backup / import backup; delete all data.
- Units, rest-timer defaults, plate/dumbbell steps.
- **Privacy, in plain words**: what the app sends, to whom, and when (see 8.8).

### 8.7 AI details
- The send preview shows the **exact text** of the request and its destination host.
- Request content = only: setup answers, the relevant plan day, recent sets (default last 2 weeks),
  and the question. **Never**: name, device id, location, app usage, contacts, anything else.
- API key stored with Android Keystore-backed secure storage; never logged, never in backups.
- Prompts ask for JSON in a fixed schema; app parses/validates; on failure shows a plain message
  and keeps the current plan.
- Default model per provider: a current mid-price model for each (configurable by the user).
- The send preview names the provider's host (api.anthropic.com, api.openai.com,
  generativelanguage.googleapis.com, or the user's server).
- No AI conversation history is kept beyond what the user sees on screen.

### 8.8 Network behaviour (the whole list)
1. AI request — only when the user presses an AI button, only to the configured host.
2. Icon/exercise pack check — only when the user presses "Check now", or on app start if they
   switched on automatic checks. Contacts GitHub only. The settings page says plainly that GitHub
   sees the phone's IP address, like visiting any web page.
Nothing else. No update checks for the app itself in v1 (users get new APKs from GitHub/F-Droid).

### 8.9 Exercise library and icons
- Bundled `exercises.json`: id, name, equipment, primary/secondary muscles, movement pattern,
  "swap group" (exercises that can replace each other), joints stressed (for "go easy on"),
  icon id, default rep range, weight step type. About 120–150 gym exercises at launch.
- **Our own icons**, drawn for this project (no copied art), as SVG, one style: simple figure +
  equipment silhouette, readable at 44 px, works on dark background.
- **Icon/exercise pack updates:** published as a GitHub Release asset (zip) with a manifest:
  pack version, list of files, SHA-256 per file. The app downloads only if the pack version is
  newer, verifies every hash, installs to app storage, and falls back to the built-in set if
  anything fails. Packs can add icons and new exercises (never code).

### 8.10 Data and backups
- Local SQLite database (via a Dart ORM such as drift). Everything on the phone.
- Backup = one JSON file the user saves wherever they choose (Android file picker); import merges or
  replaces (user picks). Backups never include the AI key.
- Android system cloud backup **disabled** (`allowBackup=false`) so nothing goes to Google's servers.

## 9. Look

Dark theme (gym-friendly), teal primary, gold for "up/now", green for done, navy tags. Big touch
targets (≥ 48 dp, steppers ~52 dp). As in the mockups. A light theme is a later nice-to-have.

## 10. Distribution and licence

- Open source on GitHub (repo under the owner's account "Balderding"; public when the owner says).
- Signed release APK on GitHub Releases; F-Droid submission after v1 is stable.
- Google Play optional later ($25 one-time) — not planned.
- **Licence (my call, owner to confirm):** code GPL-3.0 (forks must stay open, which suits
  "nobody sells this"); icons CC BY-SA 4.0.

## 11. Left to the builder

- Flutter packages (state management, ORM, secure storage, charts, notifications) — any well-kept
  package with no analytics/network code, checked before adding.
- Exact exercise list and the icon drawing work.
- Code structure, tests, the exact prompt wording for the AI.
- Exact split templates within the rules in 8.2.
