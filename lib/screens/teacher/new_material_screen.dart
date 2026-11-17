import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/material_file.dart';
import '../../models/models.dart';
import '../../services/a11y_focus.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';
import 'material_editor_screen.dart';

export '../../models/material_file.dart' show fileSizeLabel, uploadProblem;

/// Jeda antar pemeriksaan status pengubahan file.
const Duration kConversionPollInterval = Duration(seconds: 3);

/// File yang dipilih guru. Dipisah dari `PlatformFile` supaya layar ini bisa
/// diuji tanpa membuka pemilih file sungguhan.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.size,
    required this.readBytes,
  });

  final String name;

  /// Ukuran dalam byte, `null` kalau tidak bisa dibaca.
  final int? size;
  final Future<Uint8List> Function() readBytes;
}

/// Membuka pemilih file bawaan perangkat untuk semua format yang didukung.
/// Format Office lama ikut bisa dipilih, supaya guru mendapat pesan cara
/// menyimpan ulang, bukan file yang tidak bisa dipilih tanpa penjelasan.
Future<PickedFile?> pickMaterialFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: [...kUploadFormats.keys, ...kOldOfficeFormats.keys],
  );
  if (file == null) return null;
  return PickedFile(
    name: file.name,
    size: file.lengthSync() ?? await file.length(),
    readBytes: file.readAsBytes,
  );
}

enum _StatusKind { info, working, success, error }

/// Guru mengunggah satu file materi: PDF, Word, PowerPoint, Excel, CSV, teks,
/// foto, atau audio. Semuanya diubah backend ke halaman yang sama seperti
/// PDF, di latar belakang. Layar ini memantau statusnya dan mengumumkan setiap
/// langkah baru. Materi baru selalu draf.
class NewMaterialScreen extends StatefulWidget {
  const NewMaterialScreen({
    super.key,
    required this.subject,
    this.pickFile = pickMaterialFile,
    this.pollInterval = kConversionPollInterval,
  });

  final Subject subject;

  /// Diganti di tes supaya tidak membuka pemilih file sungguhan.
  final Future<PickedFile?> Function() pickFile;
  final Duration pollInterval;

  @override
  State<NewMaterialScreen> createState() => _NewMaterialScreenState();
}

class _NewMaterialScreenState extends State<NewMaterialScreen> {
  final _title = TextEditingController();
  final _statusKey = GlobalKey(debugLabel: 'status unggah');
  PickedFile? _file;

  /// Materi yang sedang atau sudah diproses.
  LessonMaterial? _material;
  bool _done = false;
  Timer? _poll;

  /// `true` setelah unggahan gagal, supaya tombolnya menjadi "Coba unggah
  /// lagi". Error lain (judul kosong, file ditolak) tidak mengubahnya.
  bool _uploadFailed = false;

  String? _status;
  _StatusKind _statusKind = _StatusKind.info;
  int _statusSerial = 0;

  bool get _working => _statusKind == _StatusKind.working;
  bool get _locked => _working || _done;

  @override
  void dispose() {
    _poll?.cancel();
    _title.dispose();
    super.dispose();
  }

  /// Semua status tampil di liveRegion, jadi TalkBack membacakannya. Pesan
  /// yang sama tidak diulang, supaya polling tidak membuat TalkBack berisik.
  void _setStatus(_StatusKind kind, String? message) {
    if (kind == _statusKind && message == _status) return;
    setState(() {
      _statusKind = kind;
      _status = message;
      _statusSerial++;
    });
  }

  Future<void> _pick() async {
    final PickedFile? file;
    try {
      file = await widget.pickFile();
    } catch (_) {
      if (!mounted) return;
      _setStatus(_StatusKind.error, 'Pemilih file tidak bisa dibuka.');
      return;
    }
    if (file == null || !mounted) return;
    final problem = uploadProblem(file.name, file.size);
    if (problem != null) {
      setState(() => _file = null);
      _setStatus(_StatusKind.error, problem);
      return;
    }
    setState(() {
      _file = file;
      _uploadFailed = false;
    });
    _setStatus(
      _StatusKind.info,
      'File dipilih: ${file.name}, ${fileSizeLabel(file.size!)}.',
    );
  }

  Future<void> _upload() async {
    final file = _file;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _setStatus(_StatusKind.error, 'Judul materi belum diisi.');
      return;
    }
    if (file == null) {
      _setStatus(_StatusKind.error, 'Pilih file materi dulu.');
      return;
    }
    _setStatus(
      _StatusKind.working,
      'Mengunggah ${file.name}. Tunggu sebentar.',
    );
    final Uint8List bytes;
    try {
      bytes = await file.readBytes();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadFailed = true);
      _setStatus(
        _StatusKind.error,
        'File ${file.name} tidak bisa dibaca. Pilih ulang filenya, lalu '
        'coba lagi.',
      );
      return;
    }
    try {
      final material = await store.uploadMaterialFile(
        widget.subject,
        title: title,
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _material = material);
      _onConversion(material.conversion);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _uploadFailed = true);
      _setStatus(
        _StatusKind.error,
        'Gagal mengunggah ${file.name}. ${e.message}',
      );
    }
  }

  void _onConversion(MaterialConversion conversion) {
    if (conversion.processing) {
      _setStatus(_StatusKind.working, conversion.message);
      _poll?.cancel();
      _poll = Timer(widget.pollInterval, _check);
      return;
    }
    if (conversion.failed) {
      _failed(conversion);
      return;
    }
    _finished(conversion);
  }

  Future<void> _check() async {
    final material = _material;
    if (material == null || !mounted) return;
    try {
      final conversion = await store.materialConversion(material.id);
      if (!mounted) return;
      _onConversion(conversion);
    } on ApiException catch (_) {
      // Gangguan sesaat: coba lagi tanpa mengubah pesan.
      if (!mounted) return;
      _poll = Timer(widget.pollInterval, _check);
    }
  }

  /// Materi yang gagal dihapus, supaya tidak menumpuk sebagai draf rusak.
  Future<void> _failed(MaterialConversion conversion) async {
    final material = _material;
    try {
      if (material != null) await store.deleteFailedMaterial(material.id);
    } on ApiException catch (_) {
      // Tetap tampil di daftar materi sebagai "Gagal diproses".
    }
    if (!mounted) return;
    setState(() {
      _material = null;
      _uploadFailed = true;
    });
    _setStatus(
      _StatusKind.error,
      '${_file?.name ?? 'File'} gagal diproses. ${conversion.error ?? ''}'
          .trim(),
    );
    moveScreenReaderFocus(_statusKey);
  }

  Future<void> _finished(MaterialConversion conversion) async {
    final material = _material!;
    final images = await _describeImages(material.id);
    if (!mounted) return;
    setState(() => _done = true);
    _setStatus(
      _StatusKind.success,
      '${conversion.step ?? 'Selesai.'} $images Materi draf ${material.title} '
      'siap diperiksa, diberi jadwal, dan soal.',
    );
    moveScreenReaderFocus(_statusKey);
  }

  /// Deskripsi AI dimulai setelah konversi dan berjalan di latar belakang.
  /// Kalau gagal dimulai, materi tetap tersimpan; guru bisa mencoba lagi di
  /// menu Gambar dan deskripsi.
  Future<String> _describeImages(String materialId) async {
    try {
      final job = await store.startDescribeImages(materialId);
      if (job.total == 0) return '';
      return 'AI sedang membuat deskripsi ${job.total} gambar di latar '
          'belakang. Periksa hasilnya di menu Gambar dan deskripsi sebelum '
          'terbit.';
    } on ApiException catch (e) {
      return 'Deskripsi gambar belum dibuat: ${e.message} Coba lagi di menu '
          'Gambar dan deskripsi.';
    }
  }

  void _openEditor() {
    final material = _material;
    if (material == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MaterialEditorScreen(subject: widget.subject, material: material),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return PurpleScaffold(
      appBar: aprevoAppBar('Materi baru'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            HeroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Pill(
                    widget.subject.name,
                    icon: Icons.folder_outlined,
                    color: const Color(0x33FFFFFF),
                    textColor: AppColors.white,
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    child: const Text(
                      'Unggah materi',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'File diubah menjadi halaman yang bisa dibaca siswa satu '
                    'per satu. Gambar dideskripsikan AI, foto dibaca '
                    'tulisannya, dan audio dibuatkan transkrip. Materi baru '
                    'masuk sebagai draf sampai kamu publikasikan.',
                    style: TextStyle(color: AppColors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              enabled: !_locked,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: fieldDecoration('Judul materi'),
            ),
            const SizedBox(height: 12),
            if (file != null) ...[
              _FileRow(file: file),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: Text(file == null ? 'Pilih file materi' : 'Ganti file'),
              onPressed: _locked ? null : _pick,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              child: Text(kUploadHelp, style: AppType.bodySmall),
            ),
            KeyedSubtree(
              key: _statusKey,
              child: _status == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _statusCard(),
                    ),
            ),
            if (!_done)
              PrimaryButton(
                label: _working
                    ? 'Sedang diproses...'
                    : _uploadFailed
                    ? 'Coba unggah lagi'
                    : 'Unggah materi',
                icon: Icons.cloud_upload_outlined,
                onPressed: _working ? null : _upload,
              )
            else
              PrimaryButton(
                label: 'Lanjut periksa materi, jadwal, dan soal',
                icon: Icons.arrow_forward,
                onPressed: _openEditor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final message = _status!;
    final key = ValueKey('status-$_statusSerial');
    if (_statusKind == _StatusKind.error) {
      return ErrorCard(key: key, message: message);
    }
    final Widget icon;
    if (_statusKind == _StatusKind.working &&
        !MediaQuery.of(context).disableAnimations) {
      icon = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.primary,
        ),
      );
    } else {
      icon = Icon(switch (_statusKind) {
        _StatusKind.working => Icons.hourglass_top,
        _StatusKind.success => Icons.check_circle,
        _ => Icons.description_outlined,
      }, color: AppColors.primary);
    }
    // liveRegion dengan key baru tiap status, sama seperti ErrorCard,
    // supaya TalkBack membacakan setiap perubahan status.
    return Semantics(
      key: key,
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: AppCard(
        color: _statusKind == _StatusKind.success
            ? AppColors.highlight
            : AppColors.white,
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: AppType.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

IconData _fileIcon(String name) => switch (extensionOf(name)) {
  'pdf' => Icons.picture_as_pdf,
  'docx' || 'txt' || 'md' => Icons.description_outlined,
  'pptx' => Icons.slideshow_outlined,
  'xlsx' || 'csv' => Icons.table_chart_outlined,
  'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
  'mp3' || 'm4a' || 'wav' || 'ogg' => Icons.audiotrack_outlined,
  _ => Icons.insert_drive_file_outlined,
};

/// File yang dipilih: jenis, nama, dan ukurannya, dibaca sebagai satu kalimat.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final PickedFile file;

  @override
  Widget build(BuildContext context) {
    final size = fileSizeLabel(file.size ?? 0);
    final format = kUploadFormats[extensionOf(file.name)]?.label ?? 'materi';
    return Semantics(
      label: 'File $format: ${file.name}, $size',
      excludeSemantics: true,
      child: AppCard(
        child: Row(
          children: [
            Icon(_fileIcon(file.name), color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.name, style: AppType.titleMedium),
                  Text(size, style: AppType.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
