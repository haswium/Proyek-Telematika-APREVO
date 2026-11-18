import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'settings.dart';

/// Efek bunyi pendek, bukan suara bicara: jawaban benar dan salah, dan
/// membalik halaman panduan.
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

  /// Desis kertas 0,3 detik saat membalik halaman panduan. Ikut saklar efek
  /// bunyi yang sama.
  Future<void> playPageTurn() async {
    if (!Settings.soundEffects) return;
    await play('sounds/page.wav');
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
