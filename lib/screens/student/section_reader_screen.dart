import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../../widgets/search_box.dart';

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
  const _ListItem(this.marker, this.text, this.line);

  final String? marker;
  final String text;

  /// Nomor baris di isi halaman, untuk menemukan blok hasil pencarian.
  final int line;
}

/// Satu baris isi halaman dengan nomor barisnya.
class _Line {
  const _Line(this.index, this.text);

  final int index;
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

/// Pencarian isi materi minimal sepanjang ini, sama dengan batas backend.
const int kMinContentSearchLength = 2;

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
          builder: (context, pages, _) => _SectionList(
            materialId: materialId,
            materialTitle: materialTitle,
            pages: pages,
          ),
        ),
      ),
    );
  }
}

/// Isi layar daftar halaman: kolom pencarian isi materi, lalu daftar halaman.
/// Selama mencari, hasilnya menggantikan daftar halaman.
class _SectionList extends StatefulWidget {
  const _SectionList({
    required this.materialId,
    required this.materialTitle,
    required this.pages,
  });

  final String materialId;
  final String materialTitle;
  final MaterialPages pages;

  @override
  State<_SectionList> createState() => _SectionListState();
}

class _SectionListState extends State<_SectionList> {
  final _query = SearchQuery();
  List<ContentSearchHit> _hits = const [];
  bool _searching = false;
  String? _error;
  String? _gone;
  int _serial = 0;

  List<MaterialSection> get _sections => widget.pages.sections;

  @override
  void initState() {
    super.initState();
    _query.addListener(_search);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.value;
    final serial = ++_serial;
    if (query.length < kMinContentSearchLength) {
      setState(() {
        _hits = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final hits = await store.searchMaterial(widget.materialId, query);
      // Jawaban untuk kata yang lama diabaikan.
      if (!mounted || serial != _serial) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted || serial != _serial) return;
      setState(() {
        _searching = false;
        if (e.statusCode == 410) {
          _gone = e.message;
        } else {
          _error = e.message;
        }
      });
    }
  }

  void _read(int index, {ContentSearchHit? hit}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SectionReaderScreen(
          materialTitle: widget.materialTitle,
          sections: _sections,
          images: widget.pages.images,
          initialIndex: index,
          searchHit: hit,
        ),
      ),
    );
  }

  void _openHit(ContentSearchHit hit) {
    final index = _sections.indexWhere((s) => s.id == hit.sectionId);
    if (index < 0) {
      announce('Halaman ini sudah berubah. Coba cari lagi.');
      return;
    }
    _read(index, hit: hit);
  }

  String? get _status {
    final query = _query.value;
    if (query.isEmpty || _error != null) return null;
    if (query.length < kMinContentSearchLength) {
      return 'Ketik minimal $kMinContentSearchLength huruf';
    }
    if (_searching) return 'Mencari...';
    return searchStatus(_hits.length, 'halaman');
  }

  @override
  Widget build(BuildContext context) {
    final gone = _gone;
    if (gone != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: goneNotice(context, gone),
      );
    }
    final sections = _sections;
    final searching = _query.value.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Semantics(
          header: true,
          child: Text(widget.materialTitle, style: AppType.headlineMedium),
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
          )
        else
          SearchBox(
            query: _query,
            label: 'Cari isi materi',
            status: _status,
            // Pesan "Mencari..." tidak dibacakan otomatis, supaya TalkBack
            // langsung membacakan jumlah hasilnya.
            live: !_searching,
          ),
        if (_error != null) ...[
          ErrorCard(key: ErrorCard.keyFor(_serial), message: _error!),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Coba lagi',
            icon: Icons.refresh,
            onPressed: _search,
          ),
        ],
        if (searching)
          for (final hit in _hits)
            ListRow(
              key: ValueKey('hasil-${hit.sectionId}'),
              icon: Icons.search,
              title: hit.title.trim().isEmpty
                  ? 'Halaman ${hit.pageIndex + 1}'
                  : 'Halaman ${hit.pageIndex + 1}: ${hit.title.trim()}',
              subtitle: hit.snippet,
              semanticLabel: hit.label,
              onTap: () => _openHit(hit),
            )
        else
          for (var i = 0; i < sections.length; i++)
            ListRow(
              icon: Icons.menu_book_outlined,
              title: sections[i].title.trim().isEmpty
                  ? 'Halaman ${i + 1}'
                  : 'Halaman ${i + 1}: ${sections[i].title.trim()}',
              semanticLabel: pagePosition(
                i,
                sections.length,
                sections[i].title,
              ),
              onTap: () => _read(i),
            ),
      ],
    );
  }
}

/// Pembaca satu halaman materi. Urutan fokus TalkBack: judul materi (bilah
/// atas), "Halaman 2 dari 10: Judul" sebagai header, isi per paragraf, lalu
/// tombol pindah halaman di bawah. Setelah pindah, fokus kembali ke header
/// dan posisinya diumumkan. Kalau dibuka dari hasil pencarian ([searchHit]),
/// fokus langsung ke blok yang memuat kata itu.
class SectionReaderScreen extends StatefulWidget {
  const SectionReaderScreen({
    super.key,
    required this.materialTitle,
    required this.sections,
    this.images = const {},
    this.initialIndex = 0,
    this.searchHit,
  });

  final String materialTitle;
  final List<MaterialSection> sections;

  /// Gambar menurut kuncinya, untuk baris `[[gambar:...]]` di isi halaman.
  final Map<String, PageImage> images;
  final int initialIndex;

  /// Hasil pencarian yang membuka layar ini. Hanya berlaku di halaman pertama
  /// yang dibuka.
  final ContentSearchHit? searchHit;

  @override
  State<SectionReaderScreen> createState() => _SectionReaderScreenState();
}

class _SectionReaderScreenState extends State<SectionReaderScreen> {
  late int _index = widget.initialIndex;
  final _scroll = ScrollController();
  final _headerFocus = FocusNode(debugLabel: 'judul halaman');
  final _headerKey = GlobalKey(debugLabel: 'judul halaman');
  final _hitKey = GlobalKey(debugLabel: 'blok hasil pencarian');
  late ContentSearchHit? _hit = widget.searchHit;

  MaterialSection get _s => widget.sections[_index];
  int get _total => widget.sections.length;

  String get _position => pagePosition(_index, _total, _s.title);

  @override
  void initState() {
    super.initState();
    // Tunggu layar tampil supaya pengumuman tidak tertimpa judul layar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hit == null) {
        _announce();
      } else {
        _afterRouteShown(_showHit);
      }
    });
  }

  /// Selama transisi, layar lama masih ada di pohon aksesibilitas, jadi fokus
  /// baru diminta setelah layar ini tampil penuh.
  void _afterRouteShown(VoidCallback action) {
    if (!mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      action();
      return;
    }
    late final AnimationStatusListener listener;
    listener = (status) {
      if (!status.isCompleted) return;
      animation.removeStatusListener(listener);
      action();
    };
    animation.addStatusListener(listener);
  }

  /// Menggulir ke blok hasil pencarian, meminta TalkBack memindahkan fokus ke
  /// sana, lalu mengumumkan cuplikannya. Kalau bloknya sudah tidak ada (isi
  /// halaman berubah sejak dicari), fokus ke judul halaman.
  void _showHit() {
    final hit = _hit;
    if (!mounted || hit == null) return;
    final target = _hitKey.currentContext ?? _headerKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target, alignment: 0.2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !target.mounted) return;
      target.findRenderObject()?.sendSemanticsEvent(const FocusSemanticEvent());
      announce('Halaman ${_index + 1}, hasil pencarian: ${hit.snippet}');
    });
  }

  bool _isHit(int line, [int? row]) =>
      _hit != null && _hit!.line == line && _hit!.row == row;

  /// Blok hasil pencarian diberi latar kuning untuk guru dan siswa low vision.
  Widget _marked(bool hit, Widget child) => hit
      ? DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.highlight),
          child: child,
        )
      : child;

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
    setState(() {
      _index = next;
      _hit = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      store.checkOpenSubject();
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
    final lines = _s.content.split('\n');
    final blocks = _group([
      for (var i = 0; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty && !_isHidden(lines[i].trim()))
          _Line(i, lines[i].trim()),
    ]);
    return PurpleScaffold(
      appBar: aprevoAppBar(widget.materialTitle),
      body: SafeArea(
        child: SubjectGoneGuard(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Semantics(
                key: _headerKey,
                container: true,
                child: Focus(
                  focusNode: _headerFocus,
                  child: Semantics(
                    header: true,
                    child: Text(_position, style: AppType.headlineMedium),
                  ),
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
                        final _Line line => _block(line),
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
    if (ContentTable.isMarker(line)) {
      return ContentTable.tryParseLine(line) == null;
    }
    if (!_imageMarker.hasMatch(line)) return false;
    final image = _image(line);
    return image == null || image.isDecorative || image.description == null;
  }

  /// Butir berurutan yang sejenis dikumpulkan menjadi satu [_ItemList].
  static List<Object> _group(List<_Line> lines) {
    final blocks = <Object>[];
    for (final entry in lines) {
      final line = entry.text;
      final numbered = _numberedItem.firstMatch(line);
      final _ListItem item;
      if (line.startsWith(_listItemPrefix)) {
        item = _ListItem(
          null,
          line.substring(_listItemPrefix.length).trim(),
          entry.index,
        );
      } else if (numbered != null) {
        item = _ListItem(
          numbered.group(0)!.trim(),
          line.substring(numbered.end).trim(),
          entry.index,
        );
      } else {
        blocks.add(entry);
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
              key: _isHit(items[i].line) ? _hitKey : null,
              container: true,
              label: listItemLabel(
                i,
                items.length,
                items[i].marker,
                items[i].text,
              ),
              excludeSemantics: true,
              child: _marked(
                _isHit(items[i].line),
                Row(
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
          ),
      ],
    );
  }

  /// Tabel: ringkasannya dibacakan sebagai judul saat fokus sampai ke tabel,
  /// lalu tiap baris satu fokus yang menyebut nama kolomnya. Baris nama kolom
  /// tidak difokus karena namanya sudah ada di tiap baris.
  Widget _table(ContentTable table, int line) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: _isHit(line) ? _hitKey : null,
          header: true,
          container: true,
          child: _marked(
            _isHit(line),
            Text(table.summary, style: AppType.titleMedium),
          ),
        ),
        const SizedBox(height: 10),
        ExcludeSemantics(
          child: _tableRow(table.columns, AppColors.lilac, AppType.titleMedium),
        ),
        for (var i = 0; i < table.rows.length; i++)
          Semantics(
            key: _isHit(line, i) ? _hitKey : null,
            container: true,
            label: table.rowLabel(i),
            excludeSemantics: true,
            child: _tableRow(
              table.rows[i],
              _isHit(line, i) ? AppColors.highlight : AppColors.white,
              AppType.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget _tableRow(List<String> cells, Color color, TextStyle style) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cell in cells)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: AppColors.ink),
                ),
                child: Text(cell, style: style),
              ),
            ),
        ],
      ),
    );
  }

  /// Satu paragraf, subjudul, atau gambar, masing-masing satu fokus TalkBack.
  Widget _block(_Line entry) {
    final line = entry.text;
    final hit = _isHit(entry.index);
    final key = hit ? _hitKey : null;
    final table = ContentTable.tryParseLine(line);
    if (table != null) return _table(table, entry.index);
    if (_imageMarker.hasMatch(line)) {
      final text = 'Gambar: ${_image(line)?.description ?? ''}';
      return Semantics(
        key: key,
        container: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hit ? AppColors.highlight : AppColors.lilac,
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
        key: key,
        header: true,
        container: true,
        child: _marked(
          hit,
          Text(
            line.substring(_subheadingPrefix.length).trim(),
            style: AppType.titleLarge,
          ),
        ),
      );
    }
    return Semantics(
      key: key,
      container: true,
      child: _marked(hit, Text(line, style: AppType.bodyLarge)),
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
