import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Seberapa sering progres deskripsi diperiksa selama proses berjalan.
const Duration kDescribePollInterval = Duration(seconds: 3);

/// Gambar di PDF materi: guru meminta deskripsi AI, lalu memeriksa,
/// memperbaiki, atau menandai gambar dekoratif sebelum materi terbit.
/// Siswa mendengar "Gambar: deskripsi" di posisi gambar dalam halaman.
///
/// Deskripsi dibuat di latar belakang, satu gambar sekali jalan. Progresnya
/// ("3 dari 12 gambar selesai") diperbarui berkala tanpa dibacakan; TalkBack
/// hanya diberi tahu saat proses dimulai, ada gambar yang gagal, dan selesai.
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
  DescribeStatus? _job;
  Timer? _poll;
  bool _starting = false;
  String? _status;
  Set<String> _knownFailures = {};
  VoidCallback? _reloadImages;

  bool get _running => _starting || (_job?.running ?? false);

  @override
  void initState() {
    super.initState();
    // Proses mungkin sudah berjalan, misalnya dimulai saat unggah.
    _check(initial: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _say(String message) {
    setState(() => _status = message);
    announce(message);
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(kDescribePollInterval, (_) => _check());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _describe() async {
    setState(() => _starting = true);
    try {
      final job = await store.startDescribeImages(widget.materialId);
      if (!mounted) return;
      setState(() {
        _starting = false;
        _job = job;
        _knownFailures = {for (final f in job.failed) f.imageId};
      });
      if (!job.running) {
        _say('Semua gambar sudah punya deskripsi atau ditandai dekoratif.');
        return;
      }
      _say(
        job.total == 0
            ? 'Memeriksa gambar materi. Hasilnya diumumkan saat selesai.'
            : 'AI mulai membuat deskripsi ${job.total} gambar, satu per satu. '
                  'Hasilnya diumumkan saat selesai atau saat ada yang gagal.',
      );
      _startPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      _say(e.message);
    }
  }

  Future<void> _check({bool initial = false}) async {
    final DescribeStatus job;
    try {
      job = await store.describeStatus(widget.materialId);
    } on ApiException catch (e) {
      if (!mounted || initial) return;
      _stopPolling();
      _say('Progres deskripsi tidak bisa dibaca. ${e.message}');
      return;
    }
    if (!mounted) return;
    final previous = _job;
    final fresh = [
      for (final f in job.failed)
        if (!_knownFailures.contains(f.imageId)) f,
    ];
    setState(() {
      _job = job;
      _knownFailures = {for (final f in job.failed) f.imageId};
    });
    if (initial) {
      if (job.running) _startPolling();
      return;
    }
    if (previous == null || previous.done != job.done || fresh.isNotEmpty) {
      _reloadImages?.call();
    }
    final finished = !job.running && (previous?.running ?? false);
    if (finished) {
      _stopPolling();
      _say(_finishedMessage(job));
    } else if (fresh.isNotEmpty) {
      _say(_failureMessage(fresh));
    }
  }

  String _finishedMessage(DescribeStatus job) {
    final error = job.error;
    if (error != null) return '$error.';
    final done = 'Deskripsi gambar selesai: ${job.done} dari ${job.total}.';
    if (job.failed.isEmpty) return '$done Periksa setiap deskripsi.';
    return '$done ${job.failed.length} gambar gagal. Coba lagi satu per satu '
        'lewat tombol di kartu gambarnya.';
  }

  String _failureMessage(List<FailedImage> fresh) {
    final first = fresh.first;
    final where = first.pageNumber == null
        ? ''
        : ' di halaman ${first.pageNumber}';
    final who = fresh.length == 1
        ? 'Satu gambar$where'
        : '${fresh.length} gambar';
    return '$who gagal dideskripsikan: ${first.message}. Gambar lain tetap '
        'diproses.';
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

  /// Progres proses latar belakang. Teks biasa, bukan liveRegion, supaya
  /// TalkBack tidak membacakan setiap perubahan angka.
  Widget _progress(DescribeStatus job) {
    final running = job.running;
    return AppCard(
      color: AppColors.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            running
                ? 'Sedang berjalan: ${job.progressText}'
                : 'Terakhir: ${job.progressText}',
            style: AppType.titleMedium,
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: job.total == 0 ? null : job.done / job.total,
                minHeight: 10,
                color: AppColors.primary,
                backgroundColor: AppColors.lilac,
              ),
            ),
          ),
          if (job.failed.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${job.failed.length} gambar gagal, bisa dicoba ulang di '
              'kartunya.',
              style: AppType.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final failures = {
      for (final f in job?.failed ?? <FailedImage>[]) f.imageId: f.message,
    };
    return PurpleScaffold(
      appBar: aprevoAppBar('Gambar materi'),
      body: SafeArea(
        child: LoadView<List<PageImage>>(
          loadingMessage: 'Memuat gambar ${widget.materialTitle}.',
          load: () => store.teacherImages(widget.materialId),
          builder: (context, images, reload) {
            _reloadImages = reload;
            return ListView(
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
                    label: _running
                        ? 'Sedang membuat deskripsi...'
                        : 'Buat deskripsi gambar dengan AI',
                    icon: Icons.auto_awesome,
                    onPressed: _running ? null : _describe,
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  Text(_status!, style: AppType.bodyMedium),
                ],
                if (job != null && (job.running || job.total > 0)) ...[
                  const SizedBox(height: 12),
                  _progress(job),
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
                    failure: failures[images[i].id],
                    canRetry: !_running,
                    onRetried: () => _check(),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
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
    this.failure,
    this.canRetry = true,
    this.onRetried,
  });

  final String materialId;
  final PageImage image;
  final int number;
  final int total;

  /// Pesan kalau AI gagal mendeskripsikan gambar ini.
  final String? failure;
  final bool canRetry;
  final VoidCallback? onRetried;

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
  void didUpdateWidget(_ImageCard old) {
    super.didUpdateWidget(old);
    // Deskripsi baru dari AI masuk ke kolom, kecuali guru sedang mengubahnya.
    final before = old.image.description ?? '';
    final after = widget.image.description ?? '';
    if (after != before && _description.text == before) {
      _description.text = after;
    }
  }

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

  Future<void> _retry() async {
    setState(() {
      _saving = true;
      _feedback = 'AI sedang mendeskripsikan gambar ini.';
    });
    String message;
    try {
      final image = await store.retryImageDescription(
        widget.materialId,
        widget.image.id,
      );
      _description.text = image.description ?? '';
      message = 'Deskripsi ${_title.toLowerCase()} dibuat. Periksa hasilnya.';
      widget.onRetried?.call();
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
    final failure = widget.failure;
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
          if (failure != null && !_decorative) ...[
            const SizedBox(height: 10),
            Text('Gagal: $failure.', style: AppType.bodyMedium),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi untuk gambar ini'),
                onPressed: _saving || !widget.canRetry ? null : _retry,
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
