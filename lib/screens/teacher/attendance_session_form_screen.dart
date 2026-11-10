import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/attendance.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../services/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';

/// Guru membuka sesi presensi: judul, waktu buka (sekarang atau atur
/// sendiri), dan waktu tutup (pilihan cepat atau atur sendiri).
///
/// Pilihan cepat dan "sekarang" dihitung backend dengan jam server (WIB),
/// bukan jam HP. Jam HP hanya dipakai sebagai nilai awal pemilih tanggal.
class AttendanceSessionFormScreen extends StatefulWidget {
  const AttendanceSessionFormScreen({
    super.key,
    required this.subject,
    required this.suggestedTitle,
  });

  final Subject subject;
  final String suggestedTitle;

  @override
  State<AttendanceSessionFormScreen> createState() =>
      _AttendanceSessionFormScreenState();
}

class _AttendanceSessionFormScreenState
    extends State<AttendanceSessionFormScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.suggestedTitle,
  );

  /// `null` berarti dibuka sekarang.
  DateTime? _opensAt;

  /// `null` berarti waktu tutup diatur sendiri lewat [_closesAt].
  ClosePreset? _preset = ClosePreset.hour1;
  DateTime? _closesAt;

  bool _busy = false;
  String? _error;
  int _errorSerial = 0;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _busy = false;
      _error = message;
      _errorSerial++;
    });
  }

  Future<DateTime?> _pick(DateTime initial, String what) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Pilih tanggal $what',
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Pilih jam $what',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickOpen() async {
    final now = DateTime.now();
    final value = await _pick(
      _opensAt ?? DateTime(now.year, now.month, now.day, now.hour + 1),
      'buka',
    );
    if (value == null || !mounted) return;
    setState(() {
      _opensAt = value;
      _error = null;
    });
    announce('Waktu buka: ${formatDateTime(value)}.');
  }

  Future<void> _pickClose() async {
    final base = _opensAt ?? DateTime.now();
    final value = await _pick(
      _closesAt ?? base.add(const Duration(hours: 1)),
      'tutup',
    );
    if (value == null || !mounted) return;
    setState(() {
      _closesAt = value;
      _error = null;
    });
    announce('Waktu tutup: ${formatDateTime(value)}.');
  }

  Future<void> _save() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError('Judul sesi wajib diisi, misalnya Pertemuan 3.');
      return;
    }
    final closesAt = _closesAt;
    if (_preset == null) {
      if (closesAt == null) {
        _showError('Pilih waktu tutup dengan tombol Atur waktu tutup.');
        return;
      }
      final opensAt = _opensAt;
      if (opensAt != null && !closesAt.isAfter(opensAt)) {
        _showError('Waktu tutup harus setelah waktu buka.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    announce('Membuka sesi $title.');
    try {
      final session = await store.createAttendanceSession(
        widget.subject.id,
        title: title,
        preset: _preset,
        opensAt: _opensAt,
        closesAt: _preset == null ? closesAt : null,
      );
      if (!mounted) return;
      announce(
        session.state == SessionState.open
            ? 'Sesi ${session.title} dibuka, '
                  '${closingPhrase(session.closesAt, DateTime.now())}.'
            : 'Sesi ${session.title} disimpan. ${session.stateText(null)}.',
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Sesi belum dibuka. ${e.message}');
    }
  }

  Widget _timeCard(String title, String value, String button, VoidCallback f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.bodySmall),
                  Text(value, style: AppType.titleMedium),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(button),
              onPressed: _busy ? null : f,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opensAt = _opensAt;
    final closesAt = _closesAt;
    final onPurple = AppType.bodyMedium.copyWith(color: AppColors.white);
    return PurpleScaffold(
      appBar: aprevoAppBar('Buka sesi presensi'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Sesi presensi ${widget.subject.name}',
                style: AppType.headlineMedium.copyWith(color: AppColors.white),
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: TextField(
                controller: _title,
                enabled: !_busy,
                maxLength: 100,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Judul pertemuan',
                  hintText: 'Contoh: Pertemuan 3',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Waktu buka'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChoiceChip(
                  label: 'Sekarang',
                  selected: opensAt == null,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _opensAt = null),
                ),
                AppChoiceChip(
                  label: 'Atur sendiri',
                  selected: opensAt != null,
                  onSelected: _busy ? null : (_) => _pickOpen(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (opensAt != null)
              _timeCard(
                'Waktu buka',
                formatDateTime(opensAt),
                'Ubah waktu buka',
                _pickOpen,
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Sesi langsung dibuka saat disimpan.',
                  style: onPurple,
                ),
              ),
            const SectionTitle('Waktu tutup'),
            Text(
              opensAt == null
                  ? 'Dihitung dari saat sesi dibuka.'
                  : 'Dihitung dari waktu buka.',
              style: onPurple,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in ClosePreset.values)
                  AppChoiceChip(
                    label: preset.label,
                    selected: _preset == preset,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _preset = preset;
                            _error = null;
                          }),
                  ),
                AppChoiceChip(
                  label: 'Atur sendiri',
                  selected: _preset == null,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _preset = null);
                          if (_closesAt == null) _pickClose();
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_preset == null)
              _timeCard(
                'Waktu tutup',
                closesAt == null ? 'Belum dipilih' : formatDateTime(closesAt),
                closesAt == null ? 'Atur waktu tutup' : 'Ubah waktu tutup',
                _pickClose,
              ),
            if (_error != null) ...[
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
              const SizedBox(height: 12),
            ],
            PrimaryButton(
              label: _busy ? 'Menyimpan...' : 'Buka sesi',
              icon: Icons.check,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
