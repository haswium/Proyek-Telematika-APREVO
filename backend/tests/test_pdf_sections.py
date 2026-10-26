import pymupdf

from pdf_sections import split_pdf_bytes


def make_pdf(pages, toc=None, image_on_page=None):
    """pages: daftar halaman, tiap halaman daftar (teks, ukuran huruf)."""
    doc = pymupdf.open()
    for page_number, lines in enumerate(pages, start=1):
        page = doc.new_page()
        y = 72
        for text, size in lines:
            page.insert_text((72, y), text, fontsize=size)
            y += size * 1.8
        if image_on_page == page_number:
            pixmap = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 8, 8), False)
            pixmap.clear_with(200)
            page.insert_image(pymupdf.Rect(72, y + 10, 140, y + 78), pixmap=pixmap)
    if toc:
        doc.set_toc(toc)
    data = doc.tobytes()
    doc.close()
    return data


def test_judul_berhuruf_besar_menjadi_sub_bab():
    pdf = make_pdf(
        [
            [
                ("Pengantar singkat tentang materi.", 11),
                ("Fotosintesis", 18),
                ("Tumbuhan membuat makanan sendiri.", 11),
                ("Respirasi", 18),
                ("Sel memecah glukosa menjadi energi.", 11),
            ]
        ]
    )
    sections = split_pdf_bytes(pdf)
    assert [s.title for s in sections] == ["Pendahuluan", "Fotosintesis", "Respirasi"]
    assert sections[1].content == "Tumbuhan membuat makanan sendiri."
    assert sections[2].content == "Sel memecah glukosa menjadi energi."


def test_penomoran_sub_bab_dikenali_tanpa_huruf_besar():
    pdf = make_pdf(
        [
            [
                ("1.1 Pengertian Energi", 11),
                ("Energi adalah kemampuan melakukan usaha.", 11),
                ("1.2 Bentuk Energi", 11),
                ("Ada energi panas, cahaya, dan gerak.", 11),
            ]
        ]
    )
    titles = [s.title for s in split_pdf_bytes(pdf)]
    assert titles == ["1.1 Pengertian Energi", "1.2 Bentuk Energi"]


def test_daftar_isi_pdf_dipakai_lebih_dulu():
    pdf = make_pdf(
        [
            [("Bagian Satu", 11), ("Isi bagian satu.", 11)],
            [("Bagian Dua", 11), ("Isi bagian dua.", 11)],
        ],
        toc=[[1, "Bagian Satu", 1], [1, "Bagian Dua", 2]],
    )
    sections = split_pdf_bytes(pdf)
    assert [s.title for s in sections] == ["Bagian Satu", "Bagian Dua"]
    assert (sections[1].page_start, sections[1].page_end) == (2, 2)
    assert "Isi bagian dua." in sections[1].content


def test_tanpa_judul_dipecah_per_halaman():
    pdf = make_pdf(
        [
            [("Kalimat pertama di halaman satu ini cukup panjang sekali.", 11)],
            [("Kalimat kedua di halaman dua ini juga cukup panjang sekali.", 11)],
        ]
    )
    sections = split_pdf_bytes(pdf)
    assert [s.title for s in sections] == ["Halaman 1", "Halaman 2"]


def test_gambar_dihitung_di_sub_bab_tempatnya():
    pdf = make_pdf(
        [
            [("Daun", 18), ("Daun berwarna hijau.", 11)],
            [("Akar", 18), ("Akar menyerap air.", 11)],
        ],
        image_on_page=2,
    )
    sections = split_pdf_bytes(pdf)
    assert [(s.title, s.image_count) for s in sections] == [("Daun", 0), ("Akar", 1)]


def test_pdf_tanpa_teks_tetap_punya_sub_bab():
    sections = split_pdf_bytes(make_pdf([[]], image_on_page=1))
    assert len(sections) == 1
    assert sections[0].title == "Halaman 1"
    assert sections[0].image_count == 1
