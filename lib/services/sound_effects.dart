import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'settings.dart';

/// Efek bunyi jawaban benar dan salah: nada pendek, bukan suara bicara.
///
/// Pengumuman TalkBack tetap ada; bunyi ini hanya tambahan supaya siswa
/// langsung tahu hasilnya. Bisa dimatikan di Profil ([Settings.soundEffects]).
/// Di tes, [soundEffects] diganti tiruan yang hanya mencatat.
class SoundEffects {
  SoundEffects();

  AudioPlayer? _player;

  /// Bunyi untuk jawaban [correct]. Tidak berbunyi kalau dimatikan di Profil.
  /// Kegagalan memutar (misalnya browser memblokir audio) diabaikan.
  Future<void> playAnswer({required bool correct}) async {
    if (!Settings.soundEffects) return;
    await play(correct ? 'sounds/correct.wav' : 'sounds/wrong.wav');
  }

  @protected
  Future<void> play(String asset) async {
    try {
      final player = _player ??= await _create();
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (error) {
      debugPrint('Efek bunyi gagal diputar: $error');
    }
  }

  Future<AudioPlayer> _create() async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);
    // Bunyi sistem untuk aksesibilitas, tanpa meminta fokus audio: suara
    // TalkBack tidak dipotong atau dipelankan.
    await player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );
    return player;
  }
}

/// Dipakai layar soal. Diganti di tes.
SoundEffects soundEffects = SoundEffects();
