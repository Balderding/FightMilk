import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'exercise.dart';
import 'gym.dart';

/// The exercise library: the bundled list plus anything a signed pack added.
class Library {
  final List<Exercise> all;
  final Map<String, Exercise> _byId;

  Library(List<Exercise> list)
      : all = List.unmodifiable(list),
        _byId = {for (final e in list) e.id: e};

  factory Library.fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return Library([for (final e in j['exercises'] as List) Exercise.fromJson(e as Map<String, dynamic>)]);
  }

  static Future<Library> load() async => Library.fromJsonString(await rootBundle.loadString('assets/exercises.json'));

  /// A new library with [extra] added; an extra with an existing id replaces it.
  Library merged(List<Exercise> extra) {
    final m = Map<String, Exercise>.from(_byId);
    for (final e in extra) {
      m[e.id] = e;
    }
    return Library(m.values.toList());
  }

  Exercise? byId(String id) => _byId[id];

  /// An id, or an exercise name typed the way people (or chat apps) write it.
  Exercise? find(String s) {
    final t = s.trim();
    final exact = _byId[t] ?? _byId[t.toLowerCase()];
    if (exact != null) return exact;
    String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final n = norm(t);
    if (n.isEmpty) return null;
    for (final e in all) {
      if (norm(e.name) == n || norm(e.id) == n) return e;
    }
    return null;
  }

  /// Bodyweight work is assumed possible in any gym.
  /// Exercises you hid (never in plans, swaps or the picker's gym list) and favourites (first).
  final Set<String> hidden = {};
  final Set<String> favs = {};

  /// With [items] (a gym profile) the gym's real equipment decides; without, the 8 kinds do.
  bool usable(Exercise e, Set<Equipment> have, Set<Joint> avoid, {Set<String>? items}) =>
      !hidden.contains(e.id) && (items != null ? gymAllows(e, items) : (have.contains(e.equipment) || e.equipment == Equipment.bodyweight)) && e.joints.intersection(avoid).isEmpty;

  List<Exercise> available(Set<Equipment> have, Set<Joint> avoid, {Set<String>? items}) => [for (final e in all) if (usable(e, have, avoid, items: items)) e];

  /// Other exercises for the same muscles that this gym has. Ones that avoid sore joints come first.
  List<Exercise> swapsFor(Exercise e, Set<Equipment> have, Set<Joint> avoid, {Set<String>? items}) => [
        for (final x in all)
          if (x.swap == e.swap && x.id != e.id && usable(x, have, avoid, items: items)) x
      ];

  List<Exercise> search(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return all;
    return [
      for (final e in all)
        if (e.name.toLowerCase().contains(s) || e.primary.any((m) => m.contains(s)) || e.equipment.name.contains(s)) e
    ];
  }
}
