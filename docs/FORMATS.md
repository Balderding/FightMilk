# FightMilk file formats

Every file is made on the phone (Settings → Your data → Export…) and only goes where you save or send it. The app sends nothing by itself.

- **Progress photos are never in any export, share or backup.** They stay in the app's own folder.
- **Body data** (weigh-ins, body fat, tape measurements, height) is only in a file when you say yes. The app asks once per export, for the formats that can hold it: Body CSV, Backup, SQLite, Everything.

All CSV files are UTF-8, comma-separated, with every field in double quotes and CRLF line ends. Weights are in the unit you pick on the Export screen.

## Sets

| Format | Columns |
|---|---|
| Strong CSV | Date, Workout Name, Duration, Exercise Name, Set Order (W / D / F for warm-up / drop / failure sets), Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE |
| Hevy CSV | title, start_time, end_time, description, exercise_title, superset_id, exercise_notes, set_index, set_type (normal / warmup / dropset / failure), weight_kg or weight_lbs, reps, distance_km, duration_seconds, rpe |
| FitNotes CSV | Date, Exercise, Category, Weight (kgs) or Weight (lbs), Reps, Distance, Distance Unit, Time (hh:mm:ss), Comment |
| Liftosaur CSV | Workout DateTime, Program, Day Name, Exercise, Equipment, Is Warmup Set?, Required Reps, Completed Reps, RPE, Completed Weight Value, Completed Weight Unit, Completed Time (best effort; Liftosaur also reads the Strong file) |
| Every column | set_id, workout_id, date, workout, note, set_number, exercise_id, exercise, muscles, equipment, type, kg, lb, reps, seconds, meters, side (L / R), effort (1 easy … 4 all-out), rpe, rest_seconds, e1rm_kg, e1rm_lb, set_note, plan_slot |

## Body, plans, records

| Format | Columns |
|---|---|
| Body CSV | date, what (body weight / body fat / tape), part, side, value, unit |
| Plans CSV | plan, in_use, day, order, exercise_id, exercise, sets, reps_low, reps_high, rest_seconds, last_set, superset |
| Records CSV | exercise, record, value, unit, date |

## Other files

- **Workouts as text (.md):** one `## <workout>, <date> (<minutes> min)` heading per workout, then one line per exercise: `- Back squat: 100 kg × 5, 102.5 kg × 5`. This is the same text as History → a workout → Share.
- **.tcx:** one `Activity Sport="Other"` per workout, with its start time, length and the sets as text in `Notes`. You can upload it yourself to Garmin Connect or Strava. A .fit file is not made: it is binary and gives these sites nothing more for weights.
- **SQLite:** a copy of the app's database. The photo list is removed, and so is the body data unless you said yes. The copy is vacuumed, so nothing deleted is left in it.
- **Backup (JSON):** `{"format": 2, "app": "workout", "schema": 3, "exported": …, "hasBody"?: false, "kv": [...], "plan": [...], "lift_state": [...], "session": [...], "set_log": [...], "body": [...], "ex_note": [...], "sha256": …}`. The `sha256` is a hash of everything else (written as compact JSON). A file whose check does not match, that is cut short, whose rows lack their fields or carry fields the app does not know, whose values cannot be read the way the app reads them (plan, lift, workout day, profile, goals, import list), or whose numbers are impossible (weights, reps, dates before 1990 or in the future) is refused before anything changes, and the restore is one database transaction. Files over 64 MB are refused before they are read. Format 1 (before 0.9, no check) still restores. The import list (`imports`) travels, so an import's Undo works after a restore; a merge adds the file's import records for the workouts that came in. `imports_undone` lists the workouts and weigh-ins of imports that were undone, so a later merge never brings them back. API keys, progress photos, the automatic-backup choice, the server and the backup status are never in it, and "Replace everything" keeps this phone's own. Restore it in Settings → Backup.
- **Locked backup:** `{"fightmilk": "backup-locked", "v": 1, "kdf": "pbkdf2-sha256", "iter": 600000, "salt": …, "nonce": …, "data": …, "mac": …}`. The backup above, encrypted with AES-256-GCM under a key from PBKDF2-HMAC-SHA256 (the round count is in the file, and must be 100 000 to 2 000 000). Without the password nobody can read it, not even the app.
- **Automatic backups:** `fightmilk-auto-YYYY-MM-DD-HHMMSS.json` (or `.locked.json`; the folder may add ` (1)`) in the folder you picked. Only files with exactly this name are ever changed there, never a folder, and the newest are kept by the date in the name. Each is written as `….json.part`, checked, then renamed, so a full folder leaves no empty file; a file under 1 kB never counts as a backup.
- **Spreadsheet (.xlsx):** sheets Workouts (date, workout, minutes, sets, volume, exercises, note), Sets (the every-column layout), Body (only when you said yes), Records and Plans. Numbers are real numbers.
- **Report (PDF):** totals for the dates, the best est. 1-rep max per workout of your 4 most-done lifts as small charts, body weight (only when you said yes) and a table of the workouts.
- **Plan (PDF):** Plan → Share plan → Print it. A page per week (4, or a program's weeks), each day's exercises with a box per set to write weight and reps in.
- **Everything (zip):** the Strong and Every-column CSVs, Plans, Records, Body (when you said yes) and a README.

## Sharing a plan

Plan → Share plan sends only the plan: its name, days, exercises, sets, reps, rest and a program's rules. It never sends your weights, training maxes, body data or photos. There is no server.

- **File (`<name>.fightmilk.json`):** `{"fightmilk": "plan", "v": 1, "name": …, "days": [{"name": …, "items": [{"exercise": "bench_press", "sets": 4, "repLow": 6, "repHigh": 8, "rest": 150, "style"?, "group"?, "perSet"?: [{"r": 5, "h"?: 8, "p"?: 0.85, "a"?: 1}], "tier"?, "tmOf"?, "bump"?}]}], "weeks"?: 4, "program"?: {"id", "basis", "rules"}}`.
- **Link:** `fightmilk://plan#` followed by the same JSON, zlib-compressed and base64url-encoded (no padding). The plan is inside the link; nothing is fetched.
- **QR code:** the link, as one QR code (error correction L). A plan too big for one code says so.
- **Text:** the plan's name, then each day's name and lines like `Bench press 4x6-8, 150s rest`. Plan → Import a plan reads it back.
- **Just one day:** any of the above with one day in it.

A received plan (opened from a link, a QR code, a file or pasted text) is checked before anything is saved:

- It is at most 1 MB, also after unpacking a link.
- It must be the format above, with sane numbers: 1-84 days, 20 exercises a day, 1-20 sets, reps 1-100 (600 seconds for timed exercises), rest 0-900 s, a % of 0-150.
- Exercises this app doesn't have are listed and left out.
- Swaps are offered for exercises your gym lacks or that load a sore joint.
- Own-script progression rules are shown line by line in plain words (the sender's comments are left out) and stay out unless you choose "Use these rules".
- It is always saved as a new plan. A link the app does not know opens nothing.

## Import (Settings → Your data → Import)

The app reads these files on the phone and shows you what it found before anything is saved:

- **Strong CSV:** also FightMilk's own Strong-layout export. W, D and F set orders are read as warm-up, drop and failure sets.
- **Hevy CSV:** `weight_kg` or `weight_lbs`, `set_type`, `duration_seconds`, `distance_km`.
- **FitNotes CSV:** `Weight (kgs)` or `Weight (lbs)`, `Time` as hh:mm:ss.
- **Liftosaur CSV:** each row's unit, and `Is Warmup Set?`.
- **Fitbod CSV:** `Weight(kg)`, `isWarmup`.
- **FightMilk's every-column CSV**, in kg.
- **Any other CSV with a header row:** columns named like Date, Exercise, Weight (or Load, kg, lbs), Reps, and optionally Workout, Unit, RPE, Note. A file with a date and a weight but no exercise is read as a body weight log (with an optional body fat column).

Rules:

- **Size:** at most 8 MB, 200 000 rows, 300 sets in one workout, 200 columns and 300 characters per cell. Weights up to 700 kg, reps up to 1000, times up to a day, distances up to 1000 km, body weights 20-400 kg; anything else is a left-out row with its reason.
- **Numbers:** `100`, `102,5`, `1,234.5`, `1.234,5`, and `100 kg` / `225 lbs` with their unit. `1,005` could be a thousand or a decimal, so that row is left out. An empty weight is 0 (bodyweight).
- **Cells:** hidden and bidi marks are removed. The `'` that CSV exports put before text like `=1+1` is taken off; the app never runs cell text, and its own exports put the guard back.
- **Units:** taken from the file when it says (a column name or a per-row unit). Otherwise it uses your unit and says so in gold, so you can change it.
- **Dates:** ISO, `2026/11/05`, `5 Nov 2026, 18:30`, `Nov 5, 2026 6:30 PM`, and `05/06/2026` (you pick day-first or month-first when every date reads both ways).
- **Exercise names** are matched to the app's library ("Bench Press (Barbell)" → Bench press). Names it can't match are listed; you pick one, or they are left out.
- **Duplicates:** an import only adds. Workouts that start within 2 minutes of one already on the phone are left out unless you switch them in.
- **Undo:** each import is listed with Undo, which takes its workouts and weigh-ins out again. Progression (the next weights) is worked out again from the history after an import and after an undo.
