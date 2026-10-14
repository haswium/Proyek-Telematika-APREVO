import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';
import 'material_editor_screen.dart';

/// Batas ukuran PDF materi: 20 MB.
const int kMaxPdfBytes = 20 * 1024 * 1024;

/// Ukuran file untuk dibaca manusia, dibulatkan ke atas: "850 KB",
/// "2,4 MB". Dibulatkan ke atas supaya file 20,04 MB tidak tampil "20,0 MB"
/// padahal ditolak.
String fileSizeLabel(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  final mb = (bytes * 10 / (1024 * 1024)).ceil() / 10;
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Alasan file ditolak, atau `null` kalau boleh diunggah. [size] `null`
/// berarti ukurannya tidak bisa dibaca.
String? pdfProblem(String fileName, int? size) {
  if (!fileName.toLowerCase().endsWith('.pdf')) {
    return 'File $fileName bukan PDF. Pilih file berakhiran .pdf.';
  }
  if (size == null) {
    return 'Ukuran file $fileName tidak bisa dibaca. Coba pilih ulang.';
  }
  if (size > kMaxPdfBytes) {
    return 'File $fileName terlalu besar, ${fileSizeLabel(size)}. Batas '
        'ukuran PDF 20 MB. Pilih file yang lebih kecil.';
  }
  return null;
}

/// File PDF yang dipilih guru. Dipisah dari `PlatformFile` supaya layar ini
/// bisa diuji tanpa membuka pemilih file sungguhan.
class PickedPdf {
  const PickedPdf({
    required this.name,
    required this.size,
    required this.readBytes,
  });

  final String name;

  /// Ukuran dalam byte, `null` kalau tidak bisa dibaca.
  final int? size;
  final Future<Uint8List> Function() readBytes;
}

/// Membuka pemilih file bawaan perangkat, hanya untuk PDF.
Future<PickedPdf?> pickPdfFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (file == null) return null;
  return PickedPdf(
    name: file.name,
    size: file.lengthSync() ?? await file.length(),
    readBytes: file.readAsBytes,
  );
}

enum _Source { pdf, typed }

enum _StatusKind { info, uploading, success, error }

/// Guru membuat materi baru di satu mata pelajaran, dengan dua pilihan
/// sumber: unggah PDF atau ketik isinya. Materi baru selalu draf.
class NewMaterialScreen extends StatefulWidget {
  const NewMaterialScreen({
    super.key,
    required this.subject,
    this.pickFile = pickPdfFile,
  });

  final Subject subject;

  /// Diganti di tes supaya tidak membuka pemilih file sungguhan.
  final Future<PickedPdf?> Function() pickFile;

  @override
  State<NewMaterialScreen> createState() => _NewMaterialScreenState();
}

class _NewMaterialScreenState extends State<NewMaterialScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  _Source _source = _Source.pdf;
  PickedPdf? _file;
  LessonMaterial? _uploaded;

  /// `true` setelah unggahan gagal, supaya tombolnya menjadi "Coba unggah
  /// lagi". Error lain (judul kosong, file ditolak) tidak mengubahnya.
  bool _uploadFailed = false;

  String? _status;
  _StatusKind _statusKind = _StatusKind.info;
  int _statusSerial = 0;

  bool get _uploading => _statusKind == _StatusKind.uploading;
  bool get _locked => _uploading || _uploaded != null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Semua status tampil di liveRegion, jadi TalkBack membacakannya. Kalau
  /// TalkBack mati, dibacakan lewat suara.
  void _setStatus(_StatusKind kind, String? message) {
    setState(() {
      _statusKind = kind;
      _status = message;
      _statusSerial++;
    });
    if (message != null) Speech.feedback(context, message);
  }

  void _choose(_Source source) {
    if (_locked || source == _source) return;
    setState(() {
      _source = source;
      _status = null;
    });
  }

  Future<void> _pick() async {
    final PickedPdf? file;
    try {
      file = await widget.pickFile();
    } catch (_) {
      if (!mounted) return;
      _setStatus(_StatusKind.error, 'Pemilih file tidak bisa dibuka.');
      return;
    }
    if (file == null || !mounted) return;
    final problem = pdfProblem(file.name, file.size);
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
      _setStatus(_StatusKind.error, 'Pilih file PDF dulu.');
      return;
    }
    _setStatus(
      _StatusKind.uploading,
      'Mengunggah ${file.name}. Tunggu sebentar.',
    );
    try {
      final bytes = await file.readBytes();
      final material = await store.uploadMaterialPdf(
        widget.subject,
        title: title,
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _uploaded = material);
      _setStatus(
        _StatusKind.success,
        'Berhasil. ${file.name} diunggah sebagai materi draf $title.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadFailed = true);
      _setStatus(
        _StatusKind.error,
        'Gagal mengunggah ${file.name}. Periksa sambungan internet, lalu '
        'coba lagi.',
      );
    }
  }

  void _createTyped() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _setStatus(_StatusKind.error, 'Judul materi belum diisi.');
      return;
    }
    final material = store.createMaterial(
      widget.subject,
      title,
      _body.text.trim(),
    );
    _openEditor(material);
  }

  void _openEditor(LessonMaterial material) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialEditorScreen(material: material),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdf = _source == _Source.pdf;
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
                      'Dari mana isi materinya?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Materi baru masuk sebagai draf. Siswa belum bisa '
                    'melihatnya sampai kamu publikasikan.',
                    style: TextStyle(color: AppColors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SourceCard(
                    label: 'Unggah PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    selected: pdf,
                    onTap: () => _choose(_Source.pdf),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SourceCard(
                    label: 'Ketik materi',
                    icon: Icons.keyboard_outlined,
                    selected: !pdf,
                    onTap: () => _choose(_Source.typed),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              enabled: !_locked,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: pdf ? TextInputAction.done : null,
              decoration: fieldDecoration('Judul materi'),
            ),
            const SizedBox(height: 12),
            if (pdf) ..._pdfSection() else ..._typedSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _typedSection() {
    return [
      TextField(
        controller: _body,
        maxLines: 8,
        decoration: fieldDecoration('Isi materi'),
      ),
      const SizedBox(height: 12),
      if (_status != null) ...[_statusCard(), const SizedBox(height: 12)],
      PrimaryButton(
        label: 'Lanjut buat soal',
        icon: Icons.arrow_forward,
        onPressed: _createTyped,
      ),
    ];
  }

  List<Widget> _pdfSection() {
    final file = _file;
    return [
      if (file != null) ...[
        _FileRow(file: file),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        icon: const Icon(Icons.attach_file),
        label: Text(file == null ? 'Pilih file PDF' : 'Ganti file PDF'),
        onPressed: _locked ? null : _pick,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        child: Text(
          'Hanya file PDF, paling besar 20 MB.',
          style: AppType.bodySmall,
        ),
      ),
      if (_status != null) ...[_statusCard(), const SizedBox(height: 12)],
      if (_uploaded == null)
        PrimaryButton(
          label: _uploadFailed ? 'Coba unggah lagi' : 'Unggah PDF',
          icon: Icons.cloud_upload_outlined,
          onPressed: _uploading ? null : _upload,
        )
      else
        PrimaryButton(
          label: 'Lanjut buat soal',
          icon: Icons.arrow_forward,
          onPressed: () => _openEditor(_uploaded!),
        ),
    ];
  }

  Widget _statusCard() {
    final message = _status!;
    final key = ValueKey('status-$_statusSerial');
    if (_statusKind == _StatusKind.error) {
      return ErrorCard(key: key, message: message);
    }
    final Widget icon;
    if (_statusKind == _StatusKind.uploading &&
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
      icon = Icon(
        switch (_statusKind) {
          _StatusKind.uploading => Icons.hourglass_top,
          _StatusKind.success => Icons.check_circle,
          _ => Icons.description_outlined,
        },
        color: AppColors.primary,
      );
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
            Expanded(
              child: Text(message, style: AppType.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// File PDF yang dipilih: nama dan ukurannya, dibaca sebagai satu kalimat.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final PickedPdf file;

  @override
  Widget build(BuildContext context) {
    final size = fileSizeLabel(file.size ?? 0);
    return Semantics(
      label: 'File PDF: ${file.name}, $size',
      excludeSemantics: true,
      child: AppCard(
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf, color: AppColors.primary),
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

/// Pilihan sumber materi. Dibaca TalkBack sebagai satu tombol dalam grup:
/// "Sumber materi: Unggah PDF, dipilih".
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sumber materi: $label',
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      excludeSemantics: true,
      child: Bouncy(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.ink, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.ink, size: 28),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
