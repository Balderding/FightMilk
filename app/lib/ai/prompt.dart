import '../domain/exercise.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/units.dart';
import 'grammar.dart';

/// The fixed instructions: what the AI is for, the exercise list it must pick from, and the JSON
/// shape. Built only from the app's own library and the user's equipment - nothing personal.
const listFormatPlan = '''
PLAN: <short plan name>
DAY: <day name>
exercise_id | sets | reps | rest seconds
exercise_id | sets | reps | rest seconds
DAY: <next day name>
exercise_id | sets | reps | rest seconds

For example:
PLAN: Upper/Lower 4-day
DAY: Upper A
bench_press | 4 | 5-8 | 150
barbell_row | 4 | 6-8 | 120''';

const listFormatDay = '''
DAY: <day name>
exercise_id | sets | reps | rest seconds
exercise_id | sets | reps | rest seconds

For example:
DAY: Upper A
bench_press | 4 | 5-8 | 150
lat_pulldown | 3 | 8-12 | 90''';

String _exerciseList(Library lib, Profile p) => lib
    .available(p.have, p.avoid)
    .map((e) => '${e.id} | ${e.name} | ${e.equipment.name} | ${e.primary.join("/")}${e.compound ? " | compound" : ""}')
    .join('\n');

const _rules = '''
- Use ONLY exercises from this list, by their id (first column). Never invent ids.
- Main lift first on each day.
- sets 1-10, reps as low-high between 1 and 30 (seconds for planks, hangs and carries, up to 120), rest 30-300 seconds in steps of 5.
- At most 12 exercises a day, no exercise twice in one day; fit the session length given.
- Respect "go easy on" joints (those exercises are already left out of the list).''';

/// Instructions to paste once into a Claude Project (or any chat app's saved instructions).
/// Built from this gym's equipment and joints; copy again after changing the setup.
String projectInstructions(Library lib, Profile p) => '''
You are a strength coach helping me through my workout app. I lift weights in a gym.

When I ask for a plan (a rotation of training days I repeat in order), reply in this workout list format, exactly, and nothing else needs to be added:
$listFormatPlan

When I ask to adjust one day, reply with just that day in the same format:
$listFormatDay

When I ask a question, answer in plain everyday words, briefly. If something sounds like pain or injury, tell me to stop that exercise and see a doctor or physiotherapist.

Rules for plans and days:
$_rules

My gym has: ${p.have.map((e) => e.name).join(', ')}. Go easy on: ${p.avoid.isEmpty ? 'nothing' : p.avoid.map((j) => jointLabel[j]!.toLowerCase()).join(', ')}. Weights in ${unitLabel(p.unit)}.

Exercise list (id | name | equipment | muscles):
${_exerciseList(lib, p)}
''';

String systemPrompt(Library lib, Profile p, {required bool wholePlan, bool plainText = false}) {
  if (plainText) {
    return '''
You are a strength coach inside a workout app for people who lift weights in a gym.
${wholePlan ? 'Design a weekly plan: a rotation of named training days the person repeats in order. Make exactly the number of days asked for unless the request says otherwise.' : 'Adjust today\'s workout using the recent training shown.'}

Rules:
$_rules

Reply in this workout list format, exactly:
${wholePlan ? listFormatPlan : listFormatDay}

Exercise list (id | name | equipment | muscles):
${_exerciseList(lib, p)}
''';
  }
  final ex = lib.available(p.have, p.avoid);
  final list = ex.map((e) => '${e.id} | ${e.name} | ${e.equipment.name} | ${e.primary.join("/")}${e.compound ? " | compound" : ""}').join('\n');
  final shape = wholePlan
      ? '{"name": "<short plan name>", "days": [{"name": "<day name>", "items": [{"exercise": "<exercise id>", "sets": 3, "repLow": 8, "repHigh": 12, "rest": 90}]}]}'
      : '{"name": "<day name>", "items": [{"exercise": "<exercise id>", "sets": 3, "repLow": 8, "repHigh": 12, "rest": 90}]}';
  return '''
You are a strength coach inside a workout app for people who lift weights in a gym.
${wholePlan ? 'Design a weekly plan: a rotation of named training days the person repeats in order.' : 'Adjust today\'s workout using the recent training shown.'}

Rules:
- Use ONLY exercises from this list, by their id (first column). Never invent ids.
- Main lift first on each day. ${wholePlan ? 'Make exactly the number of days asked for unless the request says otherwise.' : ''}
- sets 1-10, repLow and repHigh 1-30 (seconds for planks and carries, up to 120), repLow <= repHigh, rest 30-300 seconds in steps of 5.
- At most 12 exercises a day; fit the session length given.
- Respect "go easy on" joints (those exercises are already removed from the list).
- Reply with JSON only, no other text, in exactly this shape:
$shape

Exercise list (id | name | equipment | muscles):
$list
''';
}

Map<String, dynamic> _itemSchema(Library lib, Profile p) => {
      'type': 'object',
      'properties': {
        'exercise': {'type': 'string', 'enum': [for (final e in lib.available(p.have, p.avoid)) e.id]},
        'sets': {'type': 'integer'},
        'repLow': {'type': 'integer'},
        'repHigh': {'type': 'integer'},
        'rest': {'type': 'integer'},
      },
      'required': ['exercise', 'sets', 'repLow', 'repHigh', 'rest'],
      'additionalProperties': false,
    };

Map<String, dynamic> _daySchema(Library lib, Profile p) => {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'items': {'type': 'array', 'items': _itemSchema(lib, p)},
      },
      'required': ['name', 'items'],
      'additionalProperties': false,
    };

/// The exact JSON shape a whole plan must come back in. Exercise ids are limited to what this
/// gym has and the person's joints allow, so the AI cannot pick anything else.
Map<String, dynamic> planSchema(Library lib, Profile p) => {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'days': {'type': 'array', 'items': _daySchema(lib, p)},
      },
      'required': ['name', 'days'],
      'additionalProperties': false,
    };

Map<String, dynamic> daySchema(Library lib, Profile p) => _daySchema(lib, p);

/// Instructions for free questions ("Ask the coach").
String coachPrompt() => '''
You are a friendly, knowledgeable strength coach inside a free workout app for people who lift weights in a gym.
Answer the person's question in plain, everyday words, briefly (a few short paragraphs or a short list at most).
Use their setup and recent training shown in the message when it helps. Be practical: weights, sets, reps, rest, technique cues.
If something sounds like pain or injury, say to stop that exercise and see a doctor or physiotherapist. Do not diagnose.
Plain text only, no markdown headings.
''';

String _joint(Joint j) => jointLabel[j]!.toLowerCase();

/// The request text: setup answers, the current plan or day, recent sets, and the ask.
/// This is exactly what the preview sheet shows. It never carries anything about the person or
/// the phone.
String buildRequest(Profile p, Object? planOrDay, List<SetLog> recent, Library lib, String ask) {
  final u = p.unit;
  final b = StringBuffer()
    ..writeln('Goal: ${p.goal.name}')
    ..writeln('Days per week: ${p.days}')
    ..writeln('Session length: ${p.minutes} minutes')
    ..writeln('Equipment: ${p.have.map((e) => e.name).join(", ")}')
    ..writeln('Go easy on: ${p.avoid.isEmpty ? "nothing" : p.avoid.map(_joint).join(", ")}')
    ..writeln('Weights in: ${unitLabel(u)}');
  if (p.split != null) b.writeln('Wanted split: ${p.split}');

  void day(PlanDay d) {
    b.writeln('${d.name}:');
    for (final i in d.items) {
      b.writeln('  ${lib.byId(i.exerciseId)?.name ?? i.exerciseId} (${i.exerciseId}) ${i.sets} x ${i.repLow}-${i.repHigh}, rest ${i.restSec}s');
    }
  }

  if (planOrDay is Plan) {
    b.writeln('\nCurrent plan:');
    planOrDay.days.forEach(day);
  } else if (planOrDay is PlanDay) {
    b.writeln('\nToday as planned:');
    day(planOrDay);
  }

  if (recent.isNotEmpty) {
    b.writeln('\nRecent sets (weight per dumbbell for dumbbell work):');
    final byDay = <String, Map<String, List<SetLog>>>{};
    for (final s in recent) {
      final d = s.at == null ? '' : '${s.at!.year}-${s.at!.month.toString().padLeft(2, "0")}-${s.at!.day.toString().padLeft(2, "0")}';
      ((byDay[d] ??= {})[s.exerciseId] ??= []).add(s);
    }
    byDay.forEach((d, m) {
      m.forEach((ex, sets) {
        final name = lib.byId(ex)?.name ?? ex;
        b.writeln('  $d $name: ${sets.map((s) => '${fmtWeight(s.kg, u)} ${unitLabel(u)} x ${s.reps}').join(", ")}');
      });
    });
  }
  b.writeln('\nRequest: $ask');
  return b.toString();
}

/// Short instructions for the small model on the phone. The grammar enforces the format and the
/// exercise ids, so the prompt only has to explain the job.
String localSystemPrompt(Library lib, Profile p, {required bool wholePlan}) => '''
You are a strength coach in a workout app for people who lift weights in a gym.
${wholePlan ? 'Make a weekly plan of exactly ${p.days} training days that the person repeats in order. Balance the muscles across the days.' : "Adjust today's workout using the recent training shown. Keep it the same kind of day."}
Put a big compound lift first each day. Use 3-6 reps for strength, 8-12 for size. Rest 120-240 seconds on heavy lifts, 60-90 on small ones.
Answer only in this format:
${wholePlan ? listFormatPlan : listFormatDay}

Exercise ids you may use, by muscle:
${compactExerciseList(lib, p)}
''';

/// Instructions for "Today's guide": a short, practical brief for the session ahead.
String guidePrompt() => '''
You are a friendly strength coach inside a workout app. Write a short guide for the workout shown, for someone about to start it.
Plain text, no markdown headings, at most about 150 words:
- one line on today's focus,
- a quick warm-up (5 minutes, specific to today's first lift),
- one or two key form cues for each of the first two exercises,
- one line on how hard to push today, based on the recent training shown.
Use the weights and reps from the plan and recent sets when they help. Never diagnose pain; if something hurts, say to skip that exercise.
''';

String guideAsk(String dayName) => "Give me a short guide for today's workout ($dayName).";

/// Quick notes the person can add when asking the AI to adjust today.
const todayNotes = {
  'short': 'I only have about 30 minutes today.',
  'tired': 'I am tired today and slept badly.',
  'great': 'I feel great and strong today.',
  'hurts': 'Something hurts a little today; go easy around it.',
  'busy': 'The gym is busy; some machines and racks are taken.',
};
