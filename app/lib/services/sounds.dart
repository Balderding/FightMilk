import 'package:audioplayers/audioplayers.dart';

/// Reward sounds (our own, synthesised by tools/gen_sounds.py). Mode: 'cute' (uwu), 'simple', 'off'.
enum Reward { set, exercise, workout, restOver }

class Sounds {
  AudioPlayer? _p; // made on first use, so a phone with sounds off never starts the player
  String mode = 'cute';
  bool muted = false; // tests

  Future<void> play(Reward r) async {
    if (mode == 'off' || muted) return;
    final f = switch (r) {
      Reward.restOver => 'rest_over',
      Reward.set => mode == 'cute' ? 'uwu_set' : 'simple_set',
      Reward.exercise => mode == 'cute' ? 'uwu_exercise' : 'simple_exercise',
      Reward.workout => mode == 'cute' ? 'uwu_workout' : 'simple_workout',
    };
    try {
      final p = _p ??= AudioPlayer();
      await p.stop();
      await p.play(AssetSource('sounds/$f.wav'));
    } catch (_) {
      // no sound is fine; never break a workout over it
    }
  }
}
