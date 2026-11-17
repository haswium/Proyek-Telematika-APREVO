import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../models/pasted_text.dart';
import '../../services/a11y_focus.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/disclosure.dart';
import '../../widgets/playful.dart';
import 'material_editor_screen.dart';

/// Guru membuat materi dengan menempel teks (copy-paste), tanpa file.
///
/// Alurnya: isi judul dan tempel teks, tekan "Lihat pratinjau halaman",
/// periksa pembagian halamannya, lalu "Simpan sebagai draf". Pratinjau
/// dihitung backend, jadi sama persis dengan yang disimpan. Kalau teks diubah
/// setelah pratinjau, pratinjau harus dibuat ulang sebelum menyimpan.
class PasteMaterialScreen extends StatefulWidget {
  const PasteMaterialScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<PasteMaterialScreen> createState() => _PasteMaterialScreenState();
}

class _PasteMaterialScreenState extends State<PasteMaterialScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  final _previewKey = GlobalKey(debugLabel: 'pratinjau halaman');
  final _statusKey = GlobalKey(debugLabel: 'status tempel teks');

  List<PastedPage>? _pages;

  /// Teks dan judul saat pratinjau dibuat. Simpan hanya boleh kalau masih sama.
  String? _previewedText;
  String? _previewedTitle;
  bool _previewing = false;
  bool _saving = false;

  bool get _busy => _previewing || _saving;
  String? _error;
  int _errorSerial = 0;

  bool get _previewCurrent =>
      _pages != null &&
      _previewedText == _text.text &&
      _previewedTitle == _title.text.trim();

  @override
  void initState() {
    super.initState();
    // Tombol simpan dan keterangan "pratinjau perlu dibuat ulang" ikut
    // berubah saat guru mengetik.
    _text.addListener(_onChanged);
    _title.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _previewing = false;
      _saving = false;
      _error = message;
      _errorSerial++;
    });
    moveScreenReaderFocus(_statusKey);
  }

  Future<void> _preview() async {
    if (_busy) return;
    if (_text.text.trim().isEmpty) {
      _showError('Tempel isi materi dulu di kolom teks.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _previewing = true;
      _error = null;
    });
    announce('Membuat pratinjau halaman.');
    try {
      final text = _text.text;
      final title = _title.text.trim();
      final pages = await store.previewPastedText(title: title, text: text);
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _pages = pages;
        _previewedText = text;
        _previewedTitle = title;
      });
      // Fokus pindah ke ringkasan pratinjau, yang dibaca utuh.
      moveScreenReaderFocus(_previewKey);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (_busy) return;
    if (title.isEmpty) {
      _showError('Isi judul materi dulu.');
      return;
    }
    if (!_previewCurrent) {
      _showError('Teks berubah sejak pratinjau. Lihat pratinjau halaman lagi.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    announce('Menyimpan materi.');
    try {
      final material = await store.createPastedMaterial(
        widget.subject,
        title: title,
        text: _text.text,
      );
      if (!mounted) return;
      final count = _pages?.length ?? 0;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MaterialEditorScreen(subject: widget.subject, material: material),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => announce(
          'Materi $title disimpan sebagai draf, $count halaman. Periksa isinya '
          'sebelum diterbitkan.',
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Materi belum tersimpan. ${e.message}');
    }
  }

  String _previewSummary(List<PastedPage> pages) {
    final titles = pages.map((p) => p.title).join(', ');
    return 'Pratinjau: teks terbagi menjadi ${pages.length} halaman: $titles.';
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final stale = pages != null && !_previewCurrent;
    final onPurple = AppType.bodyMedium.copyWith(color: AppColors.white);
    return PurpleScaffold(
      appBar: aprevoAppBar('Tempel teks materi'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Materi baru di ${widget.subject.name}',
                style: AppType.headlineMedium.copyWith(color: AppColors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Salin teks dari dokumen atau situs, lalu tempel di kolom isi '
              'materi. Tidak perlu mengunggah file.',
              style: onPurple,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                    style: AppType.bodyLarge,
                    decoration: fieldDecoration(
                      'Judul materi',
                      hint: 'Contoh: Iklim di Indonesia',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _text,
                    enabled: !_busy,
                    minLines: 8,
                    maxLines: 16,
                    keyboardType: TextInputType.multiline,
                    style: AppType.bodyLarge,
                    decoration: fieldDecoration(
                      'Isi materi',
                      hint: 'Tempel teks di sini',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Aturan pembagian halaman, ikut dibaca TalkBack.
                  Text(kPasteRule, style: AppType.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: _statusKey,
              child: _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ErrorCard(
                        key: ErrorCard.keyFor(_errorSerial),
                        message: _error!,
                      ),
                    ),
            ),
            PrimaryButton(
              label: _previewing
                  ? 'Membuat pratinjau...'
                  : 'Lihat pratinjau halaman',
              icon: Icons.preview_outlined,
              onPressed: _busy ? null : _preview,
            ),
            if (pages != null) ...[
              const SizedBox(height: 20),
              KeyedSubtree(
                key: _previewKey,
                child: Semantics(
                  container: true,
                  header: true,
                  label: stale
                      ? 'Pratinjau lama. Teks sudah berubah, lihat pratinjau '
                            'halaman lagi.'
                      : _previewSummary(pages),
                  excludeSemantics: true,
                  child: Text(
                    stale
                        ? 'Pratinjau lama: teks sudah berubah'
                        : 'Pratinjau: ${pages.length} halaman',
                    style: AppType.titleLarge.copyWith(color: AppColors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Buka tiap halaman untuk memeriksa isinya. Kalau pembagiannya '
                'belum tepat, ubah teksnya lalu lihat pratinjau lagi.',
                style: onPurple,
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      Disclosure(
                        key: ValueKey('pratinjau-$i-${pages[i].title}'),
                        title: 'Halaman ${i + 1}: ${pages[i].title}',
                        summary: pages[i].summary,
                        child: PastedPageContent(page: pages[i]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _saving ? 'Menyimpan...' : 'Simpan sebagai draf',
                icon: Icons.save_outlined,
                onPressed: _busy || stale ? null : _save,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Isi satu halaman di pratinjau, dengan struktur yang sama seperti nanti
/// dibaca siswa: subjudul sebagai header, butir daftar dengan tanda butir.
class PastedPageContent extends StatelessWidget {
  const PastedPageContent({super.key, required this.page});

  final PastedPage page;

  @override
  Widget build(BuildContext context) {
    final lines = page.content
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return Text('Halaman ini belum berisi teks.', style: AppType.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: line.startsWith('## ')
                ? Semantics(
                    header: true,
                    child: Text(line.substring(3), style: AppType.titleMedium),
                  )
                : line.startsWith('- ')
                ? Semantics(
                    label: 'Butir: ${line.substring(2)}',
                    excludeSemantics: true,
                    child: Text(
                      '•  ${line.substring(2)}',
                      style: AppType.bodyMedium,
                    ),
                  )
                : Text(line, style: AppType.bodyMedium),
          ),
      ],
    );
  }
}
