/// Satu halaman di pratinjau materi dari teks tempelan, sebelum disimpan.
/// Pemecahannya dihitung backend (`POST /teacher/materials/text/preview`),
/// supaya pratinjau sama persis dengan yang nanti disimpan.
class PastedPage {
  const PastedPage({
    required this.title,
    required this.content,
    required this.paragraphs,
    required this.subheadings,
    required this.listItems,
    required this.words,
  });

  factory PastedPage.fromJson(Map<String, dynamic> json) => PastedPage(
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    paragraphs: (json['paragraph_count'] as num?)?.toInt() ?? 0,
    subheadings: (json['subheading_count'] as num?)?.toInt() ?? 0,
    listItems: (json['list_item_count'] as num?)?.toInt() ?? 0,
    words: (json['word_count'] as num?)?.toInt() ?? 0,
  );

  final String title;
  final String content;
  final int paragraphs;
  final int subheadings;
  final int listItems;
  final int words;

  /// "2 paragraf, 1 subjudul, 3 butir daftar, 40 kata". Jumlah nol dilewati,
  /// kecuali kata.
  String get summary => [
    if (paragraphs > 0) '$paragraphs paragraf',
    if (subheadings > 0) '$subheadings subjudul',
    if (listItems > 0) '$listItems butir daftar',
    '$words kata',
  ].join(', ');
}

/// Keterangan aturan pembagian halaman, tampil di layar dan dibaca TalkBack.
const String kPasteRule =
    'Halaman baru dimulai di setiap judul bagian. Judul bagian adalah baris '
    'pendek yang berdiri sendiri, kurang dari 60 huruf, dan tidak diakhiri '
    'titik. Kalau ingin menentukan sendiri, awali judul dengan tanda pagar '
    'dan spasi, misalnya "# Iklim".';
