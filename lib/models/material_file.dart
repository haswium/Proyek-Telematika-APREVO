/// Format file materi yang bisa diunggah guru, dan status konversinya.
///
/// Backend tetap mengenali jenis file dari isinya; pemeriksaan di sini hanya
/// supaya guru langsung tahu kalau filenya pasti ditolak (format lama, terlalu
/// besar) tanpa menunggu unggahan selesai.
library;

const int _mb = 1024 * 1024;

class UploadFormat {
  const UploadFormat(this.label, this.maxBytes, this.contentType);

  final String label;
  final int maxBytes;
  final String contentType;
}

/// Ekstensi yang didukung, sama dengan `backend/file_formats.py`.
const Map<String, UploadFormat> kUploadFormats = {
  'pdf': UploadFormat('PDF', 20 * _mb, 'application/pdf'),
  'docx': UploadFormat(
    'Word',
    20 * _mb,
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  'pptx': UploadFormat(
    'PowerPoint',
    20 * _mb,
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  ),
  'xlsx': UploadFormat(
    'Excel',
    10 * _mb,
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  'csv': UploadFormat('CSV', 2 * _mb, 'text/csv'),
  'txt': UploadFormat('teks', 2 * _mb, 'text/plain'),
  'md': UploadFormat('Markdown', 2 * _mb, 'text/markdown'),
  'jpg': UploadFormat('gambar', 10 * _mb, 'image/jpeg'),
  'jpeg': UploadFormat('gambar', 10 * _mb, 'image/jpeg'),
  'png': UploadFormat('gambar', 10 * _mb, 'image/png'),
  'mp3': UploadFormat('audio', 25 * _mb, 'audio/mpeg'),
  'm4a': UploadFormat('audio', 25 * _mb, 'audio/mp4'),
  'wav': UploadFormat('audio', 25 * _mb, 'audio/wav'),
  'ogg': UploadFormat('audio', 25 * _mb, 'audio/ogg'),
};

/// Format Office lama dan penggantinya.
const Map<String, String> kOldOfficeFormats = {
  'doc': 'docx',
  'ppt': 'pptx',
  'pps': 'pptx',
  'xls': 'xlsx',
};

/// Teks bantuan di layar unggah, dibaca TalkBack.
const String kUploadHelp =
    'Format yang didukung: PDF, Word (.docx), PowerPoint (.pptx), Excel '
    '(.xlsx), CSV, teks (.txt, .md), foto atau gambar (.jpg, .png), dan audio '
    '(.mp3, .m4a, .wav, .ogg). Batas ukuran: PDF, Word, dan PowerPoint 20 MB; '
    'Excel dan gambar 10 MB; CSV dan teks 2 MB; audio 25 MB dan paling lama 15 '
    'menit. Format lama .doc, .ppt, dan .xls perlu disimpan ulang dulu.';

String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
}

/// Ukuran file untuk dibaca manusia, dibulatkan ke atas: "850 KB",
/// "2,4 MB". Dibulatkan ke atas supaya file 20,04 MB tidak tampil "20,0 MB"
/// padahal ditolak.
String fileSizeLabel(int bytes) {
  if (bytes < _mb) return '${(bytes / 1024).ceil()} KB';
  final mb = (bytes * 10 / _mb).ceil() / 10;
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Alasan file ditolak sebelum diunggah, atau `null`. [size] `null` berarti
/// ukurannya tidak bisa dibaca.
String? uploadProblem(String fileName, int? size) {
  final extension = extensionOf(fileName);
  final replacement = kOldOfficeFormats[extension];
  if (replacement != null) {
    return 'Format .$extension lama tidak didukung. Simpan ulang $fileName '
        'sebagai .$replacement lalu unggah lagi.';
  }
  final format = kUploadFormats[extension];
  if (format == null) {
    return 'File $fileName tidak didukung. Pilih PDF, Word, PowerPoint, '
        'Excel, CSV, teks, gambar, atau audio.';
  }
  if (size == null) {
    return 'Ukuran file $fileName tidak bisa dibaca. Coba pilih ulang.';
  }
  if (size > format.maxBytes) {
    return 'File $fileName terlalu besar, ${fileSizeLabel(size)}. Batas '
        'ukuran ${format.label} ${format.maxBytes ~/ _mb} MB. Pilih file yang '
        'lebih kecil.';
  }
  return null;
}

String contentTypeFor(String fileName) =>
    kUploadFormats[extensionOf(fileName)]?.contentType ??
    'application/octet-stream';

enum ConversionState { processing, ready, failed }

/// Status pengubahan file ke halaman materi
/// (`GET /teacher/materials/{id}/conversion`).
class MaterialConversion {
  const MaterialConversion({
    this.state = ConversionState.ready,
    this.step,
    this.error,
    this.sourceType = 'pdf',
    this.sectionCount = 0,
  });

  factory MaterialConversion.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MaterialConversion();
    return MaterialConversion(
      state: switch (json['status']) {
        'processing' => ConversionState.processing,
        'failed' => ConversionState.failed,
        _ => ConversionState.ready,
      },
      step: json['step'] as String?,
      error: json['error'] as String?,
      sourceType: json['source_type'] as String? ?? 'pdf',
      sectionCount: (json['section_count'] as num?)?.toInt() ?? 0,
    );
  }

  final ConversionState state;

  /// Langkah yang sedang berjalan, atau ringkasan setelah selesai
  /// ("Selesai: 5 halaman, 2 gambar.").
  final String? step;
  final String? error;
  final String sourceType;
  final int sectionCount;

  bool get processing => state == ConversionState.processing;
  bool get failed => state == ConversionState.failed;
  bool get ready => state == ConversionState.ready;

  /// Kalimat yang diumumkan TalkBack.
  String get message => switch (state) {
    ConversionState.processing => step ?? 'Sedang diproses.',
    ConversionState.failed => 'Gagal diproses. ${error ?? ''}'.trim(),
    ConversionState.ready => step ?? 'Selesai.',
  };
}

/// Alamat sementara untuk memutar audio materi (`GET /materials/{id}/audio`).
class MaterialAudio {
  const MaterialAudio({required this.url, this.durationSeconds});

  factory MaterialAudio.fromJson(Map<String, dynamic> json) => MaterialAudio(
    url: json['url'] as String? ?? '',
    durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
  );

  final String url;
  final int? durationSeconds;
}

/// "1 menit 20 detik", "45 detik", "5 menit". Untuk dibaca TalkBack.
String spokenDuration(Duration duration) {
  final total = duration.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  if (minutes == 0) return '$seconds detik';
  if (seconds == 0) return '$minutes menit';
  return '$minutes menit $seconds detik';
}

final _imageMarker = RegExp(r'^\[\[gambar:[\w-]+\]\]$');
final _tableMarker = RegExp(r'^\[\[tabel:\{.*\}\]\]$');

/// Isi halaman yang bisa diedit guru sebagai teks biasa. Penanda gambar dan
/// tabel diganti baris pendek "[Gambar 1]" dan "[Tabel 1]", yang lebih mudah
/// dibaca dan diketik daripada penanda aslinya.
class EditablePageText {
  EditablePageText._(this.text, this._markers);

  factory EditablePageText.fromContent(String content) {
    final markers = <String, String>{};
    var images = 0;
    var tables = 0;
    final lines = <String>[];
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      String? token;
      if (_imageMarker.hasMatch(line)) token = '[Gambar ${++images}]';
      if (_tableMarker.hasMatch(line)) token = '[Tabel ${++tables}]';
      if (token != null) {
        markers[token] = line;
        lines.add(token);
      } else {
        lines.add(raw);
      }
    }
    return EditablePageText._(lines.join('\n'), markers);
  }

  /// Teks untuk kolom edit.
  final String text;
  final Map<String, String> _markers;

  bool get hasMarkers => _markers.isNotEmpty;

  /// Isi halaman dari teks hasil edit, dengan penanda asli dikembalikan.
  /// `null` kalau ada baris "[Gambar n]" atau "[Tabel n]" yang hilang,
  /// berulang, atau urutannya berubah.
  String? restore(String edited) {
    final seen = <String>[];
    final lines = <String>[];
    for (final raw in edited.split('\n')) {
      final marker = _markers[raw.trim()];
      if (marker != null) {
        seen.add(raw.trim());
        lines.add(marker);
      } else {
        lines.add(raw);
      }
    }
    final expected = _markers.keys.toList();
    if (seen.length != expected.length) return null;
    for (var i = 0; i < seen.length; i++) {
      if (seen[i] != expected[i]) return null;
    }
    return lines.join('\n');
  }
}
