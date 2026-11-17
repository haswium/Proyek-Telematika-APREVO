"""Materi dari teks tempelan guru: pemecahan halaman, pratinjau, dan simpan."""

import pytest

import main
from test_endpoints import setup_subject
from text_material import looks_like_heading, split_pasted_text


def pages(text, title="Geografi"):
    return [(s.title, s.content) for s in split_pasted_text(text, title)]


# ---- Pemecahan halaman


def test_tanda_pagar_memulai_halaman_dan_subjudul():
    text = "# Bab 1\nIsi pertama.\n## Sub\nIsi kedua.\n# Bab 2\nIsi ketiga."
    assert pages(text) == [
        ("Bab 1", "Isi pertama.\n## Sub\nIsi kedua."),
        ("Bab 2", "Isi ketiga."),
    ]


def test_dengan_pagar_baris_pendek_tidak_jadi_judul():
    text = "# Bab 1\nPendek tanpa titik\nIsi."
    assert pages(text) == [("Bab 1", "Pendek tanpa titik\nIsi.")]


def test_tanpa_pagar_baris_pendek_berdiri_sendiri_jadi_judul():
    text = "Iklim Indonesia\n\nIndonesia beriklim tropis.\n\nMusim\n\nAda dua musim."
    assert pages(text) == [
        ("Iklim Indonesia", "Indonesia beriklim tropis."),
        ("Musim", "Ada dua musim."),
    ]


def test_tanpa_baris_kosong_setiap_baris_satu_paragraf():
    text = "Bab 1 Cuaca\nCuaca adalah keadaan udara.\nSuhu diukur dengan termometer."
    assert pages(text) == [
        (
            "Bab 1 Cuaca",
            "Cuaca adalah keadaan udara.\nSuhu diukur dengan termometer.",
        )
    ]


def test_kalimat_terpotong_digabung_bukan_judul():
    # Teks salinan PDF sering terpotong di tengah kalimat, dan potongan yang
    # pendek tanpa titik tidak boleh dianggap judul.
    text = "Indonesia memiliki iklim tropis\nkarena dilalui khatulistiwa.\n\nLagi."
    assert pages(text) == [
        (
            "Geografi",
            "Indonesia memiliki iklim tropis karena dilalui khatulistiwa.\nLagi.",
        )
    ]


def test_judul_langsung_diikuti_kalimat_baru():
    text = "Intro.\n\nMusim\nAda dua musim.\n\nLagi."
    assert pages(text) == [
        ("Geografi", "Intro."),
        ("Musim", "Ada dua musim.\nLagi."),
    ]


def test_teks_sebelum_judul_pertama_memakai_judul_materi():
    assert pages("Pengantar materi.\n\nBab 1\n\nIsi.") == [
        ("Geografi", "Pengantar materi."),
        ("Bab 1", "Isi."),
    ]


def test_dua_judul_berturut_turut_jadi_judul_dan_subjudul():
    text = "Bab 1 Iklim\n\nPengertian Iklim\n\nIklim adalah rata-rata cuaca."
    assert pages(text) == [
        ("Bab 1 Iklim", "## Pengertian Iklim\nIklim adalah rata-rata cuaca."),
    ]


def test_butir_daftar_dikenali():
    text = "Musim\n\nAda dua musim:\n• kemarau\n• hujan\n1. satu\n2. dua"
    assert pages(text) == [
        ("Musim", "Ada dua musim:\n- kemarau\n- hujan\n1. satu\n2. dua"),
    ]


@pytest.mark.parametrize(
    ("line", "expected"),
    [
        ("Iklim Indonesia", True),
        ("Apa itu iklim?", True),
        ("Ini kalimat biasa.", False),
        ("- kemarau", False),
        ("1. satu", False),
        ("x" * 59, True),
        ("x" * 60, False),
        ("", False),
    ],
)
def test_ciri_judul(line, expected):
    assert looks_like_heading(line) is expected


def test_spasi_aneh_dari_word_dirapikan():
    text = "Musim\r\n\r\nAda dua   musim.​"
    assert pages(text) == [("Musim", "Ada dua musim.")]


# ---- Endpoint


@pytest.fixture
def kelas(client, login, fake_db):
    _teacher_id, subject, _material = setup_subject(client, login, fake_db)
    return subject


def test_pratinjau_tidak_menyimpan(client, kelas, fake_db):
    before = len(fake_db.get("materials", []))
    response = client.post(
        "/teacher/materials/text/preview",
        json={"title": "Iklim", "text": "Musim\n\nAda dua musim:\n- kemarau\n- hujan"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["pages"] == [
        {
            "title": "Musim",
            "content": "Ada dua musim:\n- kemarau\n- hujan",
            "paragraph_count": 1,
            "subheading_count": 0,
            "list_item_count": 2,
            "word_count": 5,
        }
    ]
    assert len(fake_db.get("materials", [])) == before


def test_simpan_materi_teks_sebagai_draf(client, kelas, fake_db):
    response = client.post(
        "/teacher/materials/text",
        json={
            "title": " Iklim ",
            "subject_id": kelas["id"],
            "text": "Iklim\n\nIsi satu.\n\nMusim\n\nIsi dua.",
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    material = body["material"]
    assert material["title"] == "Iklim"
    assert material["is_published"] is False
    assert material["file_url"] == ""
    assert [s["title"] for s in body["sections"]] == ["Iklim", "Musim"]
    rows = [
        row
        for row in fake_db["material_sections"]
        if row["material_id"] == material["id"]
    ]
    assert sorted((row["position"], row["content"]) for row in rows) == [
        (1, "Isi satu."),
        (2, "Isi dua."),
    ]
    # Isinya bisa dibuka dengan endpoint halaman yang sama seperti materi PDF.
    sections = client.get(f"/materials/{material['id']}/sections")
    assert sections.status_code == 200, sections.text


@pytest.mark.parametrize("text", ["", "   \n\n  ", "Judul saja"])
def test_teks_kosong_ditolak(client, kelas, fake_db, text):
    before = len(fake_db.get("materials", []))
    response = client.post(
        "/teacher/materials/text",
        json={"title": "Iklim", "subject_id": kelas["id"], "text": text},
    )
    assert response.status_code == 422
    assert "kosong" in response.json()["detail"]
    assert len(fake_db.get("materials", [])) == before


def test_teks_terlalu_panjang_ditolak(client, kelas):
    response = client.post(
        "/teacher/materials/text",
        json={
            "title": "Iklim",
            "subject_id": kelas["id"],
            "text": "a" * (main.MAX_TEXT_LENGTH + 1),
        },
    )
    assert response.status_code == 422


def test_halaman_terlalu_banyak_ditolak(client, kelas):
    text = "\n\n".join(f"Bab {i}\n\nIsi." for i in range(main.MAX_PAGES + 1))
    response = client.post(
        "/teacher/materials/text/preview", json={"title": "Iklim", "text": text}
    )
    assert response.status_code == 422
    assert "maksimal" in response.json()["detail"]


def test_kelas_guru_lain_ditolak(client, kelas, login, fake_db):
    login("teacher", "Guru Lain")
    before = len(fake_db.get("materials", []))
    response = client.post(
        "/teacher/materials/text",
        json={"title": "Iklim", "subject_id": kelas["id"], "text": "Isi."},
    )
    assert response.status_code == 404
    assert len(fake_db.get("materials", [])) == before


def test_siswa_ditolak(client, kelas, login):
    login("student", "Budi")
    preview = client.post("/teacher/materials/text/preview", json={"text": "Isi."})
    assert preview.status_code == 403
    create = client.post(
        "/teacher/materials/text",
        json={"title": "A", "subject_id": kelas["id"], "text": "Isi."},
    )
    assert create.status_code == 403
