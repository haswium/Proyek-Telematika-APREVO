import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Isi sub-bab yang kosong membuat TalkBack berhenti di elemen tanpa suara,
/// jadi tampilkan kalimat ini.
const String _emptyContent = 'Isi sub bab ini kosong.';

/// Daftar sub-bab satu materi. Dipakai siswa dan guru.
class MaterialSectionsScreen extends StatelessWidget {
  const MaterialSectionsScreen({
    super.key,
    required this.materialId,
    required this.materialTitle,
  });

  final String materialId;
  final String materialTitle;

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Sub bab'),
      body: SafeArea(
        child: LoadView<List<MaterialSection>>(
          listenToStore: false,
          loadingMessage: 'Memuat sub bab $materialTitle.',
          load: () => store.sections(materialId),
          builder: (context, sections, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Semantics(
                header: true,
                child: Text(materialTitle, style: AppType.headlineMedium),
              ),
              const SizedBox(height: 6),
              Text(
                sections.isEmpty
                    ? 'Belum ada sub bab.'
                    : '${sections.length} sub bab. Pilih satu untuk '
                          'didengarkan.',
                style: AppType.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (sections.isEmpty)
                const EmptyState(
                  message:
                      'Materi ini belum punya sub bab. Minta guru '
                      'mengunggah ulang PDF-nya.',
                ),
              for (var i = 0; i < sections.length; i++)
                ListRow(
                  icon: Icons.headphones_outlined,
                  title: 'Sub bab ${i + 1}: ${sections[i].title}',
                  subtitle: sections[i].pagesText.isEmpty
                      ? null
                      : sections[i].pagesText,
                  semanticLabel: _rowLabel(sections, i),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SectionReaderScreen(
                        materialTitle: materialTitle,
                        sections: sections,
                        initialIndex: i,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _rowLabel(List<MaterialSection> sections, int i) {
    final s = sections[i];
    final pages = s.pagesText.isEmpty ? '' : ', ${s.pagesText.toLowerCase()}';
    return 'Sub bab ${i + 1} dari ${sections.length}: ${s.title}$pages';
  }
}

/// Pembaca satu sub-bab, dengan tombol Dengarkan dan pindah ke sub-bab
/// sebelumnya atau berikutnya. Setiap pindah diumumkan:
/// "Sub bab 2 dari 5: Judul".
class SectionReaderScreen extends StatefulWidget {
  const SectionReaderScreen({
    super.key,
    required this.materialTitle,
    required this.sections,
    this.initialIndex = 0,
  });

  final String materialTitle;
  final List<MaterialSection> sections;
  final int initialIndex;

  @override
  State<SectionReaderScreen> createState() => _SectionReaderScreenState();
}

class _SectionReaderScreenState extends State<SectionReaderScreen> {
  late int _index = widget.initialIndex;

  MaterialSection get _s => widget.sections[_index];
  int get _total => widget.sections.length;

  String get _position => 'Sub bab ${_index + 1} dari $_total';

  @override
  void initState() {
    super.initState();
    // Tunggu layar tampil supaya pengumuman tidak tertimpa judul halaman.
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void dispose() {
    Speech.stop();
    super.dispose();
  }

  void _announce() {
    if (!mounted) return;
    final message = '$_position: ${_s.title}';
    Speech.announce(message);
    Speech.feedback(context, message);
  }

  /// Teks yang dibacakan tombol Dengarkan.
  String _spoken() {
    final b = StringBuffer('$_position. ${_s.title}. ');
    b.write(_s.content.trim().isEmpty ? _emptyContent : _s.content.trim());
    final image = _s.imageDescription;
    if (image != null && image.trim().isNotEmpty) {
      b.write(' Deskripsi gambar: ${image.trim()}');
    }
    return b.toString();
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _total) return;
    Speech.stop();
    setState(() => _index = next);
    _announce();
  }

  @override
  Widget build(BuildContext context) {
    final image = _s.imageDescription;
    final hasPrev = _index > 0;
    final hasNext = _index < _total - 1;
    return PurpleScaffold(
      appBar: aprevoAppBar(widget.materialTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(_position, style: AppType.bodyMedium),
            const SizedBox(height: 4),
            Semantics(
              header: true,
              child: Text(_s.title, style: AppType.headlineMedium),
            ),
            if (_s.pagesText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_s.pagesText, style: AppType.bodySmall),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Dengarkan sub bab ini',
              icon: Icons.volume_up,
              onPressed: () => Speech.speak(_spoken()),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Hentikan suara'),
              onPressed: Speech.stop,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: hasPrev
                        ? 'Sub bab sebelumnya: '
                              '${widget.sections[_index - 1].title}'
                        : 'Sub bab sebelumnya, tidak ada',
                    button: true,
                    enabled: hasPrev,
                    onTap: hasPrev ? () => _go(-1) : null,
                    excludeSemantics: true,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Sebelumnya'),
                      onPressed: hasPrev ? () => _go(-1) : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    label: hasNext
                        ? 'Sub bab berikutnya: '
                              '${widget.sections[_index + 1].title}'
                        : 'Sub bab berikutnya, tidak ada',
                    button: true,
                    enabled: hasNext,
                    onTap: hasNext ? () => _go(1) : null,
                    excludeSemantics: true,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Berikutnya'),
                      onPressed: hasNext ? () => _go(1) : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AppCard(
              key: ValueKey('section-$_index'),
              color: AppColors.soft,
              child: Text(
                _s.content.trim().isEmpty ? _emptyContent : _s.content.trim(),
                style: AppType.bodyLarge,
              ),
            ),
            if (image != null && image.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              AppCard(
                color: AppColors.lilac,
                child: Text(
                  'Deskripsi gambar: ${image.trim()}',
                  style: AppType.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
