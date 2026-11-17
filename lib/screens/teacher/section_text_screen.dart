import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/material_file.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Daftar halaman yang teksnya bisa diperbaiki guru: hasil foto yang salah
/// baca, transkrip audio yang salah dengar, atau teks dari format lain.
class SectionTextListScreen extends StatelessWidget {
  const SectionTextListScreen({
    super.key,
    required this.materialId,
    required this.materialTitle,
  });

  final String materialId;
  final String materialTitle;

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Ubah teks halaman'),
      body: SafeArea(
        child: LoadView<MaterialPages>(
          loadingMessage: 'Memuat halaman $materialTitle.',
          load: () => store.sections(materialId),
          builder: (context, pages, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SectionTitle('Halaman $materialTitle (${pages.sections.length})'),
              Text(
                'Pilih halaman yang teksnya ingin diperbaiki.',
                style: AppType.bodyMedium.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: 12),
              if (pages.sections.isEmpty)
                const EmptyState(message: 'Materi ini belum punya halaman.'),
              for (var i = 0; i < pages.sections.length; i++)
                ListRow(
                  key: ValueKey(pages.sections[i].id),
                  icon: Icons.edit_note,
                  title: pages.sections[i].title.trim().isEmpty
                      ? 'Halaman ${i + 1}'
                      : 'Halaman ${i + 1}: ${pages.sections[i].title.trim()}',
                  semanticLabel:
                      'Ubah teks halaman ${i + 1}'
                      '${pages.sections[i].title.trim().isEmpty ? '' : ': ${pages.sections[i].title.trim()}'}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SectionTextEditorScreen(
                        materialId: materialId,
                        section: pages.sections[i],
                        number: i + 1,
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
}

/// Mengedit judul dan teks satu halaman. Baris "[Gambar 1]" dan "[Tabel 1]"
/// menandai posisi gambar dan tabel; isinya diubah di menu masing-masing.
class SectionTextEditorScreen extends StatefulWidget {
  const SectionTextEditorScreen({
    super.key,
    required this.materialId,
    required this.section,
    required this.number,
  });

  final String materialId;
  final MaterialSection section;
  final int number;

  @override
  State<SectionTextEditorScreen> createState() =>
      _SectionTextEditorScreenState();
}

/// Aturan format teks halaman, tampil di layar dan dibaca TalkBack.
const String kSectionTextHelp =
    'Satu paragraf satu baris. Awali subjudul dengan dua tanda pagar dan spasi, '
    'misalnya "## Musim". Awali butir daftar dengan tanda minus dan spasi, '
    'misalnya "- kemarau".';

const String kSectionMarkerHelp =
    'Baris seperti [Gambar 1] dan [Tabel 1] menandai posisi gambar dan tabel. '
    'Jangan dihapus atau dipindah. Ubah deskripsi gambar di menu Gambar dan '
    'deskripsi, dan isi tabel di menu Tabel.';

class _SectionTextEditorScreenState extends State<SectionTextEditorScreen> {
  late final EditablePageText _editable = EditablePageText.fromContent(
    widget.section.content,
  );
  late final _title = TextEditingController(text: widget.section.title);
  late final _text = TextEditingController(text: _editable.text);
  bool _saving = false;
  String? _error;
  int _errorSerial = 0;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _saving = false;
      _error = message;
      _errorSerial++;
    });
  }

  Future<void> _save() async {
    final content = _editable.restore(_text.text);
    if (content == null) {
      _showError(
        'Baris [Gambar] atau [Tabel] terhapus atau urutannya berubah. '
        'Kembalikan barisnya, lalu simpan lagi.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    announce('Menyimpan halaman ${widget.number}.');
    try {
      await store.updateSectionText(
        widget.materialId,
        widget.section.id,
        title: _title.text.trim(),
        content: content,
      );
      if (!mounted) return;
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => announce('Halaman ${widget.number} disimpan.'),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Halaman belum tersimpan. ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Halaman ${widget.number}'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    enabled: !_saving,
                    style: AppType.bodyLarge,
                    decoration: fieldDecoration('Judul halaman'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _text,
                    enabled: !_saving,
                    minLines: 8,
                    maxLines: 20,
                    keyboardType: TextInputType.multiline,
                    style: AppType.bodyLarge,
                    decoration: fieldDecoration('Teks halaman'),
                  ),
                  const SizedBox(height: 12),
                  // Tiap keterangan satu fokus TalkBack sendiri.
                  Semantics(
                    container: true,
                    child: Text(kSectionTextHelp, style: AppType.bodySmall),
                  ),
                  if (_editable.hasMarkers) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      container: true,
                      child: Text(kSectionMarkerHelp, style: AppType.bodySmall),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
              const SizedBox(height: 12),
            ],
            PrimaryButton(
              label: _saving ? 'Menyimpan...' : 'Simpan halaman',
              icon: Icons.save_outlined,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
