import re

import pymupdf

from pdf_sections import (
    normalize_content,
    page_images,
    plain_text,
    replace_table,
    split_pdf_bytes,
    table_marker,
    table_row_label,
    tables_in,
)

FONT = pymupdf.Font("helv")
IMAGE_LINE = re.compile(r"^\[\[gambar:xref-\d+\]\]$")


def place_words(page, x, y, text, size, word_gap):
    """Menulis kata satu per satu tanpa karakter spasi, seperti PDF Canva."""
    for word in text.split():
        page.insert_text((x, y), word, fontsize=size)
        x += FONT.text_length(word, size) + size * word_gap


def image(page, rect, shade):
    pixmap = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 8, 8), False)
    # Warna berbeda supaya tiap gambar punya xref sendiri.
    pixmap.clear_with(shade)
    return page.insert_image(rect, pixmap=pixmap, keep_proportion=False)


def make_pdf(pages, word_gap=0.1, image_on_page=None):
    """pages: daftar halaman, tiap halaman daftar (teks, ukuran huruf).

    Teks kosong ("", 0) membuat jarak kosong satu baris. ("GAMBAR", sisi)
    menaruh gambar persegi di posisi itu. Jarak antar kata 0,1 kali ukuran
    huruf membuat MuPDF tidak menyisipkan spasi.
    """
    doc = pymupdf.open()
    shade = 100
    for page_number, lines in enumerate(pages, start=1):
        page = doc.new_page()
        y = 72
        for text, size in lines:
            if text == "GAMBAR":
                image(page, pymupdf.Rect(72, y, 72 + size, y + size), shade)
                shade += 20
                y += size + 20
                continue
            if text:
                place_words(page, 72, y, text, size, word_gap)
            y += (size or 11) * 1.3
        if image_on_page == page_number:
            image(page, pymupdf.Rect(72, y + 10, 140, y + 78), 200)
    data = doc.tobytes()
    doc.close()
    return data


def test_kata_tanpa_spasi_dipisah_dari_jaraknya():
    pdf = make_pdf([[("Budi mengeluarkan amplop coklat dari tas.", 11)]])
    # Pastikan PDF tiruan memang memunculkan masalahnya.
    with pymupdf.open(stream=pdf, filetype="pdf") as doc:
        assert "Budimengeluarkanamplopcoklat" in doc[0].get_text()
    page = split_pdf_bytes(pdf)[0]
    assert page.content == "Budi mengeluarkan amplop coklat dari tas."


def test_spasi_asli_di_pdf_tetap_satu_spasi():
    pdf = make_pdf([[("Budi menabung setiap hari.", 11)]], word_gap=0.3)
    assert split_pdf_bytes(pdf)[0].content == "Budi menabung setiap hari."


def test_baris_terpotong_digabung_menjadi_paragraf():
    pdf = make_pdf(
        [
            [
                ("Budi mengeluarkan amplop coklat", 11),
                ("dari dalam tasnya lalu membuka-", 11),
                ("nya pelan-pelan.", 11),
                ("", 0),
                ("Ibu tersenyum melihatnya.", 11),
            ]
        ]
    )
    assert split_pdf_bytes(pdf)[0].content.split("\n") == [
        "Budi mengeluarkan amplop coklat dari dalam tasnya lalu membukanya "
        "pelan-pelan.",
        "Ibu tersenyum melihatnya.",
    ]


def test_judul_halaman_dari_huruf_terbesar():
    pdf = make_pdf(
        [
            [
                ("Ayo Menabung", 24),
                ("Mengenal Uang", 16),
                ("Uang dipakai untuk membeli barang.", 11),
            ]
        ]
    )
    page = split_pdf_bytes(pdf)[0]
    assert page.title == "Ayo Menabung"
    assert page.content.split("\n") == [
        "## Mengenal Uang",
        "Uang dipakai untuk membeli barang.",
    ]


def test_keterangan_sumber_tidak_masuk_paragraf():
    pdf = make_pdf(
        [
            [
                ("Budi membuka aplikasi ScratchJr", 11),
                ("Sumber : Canva Sites", 8),
                ("di tablet milik kakaknya.", 11),
            ]
        ],
        image_on_page=1,
    )
    page = split_pdf_bytes(pdf)[0]
    assert "Sumber" not in page.content
    assert "Canva" not in page.content
    assert plain_text(page.content).split("\n") == [
        "Budi membuka aplikasi ScratchJr",
        "di tablet milik kakaknya.",
    ]
    assert page.image_count == 1


def test_satu_bagian_per_halaman():
    pdf = make_pdf(
        [
            [("Bab Satu", 20), ("Isi halaman pertama.", 11)],
            [("Isi halaman kedua tanpa judul.", 11)],
        ]
    )
    pages = split_pdf_bytes(pdf)
    assert [(p.title, p.page_start, p.page_end) for p in pages] == [
        ("Bab Satu", 1, 1),
        ("", 2, 2),
    ]
    assert pages[1].content == "Isi halaman kedua tanpa judul."


def test_halaman_tanpa_teks_tetap_ada():
    pages = split_pdf_bytes(make_pdf([[]], image_on_page=1))
    assert len(pages) == 1
    assert pages[0].title == ""
    assert IMAGE_LINE.match(pages[0].content)
    assert pages[0].image_count == 1


def test_gambar_di_urutan_baca_di_antara_paragraf():
    pdf = make_pdf(
        [
            [
                ("Ayo Menabung", 24),
                ("Budi mengeluarkan amplop coklat.", 11),
                ("GAMBAR", 120),
                ("Ibu tersenyum melihatnya.", 11),
                ("GAMBAR", 100),
            ]
        ]
    )
    lines = split_pdf_bytes(pdf)[0].content.split("\n")
    assert len(lines) == 4
    assert lines[0] == "Budi mengeluarkan amplop coklat."
    assert IMAGE_LINE.match(lines[1])
    assert lines[2] == "Ibu tersenyum melihatnya."
    assert IMAGE_LINE.match(lines[3])
    assert lines[1] != lines[3]


def test_gambar_yang_sama_dipakai_dengan_kunci_yang_sama():
    doc = pymupdf.open()
    for _ in range(2):
        page = doc.new_page()
        place_words(page, 72, 72, "Isi halaman.", 11, 0.3)
    xref = image(doc[0], pymupdf.Rect(72, 100, 200, 228), 50)
    doc[1].insert_image(pymupdf.Rect(72, 100, 200, 228), xref=xref)
    pages = split_pdf_bytes(doc.tobytes())
    markers = [p.content.split("\n")[1] for p in pages]
    assert markers[0] == markers[1] == f"[[gambar:xref-{xref}]]"


def test_ikon_kecil_dan_latar_penuh_ditandai_dekoratif():
    doc = pymupdf.open()
    page = doc.new_page()
    image(page, page.rect, 10)
    image(page, pymupdf.Rect(72, 72, 96, 96), 60)
    image(page, pymupdf.Rect(72, 200, 272, 400), 120)
    with pymupdf.open(stream=doc.tobytes(), filetype="pdf") as reopened:
        images = page_images(reopened[0], 1)
    assert [i.decorative for i in images] == [True, True, False]


def test_teks_polos_tanpa_penanda_untuk_ai_soal():
    content = "## Mengenal Uang\n[[gambar:xref-4]]\nUang dipakai untuk membeli."
    assert plain_text(content) == "Mengenal Uang\nUang dipakai untuk membeli."


def test_butir_menjadi_daftar_terpisah_dari_kalimat_pengantar():
    doc = pymupdf.open()
    page = doc.new_page()
    place_words(page, 72, 72, "Pada hari ini kamu akan belajar:", 11, 0.1)
    # Butir menempel di baris yang sama.
    place_words(page, 72, 88, "• Mengenal aplikasi ScratchJr", 11, 0.1)
    # Tanda butir terpisah dengan ukuran lain, sejajar dengan teksnya.
    page.insert_text((72, 104), "•", fontsize=14)
    place_words(page, 86, 104, "Membuat karakter bergerak dan", 11, 0.1)
    # Lanjutan butir menjorok sejajar teks butir.
    place_words(page, 86, 118, "berbicara", 11, 0.1)
    place_words(page, 72, 134, "Ayo mulai sekarang.", 11, 0.1)
    lines = split_pdf_bytes(doc.tobytes())[0].content.split("\n")
    assert lines == [
        "Pada hari ini kamu akan belajar:",
        "- Mengenal aplikasi ScratchJr",
        "- Membuat karakter bergerak dan berbicara",
        "Ayo mulai sekarang.",
    ]


def test_tanda_butir_simbol_dibuang():
    from pdf_sections import Line, mark_bullets

    def line(text, x0=72.0):
        return Line(text, 11, False, x0, 0, 300, 11, 10)

    marked = mark_bullets(
        [line("●Mengenal ScratchJr"), line(" Menabung"), line("● ", 72)]
    )
    assert [(m.text, m.bullet) for m in marked[:2]] == [
        ("Mengenal ScratchJr", True),
        ("Menabung", True),
    ]


def test_tanda_minus_dalam_kalimat_bukan_butir():
    pdf = make_pdf([[("-5 derajat adalah suhu di bawah nol.", 11)]])
    assert split_pdf_bytes(pdf)[0].content == "-5 derajat adalah suhu di bawah nol."


def test_dua_kolom_dibaca_kolom_kiri_dulu():
    """Seperti halaman 2 ScratchJR: dua blok berdampingan, kalimatnya
    terpotong di ketinggian yang sama."""
    doc = pymupdf.open()
    page = doc.new_page()
    image(page, pymupdf.Rect(145, 177, 232, 250), 70)
    image(page, pymupdf.Rect(378, 177, 466, 253), 90)
    place_words(page, 144, 295, "Kirim Pesan", 12, 0.3)
    place_words(page, 368, 295, "Terima Pesan", 12, 0.3)
    place_words(page, 96, 325, "Satu sprite mengirim aba-aba", 11, 0.3)
    place_words(page, 339, 325, "Ketika sprite lain mulai saat", 11, 0.3)
    place_words(page, 88, 341, "ke sprite lain.", 11, 0.3)
    place_words(page, 361, 341, "menerima aba-aba", 11, 0.3)
    place_words(page, 72, 390, "Pesan seperti aba-aba di kelas.", 11, 0.3)
    lines = split_pdf_bytes(doc.tobytes())[0].content.split("\n")
    text = [line for line in lines if not IMAGE_LINE.match(line)]
    assert text == [
        "Kirim Pesan",
        "Satu sprite mengirim aba-aba ke sprite lain.",
        "Terima Pesan",
        "Ketika sprite lain mulai saat menerima aba-aba",
        "Pesan seperti aba-aba di kelas.",
    ]
    # Gambar kolom kiri sebelum teks kolom kiri, gambar kanan sesudahnya.
    assert IMAGE_LINE.match(lines[0])
    assert IMAGE_LINE.match(lines[3])


def test_tabel_satu_baris_per_sel_tetap_dibaca_per_baris():
    doc = pymupdf.open()
    page = doc.new_page()
    for row, (name, age) in enumerate(
        [("Nama", "Umur"), ("Budi", "delapan"), ("Gia", "sembilan")]
    ):
        y = 100 + row * 30
        place_words(page, 72, y, name, 11, 0.3)
        place_words(page, 300, y, age, 11, 0.3)
    lines = split_pdf_bytes(doc.tobytes())[0].content.split("\n")
    assert lines == ["Nama", "Umur", "Budi", "delapan", "Gia", "sembilan"]


def test_spasi_sebelum_tanda_baca_dibuang():
    pdf = make_pdf([[("Pada hari ini kamu akan belajar :", 11)]], word_gap=0.3)
    assert split_pdf_bytes(pdf)[0].content == "Pada hari ini kamu akan belajar:"


def test_tabel_gambar_dan_keterangan_tetap_dibaca_per_baris():
    """Seperti halaman 5 ScratchJR: gambar blok di kiri, nama dan penjelasan
    di kanan."""
    doc = pymupdf.open()
    page = doc.new_page()
    for row, (name, text) in enumerate(
        [("Say", "Untuk membuat percakapan"), ("Move Right", "Berjalan ke kanan")]
    ):
        y = 100 + row * 80
        image(page, pymupdf.Rect(72, y, 132, y + 60), 60 + row * 30)
        place_words(page, 200, y + 15, name, 11, 0.3)
        place_words(page, 200, y + 30, text, 11, 0.3)
    lines = split_pdf_bytes(doc.tobytes())[0].content.split("\n")
    text = [line for line in lines if not IMAGE_LINE.match(line)]
    assert text == [
        "Say Untuk membuat percakapan",
        "Move Right Berjalan ke kanan",
    ]
    assert [bool(IMAGE_LINE.match(line)) for line in lines] == [
        True,
        False,
        True,
        False,
    ]


# Teks halaman 2 materi ScratchJR (Sesi 7 - Mengirim Pesan Rahasia).
SCRATCHJR_PAGE_2_ITEMS = [
    "Membuka modul pembelajaran CodeJR.",
    "Mengenal code block Send Message di CodeJR.",
    "Mengenal code block Receive Message di CodeJR.",
    "Belajar bahwa sprite bisa mengirim pesan agar sprite lain melakukan sesuatu.",
    "Membuat satu project CodeJR dengan tema Amplop Ajaib.",
]


def test_halaman_2_scratchjr_tanda_butir_di_tengah_baris_dipecah():
    """Butir pertama menempel di baris kalimat pengantar, butir lain di
    baris sendiri dengan tanda yang menempel."""
    doc = pymupdf.open()
    page = doc.new_page()
    place_words(page, 72, 74, "2. Send Message dan Receive Message", 16, 0.1)
    place_words(
        page, 72, 109, "Pesan di CodeJr ini sebenarnya seperti aba-aba.", 11, 0.1
    )
    place_words(
        page,
        72,
        150,
        f"Pada hari ini kamu akan belajar : • {SCRATCHJR_PAGE_2_ITEMS[0]}",
        11,
        0.1,
    )
    y = 170
    for item in SCRATCHJR_PAGE_2_ITEMS[1:]:
        place_words(page, 72, y, f"•{item}", 11, 0.1)
        y += 20
    section = split_pdf_bytes(doc.tobytes())[0]
    # Judul bernomor tetap judul halaman, bukan butir.
    assert section.title == "2. Send Message dan Receive Message"
    assert section.content.split("\n") == [
        "Pesan di CodeJr ini sebenarnya seperti aba-aba.",
        "Pada hari ini kamu akan belajar:",
        *[f"- {item}" for item in SCRATCHJR_PAGE_2_ITEMS],
    ]
    assert "•" not in section.content


def test_daftar_bernomor_memakai_nomor_aslinya():
    pdf = make_pdf(
        [
            [
                ("Langkah membuat project:", 11),
                ("", 0),
                ("10. Klik icon gambar dan pilih background CLASSROOM.", 11),
                ("", 0),
                ("11. Masukkan 2 sprite.", 11),
                ("", 0),
                ("a) Sprite Budi", 11),
                ("", 0),
                ("b) Sprite Gia", 11),
                ("", 0),
                ("M. Rizki membantu Budi.", 11),
            ]
        ]
    )
    assert split_pdf_bytes(pdf)[0].content.split("\n") == [
        "Langkah membuat project:",
        "10. Klik icon gambar dan pilih background CLASSROOM.",
        "11. Masukkan 2 sprite.",
        "a) Sprite Budi",
        "b) Sprite Gia",
        # Huruf besar dianggap inisial nama, bukan nomor butir.
        "M. Rizki membantu Budi.",
    ]


def test_nomor_terpisah_dari_teksnya_tetap_butir():
    from pdf_sections import Line, mark_bullets

    def line(text, x0, size=11):
        return Line(text, size, False, x0, 0, 300, 11, 10)

    marked = mark_bullets([line("3.", 72, 12), line("Simpan proyekmu.", 90)])
    assert [(m.text, m.bullet, m.number) for m in marked] == [
        ("Simpan proyekmu.", True, "3.")
    ]


def test_isi_lama_dengan_tanda_butir_dirapikan_saat_dibaca():
    from pdf_sections import normalize_content

    old = (
        "## Tujuan\n"
        "Pada hari ini kamu akan belajar : "
        + " ".join(f"● {item}" for item in SCRATCHJR_PAGE_2_ITEMS)
        + "\n[[gambar:xref-14]]\n"
        "• Sudah berupa butir\n"
        "* Butir bintang\n"
        "-5 derajat adalah suhu di bawah nol."
    )
    assert normalize_content(old).split("\n") == [
        "## Tujuan",
        "Pada hari ini kamu akan belajar :",
        *[f"- {item}" for item in SCRATCHJR_PAGE_2_ITEMS],
        "[[gambar:xref-14]]",
        "- Sudah berupa butir",
        "- Butir bintang",
        "-5 derajat adalah suhu di bawah nol.",
    ]


def test_emoji_bola_lampu_di_refleksi_scratchjr_menjadi_butir():
    """Seperti halaman 10 ScratchJR: tiga butir 💡 dalam satu baris."""
    from pdf_sections import normalize_content

    content = "💡 Siapa pengirimnya? 💡 Siapa penerimanya? 💡 Mengapa harus jelas?"
    assert normalize_content(content).split("\n") == [
        "- Siapa pengirimnya?",
        "- Siapa penerimanya?",
        "- Mengapa harus jelas?",
    ]


def test_lanjutan_butir_tanpa_indentasi_tetap_satu_butir():
    """Seperti halaman 10 ScratchJR: baris lanjutan sejajar dengan tanda butir."""
    pdf = make_pdf(
        [
            [
                ("💡 Mengapa warna pesan pengirim", 11),
                ("dan penerima harus sama?", 11),
                ("💡 Siapa pengirimnya?", 11),
                ("", 0),
                ("Paragraf setelah daftar.", 11),
            ]
        ]
    )
    assert split_pdf_bytes(pdf)[0].content.split("\n") == [
        "- Mengapa warna pesan pengirim dan penerima harus sama?",
        "- Siapa pengirimnya?",
        "Paragraf setelah daftar.",
    ]


def draw_table(page, x0, y0, widths, rows, row_height=40):
    """Tabel bergaris. Teksnya ditulis tanpa karakter spasi seperti PDF Canva."""
    x1 = x0 + sum(widths)
    y1 = y0 + row_height * len(rows)
    for i in range(len(rows) + 1):
        page.draw_line((x0, y0 + i * row_height), (x1, y0 + i * row_height))
    x = x0
    for width in [0, *widths]:
        x += width
        page.draw_line((x, y0), (x, y1))
    for r, row in enumerate(rows):
        x = x0
        for width, text in zip(widths, row):
            place_words(page, x + 4, y0 + r * row_height + 16, text, 11, 0.1)
            x += width


DETEKTIF = [
    ["Masalah", "Penyebab", "Perbaikan"],
    ["Sprite diam", "1. Warna beda", "Samakan warna"],
    ["Sprite salah arah", "Blok salah", "Ganti blok"],
]


def test_tabel_bergaris_disimpan_sebagai_tabel_dengan_spasi_utuh():
    doc = pymupdf.open()
    page = doc.new_page()
    place_words(page, 72, 60, "7. Detektif Code:", 18, 0.1)
    place_words(page, 72, 90, "Cari penyebab masalahnya.", 11, 0.1)
    draw_table(page, 72, 110, [150, 150, 150], DETEKTIF)
    place_words(page, 72, 300, "Sudah selesai.", 11, 0.1)
    section = split_pdf_bytes(doc.tobytes())[0]
    assert tables_in(section.content) == [
        {
            "title": "7. Detektif Code",
            "columns": DETEKTIF[0],
            "rows": DETEKTIF[1:],
        }
    ]
    lines = section.content.split("\n")
    assert lines[0] == "Cari penyebab masalahnya."
    assert lines[1].startswith("[[tabel:")
    assert lines[2:] == ["Sudah selesai."]


def test_tabel_berisi_gambar_tetap_dibaca_per_baris():
    doc = pymupdf.open()
    page = doc.new_page()
    draw_table(page, 72, 110, [150, 150], [["Blok", "Arti"], ["", "Berjalan"]], 80)
    image(page, pymupdf.Rect(80, 195, 140, 255), 120)
    section = split_pdf_bytes(doc.tobytes())[0]
    assert tables_in(section.content) == []
    assert "Berjalan" in section.content


def test_garis_satu_baris_bukan_tabel():
    doc = pymupdf.open()
    page = doc.new_page()
    draw_table(page, 72, 110, [150, 150], [["Catatan", "Penting"]])
    assert tables_in(split_pdf_bytes(doc.tobytes())[0].content) == []


def test_label_baris_tabel_menyebut_nama_kolom():
    assert table_row_label(
        ["Langkah", "Keterangan", "Catatan"],
        ["Ambil", "1. Buka menu\n2. Pilih blok.", ""],
        1,
    ) == "Baris 1. Langkah: Ambil. Keterangan: 1. Buka menu. 2. Pilih blok."


def test_penanda_tabel_tidak_dirusak_saat_isi_dirapikan_dan_masuk_ke_ai():
    table = {"title": "Uji", "columns": ["A", "B"], "rows": [["\u25cf x y", "z"]]}
    content = f"Pengantar\n{table_marker(table)}"
    assert normalize_content(content) == content
    assert plain_text(content).split("\n") == [
        "Pengantar",
        "Uji",
        "Baris 1. A: \u25cf x y. B: z.",
    ]


def test_mengganti_tabel_sesuai_urutan():
    first = {"title": "Satu", "columns": ["A", "B"], "rows": [["1", "2"]]}
    second = {"title": "Dua", "columns": ["A", "B"], "rows": [["3", "4"]]}
    content = f"{table_marker(first)}\nTengah\n{table_marker(second)}"
    changed = {**second, "title": "Baru"}
    assert tables_in(replace_table(content, 1, changed)) == [first, changed]
    assert replace_table(content, 2, changed) is None
