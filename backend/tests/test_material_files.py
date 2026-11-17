"""Unggah materi semua format lewat POST /teacher/materials/files.

File contoh dibuat di tes (python-docx, python-pptx, openpyxl, Pillow, wave).
Gemini selalu tiruan. TestClient menjalankan background task sebelum
mengembalikan respons, jadi konversi sudah selesai saat respons diterima.
"""

import io
import json
import wave
import zipfile
from types import SimpleNamespace

import pytest
from docx import Document
from openpyxl import Workbook
from PIL import Image
from pptx import Presentation
from pptx.util import Inches

import ai_media
import file_formats
import main
from ai_client import GeminiKeyMissing
from ai_media import PhotoReading
from file_formats import UnsupportedFile, detect
from test_endpoints import setup_subject
from test_images import FakeStorage

# ---- File contoh


def png_bytes(size=(300, 200)):
    out = io.BytesIO()
    Image.new("RGB", size, "white").save(out, "PNG")
    return out.getvalue()


def jpg_bytes():
    out = io.BytesIO()
    Image.new("RGB", (400, 300), "white").save(out, "JPEG")
    return out.getvalue()


def docx_bytes():
    document = Document()
    document.add_paragraph("Pengantar materi.")
    document.add_heading("Iklim", level=1)
    document.add_paragraph("Indonesia beriklim tropis.")
    document.add_heading("Musim", level=2)
    document.add_paragraph("kemarau", style="List Bullet")
    document.add_paragraph("hujan", style="List Bullet")
    table = document.add_table(rows=2, cols=2)
    table.cell(0, 0).text = "Musim"
    table.cell(0, 1).text = "Bulan"
    table.cell(1, 0).text = "Hujan"
    table.cell(1, 1).text = "Oktober"
    document.add_picture(io.BytesIO(png_bytes()))
    # Teks alternatif dari Word menjadi deskripsi awal.
    document.inline_shapes[0]._inline.docPr.set("descr", "Peta curah hujan")
    document.add_heading("Cuaca", level=1)
    document.add_paragraph("Cuaca berubah setiap hari.")
    out = io.BytesIO()
    document.save(out)
    return out.getvalue()


def pptx_bytes():
    presentation = Presentation()
    first = presentation.slides.add_slide(presentation.slide_layouts[1])
    first.shapes.title.text = "Iklim"
    body = first.placeholders[1].text_frame
    body.text = "Tropis"
    body.add_paragraph().text = "Dua musim"
    first.notes_slide.notes_text_frame.text = "Tanyakan musim favorit siswa."
    second = presentation.slides.add_slide(presentation.slide_layouts[6])
    box = second.shapes.add_textbox(Inches(1), Inches(0.5), Inches(4), Inches(1))
    box.text_frame.text = "Data curah hujan"
    table = second.shapes.add_table(
        2, 2, Inches(1), Inches(2), Inches(4), Inches(1)
    ).table
    table.cell(0, 0).text = "Bulan"
    table.cell(0, 1).text = "mm"
    table.cell(1, 0).text = "Januari"
    table.cell(1, 1).text = "300"
    second.shapes.add_picture(io.BytesIO(png_bytes()), Inches(1), Inches(4))
    out = io.BytesIO()
    presentation.save(out)
    return out.getvalue()


def xlsx_bytes():
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Nilai"
    sheet.append(["Nama", "Nilai"])
    sheet.append(["Andi", 80])
    sheet.append(["Budi", 7.5])
    workbook.create_sheet("Kosong")
    hidden = workbook.create_sheet("Rahasia")
    hidden.append(["jangan tampil"])
    hidden.sheet_state = "hidden"
    out = io.BytesIO()
    workbook.save(out)
    return out.getvalue()


def wav_bytes(seconds=1):
    out = io.BytesIO()
    with wave.open(out, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(1)
        audio.setframerate(8000)
        audio.writeframes(b"\x80" * 8000 * seconds)
    return out.getvalue()


def zip_bytes(files: dict[str, bytes]):
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    return out.getvalue()


OLE2 = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" + b"\x00" * 600


# ---- Deteksi format dari isi file


@pytest.fixture
def write(tmp_path):
    def _write(data, name="file"):
        path = tmp_path / name
        path.write_bytes(data)
        return path

    return _write


@pytest.mark.parametrize(
    ("data", "name", "kind", "content_type"),
    [
        (b"%PDF-1.7\n...", "a.pdf", "pdf", "application/pdf"),
        (docx_bytes(), "a.docx", "docx", None),
        (pptx_bytes(), "a.pptx", "pptx", None),
        (xlsx_bytes(), "a.xlsx", "xlsx", None),
        (jpg_bytes(), "a.jpg", "image", "image/jpeg"),
        (png_bytes(), "a.png", "image", "image/png"),
        (wav_bytes(), "a.wav", "audio", "audio/wav"),
        (b"OggS\x00\x02" + b"\x00" * 50, "a.ogg", "audio", "audio/ogg"),
        (b"ID3\x04\x00" + b"\x00" * 50, "a.mp3", "audio", "audio/mpeg"),
        (b"\xff\xfb\x90\x64" + b"\x00" * 50, "a.mp3", "audio", "audio/mpeg"),
        (b"\x00\x00\x00\x20ftypM4A \x00\x00", "a.m4a", "audio", "audio/mp4"),
        ("Nama;Nilai\nAndi;80".encode(), "a.csv", "csv", "text/csv"),
        ("# Judul\nIsi".encode(), "a.md", "md", "text/markdown"),
        ("Musim hujan ☔".encode(), "a.txt", "txt", "text/plain"),
    ],
    # ID pendek: isi file tidak ikut masuk ke nama tes.
    ids=lambda value: value if isinstance(value, str) and len(value) < 40 else "isi",
)
def test_format_dikenali_dari_isi(write, data, name, kind, content_type):
    detected = detect(write(data, name), name)
    assert detected.kind == kind
    if content_type:
        assert detected.content_type == content_type


def test_nama_file_salah_tetap_dikenali_dari_isi(write):
    # DOCX yang namanya .pdf tetap dibaca sebagai DOCX.
    assert detect(write(docx_bytes(), "tugas.pdf"), "tugas.pdf").kind == "docx"
    # Teks yang namanya .pdf bukan PDF.
    assert detect(write(b"bukan pdf", "a.pdf"), "a.pdf").kind == "txt"


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("lama.doc", "Simpan ulang sebagai .docx"),
        ("lama.ppt", "Simpan ulang sebagai .pptx"),
        ("lama.xls", "Simpan ulang sebagai .xlsx"),
        ("tanpa-nama", "Simpan ulang sebagai .pptx/.docx/.xlsx"),
    ],
)
def test_format_office_lama_ditolak_dengan_pesan_jelas(write, name, expected):
    with pytest.raises(UnsupportedFile) as caught:
        detect(write(OLE2, name), name)
    assert expected in str(caught.value)
    assert "lalu unggah lagi" in str(caught.value)


def test_video_dan_biner_tidak_dikenal_ditolak(write):
    video = b"\x00\x00\x00\x20ftypisom\x00\x00"
    with pytest.raises(UnsupportedFile, match="video"):
        detect(write(video, "film.mp4"), "film.mp4")
    with pytest.raises(UnsupportedFile, match="tidak didukung"):
        detect(write(b"\x00\x01\x02\x03" * 100, "a.bin"), "a.bin")
    with pytest.raises(UnsupportedFile, match="tidak didukung"):
        detect(write(zip_bytes({"isi.txt": b"x"}), "a.zip"), "a.zip")


def test_zip_bomb_ditolak(write, monkeypatch):
    monkeypatch.setattr(file_formats, "MAX_UNZIPPED_BYTES", 1000)
    bomb = zip_bytes({"word/document.xml": b"0" * 5000})
    with pytest.raises(UnsupportedFile, match="terlalu besar") as caught:
        detect(write(bomb, "a.docx"), "a.docx")
    assert caught.value.status_code == 413


# ---- Endpoint


@pytest.fixture
def kelas(client, login, fake_db, monkeypatch):
    storage = FakeStorage()
    monkeypatch.setattr(main.supabase_admin, "storage", storage, raising=False)
    # Kunci Gemini dianggap ada; panggilan Gemini sendiri tetap tiruan.
    monkeypatch.setattr(main, "require_gemini", lambda: None)
    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    return SimpleNamespace(
        id=subject["id"], teacher=teacher_id, storage=storage, db=fake_db
    )


def unggah(client, kelas, name, data, title="Iklim", content_type="application/octet-stream"):
    return client.post(
        "/teacher/materials/files",
        data={"title": title, "subject_id": kelas.id},
        files={"file": (name, data, content_type)},
    )


def selesai(client, response):
    """Status konversi setelah background task selesai."""
    assert response.status_code == 202, response.text
    material_id = response.json()["material"]["id"]
    status = client.get(f"/teacher/materials/{material_id}/conversion").json()
    return material_id, status


def halaman(kelas, material_id):
    rows = [r for r in kelas.db.get("material_sections", []) if r["material_id"] == material_id]
    return [(r["title"], r["content"]) for r in sorted(rows, key=lambda r: r["position"])]


def gambar(kelas, material_id):
    return [r for r in kelas.db.get("material_images", []) if r["material_id"] == material_id]


def test_docx(client, kelas):
    response = unggah(client, kelas, "iklim.docx", docx_bytes())
    # Endpoint langsung menjawab: materi draf berstatus processing.
    assert response.json()["conversion"]["status"] == "processing"
    assert response.json()["material"]["is_published"] is False
    material_id, status = selesai(client, response)

    assert status["status"] == "ready", status
    assert status["source_type"] == "docx"
    assert status["step"] == "Selesai: 3 halaman, 1 gambar."
    pages = halaman(kelas, material_id)
    assert [title for title, _ in pages] == ["Iklim", "Iklim", "Cuaca"]
    assert pages[0][1] == "Pengantar materi."
    iklim = pages[1][1].split("\n")
    assert iklim[:4] == [
        "Indonesia beriklim tropis.",
        "## Musim",
        "- kemarau",
        "- hujan",
    ]
    assert json.loads(iklim[4][len("[[tabel:") : -2]) == {
        "title": "Tabel 1",
        "columns": ["Musim", "Bulan"],
        "rows": [["Hujan", "Oktober"]],
    }
    assert iklim[5] == "[[gambar:docx-1]]"
    [image] = gambar(kelas, material_id)
    assert image["image_key"] == "docx-1"
    assert image["page_number"] == 2
    assert image["description"] == "Peta curah hujan"
    assert ("material-images", image["image_url"]) in kelas.storage.files
    # File asli disimpan di bucket material-files.
    material = next(m for m in kelas.db["materials"] if m["id"] == material_id)
    assert (main.MATERIAL_FILES_BUCKET, material["source_path"]) in kelas.storage.files


def test_pptx(client, kelas):
    material_id, status = selesai(client, unggah(client, kelas, "a.pptx", pptx_bytes()))
    assert status["status"] == "ready", status
    pages = halaman(kelas, material_id)
    assert pages[0] == (
        "Iklim",
        "- Tropis\n- Dua musim\n## Catatan pembicara\nTanyakan musim favorit siswa.",
    )
    title, content = pages[1]
    assert title == "Slide 2"
    lines = content.split("\n")
    assert lines[0] == "Data curah hujan"
    assert lines[1].startswith("[[tabel:")
    assert lines[2] == "[[gambar:pptx-s2-1]]"
    [image] = gambar(kelas, material_id)
    # Tanpa teks alternatif: dideskripsikan AI lewat job deskripsi.
    assert image["description"] is None
    assert image["page_number"] == 2


def test_xlsx_satu_sheet_satu_halaman(client, kelas):
    material_id, status = selesai(client, unggah(client, kelas, "nilai.xlsx", xlsx_bytes()))
    assert status["status"] == "ready", status
    [(title, content)] = halaman(kelas, material_id)
    assert title == "Nilai"
    assert json.loads(content[len("[[tabel:") : -2]) == {
        "title": "Nilai",
        "columns": ["Nama", "Nilai"],
        "rows": [["Andi", "80"], ["Budi", "7,5"]],
    }
    # Tabel dibaca per sel dengan nama kolom.
    assert main.plain_text(content).split("\n")[1] == "Baris 1. Nama: Andi. Nilai: 80."


def test_xlsx_besar_dipotong_dengan_keterangan(client, kelas, monkeypatch):
    from converters import sheet_material

    monkeypatch.setattr(sheet_material, "MAX_TABLE_ROWS", 2)
    workbook = Workbook()
    workbook.active.append(["No"])
    for number in range(5):
        workbook.active.append([number])
    out = io.BytesIO()
    workbook.save(out)
    material_id, _ = selesai(client, unggah(client, kelas, "a.xlsx", out.getvalue()))
    [(_, content)] = halaman(kelas, material_id)
    assert content.startswith("Tabel ini dipotong: menampilkan 2 dari 5 baris.")


def test_csv(client, kelas):
    data = "Nama;Nilai\nAndi;80\nBudi;75\n".encode()
    material_id, status = selesai(client, unggah(client, kelas, "nilai.csv", data, title="Nilai"))
    assert status["status"] == "ready"
    [(title, content)] = halaman(kelas, material_id)
    assert title == "Nilai"
    assert json.loads(content[len("[[tabel:") : -2])["rows"] == [["Andi", "80"], ["Budi", "75"]]


def test_txt_memakai_aturan_tempel_teks(client, kelas):
    data = "Musim\n\nAda dua musim.\n\nCuaca\n\nBerubah setiap hari.".encode()
    material_id, _ = selesai(client, unggah(client, kelas, "a.txt", data))
    assert halaman(kelas, material_id) == [
        ("Musim", "Ada dua musim."),
        ("Cuaca", "Berubah setiap hari."),
    ]


def test_markdown(client, kelas):
    data = (
        "# Iklim\n\nIklim **tropis**, lihat [peta](http://x).\n\n## Musim\n\n"
        "* kemarau\n* hujan\n\n| Bulan | mm |\n|---|---|\n| Jan | 300 |\n"
    ).encode()
    material_id, _ = selesai(client, unggah(client, kelas, "a.md", data))
    [(title, content)] = halaman(kelas, material_id)
    assert title == "Iklim"
    lines = content.split("\n")
    assert lines[:4] == ["Iklim tropis, lihat peta.", "## Musim", "- kemarau", "- hujan"]
    assert json.loads(lines[4][len("[[tabel:") : -2])["columns"] == ["Bulan", "mm"]


def test_foto_dibaca_gemini(client, kelas, monkeypatch):
    calls = []

    def fake_read(image_bytes):
        calls.append(image_bytes)
        return PhotoReading(
            title="Siklus Air",
            lines=["Air menguap karena panas.", "## Tahap", "- penguapan", "- hujan"],
            description="Diagram panah melingkar dari laut ke awan lalu ke gunung.",
        )

    monkeypatch.setattr(main, "read_photo", fake_read)
    material_id, status = selesai(client, unggah(client, kelas, "papan.jpg", jpg_bytes()))
    assert status["status"] == "ready", status
    assert status["source_type"] == "image"
    assert len(calls) == 1
    assert halaman(kelas, material_id) == [
        (
            "Siklus Air",
            "Air menguap karena panas.\n## Tahap\n- penguapan\n- hujan\n[[gambar:foto-1]]",
        )
    ]
    [image] = gambar(kelas, material_id)
    # Deskripsi dari Gemini sebagai isian awal yang bisa diubah guru.
    assert image["description"].startswith("Diagram panah")


def test_audio_ditranskrip_dan_bisa_diputar(client, kelas, monkeypatch):
    seen = {}

    def fake_transcribe(path, mime_type):
        seen["mime"] = mime_type
        # File dikirim dari disk, tidak dimuat ke memori oleh endpoint.
        seen["exists"] = path.exists()
        return "Selamat pagi anak-anak.\n\nHari ini kita belajar iklim."

    monkeypatch.setattr(main, "transcribe_audio", fake_transcribe)
    material_id, status = selesai(client, unggah(client, kelas, "rekaman.wav", wav_bytes(2)))
    assert status["status"] == "ready", status
    assert seen == {"mime": "audio/wav", "exists": True}
    assert halaman(kelas, material_id) == [
        ("Transkrip", "Selamat pagi anak-anak.\nHari ini kita belajar iklim.")
    ]
    material = next(m for m in kelas.db["materials"] if m["id"] == material_id)
    assert material["audio_duration_seconds"] == 2
    assert material["source_path"].endswith("/source.wav")

    sections = client.get(f"/materials/{material_id}/sections").json()["material"]
    assert sections["source_type"] == "audio"
    assert sections["has_audio"] is True
    audio = client.get(f"/materials/{material_id}/audio")
    assert audio.status_code == 200, audio.text
    assert audio.json() == {
        "url": f"https://tanda.test/{material['source_path']}",
        "expires_in": 3600,
        "duration_seconds": 2,
    }


def test_audio_lebih_dari_15_menit_ditolak(client, kelas, monkeypatch):
    monkeypatch.setattr(main, "MAX_AUDIO_SECONDS", 1)
    response = unggah(client, kelas, "panjang.wav", wav_bytes(3))
    assert response.status_code == 413
    assert "terlalu panjang" in response.json()["detail"]
    assert not [m for m in kelas.db["materials"] if m.get("source_type") == "audio"]


def test_materi_bukan_audio_tidak_punya_audio(client, kelas):
    assert client.get("/materials/m1/audio").status_code == 404


def test_audio_kelas_terhapus_ditolak_untuk_siswa(client, kelas, login, monkeypatch):
    monkeypatch.setattr(main, "transcribe_audio", lambda *_: "Halo.")
    material_id, _ = selesai(client, unggah(client, kelas, "a.wav", wav_bytes()))
    material = next(m for m in kelas.db["materials"] if m["id"] == material_id)
    material["is_published"] = True
    student = login("student", "Budi")
    kelas.db.setdefault("subject_students", []).append(
        {"subject_id": kelas.id, "student_id": student}
    )
    assert client.get(f"/materials/{material_id}/audio").status_code == 200
    kelas.db["subjects"][0]["deleted_at"] = "2026-11-01T00:00:00+00:00"
    assert client.get(f"/materials/{material_id}/audio").status_code == 410


@pytest.mark.parametrize("name", ["lama.doc", "lama.ppt", "lama.xls"])
def test_unggah_office_lama_ditolak_tanpa_materi(client, kelas, name):
    before = len(kelas.db["materials"])
    response = unggah(client, kelas, name, OLE2)
    assert response.status_code == 400
    assert "Simpan ulang sebagai" in response.json()["detail"]
    assert len(kelas.db["materials"]) == before
    assert not list(main.UPLOAD_DIR.glob("*.upload"))


def test_batas_ukuran_per_format(client, kelas):
    data = b"a" * (2 * 1024 * 1024 + 1)
    response = unggah(client, kelas, "besar.txt", data)
    assert response.status_code == 413
    assert "teks (.txt) maksimal 2 MB" in response.json()["detail"]


def test_batas_ukuran_unggahan(client, kelas, monkeypatch):
    monkeypatch.setattr(main, "MAX_UPLOAD_BYTES", 10)
    response = unggah(client, kelas, "a.txt", b"a" * 11)
    assert response.status_code == 413
    assert not list(main.UPLOAD_DIR.glob("*.upload"))


def test_foto_tanpa_kunci_gemini_ditolak(client, kelas, monkeypatch):
    def missing():
        raise main.HTTPException(status_code=503, detail=main.GEMINI_KEY_MISSING_DETAIL)

    monkeypatch.setattr(main, "require_gemini", missing)
    response = unggah(client, kelas, "a.png", png_bytes())
    assert response.status_code == 503


def test_dokumen_rusak_gagal_dengan_pesan_dan_bersih(client, kelas):
    broken = zip_bytes({"word/document.xml": b"<bukan xml"})
    material_id, status = selesai(client, unggah(client, kelas, "rusak.docx", broken))
    assert status["status"] == "failed"
    assert "tidak bisa dibaca" in status["error"]
    assert halaman(kelas, material_id) == []
    material = next(m for m in kelas.db["materials"] if m["id"] == material_id)
    assert material["source_path"] is None
    assert not [key for key in kelas.storage.files if key[0] == main.MATERIAL_FILES_BUCKET]
    assert not list(main.UPLOAD_DIR.glob("*.upload"))


def test_gemini_gagal_saat_foto(client, kelas, monkeypatch):
    def missing(_):
        raise GeminiKeyMissing("x")

    monkeypatch.setattr(main, "read_photo", missing)
    _, status = selesai(client, unggah(client, kelas, "a.png", png_bytes()))
    assert status["status"] == "failed"
    assert status["error"] == main.GEMINI_KEY_MISSING_DETAIL


def test_materi_yang_diproses_belum_bisa_terbit(client, kelas):
    kelas.db["materials"][0]["conversion_status"] = "processing"
    response = client.patch("/teacher/materials/m1", json={"is_published": True})
    assert response.status_code == 409
    assert "masih diproses" in response.json()["detail"]
    kelas.db["materials"][0]["conversion_status"] = "failed"
    response = client.patch("/teacher/materials/m1", json={"is_published": True})
    assert "gagal diproses" in response.json()["detail"]


def test_daftar_materi_guru_memuat_status(client, kelas):
    response = unggah(client, kelas, "a.txt", b"Isi materi.")
    material_id = response.json()["material"]["id"]
    materials = client.get(f"/teacher/subjects/{kelas.id}/materials").json()["materials"]
    row = next(m for m in materials if m["id"] == material_id)
    assert row["source_type"] == "txt"
    assert row["conversion"]["status"] == "ready"
    # Materi lama sebelum migrasi 008 dianggap PDF yang siap.
    old = next(m for m in materials if m["id"] == "m1")
    assert old["conversion"]["status"] == "ready"
    assert old["source_type"] == "pdf"


def test_restart_menandai_konversi_terputus(kelas):
    kelas.db["materials"][0]["conversion_status"] = "processing"
    main.mark_interrupted_conversions()
    material = kelas.db["materials"][0]
    assert material["conversion_status"] == "failed"
    assert "dimulai ulang" in material["conversion_error"]


def test_kelas_terhapus_ditolak_sebelum_menyimpan(client, kelas):
    kelas.db["subjects"][0]["deleted_at"] = "2026-11-01T00:00:00+00:00"
    before = len(kelas.db["materials"])
    response = unggah(client, kelas, "a.txt", b"Isi.")
    assert response.status_code == 404
    assert len(kelas.db["materials"]) == before


def test_siswa_tidak_bisa_mengunggah(client, kelas, login):
    login("student", "Budi")
    assert unggah(client, kelas, "a.txt", b"Isi.").status_code == 403


# ---- Edit teks halaman


@pytest.fixture
def halaman_teks(kelas):
    kelas.db["material_sections"] = [
        {
            "id": "s1",
            "material_id": "m1",
            "position": 1,
            "title": "Transkrip",
            "content": "Kalimat salah dengar.\n[[gambar:foto-1]]\nPenutup.",
        }
    ]
    return kelas


def test_guru_mengedit_teks_halaman(client, halaman_teks):
    response = client.patch(
        "/teacher/materials/m1/sections/s1",
        json={
            "title": "  Transkrip   pagi ",
            "content": "Kalimat yang benar.\n\n[[gambar:foto-1]]\n• Penutup",
        },
    )
    assert response.status_code == 200, response.text
    assert response.json()["section"] == {
        "id": "s1",
        "title": "Transkrip pagi",
        "content": "Kalimat yang benar.\n[[gambar:foto-1]]\n- Penutup",
    }


def test_penanda_gambar_tidak_boleh_hilang(client, halaman_teks):
    response = client.patch(
        "/teacher/materials/m1/sections/s1", json={"content": "Tanpa gambar."}
    )
    assert response.status_code == 422
    assert "tidak boleh dihapus" in response.json()["detail"]
    assert halaman_teks.db["material_sections"][0]["content"].startswith("Kalimat salah")


def test_halaman_materi_lain_tidak_ditemukan(client, halaman_teks):
    halaman_teks.db["material_sections"][0]["material_id"] = "lain"
    response = client.patch("/teacher/materials/m1/sections/s1", json={"title": "X"})
    assert response.status_code == 404


# ---- Files API Gemini untuk audio


class FakeFiles:
    def __init__(self, states):
        self.states = list(states)
        self.uploaded = []
        self.deleted = []

    def upload(self, file, config):
        self.uploaded.append((file, config))
        return SimpleNamespace(name="files/abc", state=SimpleNamespace(name=self.states.pop(0)))

    def get(self, name):
        return SimpleNamespace(name=name, state=SimpleNamespace(name=self.states.pop(0)))

    def delete(self, name):
        self.deleted.append(name)


def fake_client(states, generate):
    files = FakeFiles(states)
    models = SimpleNamespace(generate_content=generate)
    return SimpleNamespace(files=files, models=models), files


def test_transkrip_lewat_files_api_dan_file_dihapus(tmp_path, monkeypatch):
    path = tmp_path / "a.mp3"
    path.write_bytes(b"ID3" + b"\x00" * 10)
    captured = []

    def generate(model, contents):
        captured.append(contents)
        return SimpleNamespace(text="  Halo semua.  ")

    client, files = fake_client(["PROCESSING", "ACTIVE"], generate)
    monkeypatch.setattr(ai_media, "gemini_client", lambda: client)
    monkeypatch.setattr(ai_media, "FILE_POLL_SECONDS", 0)

    assert ai_media.transcribe_audio(path, "audio/mpeg") == "Halo semua."
    # Diunggah dari path di disk, bukan bytes; lalu dirujuk di prompt.
    assert files.uploaded == [
        (str(path), {"mime_type": "audio/mpeg", "display_name": "aprevo-audio"})
    ]
    assert captured[0][0].name == "files/abc"
    assert files.deleted == ["files/abc"]


def test_file_gemini_tetap_dihapus_kalau_transkrip_gagal(tmp_path, monkeypatch):
    path = tmp_path / "a.mp3"
    path.write_bytes(b"ID3")

    def generate(**_):
        raise RuntimeError("429 RESOURCE_EXHAUSTED")

    client, files = fake_client(["ACTIVE"], generate)
    monkeypatch.setattr(ai_media, "gemini_client", lambda: client)
    with pytest.raises(RuntimeError):
        ai_media.transcribe_audio(path, "audio/mpeg")
    assert files.deleted == ["files/abc"]


def test_file_gemini_gagal_diproses(tmp_path, monkeypatch):
    path = tmp_path / "a.mp3"
    path.write_bytes(b"ID3")
    client, files = fake_client(["FAILED"], lambda **_: None)
    monkeypatch.setattr(ai_media, "gemini_client", lambda: client)
    with pytest.raises(ValueError, match="gagal memproses"):
        ai_media.transcribe_audio(path, "audio/mpeg")
    assert files.deleted == ["files/abc"]


def test_materi_gagal_bisa_dihapus(client, kelas):
    broken = zip_bytes({"word/document.xml": b"<bukan xml"})
    material_id, status = selesai(client, unggah(client, kelas, "rusak.docx", broken))
    assert status["status"] == "failed"
    response = client.delete(f"/teacher/materials/{material_id}")
    assert response.status_code == 200, response.text
    assert not [m for m in kelas.db["materials"] if m["id"] == material_id]


def test_materi_yang_berhasil_tidak_bisa_dihapus_di_sini(client, kelas):
    response = client.delete("/teacher/materials/m1")
    assert response.status_code == 409
    assert [m for m in kelas.db["materials"] if m["id"] == "m1"]


def test_hapus_materi_gagal_di_kelas_terhapus_ditolak(client, kelas):
    kelas.db["materials"][0]["conversion_status"] = "failed"
    kelas.db["subjects"][0]["deleted_at"] = "2026-11-01T00:00:00+00:00"
    assert client.delete("/teacher/materials/m1").status_code == 404
    assert [m for m in kelas.db["materials"] if m["id"] == "m1"]


# ---- Unggah MP3 dan pesan error yang jelas (masalah dari versi web)


def mp3_bytes(frames=40):
    """MP3 kecil yang sah: header ID3v2.4 lalu frame MPEG-1 Layer III
    128 kbps 44,1 kHz (417 byte per frame, sekitar 26 ms)."""
    id3 = b"ID3\x04\x00\x00\x00\x00\x00\x00"
    frame = b"\xff\xfb\x90\x64" + b"\x00" * 413
    return id3 + frame * frames


def test_mp3_dari_web_diterima(client, kelas, monkeypatch):
    # Versi web mengirim bytes dengan content-type audio/mpeg dari ekstensi.
    seen = {}

    def fake_transcribe(path, mime_type):
        seen["mime"] = mime_type
        return "Halo semua."

    monkeypatch.setattr(main, "transcribe_audio", fake_transcribe)
    response = unggah(
        client, kelas, "rekaman.mp3", mp3_bytes(), content_type="audio/mpeg"
    )
    material_id, status = selesai(client, response)
    assert status["status"] == "ready", status
    assert seen["mime"] == "audio/mpeg"
    material = next(m for m in kelas.db["materials"] if m["id"] == material_id)
    assert material["audio_duration_seconds"] == 1
    assert material["source_path"].endswith("/source.mp3")


def fail_insert(monkeypatch, error):
    """Insert ke tabel materials gagal seperti di Supabase sungguhan."""
    real_table = main.supabase_admin.table

    def table(name):
        query = real_table(name)
        if name != "materials":
            return query
        real_insert = query.insert

        def insert(payload):
            def execute():
                raise error

            built = real_insert(payload)
            built.execute = execute
            return built

        query.insert = insert
        return query

    monkeypatch.setattr(main.supabase_admin, "table", table)


def test_kolom_migrasi_008_belum_ada_dijawab_jelas(client, kelas, monkeypatch, caplog):
    fail_insert(
        monkeypatch,
        main.APIError(
            {
                "code": "PGRST204",
                "message": "Could not find the 'audio_duration_seconds' column of "
                "'materials' in the schema cache",
            }
        ),
    )
    with caplog.at_level("ERROR", logger="main"):
        response = unggah(client, kelas, "rekaman.mp3", mp3_bytes())
    # Bukan 500 "Server mengalami kesalahan", tetapi penyebabnya.
    assert response.status_code == 503
    assert "migrasi 008_format_materi.sql" in response.json()["detail"]
    assert "UPLOAD_GAGAL" in caplog.text and "PGRST204" in caplog.text
    assert not list(main.UPLOAD_DIR.glob("*.upload"))


def test_error_database_lain_menyebut_kodenya(client, kelas, monkeypatch):
    fail_insert(
        monkeypatch,
        main.APIError({"code": "23514", "message": "violates check constraint"}),
    )
    response = unggah(client, kelas, "a.txt", b"Isi.")
    assert response.status_code == 500
    assert response.json()["detail"] == (
        "Materi gagal disimpan di database (kode 23514). Coba lagi, atau "
        "hubungi pengelola server."
    )


def test_bucket_belum_ada_pesan_gagal_jelas(client, kelas, monkeypatch, caplog):
    monkeypatch.setattr(main, "transcribe_audio", lambda *_: "Halo.")

    class MissingBucket:
        def __init__(self, storage):
            self.storage = storage

        def from_(self, name):
            if name == main.MATERIAL_FILES_BUCKET:
                raise RuntimeError("{'statusCode': 404, 'error': 'Bucket not found'}")
            return self.storage.from_(name)

    monkeypatch.setattr(main.supabase_admin, "storage", MissingBucket(kelas.storage))
    with caplog.at_level("ERROR", logger="main"):
        _, status = selesai(client, unggah(client, kelas, "a.mp3", mp3_bytes()))
    assert status["status"] == "failed"
    assert "bucket material-files belum ada" in status["error"]
    assert "KONVERSI_GAGAL" in caplog.text


def test_health_config_memeriksa_migrasi_dan_bucket(client, kelas, monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_CONFIG_PROBLEMS", [])
    fail_select = main.APIError(
        {"code": "42703", "message": "column materials.source_type does not exist"}
    )
    real_table = main.supabase_admin.table

    def table(name):
        query = real_table(name)
        if name == "materials":
            def execute():
                raise fail_select
            query.execute = execute
        return query

    class NoBucket:
        def get_bucket(self, _name):
            raise RuntimeError("Bucket not found")

    monkeypatch.setattr(main.supabase_admin, "table", table)
    monkeypatch.setattr(main.supabase_admin, "storage", NoBucket())
    body = client.get("/health/config").json()
    assert body == {
        "ok": False,
        "problems": [main.MIGRATION_008_MISSING, main.BUCKET_MISSING],
    }


def test_health_config_siap_unggah(client, kelas, monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_CONFIG_PROBLEMS", [])

    class Bucket:
        def get_bucket(self, name):
            return {"id": name}

    monkeypatch.setattr(main.supabase_admin, "storage", Bucket())
    assert client.get("/health/config").json() == {"ok": True, "problems": []}
