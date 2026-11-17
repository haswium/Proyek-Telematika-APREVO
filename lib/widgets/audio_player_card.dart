import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/material_file.dart';
import '../services/announce.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Lompatan tombol Mundur dan Maju.
const Duration kAudioSkip = Duration(seconds: 10);

/// Pemutar audio yang dipakai kartu ini. Diganti tiruan di tes.
abstract class LessonAudioPlayer {
  Stream<Duration> get positions;
  Stream<void> get completed;
  Future<void> play(String url, Duration from);
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class _AudioPlayersLessonPlayer implements LessonAudioPlayer {
  final _player = AudioPlayer();

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Stream<void> get completed => _player.onPlayerComplete;

  @override
  Future<void> play(String url, Duration from) =>
      _player.play(UrlSource(url), position: from);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Membuat pemutar untuk satu kartu. Diganti di tes.
LessonAudioPlayer Function() createLessonAudioPlayer =
    _AudioPlayersLessonPlayer.new;

/// Pemutar audio asli materi audio, di layar baca siswa dan guru.
///
/// Empat tombol berlabel jelas, tanpa gestur geser: Putar audio / Jeda audio
/// (satu tombol yang labelnya berganti), Mundur 10 detik, dan Maju 10 detik.
/// Tidak diputar otomatis. Posisi dibaca sebagai teks ("1 menit 20 detik dari
/// 5 menit") dan diumumkan saat dijeda atau digeser, tidak setiap detik.
class AudioPlayerCard extends StatefulWidget {
  const AudioPlayerCard({
    super.key,
    required this.materialId,
    this.durationSeconds,
  });

  final String materialId;
  final int? durationSeconds;

  @override
  State<AudioPlayerCard> createState() => _AudioPlayerCardState();
}

class _AudioPlayerCardState extends State<AudioPlayerCard> {
  LessonAudioPlayer? _player;
  final _subscriptions = <StreamSubscription<Object?>>[];
  MaterialAudio? _audio;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  int _errorSerial = 0;

  Duration? get _length {
    final seconds = _audio?.durationSeconds ?? widget.durationSeconds;
    return seconds == null ? null : Duration(seconds: seconds);
  }

  String get _positionText {
    final length = _length;
    final now = spokenDuration(_position);
    return length == null ? now : '$now dari ${spokenDuration(length)}';
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  LessonAudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = createLessonAudioPlayer();
    _subscriptions
      ..add(
        player.positions.listen((position) {
          if (mounted) setState(() => _position = position);
        }),
      )
      ..add(
        player.completed.listen((_) {
          if (!mounted) return;
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
          announce('Audio selesai.');
        }),
      );
    return _player = player;
  }

  void _showError(String message) {
    setState(() {
      _loading = false;
      _playing = false;
      _error = message;
      _errorSerial++;
    });
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final player = _ensurePlayer();
    if (_playing) {
      await player.pause();
      if (!mounted) return;
      setState(() => _playing = false);
      announce('Audio dijeda di $_positionText.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Alamatnya berlaku 1 jam, jadi diminta saat pertama diputar.
      final audio = _audio ??= await store.materialAudio(widget.materialId);
      await player.play(audio.url, _position);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playing = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Audio belum bisa diputar. ${e.message}');
    } catch (_) {
      if (!mounted) return;
      // Alamat lama mungkin sudah kedaluwarsa: minta lagi saat dicoba ulang.
      _audio = null;
      _showError('Audio belum bisa diputar. Periksa internet, lalu coba lagi.');
    }
  }

  Future<void> _skip(Duration delta) async {
    final length = _length;
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (length != null && target > length) target = length;
    final player = _player;
    if (player != null && (_playing || _audio != null)) {
      await player.seek(target);
    }
    if (!mounted) return;
    setState(() => _position = target);
    announce('Posisi $_positionText.');
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playLabel = _loading
        ? 'Menyiapkan audio'
        : _playing
        ? 'Jeda audio'
        : 'Putar audio';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Audio materi', style: AppType.titleMedium),
          ),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            label: 'Posisi audio: $_positionText',
            excludeSemantics: true,
            child: Text(_positionText, style: AppType.bodyMedium),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: playLabel,
            icon: _playing ? Icons.pause : Icons.play_arrow,
            onPressed: _loading ? null : _toggle,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _button(
                  label: 'Mundur 10 detik',
                  icon: Icons.replay_10,
                  onPressed: () => _skip(-kAudioSkip),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _button(
                  label: 'Maju 10 detik',
                  icon: Icons.forward_10,
                  onPressed: () => _skip(kAudioSkip),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
          ],
        ],
      ),
    );
  }
}
