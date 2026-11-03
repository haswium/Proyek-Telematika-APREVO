import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Guru memeriksa dan mengedit tabel yang dibaca otomatis dari PDF. Siswa
/// mendengar "Baris 1. Kolom: isi." per baris tabel.
class MaterialTablesScreen extends StatelessWidget {
  const MaterialTablesScreen({
    super.key,
    required this.materialId,
    required this.materialTitle,
  });

  final String materialId;
  final String materialTitle;

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Tabel materi'),
      body: SafeArea(
        child: LoadView<MaterialPages>(
          loadingMessage: 'Memuat tabel $materialTitle.',
          load: () => store.sections(materialId),
          builder: (context, pages, _) {
            final cards = [
              for (final section in pages.sections)
                for (final (index, table) in section.tables.indexed)
                  _TableCard(
                    key: ValueKey('${section.id}-$index'),
                    materialId: materialId,
                    section: section,
                    index: index,
                    table: table,
                  ),
            ];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Semantics(
                  header: true,
                  child: Text(materialTitle, style: AppType.headlineMedium),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tabel dibaca otomatis dari PDF dan bisa salah, jadi periksa '
                  'dan perbaiki isinya sebelum materi terbit.',
                  style: AppType.bodyMedium,
                ),
                const SizedBox(height: 20),
                if (cards.isEmpty)
                  const EmptyState(message: 'Materi ini tidak punya tabel.'),
                for (final card in cards) ...[card, const SizedBox(height: 16)],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TableCard extends StatefulWidget {
  const _TableCard({
    super.key,
    required this.materialId,
    required this.section,
    required this.index,
    required this.table,
  });

  final String materialId;
  final MaterialSection section;
  final int index;
  final ContentTable table;

  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  late final _title = TextEditingController(text: widget.table.title);
  late final _columns = [
    for (final name in widget.table.columns) TextEditingController(text: name),
  ];
  late final _rows = [
    for (final row in widget.table.rows)
      [for (final cell in row) TextEditingController(text: cell)],
  ];
  bool _saving = false;
  String? _feedback;

  @override
  void dispose() {
    _title.dispose();
    for (final c in [..._columns, for (final row in _rows) ...row]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _feedback = null;
    });
    String message;
    try {
      await store.updateTable(
        widget.materialId,
        widget.section.id,
        widget.index,
        ContentTable(
          title: _title.text,
          columns: [for (final c in _columns) c.text],
          rows: [
            for (final row in _rows) [for (final c in row) c.text],
          ],
        ),
      );
      message = 'Tabel disimpan.';
    } on ApiException catch (e) {
      message = e.message;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _feedback = message;
    });
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 5,
        style: AppType.bodyLarge,
        decoration: fieldDecoration(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.section.pageStart ?? widget.section.position;
    return AppCard(
      color: AppColors.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Tabel di halaman $page, ${_columns.length} kolom, '
              '${_rows.length} baris',
              style: AppType.titleMedium,
            ),
          ),
          _field(_title, 'Judul tabel'),
          for (var c = 0; c < _columns.length; c++)
            _field(_columns[c], 'Nama kolom ${c + 1}'),
          for (var r = 0; r < _rows.length; r++)
            for (var c = 0; c < _columns.length; c++)
              _field(_rows[r][c], 'Baris ${r + 1}, ${widget.table.columns[c]}'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Simpan tabel',
              icon: Icons.save_outlined,
              onPressed: _saving ? null : _save,
            ),
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 10),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(_feedback!, style: AppType.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }
}
