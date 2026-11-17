import 'package:aprevo/services/sound_effects.dart';

/// Mencatat bunyi yang diputar, tanpa plugin audio.
class FakeSoundEffects extends SoundEffects {
  final played = <String>[];

  @override
  Future<void> play(String asset) async => played.add(asset);
}

FakeSoundEffects get fakeSound => soundEffects as FakeSoundEffects;
