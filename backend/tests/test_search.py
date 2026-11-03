"""Pencarian isi materi."""

import json

import pytest

import main
from pdf_sections import search_snippet
from test_endpoints import setup_subject


def add_section(db, section_id, position, title, *lines):
    db.setdefault("material_sections", []).append(
        {
            "id": section_id,
            "material_id": "m1",
            "position": position,
            "title": title,
            "content": "\n".join(lines),
        }
    )


TABLE = {
    "title": "Bagian daun",
    "columns": ["Nama", "Fungsi"],
    "rows": [["Stomata", "Tempat pertukaran gas"], ["Klorofil", "Menyerap\ncahaya"]],
}


@pytest.fixture
def materi(client, login, fake_db):
    """Materi dengan semua jenis blok. Yang aktif sesudahnya: guru pemilik."""
    _, subject, _ = setup_subject(client, login, fake_db)
    # Sengaja disisipkan tidak urut dan nomornya melompat, seperti `position`
    # yang tidak selalu berurutan.
    add_section(fake_db, "s2", 7, "Fotosintesis", "Pengantar.", "", "Daun memasak.")
    add_section(
        fake_db,
        "s1",
        3,
        "Pembuka",
        "## Subjudul akar",
        "- Butir batang",
        "12. Butir bernomor ranting",
        "[[gambar:xref-1]]",
        "[[gambar:xref-2]]",
        "[[gambar:xref-3]]",
        f"[[tabel:{json.dumps(TABLE)}]]",
        "[[tabel:{bukan json}]]",
    )
    fake_db["material_images"] = [
        {
            "id": "g1",
            "material_id": "m1",
            "image_key": "xref-1",
            "image_url": "1.png",
            "description": "Kupu-kupu hinggap di bunga",
            "is_decorative": False,
        },
        {
            "id": "g2",
            "material_id": "m1",
            "image_key": "xref-2",
            "image_url": "2.png",
            "description": "Bingkai dekoratif zamrud",
            "is_decorative": True,
        },
        {
            "id": "g3",
            "material_id": "m1",
            "image_key": "xref-3",
            "image_url": "3.png",
            "description": None,
            "is_decorative": False,
        },
    ]
    return subject


def search(client, query):
    response = client.get("/materials/m1/search", params={"q": query})
    assert response.status_code == 200, response.text
    return response.json()["results"]


def only(client, query):
    results = search(client, query)
    assert len(results) == 1, results
    return results[0]


def test_nomor_halaman_mengikuti_urutan_layar_baca(client, materi):
    hit = only(client, "memasak")
    assert hit["section_id"] == "s2"
    # `position`-nya 7, tetapi halaman kedua di layar baca.
    assert hit["page_index"] == 1
    assert hit["title"] == "Fotosintesis"


def test_baris_menunjuk_isi_yang_sama_dengan_jawaban_sections(client, materi):
    hit = only(client, "memasak")
    assert hit["line"] == 2 and hit["row"] is None
    sections = client.get("/materials/m1/sections").json()["sections"]
    content = next(s for s in sections if s["id"] == "s2")["content"]
    assert content.split("\n")[hit["line"]] == "Daun memasak."


def test_huruf_besar_kecil_dan_spasi_tidak_dibedakan(client, materi):
    assert only(client, "  DAUN   memasak ")["section_id"] == "s2"


@pytest.mark.parametrize(
    "query,line,row,snippet",
    [
        ("akar", 0, None, "Subjudul akar"),
        ("batang", 1, None, "Butir batang"),
        ("ranting", 2, None, "12. Butir bernomor ranting"),
        ("kupu", 3, None, "Gambar: Kupu-kupu hinggap di bunga"),
        ("bagian daun", 6, None, "Bagian daun"),
        ("stomata", 6, 0, "Baris 1. Nama: Stomata. Fungsi: Tempat pertukaran gas."),
        ("klorofil", 6, 1, "Baris 2. Nama: Klorofil. Fungsi: Menyerap. cahaya."),
        ("menyerap cahaya", 6, 1, "Baris 2. Nama: Klorofil. Fungsi: Menyerap. cahaya."),
        ("fungsi", 6, 0, "Baris 1. Nama: Stomata. Fungsi: Tempat pertukaran gas."),
    ],
)
def test_blok_yang_ditunjuk(client, materi, query, line, row, snippet):
    hit = only(client, query)
    assert (hit["line"], hit["row"], hit["snippet"]) == (line, row, snippet)


@pytest.mark.parametrize(
    "query",
    [
        "columns",  # kunci JSON tabel
        "rows",
        "xref",  # penanda gambar
        "zamrud",  # gambar dekoratif
        "bukan json",  # tabel rusak yang tidak ditampilkan
        "baris 1",  # awalan label tabel, bukan isi
    ],
)
def test_yang_tidak_dibacakan_tidak_ikut_dicari(client, materi, query):
    assert search(client, query) == []


def test_judul_halaman_hanya_dipakai_kalau_isinya_tidak_cocok(
    client, materi, fake_db
):
    hit = only(client, "fotosintesis")
    assert hit["line"] is None and hit["snippet"] == "Fotosintesis"

    fake_db["material_sections"][0]["content"] += "\nProses fotosintesis di daun."
    hit = only(client, "fotosintesis")
    assert hit["line"] == 3 and hit["snippet"] == "Proses fotosintesis di daun."


def test_satu_hasil_per_halaman_di_blok_pertama(client, materi, fake_db):
    fake_db["material_sections"][1]["content"] += "\nButir batang lagi."
    assert only(client, "batang")["line"] == 1


def test_urutan_hasil_mengikuti_halaman(client, materi, fake_db):
    fake_db["material_sections"][0]["content"] += "\nUlangi batang."
    assert [hit["page_index"] for hit in search(client, "batang")] == [0, 1]


@pytest.mark.parametrize("query", ["", " ", "a", " a ", "x" * 101])
def test_panjang_kata_diperiksa(client, materi, query):
    response = client.get("/materials/m1/search", params={"q": query})
    assert response.status_code == 400


def test_cuplikan_memuat_kata_dan_terpotong_di_batas_kata():
    text = " ".join(f"kata{n}" for n in range(100))
    snippet = search_snippet(text, "kata50")
    assert "kata50" in snippet
    assert snippet.startswith("...kata") and snippet.endswith("...")
    assert len(snippet) <= 126
    # Tiap potongan utuh, tidak ada kata yang terbelah.
    assert all(word in text.split() for word in snippet.strip(".").split())


def test_cuplikan_di_awal_dan_akhir_tanpa_titik_di_sisi_itu():
    text = " ".join(f"kata{n}" for n in range(100))
    assert search_snippet(text, "kata0").startswith("kata0")
    assert search_snippet(text, "kata99").endswith("kata99")


def test_siswa_anggota_bisa_mencari(client, materi, login, fake_db):
    login("student", "Budi")
    client.post("/student/subjects/join", json={"code": materi["access_code"]})
    assert only(client, "memasak")["section_id"] == "s2"


def test_siswa_bukan_anggota_ditolak(client, materi, login):
    login("student", "Budi")
    response = client.get("/materials/m1/search", params={"q": "memasak"})
    assert response.status_code == 403


def test_siswa_tidak_bisa_mencari_di_materi_draf(client, materi, login, fake_db):
    login("student", "Budi")
    client.post("/student/subjects/join", json={"code": materi["access_code"]})
    fake_db["materials"][0]["is_published"] = False
    response = client.get("/materials/m1/search", params={"q": "memasak"})
    assert response.status_code == 403


def test_guru_lain_tidak_bisa_mencari(client, materi, login):
    login("teacher", "Guru Lain")
    response = client.get("/materials/m1/search", params={"q": "memasak"})
    assert response.status_code == 404


def test_tanpa_login_ditolak(client, materi):
    main.app.dependency_overrides.pop(main.get_current_user)
    response = client.get("/materials/m1/search", params={"q": "memasak"})
    assert response.status_code in (401, 403)
