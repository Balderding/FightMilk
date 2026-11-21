import 'package:uuid/uuid.dart';

import 'exercise.dart';

/// Gym profiles: what is actually in the room.
///
/// The 8 equipment kinds (barbell, machine, ...) are too coarse: "machines" said yes to all 41
/// machine exercises, including a hack squat your gym may not have. A gym here is a list of real
/// items (a leg press, a Smith machine, a pull-up bar, dumbbells...), and each exercise says which
/// items it needs. The active gym's list decides what the plan maker, swaps, checks and the AI
/// may use. With no gym set up the app works as before (by kinds).

class GymItem {
  final String id;
  final String label;
  final String area;
  const GymItem(this.id, this.label, this.area);
}

/// Areas in walk-through order (how you would walk round a gym).
const gymAreas = <String, String>{
  'machines': 'Machines (pin-loaded)',
  'plate': 'Plate-loaded machines',
  'cables': 'Cables',
  'racks': 'Smith machine, racks and bars',
  'benches': 'Benches',
  'free': 'Free weights',
  'stations': 'Bodyweight stations',
  'functional': 'Functional area',
};

const gymItems = <GymItem>[
  // machines
  GymItem('chest_press_m', 'Chest press machine', 'machines'),
  GymItem('incline_press_m', 'Incline press machine', 'machines'),
  GymItem('pec_deck', 'Pec deck / rear delt fly', 'machines'),
  GymItem('shoulder_press_m', 'Shoulder press machine', 'machines'),
  GymItem('lateral_raise_m', 'Lateral raise machine', 'machines'),
  GymItem('row_m', 'Seated row machine', 'machines'),
  GymItem('lat_pulldown', 'Lat pulldown', 'machines'),
  GymItem('seated_row_station', 'Seated cable row', 'machines'),
  GymItem('assisted_pullup', 'Assisted pull-up machine', 'machines'),
  GymItem('dip_m', 'Seated dip machine', 'machines'),
  GymItem('pullover_m', 'Pullover machine', 'machines'),
  GymItem('leg_press', 'Leg press (sled, plate-loaded)', 'machines'),
  GymItem('seated_leg_press', 'Seated leg press (pin-loaded)', 'machines'),
  GymItem('leg_ext', 'Leg extension', 'machines'),
  GymItem('seated_curl', 'Seated leg curl', 'machines'),
  GymItem('lying_curl', 'Lying leg curl', 'machines'),
  GymItem('standing_curl', 'Standing leg curl', 'machines'),
  GymItem('abductor', 'Hip abductor (out)', 'machines'),
  GymItem('adductor', 'Hip adductor (in)', 'machines'),
  GymItem('glute_kick_m', 'Glute kickback machine', 'machines'),
  GymItem('hip_thrust_m', 'Hip thrust / glute drive machine', 'machines'),
  GymItem('standing_calf', 'Standing calf raise machine', 'machines'),
  GymItem('seated_calf', 'Seated calf raise', 'machines'),
  GymItem('donkey_calf', 'Donkey calf raise', 'machines'),
  GymItem('preacher_m', 'Biceps curl machine', 'machines'),
  GymItem('triceps_m', 'Triceps extension machine', 'machines'),
  GymItem('shrug_m', 'Shrug machine', 'machines'),
  GymItem('crunch_m', 'Ab crunch machine', 'machines'),
  GymItem('back_ext', 'Back extension bench', 'machines'),
  GymItem('reverse_hyper_m', 'Reverse hyper', 'machines'),
  GymItem('ghd', 'Glute-ham developer (GHD)', 'machines'),
  // plate-loaded
  GymItem('plate_chest_press', 'Plate-loaded chest press', 'plate'),
  GymItem('plate_row', 'Plate-loaded row', 'plate'),
  GymItem('hack_squat', 'Hack squat', 'plate'),
  GymItem('pendulum', 'Pendulum squat', 'plate'),
  GymItem('belt_squat', 'Belt squat', 'plate'),
  GymItem('v_squat', 'V-squat', 'plate'),
  GymItem('t_bar', 'T-bar row', 'plate'),
  GymItem('sled', 'Push sled', 'plate'),
  // cables
  GymItem('cable_tower', 'Cable tower / crossover / dual pulley', 'cables'),
  // racks and bars
  GymItem('smith', 'Smith machine', 'racks'),
  GymItem('power_rack', 'Power rack / squat rack', 'racks'),
  GymItem('barbell', 'Olympic barbell and plates', 'racks'),
  GymItem('fixed_barbells', 'Fixed-weight barbells', 'racks'),
  GymItem('ez_bar', 'EZ curl bar', 'racks'),
  GymItem('trap_bar', 'Trap / hex bar', 'racks'),
  GymItem('safety_bar', 'Safety squat bar', 'racks'),
  GymItem('landmine', 'Landmine', 'racks'),
  GymItem('bench_station', 'Flat bench press station', 'racks'),
  GymItem('incline_station', 'Incline bench press station', 'racks'),
  GymItem('decline_station', 'Decline bench press station', 'racks'),
  // benches
  GymItem('flat_bench', 'Flat bench', 'benches'),
  GymItem('adj_bench', 'Adjustable bench (incline)', 'benches'),
  GymItem('preacher_bench', 'Preacher bench', 'benches'),
  GymItem('ab_bench', 'Ab / decline sit-up bench', 'benches'),
  // free weights
  GymItem('dumbbells', 'Dumbbells', 'free'),
  GymItem('kettlebells', 'Kettlebells', 'free'),
  GymItem('plates_loose', 'Loose weight plates', 'free'),
  GymItem('bands', 'Resistance bands', 'free'),
  // bodyweight stations
  GymItem('pullup_bar', 'Pull-up bar', 'stations'),
  GymItem('dip_station', 'Dip station', 'stations'),
  GymItem('captains_chair', "Captain's chair (knee raise / dip)", 'stations'),
  // functional
  GymItem('trx', 'TRX / suspension straps', 'functional'),
  GymItem('med_ball', 'Medicine balls', 'functional'),
  GymItem('box', 'Plyo box', 'functional'),
  GymItem('ab_wheel', 'Ab wheel', 'functional'),
  GymItem('wrist_roller', 'Wrist roller', 'functional'),
];

final gymItemById = {for (final i in gymItems) i.id: i};

/// Which items an exercise needs. Each inner set is one way to do it; any one that the gym has
/// all of is enough. Empty list = needs nothing (bodyweight).
const _needs = <String, List<Set<String>>>{
  // machines
  'machine_chest_press': [{'chest_press_m'}],
  'incline_machine_press': [{'incline_press_m'}],
  'pec_deck': [{'pec_deck'}],
  'reverse_pec_deck': [{'pec_deck'}],
  'machine_shoulder_press': [{'shoulder_press_m'}],
  'machine_lateral_raise': [{'lateral_raise_m'}],
  'chest_supported_row': [{'row_m'}],
  'machine_row': [{'row_m'}],
  'machine_pulldown': [{'lat_pulldown'}],
  'lat_pulldown': [{'lat_pulldown'}],
  'close_grip_pulldown': [{'lat_pulldown'}],
  'single_arm_pulldown': [{'lat_pulldown'}, {'cable_tower'}],
  'seated_cable_row': [{'seated_row_station'}],
  'cable_row_wide': [{'seated_row_station'}],
  'single_arm_cable_row': [{'seated_row_station'}, {'cable_tower'}],
  'assisted_pull_up': [{'assisted_pullup'}],
  'machine_dip': [{'dip_m'}, {'assisted_pullup'}],
  'machine_pullover': [{'pullover_m'}],
  'leg_press': [{'leg_press'}],
  'leg_press_single': [{'leg_press'}, {'seated_leg_press'}],
  'leg_press_calf_raise': [{'leg_press'}, {'seated_leg_press'}],
  'horizontal_leg_press': [{'seated_leg_press'}],
  'leg_extension': [{'leg_ext'}],
  'single_leg_extension': [{'leg_ext'}],
  'seated_leg_curl': [{'seated_curl'}],
  'lying_leg_curl': [{'lying_curl'}],
  'standing_leg_curl': [{'standing_curl'}],
  'hip_abduction': [{'abductor'}],
  'hip_adduction': [{'adductor'}],
  'machine_glute_kickback': [{'glute_kick_m'}],
  'machine_hip_thrust': [{'hip_thrust_m'}],
  'standing_calf_raise': [{'standing_calf'}],
  'seated_calf_raise': [{'seated_calf'}],
  'donkey_calf_raise': [{'donkey_calf'}],
  'preacher_curl_machine': [{'preacher_m'}],
  'machine_triceps_ext': [{'triceps_m'}],
  'machine_shrug': [{'shrug_m'}],
  'machine_crunch': [{'crunch_m'}],
  'captains_chair': [{'captains_chair'}],
  'back_extension': [{'back_ext'}],
  'reverse_hyper': [{'reverse_hyper_m'}],
  'glute_ham_raise': [{'ghd'}],
  // plate-loaded
  'hammer_chest_press': [{'plate_chest_press'}],
  'iso_lateral_row': [{'plate_row'}],
  'hack_squat': [{'hack_squat'}],
  'pendulum_squat': [{'pendulum'}],
  'belt_squat': [{'belt_squat'}],
  'v_squat': [{'v_squat'}],
  'sled_push': [{'sled'}],
  't_bar_row': [{'t_bar'}, {'barbell', 'landmine'}],
  // barbell
  'back_squat': [{'barbell', 'power_rack'}],
  'front_squat': [{'barbell', 'power_rack'}],
  'box_squat': [{'barbell', 'power_rack'}],
  'pause_squat': [{'barbell', 'power_rack'}],
  'zercher_squat': [{'barbell', 'power_rack'}],
  'safety_bar_squat': [{'barbell', 'power_rack', 'safety_bar'}],
  'barbell_split_squat': [{'barbell', 'power_rack'}],
  'reverse_lunge': [{'barbell', 'power_rack'}],
  'rack_pull': [{'barbell', 'power_rack'}],
  'good_morning': [{'barbell', 'power_rack'}],
  'barbell_calf_raise': [{'barbell', 'power_rack'}],
  'overhead_press': [{'barbell', 'power_rack'}],
  'push_press': [{'barbell', 'power_rack'}],
  'z_press': [{'barbell', 'power_rack'}],
  'seated_barbell_press': [{'barbell', 'power_rack', 'adj_bench'}],
  'bench_press': [{'barbell', 'bench_station'}, {'barbell', 'power_rack', 'flat_bench'}],
  'close_grip_bench': [{'barbell', 'bench_station'}, {'barbell', 'power_rack', 'flat_bench'}],
  'reverse_grip_bench': [{'barbell', 'bench_station'}, {'barbell', 'power_rack', 'flat_bench'}],
  'jm_press': [{'barbell', 'bench_station'}, {'barbell', 'power_rack', 'flat_bench'}],
  'incline_bench_press': [{'barbell', 'incline_station'}, {'barbell', 'power_rack', 'adj_bench'}],
  'decline_bench_press': [{'barbell', 'decline_station'}],
  'floor_press': [{'barbell'}],
  'landmine_chest_press': [{'barbell', 'landmine'}],
  'landmine_press': [{'barbell', 'landmine'}],
  'landmine_rotation': [{'barbell', 'landmine'}],
  'meadows_row': [{'barbell', 'landmine'}],
  'trap_bar_deadlift': [{'trap_bar'}],
  'trap_bar_shrug': [{'trap_bar'}],
  'trap_bar_carry': [{'trap_bar'}],
  'ez_bar_curl': [{'ez_bar'}, {'fixed_barbells'}],
  'ez_preacher_curl': [{'ez_bar', 'preacher_bench'}, {'fixed_barbells', 'preacher_bench'}],
  'skull_crusher': [{'barbell', 'flat_bench'}, {'ez_bar', 'flat_bench'}, {'fixed_barbells', 'flat_bench'}],
  'seal_row': [{'barbell', 'flat_bench'}],
  'hip_thrust': [{'barbell', 'flat_bench'}],
  'barbell_glute_bridge': [{'barbell'}],
  // light barbell work a fixed-weight bar does fine
  'barbell_curl': [{'barbell'}, {'fixed_barbells'}],
  'reverse_curl': [{'barbell'}, {'fixed_barbells'}, {'ez_bar'}],
  'drag_curl': [{'barbell'}, {'fixed_barbells'}],
  'barbell_upright_row': [{'barbell'}, {'fixed_barbells'}, {'ez_bar'}],
  'barbell_front_raise': [{'barbell'}, {'fixed_barbells'}],
  'barbell_row': [{'barbell'}, {'fixed_barbells'}],
  'yates_row': [{'barbell'}, {'fixed_barbells'}],
  'romanian_deadlift': [{'barbell'}, {'fixed_barbells'}],
  'stiff_leg_deadlift': [{'barbell'}, {'fixed_barbells'}],
  'barbell_shrug': [{'barbell'}, {'fixed_barbells'}],
  'barbell_wrist_curl': [{'barbell'}, {'fixed_barbells'}, {'ez_bar'}],
  // dumbbells on a bench
  'db_bench_press': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'db_fly': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'db_skull_crusher': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'tate_press': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'db_pullover': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'one_arm_db_row': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'db_hip_thrust': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'db_leg_curl': [{'dumbbells', 'flat_bench'}, {'dumbbells', 'adj_bench'}],
  'incline_db_press': [{'dumbbells', 'adj_bench'}],
  'incline_db_fly': [{'dumbbells', 'adj_bench'}],
  'incline_db_curl': [{'dumbbells', 'adj_bench'}],
  'chest_supported_db_row': [{'dumbbells', 'adj_bench'}],
  'chest_supported_rear_fly': [{'dumbbells', 'adj_bench'}],
  'seated_db_press': [{'dumbbells', 'adj_bench'}],
  'arnold_press': [{'dumbbells', 'adj_bench'}],
  'spider_curl': [{'dumbbells', 'adj_bench'}],
  'decline_db_press': [{'dumbbells', 'decline_station'}, {'dumbbells', 'ab_bench'}],
  'db_preacher_curl': [{'dumbbells', 'preacher_bench'}],
  'db_step_up': [{'dumbbells', 'box'}, {'dumbbells', 'flat_bench'}],
  // bands
  'band_assisted_pull_up': [{'bands', 'pullup_bar'}],
  // bodyweight stations
  'pull_up': [{'pullup_bar'}, {'assisted_pullup'}],
  'chin_up': [{'pullup_bar'}, {'assisted_pullup'}],
  'neutral_grip_pull_up': [{'pullup_bar'}, {'assisted_pullup'}],
  'dead_hang': [{'pullup_bar'}, {'assisted_pullup'}],
  'chin_up_hold': [{'pullup_bar'}, {'assisted_pullup'}],
  'toes_to_bar': [{'pullup_bar'}],
  'hanging_leg_raise': [{'pullup_bar'}, {'captains_chair'}],
  'dips': [{'dip_station'}, {'captains_chair'}, {'assisted_pullup'}],
  'weighted_dip': [{'dip_station'}, {'captains_chair'}],
  'inverted_row': [{'smith'}, {'power_rack'}, {'trx'}],
  'trx_row': [{'trx'}],
  'bench_dip': [{'flat_bench'}, {'adj_bench'}],
  'ab_wheel': [{'ab_wheel'}],
  'decline_situp': [{'ab_bench'}],
  'box_jump': [{'box'}],
  'med_ball_slam': [{'med_ball'}],
  'wrist_roller': [{'wrist_roller'}],
  'plate_front_raise': [{'plates_loose'}, {'barbell'}],
  'plate_pinch': [{'plates_loose'}, {'barbell'}],
  'plate_neck_curl': [{'plates_loose'}, {'barbell'}],
  'svend_press': [{'plates_loose'}, {'barbell'}],
};

/// The default need by kind, for exercises not listed above.
List<Set<String>> _byKind(Equipment k) => switch (k) {
      Equipment.barbell => [{'barbell'}],
      Equipment.dumbbell => [{'dumbbells'}],
      Equipment.machine => [{'__unmapped_machine__'}],
      Equipment.cable => [{'cable_tower'}],
      Equipment.smith => [{'smith'}],
      Equipment.kettlebell => [{'kettlebells'}],
      Equipment.band => [{'bands'}],
      Equipment.bodyweight => const [],
    };

/// Needs of your own exercises (set when the library is built; see AppState).
final Map<String, List<Set<String>>> customNeeds = {};

List<Set<String>> needsOf(Exercise e) => customNeeds[e.id] ?? _needs[e.id] ?? _byKind(e.equipment);

bool gymAllows(Exercise e, Set<String> items) {
  final n = needsOf(e);
  return n.isEmpty || n.any((opt) => items.containsAll(opt));
}

/// What the gym is missing for [e], in plain words (the easiest way to get it).
String missingFor(Exercise e, Set<String> items) {
  final n = needsOf(e);
  if (n.isEmpty) return '';
  final best = [...n]..sort((a, b) => a.difference(items).length.compareTo(b.difference(items).length));
  return best.first.difference(items).map((i) => (gymItemById[i]?.label ?? i).toLowerCase()).join(' and ');
}

/// The 8 old kinds a gym counts as having (the setup screen and older checks use them).
Set<Equipment> kindsOf(Set<String> items) => {
      Equipment.bodyweight,
      if (items.contains('dumbbells')) Equipment.dumbbell,
      if (items.any((i) => {'barbell', 'fixed_barbells', 'ez_bar', 'trap_bar'}.contains(i))) Equipment.barbell,
      if (items.any((i) => gymItemById[i]?.area == 'machines' || gymItemById[i]?.area == 'plate')) Equipment.machine,
      if (items.contains('cable_tower') || items.contains('lat_pulldown') || items.contains('seated_row_station')) Equipment.cable,
      if (items.contains('smith')) Equipment.smith,
      if (items.contains('kettlebells')) Equipment.kettlebell,
      if (items.contains('bands')) Equipment.band,
    };

class Gym {
  final String id;
  final String name;
  final Set<String> items;
  final double? maxDumbbellKg; // heaviest dumbbell; null = not set
  final double? barKg; // the barbell; null = standard (20 kg / 45 lb)
  final double smithKg; // what the Smith bar counts as (many are counterbalanced: 0)
  final List<double>? plates; // plate sizes in [platesUnit]; null = the standard set
  final String platesUnit; // 'kg' or 'lb'
  const Gym({required this.id, required this.name, required this.items, this.maxDumbbellKg, this.barKg, this.smithKg = 0, this.plates, this.platesUnit = 'lb'});

  factory Gym.create(String name, Set<String> items, {double? maxDumbbellKg}) => Gym(id: const Uuid().v4(), name: name, items: items, maxDumbbellKg: maxDumbbellKg);

  Gym copyWith({String? name, Set<String>? items, double? maxDumbbellKg, bool clearMaxDb = false, double? barKg, double? smithKg, List<double>? plates, String? platesUnit}) => Gym(
      id: id,
      name: name ?? this.name,
      items: items ?? this.items,
      maxDumbbellKg: clearMaxDb ? null : (maxDumbbellKg ?? this.maxDumbbellKg),
      barKg: barKg ?? this.barKg,
      smithKg: smithKg ?? this.smithKg,
      plates: plates ?? this.plates,
      platesUnit: platesUnit ?? this.platesUnit);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.toList()..sort(),
        'maxDb': maxDumbbellKg,
        if (barKg != null) 'bar': barKg,
        if (smithKg != 0) 'smith': smithKg,
        if (plates != null) 'plates': plates,
        'platesUnit': platesUnit,
      };

  factory Gym.fromJson(Map<String, dynamic> j) => Gym(
        id: j['id'] as String,
        name: j['name'] as String,
        items: {for (final i in (j['items'] as List)) if (gymItemById.containsKey(i)) i as String},
        maxDumbbellKg: (j['maxDb'] as num?)?.toDouble(),
        barKg: (j['bar'] as num?)?.toDouble(),
        smithKg: ((j['smith'] ?? 0) as num).toDouble(),
        plates: j['plates'] == null ? null : [for (final x in j['plates'] as List) (x as num).toDouble()],
        platesUnit: (j['platesUnit'] ?? 'lb') as String,
      );
}

class GymTemplate {
  final String id;
  final String label;
  final String note;
  final Set<String> items;
  final double? maxDumbbellKg;
  const GymTemplate(this.id, this.label, this.note, this.items, {this.maxDumbbellKg});
}

/// Starting points; you then tick what your gym really has (walk-through).
const gymTemplates = <GymTemplate>[
  GymTemplate(
    'planet_fitness',
    'Planet Fitness',
    'The usual Planet Fitness set-up: pin-loaded machines, Smith machines instead of squat racks, cable towers, dumbbells to about 75 lb, fixed-weight bars, functional area. Clubs differ: tick plate-loaded machines (hack squat, leg press) or a rack if yours has them.',
    {
      'chest_press_m', 'incline_press_m', 'pec_deck', 'shoulder_press_m', 'row_m', 'lat_pulldown', 'seated_row_station', 'assisted_pullup',
      'seated_leg_press', 'leg_ext', 'seated_curl', 'abductor', 'adductor', 'preacher_m', 'triceps_m', 'crunch_m', 'back_ext',
      'cable_tower', 'smith', 'fixed_barbells', 'flat_bench', 'adj_bench', 'ab_bench', 'dumbbells', 'kettlebells', 'plates_loose', 'bands',
      'captains_chair', 'trx', 'med_ball',
    },
    maxDumbbellKg: 34,
  ),
  GymTemplate(
    'commercial',
    'Big commercial gym',
    'A full gym: racks and platforms, plate-loaded and pin-loaded machines, cables, dumbbells to 50 kg / 120 lb.',
    {
      'chest_press_m', 'incline_press_m', 'pec_deck', 'shoulder_press_m', 'lateral_raise_m', 'row_m', 'lat_pulldown', 'seated_row_station', 'assisted_pullup',
      'leg_press', 'seated_leg_press', 'leg_ext', 'seated_curl', 'lying_curl', 'abductor', 'adductor', 'hip_thrust_m', 'standing_calf', 'seated_calf',
      'preacher_m', 'triceps_m', 'crunch_m', 'back_ext', 'plate_chest_press', 'plate_row', 'hack_squat', 't_bar',
      'cable_tower', 'smith', 'power_rack', 'barbell', 'fixed_barbells', 'ez_bar', 'trap_bar', 'landmine', 'bench_station', 'incline_station', 'decline_station',
      'flat_bench', 'adj_bench', 'preacher_bench', 'ab_bench', 'dumbbells', 'kettlebells', 'plates_loose', 'bands',
      'pullup_bar', 'dip_station', 'captains_chair', 'trx', 'med_ball', 'box', 'ab_wheel',
    },
    maxDumbbellKg: 50,
  ),
  GymTemplate('home_garage', 'Home garage gym', 'A rack, a barbell and plates, a bench, dumbbells and a pull-up bar.',
      {'power_rack', 'barbell', 'flat_bench', 'adj_bench', 'dumbbells', 'plates_loose', 'pullup_bar', 'bands'}),
  GymTemplate('hotel', 'Hotel or apartment gym', 'A rack of light dumbbells, an adjustable bench and maybe a cable machine.', {'dumbbells', 'adj_bench', 'flat_bench'}, maxDumbbellKg: 23),
  GymTemplate('bodyweight', 'Bodyweight only', 'Nothing but you (and a floor). Add a pull-up bar or bands if you have them.', {}),
  GymTemplate('empty', 'Start empty', 'Tick everything yourself.', {}),
];
