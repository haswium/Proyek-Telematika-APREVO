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

/// Butir bernomor dengan nomor aslinya: "3. Buka aplikasi" atau "b) ...".
final RegExp _numberedItem = RegExp(r'^(\d{1,3}|[a-z])[.)] (?=\S)');

/// Satu butir daftar. [marker] berisi nomor aslinya ("3."), atau null untuk
/// butir bertitik.
class _ListItem {
  const _ListItem(this.marker, this.text);

  final String? marker;
  final String text;
}

/// Jenis penanda butir. Daftar dipisah kalau jenisnya berganti, misalnya
/// "10. 11." lalu "a) b)".
enum _Marker { dot, number, letter }

_Marker _markerOf(_ListItem item) {
  final marker = item.marker;
  if (marker == null) return _Marker.dot;
  return int.tryParse(marker.substring(0, marker.length - 1)) == null
      ? _Marker.letter
      : _Marker.number;
}

/// Butir berurutan yang sejenis.
class _ItemList {
  _ItemList(this.kind);

  final _Marker kind;
  bool get numbered => kind != _Marker.dot;
  final items = <_ListItem>[];
}

/// Label TalkBack satu butir: "Butir 1 dari 4: isi". Nomor asli ikut
/// dibacakan kalau berbeda dari urutannya, misalnya daftar yang berlanjut
/// dari halaman sebelumnya ("Butir 1 dari 3, nomor 10: isi").
String listItemLabel(int index, int total, String? marker, String text) {
  final position = 'Butir ${index + 1} dari $total';
  if (marker == null) return '$position: $text';
  final value = marker.substring(0, marker.length - 1);
  final number = int.tryParse(value);
  final expected = number == null
      ? value.codeUnitAt(0) - 'a'.codeUnitAt(0) == index
      : number == index + 1;
  return expected ? '$position: $text' : '$position, nomor $value: $text';
}

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
                      final _ItemList list => _list(list),
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

  /// Butir berurutan yang sejenis dikumpulkan menjadi satu [_ItemList].
  static List<Object> _group(List<String> lines) {
    final blocks = <Object>[];
    for (final line in lines) {
      final numbered = _numberedItem.firstMatch(line);
      final _ListItem item;
      if (line.startsWith(_listItemPrefix)) {
        item = _ListItem(null, line.substring(_listItemPrefix.length).trim());
      } else if (numbered != null) {
        item = _ListItem(
          numbered.group(0)!.trim(),
          line.substring(numbered.end).trim(),
        );
      } else {
        blocks.add(line);
        continue;
      }
      final kind = _markerOf(item);
      final last = blocks.isEmpty ? null : blocks.last;
      if (last is _ItemList && last.kind == kind) {
        last.items.add(item);
      } else {
        blocks.add(_ItemList(kind)..items.add(item));
      }
    }
    return blocks;
  }

  /// Daftar: titik atau nomor digambar aplikasi, bukan bagian dari teks.
  /// Tiap butir satu fokus TalkBack, dibacakan "Butir 1 dari 3: ..."
  /// supaya siswa tahu panjang daftarnya.
  Widget _list(_ItemList list) {
    final items = list.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Semantics(
              container: true,
              label: listItemLabel(
                i,
                items.length,
                items[i].marker,
                items[i].text,
              ),
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: list.numbered ? 36 : 22,
                    child: items[i].marker == null
                        ? const _BulletDot()
                        : Text(
                            items[i].marker!,
                            style: AppType.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Text(items[i].text, style: AppType.bodyLarge),
                  ),
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

/// Titik butir yang digambar, sejajar dengan baris pertama teksnya.
class _BulletDot extends StatelessWidget {
  const _BulletDot();

  @override
  Widget build(BuildContext context) {
    final size = AppType.bodyLarge.fontSize ?? 16;
    return Padding(
      padding: EdgeInsets.only(top: size * 0.55),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
