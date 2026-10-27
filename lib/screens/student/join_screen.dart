import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/announce.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../../widgets/mascot.dart';
import 'subject_screen.dart';

/// Beranda siswa: memasukkan kode akses kelas, dan daftar kelas yang sudah
/// diikuti. Satu kode membuka satu kelas beserta semua materi publiknya.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key, required this.studentName});

  final String studentName;

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final _code = TextEditingController();
  bool _joining = false;
  String? _error;
  int _errorSerial = 0;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _error = message;
      _errorSerial++;
    });
  }

  /// Pesan sukses: TalkBack lewat announce, tanpa TalkBack lewat suara.
  void _say(String message) {
    announce(message);
  }

  void _open(Subject subject) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: kMaterialListRoute,
        builder: (_) => StudentSubjectScreen(
          subject: subject,
          studentName: widget.studentName,
        ),
      ),
    );
  }

  Future<void> _join() async {
    if (_joining) return;
    final code = cleanAccessCode(_code.text);
    if (code.isEmpty) {
      _showError('Kode belum diisi.');
      return;
    }
    if (code.length < kAccessCodeLength) {
      _showError(
        'Kode harus $kAccessCodeLength huruf. Baru ${code.length} huruf: '
        '${spellCode(code)}.',
      );
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    announce('Sedang bergabung dengan kode ${spellCode(code)}.');
    final JoinResult result;
    try {
      result = await store.joinSubject(code);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      _showError(e.message);
      return;
    }
    if (!mounted) return;
    setState(() => _joining = false);
    final subject = result.subject;
    if (subject == null) {
      _showError(
        'Kode ${spellCode(code)} tidak ditemukan. Periksa lagi kode dari '
        'guru.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _code.clear();
    _say(
      result.status == JoinStatus.alreadyJoined
          ? 'Kamu sudah ikut ${subject.name}.'
          : 'Bergabung ke ${subject.name}.',
    );
    _open(subject);
  }

  String _summary(Subject s) {
    final teacher = s.teacherName;
    final count = '${s.materialCount} materi';
    return teacher == null || teacher.isEmpty ? count : '$count, guru $teacher';
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Kelas'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            MascotBubble(
              text:
                  'Halo, ${widget.studentName}! Aku Odi. Masukkan '
                  'kode $kAccessCodeLength huruf dari gurumu untuk '
                  'bergabung ke kelas.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              enabled: !_joining,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [AccessCodeFormatter()],
              style: AppType.bodyLarge,
              decoration: fieldDecoration('Kode kelas', hint: 'Contoh: KXPRTA'),
              onSubmitted: (_) => _join(),
            ),
            _TypedCode(controller: _code),
            const SizedBox(height: 12),
            if (_error != null) ...[
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
              const SizedBox(height: 12),
            ],
            PrimaryButton(
              label: _joining ? 'Sedang bergabung...' : 'Gabung',
              icon: Icons.key,
              onPressed: _joining ? null : _join,
            ),
            const SizedBox(height: 16),
            LoadView<List<Subject>>(
              scrollable: false,
              padding: EdgeInsets.zero,
              loadingMessage: 'Memuat kelasmu.',
              load: store.studentSubjects,
              builder: (context, subjects, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionTitle('Kelas yang kamu ikuti (${subjects.length})'),
                  if (subjects.isEmpty)
                    const EmptyState(
                      message:
                          'Belum ada kelas. Masukkan kode dari '
                          'gurumu di atas.',
                    ),
                  for (final s in subjects)
                    ListRow(
                      icon: Icons.folder_outlined,
                      title: s.name,
                      subtitle: _summary(s),
                      semanticLabel: 'Kelas ${s.name}. ${_summary(s)}.',
                      onTap: () => _open(s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kode yang sudah diketik, dieja per huruf. TalkBack membaca isi kolom
/// sebagai satu kata ("kxprta"), jadi baris ini membantu siswa memeriksa
/// ketikannya. Sengaja bukan liveRegion supaya tidak bersuara tiap ketukan.
class _TypedCode extends StatelessWidget {
  const _TypedCode({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final code = value.text;
        if (code.isEmpty) return const SizedBox.shrink();
        final count = '${code.length} dari $kAccessCodeLength huruf';
        return Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Semantics(
            label: 'Kode yang diketik: ${spellCode(code)}. $count.',
            excludeSemantics: true,
            child: Text(
              'Kode yang diketik: ${spellCode(code)} ($count)',
              style: AppType.bodyMedium,
            ),
          ),
        );
      },
    );
  }
}
