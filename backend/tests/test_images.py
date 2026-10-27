import pymupdf
import pytest

import main
from test_endpoints import setup_subject


def make_pdf():
    """Halaman 1: teks, foto besar, ikon kecil. Halaman 2: foto yang sama."""
    doc = pymupdf.open()
    page = doc.new_page()
    page.insert_text((72, 72), "Budi menabung.", fontsize=11)
    photo = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 8, 8), False)
    photo.clear_with(120)
    xref = page.insert_image(pymupdf.Rect(72, 100, 272, 300), pixmap=photo)
    icon = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 8, 8), False)
    icon.clear_with(40)
    page.insert_image(pymupdf.Rect(72, 320, 92, 340), pixmap=icon)
    doc.new_page().insert_image(pymupdf.Rect(72, 100, 272, 300), xref=xref)
    data = doc.tobytes()
    doc.close()
    return data


class FakeBucket:
    def __init__(self, storage, name):
        self.storage = storage
        self.name = name

    def upload(self, path, file, file_options):
        self.storage.files[(self.name, path)] = file

    def download(self, path):
        return self.storage.files[(self.name, path)]

    def remove(self, paths):
        for path in paths:
            self.storage.files.pop((self.name, path), None)

    def create_signed_url(self, path, expires_in):
        return {"signedURL": f"https://tanda.test/{path}"}


class FakeStorage:
    def __init__(self):
        self.files = {}

    def from_(self, bucket):
        return FakeBucket(self, bucket)


@pytest.fixture
def storage(fake_db, monkeypatch):
    fake = FakeStorage()
    monkeypatch.setattr(main.supabase_admin, "storage", fake, raising=False)
    return fake


@pytest.fixture
def gemini(monkeypatch):
    calls = []

    def describe(image_bytes):
        calls.append(image_bytes)
        return "Budi memasukkan uang koin ke celengan."

    monkeypatch.setattr(main, "describe_image", describe)
    return calls


def upload(client, login, fake_db):
    _, subject, _ = setup_subject(client, login, fake_db)
    response = client.post(
        "/teacher/materials/upload",
        data={"title": "Menabung", "subject_id": subject["id"]},
        files={"file": ("menabung.pdf", make_pdf(), "application/pdf")},
    )
    assert response.status_code == 200, response.text
    return response.json()["material"]["id"], subject


def images(client, material_id):
    return client.get(f"/teacher/materials/{material_id}/images").json()["images"]


def test_unggah_menyimpan_gambar_tanpa_memanggil_gemini(
    client, login, fake_db, storage, gemini
):
    material_id, _ = upload(client, login, fake_db)
    saved = images(client, material_id)
    # Foto dipakai di dua halaman tetapi satu baris; ikon langsung dekoratif.
    assert [(i["page_number"], i["is_decorative"]) for i in saved] == [
        (1, False),
        (1, True),
    ]
    assert [i["needs_description"] for i in saved] == [True, False]
    assert saved[0]["preview_url"].startswith("https://tanda.test/")
    assert gemini == []


def start(client, material_id):
    return client.post(f"/teacher/materials/{material_id}/generate-image-description")


def status(client, material_id):
    return client.get(f"/teacher/materials/{material_id}/image-description").json()


def make_photos_pdf(count):
    """Satu halaman dengan beberapa foto yang perlu dideskripsikan."""
    doc = pymupdf.open()
    page = doc.new_page()
    for i in range(count):
        photo = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 8, 8), False)
        photo.clear_with(30 + i * 40)
        page.insert_image(pymupdf.Rect(72, 72 + i * 150, 272, 202 + i * 150), pixmap=photo)
    data = doc.tobytes()
    doc.close()
    return data


def test_proses_dimulai_di_latar_belakang_lalu_progres_dibaca(
    client, login, fake_db, storage, gemini
):
    material_id, _ = upload(client, login, fake_db)
    response = start(client, material_id)
    # Endpoint langsung menjawab dengan status awal.
    assert response.status_code == 202
    assert response.json() | {"failed": []} == {
        "material_id": material_id,
        "running": True,
        "total": 1,
        "done": 0,
        "failed": [],
        "error": None,
        "pending": 1,
    }
    # TestClient menjalankan tugas latar belakang sebelum kembali.
    assert len(gemini) == 1
    assert status(client, material_id) | {"material_id": None} == {
        "material_id": None,
        "running": False,
        "total": 1,
        "done": 1,
        "failed": [],
        "error": None,
        "pending": 0,
    }
    photo = images(client, material_id)[0]
    assert photo["description"] == "Budi memasukkan uang koin ke celengan."

    # Dipanggil lagi: tidak ada yang perlu dideskripsikan.
    start(client, material_id)
    assert len(gemini) == 1
    assert status(client, material_id)["total"] == 0


def test_gambar_gagal_tidak_menghentikan_gambar_lain_dan_ada_jeda(
    client, login, fake_db, storage, monkeypatch
):
    _, subject, _ = setup_subject(client, login, fake_db)
    response = client.post(
        "/teacher/materials/upload",
        data={"title": "Foto", "subject_id": subject["id"]},
        files={"file": ("foto.pdf", make_photos_pdf(3), "application/pdf")},
    )
    material_id = response.json()["material"]["id"]
    calls = []

    def describe(_bytes):
        calls.append(len(calls))
        if len(calls) == 2:
            raise RuntimeError("429 RESOURCE_EXHAUSTED: quota exceeded")
        return f"Foto {len(calls)}."

    sleeps = []
    monkeypatch.setattr(main, "describe_image", describe)
    monkeypatch.setattr(main, "GEMINI_DELAY_SECONDS", 4)
    monkeypatch.setattr(main, "GEMINI_RATE_LIMIT_PAUSE_SECONDS", 30)
    monkeypatch.setattr(main.time, "sleep", sleeps.append)
    start(client, material_id)

    body = status(client, material_id)
    assert len(calls) == 3
    assert (body["total"], body["done"], body["pending"]) == (3, 2, 1)
    assert [f["message"] for f in body["failed"]] == [
        "Batas pemakaian Gemini tercapai. Coba lagi beberapa menit lagi"
    ]
    # Jeda antar gambar, ditambah jeda panjang setelah kena batas pemakaian.
    assert sleeps == [4, 30, 4]


def test_gambar_gagal_dicoba_ulang_satu_per_satu(
    client, login, fake_db, storage, monkeypatch
):
    material_id, _ = upload(client, login, fake_db)

    def broken(_bytes):
        raise RuntimeError("server Gemini sibuk")

    monkeypatch.setattr(main, "describe_image", broken)
    start(client, material_id)
    failed = status(client, material_id)["failed"]
    assert [(f["page_number"], f["message"]) for f in failed] == [
        (1, "AI gagal mendeskripsikan gambar ini. Coba lagi")
    ]
    retry = f"/teacher/materials/{material_id}/images/{failed[0]['image_id']}/describe"
    response = client.post(retry)
    assert response.status_code == 502
    assert response.json()["detail"] == "AI gagal mendeskripsikan gambar ini. Coba lagi"

    monkeypatch.setattr(main, "describe_image", lambda _bytes: "Celengan.")
    response = client.post(retry)
    assert response.status_code == 200, response.text
    assert response.json()["image"]["description"] == "Celengan."
    body = status(client, material_id)
    assert (body["failed"], body["pending"]) == ([], 0)


def test_proses_yang_berjalan_tidak_dimulai_dua_kali(
    client, login, fake_db, storage, gemini
):
    material_id, _ = upload(client, login, fake_db)
    main.DESCRIBE_JOBS[material_id] = main.DescribeJob(total=5, done=2)
    body = start(client, material_id).json()
    assert (body["running"], body["total"], body["done"]) == (True, 5, 2)
    assert gemini == []
    photo = images(client, material_id)[0]
    response = client.post(f"/teacher/materials/{material_id}/images/{photo['id']}/describe")
    assert response.status_code == 409


def test_guru_lain_tidak_bisa_melihat_progres(client, login, fake_db, storage, gemini):
    material_id, _ = upload(client, login, fake_db)
    login("teacher", "Pak Lain")
    response = client.get(f"/teacher/materials/{material_id}/image-description")
    assert response.status_code == 404


def test_terbit_ditolak_selama_ada_gambar_tanpa_deskripsi(
    client, login, fake_db, storage, gemini
):
    material_id, _ = upload(client, login, fake_db)
    publish = lambda: client.patch(  # noqa: E731
        f"/teacher/materials/{material_id}", json={"is_published": True}
    )
    response = publish()
    assert response.status_code == 409
    assert "1 gambar (halaman 1)" in response.json()["detail"]

    client.post(f"/teacher/materials/{material_id}/generate-image-description")
    assert publish().status_code == 200


def test_gambar_yang_ditandai_dekoratif_tidak_menghalangi_terbit(
    client, login, fake_db, storage, gemini
):
    material_id, _ = upload(client, login, fake_db)
    photo = images(client, material_id)[0]
    response = client.patch(
        f"/teacher/materials/{material_id}/images/{photo['id']}",
        json={"is_decorative": True},
    )
    assert response.json()["image"]["needs_description"] is False
    response = client.patch(
        f"/teacher/materials/{material_id}", json={"is_published": True}
    )
    assert response.status_code == 200


def test_guru_edit_deskripsi_dan_materi_terbit_tetap_lengkap(
    client, login, fake_db, storage, gemini
):
    material_id, _ = upload(client, login, fake_db)
    client.post(f"/teacher/materials/{material_id}/generate-image-description")
    photo = images(client, material_id)[0]
    url = f"/teacher/materials/{material_id}/images/{photo['id']}"

    response = client.patch(url, json={"description": "  Budi menabung.  "})
    assert response.status_code == 200, response.text
    assert response.json()["image"]["description"] == "Budi menabung."
    assert client.patch(url, json={}).status_code == 400
    assert (
        client.patch(
            f"/teacher/materials/{material_id}/images/salah",
            json={"is_decorative": False},
        ).status_code
        == 404
    )

    client.patch(f"/teacher/materials/{material_id}", json={"is_published": True})
    # Setelah terbit, deskripsi tidak boleh dikosongkan.
    response = client.patch(url, json={"description": "   "})
    assert response.status_code == 409
    assert images(client, material_id)[0]["description"] == "Budi menabung."


def test_guru_lain_tidak_bisa_mengubah_gambar(client, login, fake_db, storage, gemini):
    material_id, _ = upload(client, login, fake_db)
    image_id = images(client, material_id)[0]["id"]
    login("teacher", "Pak Lain")
    response = client.patch(
        f"/teacher/materials/{material_id}/images/{image_id}",
        json={"is_decorative": True},
    )
    assert response.status_code == 404


def test_siswa_menerima_deskripsi_sesuai_penanda(
    client, login, fake_db, storage, gemini
):
    material_id, subject = upload(client, login, fake_db)
    client.post(f"/teacher/materials/{material_id}/generate-image-description")
    client.patch(f"/teacher/materials/{material_id}", json={"is_published": True})

    login("student")
    client.post("/student/subjects/join", json={"code": subject["access_code"]})
    body = client.get(f"/materials/{material_id}/sections").json()
    marker = body["sections"][0]["content"].split("\n")[1]
    image = next(i for i in body["images"] if f"[[gambar:{i['image_key']}]]" == marker)
    assert image["description"] == "Budi memasukkan uang koin ke celengan."
    assert "image_url" not in image


def test_materi_lama_tanpa_baris_gambar_diproses_dari_pdf(
    client, login, fake_db, storage, gemini
):
    material_id, _ = upload(client, login, fake_db)
    # Seperti materi yang diunggah sebelum gambar disimpan saat unggah.
    fake_db["material_images"] = []
    start(client, material_id)
    assert len(images(client, material_id)) == 2
    assert status(client, material_id)["pending"] == 0


def test_ai_soal_tidak_menerima_penanda_gambar(client, login, fake_db, monkeypatch):
    setup_subject(client, login, fake_db)
    fake_db["material_sections"] = [
        {
            "id": "s1",
            "material_id": "m1",
            "position": 1,
            "content": "## Menabung\n[[gambar:xref-5]]\nBudi menabung.",
        }
    ]
    seen = {}

    def fake_quiz(materi, total_questions, quiz_type):
        seen["materi"] = materi
        return main.AIOutput(questions=[])

    monkeypatch.setattr(main, "generate_quiz", fake_quiz)
    response = client.post(
        "/teacher/materials/m1/generate-quiz",
        json={"total_questions": 1, "quiz_type": "true_false"},
    )
    assert response.status_code == 200, response.text
    assert seen["materi"] == "Menabung\nBudi menabung."
