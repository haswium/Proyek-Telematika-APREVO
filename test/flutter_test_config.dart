import 'dart:async';

import 'package:aprevo/services/settings.dart';
import 'package:aprevo/services/sound_effects.dart';

import 'fake_sound.dart';

/// Berlaku untuk semua tes: efek bunyi tidak pernah memanggil plugin audio,
/// dan pengaturan perangkat kembali ke bawaan.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  soundEffects = FakeSoundEffects();
  Settings.reset();
  // Dialog tawaran panduan menutupi beranda di tes lain. Tes panduan
  // menyalakannya sendiri.
  Settings.offerGuide = false;
  await testMain();
}
