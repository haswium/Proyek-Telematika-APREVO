import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Gambar di PDF materi: guru meminta deskripsi AI, lalu memeriksa,
/// memperbaiki, atau menandai gambar dekoratif sebelum materi terbit.
/// Siswa mendengar "Gambar: deskripsi" di posisi gambar dalam halaman.
class MaterialImagesScreen extends StatefulWidget {
  const MaterialImagesScreen({
    super.key,
    required this.materialId,
    required this.materialTitle,
  });

  final String materialId;
  final String materialTitle;

  @override
  State<MaterialImagesScreen> createState() => _MaterialImagesScreenState();
}

class _MaterialImagesScreenState extends State<MaterialImagesScreen> {
  bool _describing = false;
  String? _status;

  Future<void> _describe() async {
    setState(() {
      _describing = true;
      _status = 'Membuat deskripsi gambar dengan AI. Tunggu sebentar.';
    });
    announce(_status!);
    String message;
    try {
      final pending = await store.describeImages(widget.materialId);
      message = pending == 0
          ? 'Deskripsi gambar selesai dibuat. Periksa setiap deskripsi.'
          : '$pending gambar masih belum punya deskripsi. Pilih tombol ini '
                'lagi untuk mencoba ulang, atau tulis deskripsinya sendiri.';
    } on ApiException catch (e) {
      message = e.message;
    }
    if (!mounted) return;
    setState(() {
      _describing = false;
      _status = message;
    });
  }

  /// Ringkasan gambar yang menghalangi materi terbit.
  List<Widget> _pending(List<PageImage> images) {
    final pending = [
      for (var i = 0; i < images.length; i++)
        if (images[i].needsDescription) (number: i + 1, image: images[i]),
    ];
    if (pending.isEmpty) {
      if (images.isEmpty) return const [];
      return [
        Text(
          'Semua gambar sudah punya deskripsi atau ditandai dekoratif.',
          style: AppType.bodyMedium,
        ),
        const SizedBox(height: 16),
      ];
    }
    return [
      AppCard(
        color: AppColors.highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Belum dideskripsikan (${pending.length})',
                style: AppType.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Materi baru bisa terbit setelah gambar ini diberi deskripsi '
              'atau ditandai dekoratif.',
              style: AppType.bodyMedium,
            ),
            const SizedBox(height: 8),
            for (final p in pending)
              Text(
                '• Gambar ${p.number}'
                '${p.image.pageNumber == null ? '' : ', halaman ${p.image.pageNumber}'}',
                style: AppType.bodyMedium,
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Gambar materi'),
      body: SafeArea(
        child: LoadView<List<PageImage>>(
          loadingMessage: 'Memuat gambar ${widget.materialTitle}.',
          load: () => store.teacherImages(widget.materialId),
          builder: (context, images, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Semantics(
                header: true,
                child: Text(
                  widget.materialTitle,
                  style: AppType.headlineMedium,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'AI membuat deskripsi setiap gambar untuk siswa. AI bisa '
                'salah, jadi periksa dan perbaiki sebelum materi terbit. '
                'Gambar dekoratif tidak dibacakan ke siswa.',
                style: AppType.bodyMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _describing
                      ? 'Sedang membuat deskripsi...'
                      : 'Buat deskripsi gambar dengan AI',
                  icon: Icons.auto_awesome,
                  onPressed: _describing ? null : _describe,
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(_status!, style: AppType.bodyMedium),
                ),
              ],
              const SizedBox(height: 20),
              if (images.isEmpty)
                const EmptyState(message: 'Materi ini tidak punya gambar.'),
              ..._pending(images),
              for (var i = 0; i < images.length; i++) ...[
                _ImageCard(
                  key: ValueKey(images[i].id),
                  materialId: widget.materialId,
                  image: images[i],
                  number: i + 1,
                  total: images.length,
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageCard extends StatefulWidget {
  const _ImageCard({
    super.key,
    required this.materialId,
    required this.image,
    required this.number,
    required this.total,
  });

  final String materialId;
  final PageImage image;
  final int number;
  final int total;

  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard> {
  late final _description = TextEditingController(
    text: widget.image.description ?? '',
  );
  late bool _decorative = widget.image.isDecorative;
  bool _saving = false;
  String? _feedback;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  String get _title {
    final page = widget.image.pageNumber;
    final where = page == null ? '' : ', halaman $page';
    return 'Gambar ${widget.number} dari ${widget.total}$where';
  }

  Future<void> _save({String? description, bool? decorative}) async {
    setState(() {
      _saving = true;
      _feedback = null;
    });
    String message;
    try {
      await store.updateImage(
        widget.materialId,
        widget.image.id,
        description: description,
        isDecorative: decorative,
      );
      if (decorative != null) _decorative = decorative;
      message = decorative == null
          ? 'Deskripsi ${_title.toLowerCase()} disimpan.'
          : decorative
          ? 'Ditandai dekoratif, tidak dibacakan ke siswa.'
          : 'Tidak dekoratif lagi, deskripsinya dibacakan ke siswa.';
    } on ApiException catch (e) {
      message = e.message;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _feedback = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.image.previewUrl;
    return AppCard(
      color: AppColors.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(_title, style: AppType.titleMedium),
          ),
          if (preview != null) ...[
            const SizedBox(height: 10),
            // Pratinjau untuk guru yang melihat layar. Isinya sudah
            // diwakili kolom deskripsi, jadi tidak dibacakan.
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  preview,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(
                    'Pratinjau tidak bisa dimuat.',
                    style: AppType.bodySmall,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _decorative,
              onChanged: _saving ? null : (v) => _save(decorative: v),
              title: Text(
                'Dekoratif, tidak dibacakan',
                style: AppType.titleMedium,
              ),
              subtitle: Text(
                'Untuk hiasan yang tidak penting bagi pelajaran',
                style: AppType.bodySmall,
              ),
            ),
          ),
          if (!_decorative) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 4,
              style: AppType.bodyLarge,
              decoration: fieldDecoration(
                'Deskripsi untuk siswa',
                hint: 'Siapa, melakukan apa, ada tulisan apa',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Simpan deskripsi',
                icon: Icons.save_outlined,
                onPressed: _saving
                    ? null
                    : () => _save(description: _description.text),
              ),
            ),
          ],
          if (_feedback != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(_feedback!, style: AppType.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }
}
