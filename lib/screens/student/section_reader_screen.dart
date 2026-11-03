import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Halaman yang kosong membuat TalkBack berhenti di elemen tanpa suara,
/// jadi tampilkan kalimat ini.
const String _emptyContent = 'Halaman ini tidak berisi teks.';

/// Awalan subjudul di isi halaman dari backend (lihat pdf_sections.py).
const String _subheadingPrefix = '## ';

/// Awalan butir daftar di isi halaman. Butir berurutan menjadi satu daftar.
const String _listItemPrefix = '- ';

/// Baris gambar di isi halaman: `[[gambar:xref-12]]`.
final RegExp _imageMarker = RegExp(r'^\[\[gambar:([\w-]+)\]\]$');

/// "Halaman 2 dari 10: Judul", atau tanpa judul kalau halaman tidak punya.
String pagePosition(int index, int total, String title) {
  final position = 'Halaman ${index + 1} dari $total';
  return title.trim().isEmpty ? position : '$position: ${title.trim()}';
}

/// Daftar halaman satu materi. Dipakai siswa dan guru.
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
      appBar: aprevoAppBar('Daftar halaman'),
      body: SafeArea(
        child: LoadView<MaterialPages>(
          listenToStore: false,
          loadingMessage: 'Memuat halaman $materialTitle.',
          load: () => store.sections(materialId),
          builder: (context, pages, _) => _list(context, pages.sections, pages),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<MaterialSection> sections,
    MaterialPages pages,
  ) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Semantics(
        header: true,
        child: Text(materialTitle, style: AppType.headlineMedium),
      ),
      const SizedBox(height: 6),
      Text(
        sections.isEmpty
            ? 'Belum ada halaman.'
            : '${sections.length} halaman. Pilih satu untuk dibaca.',
        style: AppType.bodyMedium,
      ),
      const SizedBox(height: 16),
      if (sections.isEmpty)
        const EmptyState(
          message:
              'Materi ini belum punya halaman. Minta guru '
              'mengunggah ulang PDF-nya.',
        ),
      for (var i = 0; i < sections.length; i++)
        ListRow(
          icon: Icons.menu_book_outlined,
          title: sections[i].title.trim().isEmpty
              ? 'Halaman ${i + 1}'
              : 'Halaman ${i + 1}: ${sections[i].title.trim()}',
          semanticLabel: pagePosition(i, sections.length, sections[i].title),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SectionReaderScreen(
                materialTitle: materialTitle,
                sections: sections,
                images: pages.images,
                initialIndex: i,
              ),
            ),
          ),
        ),
    ],
  );
}

/// Pembaca satu halaman materi. Urutan fokus TalkBack: judul materi (bilah
/// atas), "Halaman 2 dari 10: Judul" sebagai header, isi per paragraf, lalu
/// tombol pindah halaman di bawah. Setelah pindah, fokus kembali ke header
/// dan posisinya diumumkan.
class SectionReaderScreen extends StatefulWidget {
  const SectionReaderScreen({
    super.key,
    required this.materialTitle,
    required this.sections,
    this.images = const {},
    this.initialIndex = 0,
  });

  final String materialTitle;
  final List<MaterialSection> sections;

  /// Gambar menurut kuncinya, untuk baris `[[gambar:...]]` di isi halaman.
  final Map<String, PageImage> images;
  final int initialIndex;

  @override
  State<SectionReaderScreen> createState() => _SectionReaderScreenState();
}

class _SectionReaderScreenState extends State<SectionReaderScreen> {
  late int _index = widget.initialIndex;
  final _scroll = ScrollController();
  final _headerFocus = FocusNode(debugLabel: 'judul halaman');

  MaterialSection get _s => widget.sections[_index];
  int get _total => widget.sections.length;

  String get _position => pagePosition(_index, _total, _s.title);

  @override
  void initState() {
    super.initState();
    // Tunggu layar tampil supaya pengumuman tidak tertimpa judul layar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _headerFocus.dispose();
    super.dispose();
  }

  void _announce() {
    if (!mounted) return;
    announce(_position);
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _total) return;
    setState(() => _index = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      // Fokus pindah dari tombol ke header halaman baru, supaya siswa
      // langsung membaca dari atas.
      _headerFocus.requestFocus();
      _announce();
    });
  }

  void _finish() {
    Navigator.popUntil(
      context,
      (route) =>
          route.settings.name == kMaterialListRoute.name || route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPrev = _index > 0;
    final isLast = _index == _total - 1;
    final blocks = _group([
      for (final line in _s.content.split('\n'))
        if (line.trim().isNotEmpty && !_isHidden(line.trim())) line.trim(),
    ]);
    return PurpleScaffold(
      appBar: aprevoAppBar(widget.materialTitle),
      body: SafeArea(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Focus(
              focusNode: _headerFocus,
              child: Semantics(
                header: true,
                child: Text(_position, style: AppType.headlineMedium),
              ),
            ),
            const SizedBox(height: 20),
            AppCard(
              key: ValueKey('halaman-$_index'),
              color: AppColors.soft,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (blocks.isEmpty)
                    Text(_emptyContent, style: AppType.bodyLarge),
                  for (var i = 0; i < blocks.length; i++) ...[
                    if (i > 0) const SizedBox(height: 18),
                    switch (blocks[i]) {
                      final List<String> items => _list(items),
                      final String line => _block(line),
                      _ => const SizedBox.shrink(),
                    },
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: isLast
                  ? PrimaryButton(
                      label: 'Selesai, kembali ke daftar materi',
                      icon: Icons.check,
                      onPressed: _finish,
                    )
                  : PrimaryButton(
                      label: 'Halaman berikutnya',
                      icon: Icons.arrow_forward,
                      onPressed: () => _go(1),
                    ),
            ),
            if (hasPrev) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Halaman sebelumnya'),
                  onPressed: () => _go(-1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  PageImage? _image(String line) {
    final match = _imageMarker.firstMatch(line);
    return match == null ? null : widget.images[match.group(1)];
  }

  /// Gambar dekoratif tidak ditampilkan dan tidak dibacakan. Gambar tanpa
  /// deskripsi juga disembunyikan: materi hanya bisa terbit kalau semua
  /// gambarnya berdeskripsi, jadi ini hanya terjadi di pratinjau guru.
  bool _isHidden(String line) {
    if (!_imageMarker.hasMatch(line)) return false;
    final image = _image(line);
    return image == null || image.isDecorative || image.description == null;
  }

  /// Butir berurutan dikumpulkan menjadi satu daftar (`List<String>`).
  static List<Object> _group(List<String> lines) {
    final blocks = <Object>[];
    for (final line in lines) {
      if (line.startsWith(_listItemPrefix)) {
        final item = line.substring(_listItemPrefix.length).trim();
        final last = blocks.isEmpty ? null : blocks.last;
        if (last is List<String>) {
          last.add(item);
        } else {
          blocks.add(<String>[item]);
        }
      } else {
        blocks.add(line);
      }
    }
    return blocks;
  }

  /// Daftar berbutir: tiap butir satu fokus TalkBack, dibacakan
  /// "Butir 1 dari 3: ..." supaya siswa tahu panjang daftarnya.
  Widget _list(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Semantics(
              container: true,
              label: 'Butir ${i + 1} dari ${items.length}: ${items[i]}',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•', style: AppType.bodyLarge),
                  const SizedBox(width: 10),
                  Expanded(child: Text(items[i], style: AppType.bodyLarge)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Satu paragraf, subjudul, atau gambar, masing-masing satu fokus TalkBack.
  Widget _block(String line) {
    if (_imageMarker.hasMatch(line)) {
      final text = 'Gambar: ${_image(line)?.description ?? ''}';
      return Semantics(
        container: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.lilac,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.ink, width: 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: Icon(Icons.image_outlined)),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: AppType.bodyLarge)),
            ],
          ),
        ),
      );
    }
    if (line.startsWith(_subheadingPrefix)) {
      return Semantics(
        header: true,
        container: true,
        child: Text(
          line.substring(_subheadingPrefix.length).trim(),
          style: AppType.titleLarge,
        ),
      );
    }
    return Semantics(
      container: true,
      child: Text(line, style: AppType.bodyLarge),
    );
  }
}
