import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/announce.dart';
import '../../services/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';

/// Guru membuat pre-test atau post-test dengan jadwalnya, atau mengubah
/// jadwal kuis yang sudah ada. Mengembalikan `true` lewat Navigator.pop
/// kalau tersimpan.
class QuizScheduleScreen extends StatefulWidget {
  const QuizScheduleScreen({
    super.key,
    required this.materialId,
    required this.kind,
    this.existing,
  });

  final String materialId;
  final TestKind kind;

  /// `null` kalau kuisnya belum dibuat.
  final QuizInfo? existing;

  @override
  State<QuizScheduleScreen> createState() => _QuizScheduleScreenState();
}

class _QuizScheduleScreenState extends State<QuizScheduleScreen> {
  late DateTime _from;
  late DateTime _until;
  bool _busy = false;
  String? _error;
  int _errorSerial = 0;

  String get _label => widget.kind.label;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Bawaan: mulai jam berikutnya, tenggat seminggu kemudian.
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
    _from = widget.existing?.availableFrom ?? nextHour;
    _until = widget.existing?.deadlineAt ?? _from.add(const Duration(days: 7));
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
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
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

  Future<void> _pickFrom() async {
    final value = await _pick(_from, 'buka');
    if (value == null || !mounted) return;
    setState(() {
      // Tenggat ikut bergeser supaya tetap setelah waktu buka.
      if (!_until.isAfter(value)) {
        _until = value.add(_until.difference(_from).abs());
        if (!_until.isAfter(value)) {
          _until = value.add(const Duration(days: 7));
        }
      }
      _from = value;
      _error = null;
    });
    announce('Waktu buka: ${formatDateTime(value)}.');
  }

  Future<void> _pickUntil() async {
    final value = await _pick(_until, 'tenggat');
    if (value == null || !mounted) return;
    setState(() {
      _until = value;
      _error = null;
    });
    announce('Tenggat: ${formatDateTime(value)}.');
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_until.isAfter(_from)) {
      _showError('Tenggat harus setelah waktu buka.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    announce('Menyimpan jadwal $_label.');
    final from = isoWithOffset(_from);
    final until = isoWithOffset(_until);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await store.createQuiz(
          widget.materialId,
          widget.kind,
          availableFrom: from,
          deadlineAt: until,
        );
      } else {
        await store.updateSchedule(
          existing.id,
          availableFrom: from,
          deadlineAt: until,
        );
      }
      if (!mounted) return;
      final message =
          'Jadwal $_label disimpan. Dibuka ${formatDateTime(_from)} sampai '
          '${formatDateTime(_until)}.';
      announce(message);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Jadwal belum tersimpan. ${e.message}');
    }
  }

  Widget _timeCard(String title, DateTime value, VoidCallback onChange) {
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
                  Text(formatDateTime(value), style: AppType.titleMedium),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text('Ubah ${title.toLowerCase()}'),
              onPressed: _busy ? null : onChange,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.existing == null;
    return PurpleScaffold(
      appBar: aprevoAppBar(creating ? 'Buat $_label' : 'Jadwal $_label'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Siswa hanya bisa mengerjakan $_label di antara waktu buka '
              'dan tenggat. Jawaban benar dan pembahasan terbuka setelah '
              'tenggat lewat.',
              style: AppType.bodyMedium,
            ),
            const SizedBox(height: 16),
            _timeCard('Waktu buka', _from, _pickFrom),
            _timeCard('Tenggat', _until, _pickUntil),
            if (_error != null) ...[
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
              const SizedBox(height: 12),
            ],
            PrimaryButton(
              label: _busy
                  ? 'Menyimpan...'
                  : creating
                  ? 'Buat $_label'
                  : 'Simpan jadwal',
              icon: Icons.check,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
