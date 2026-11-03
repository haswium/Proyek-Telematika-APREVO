import pymupdf
import pytest

import main


def make_pdf():
    doc = pymupdf.open()
    page = doc.new_page()
    page.insert_text((72, 72), "Fotosintesis", fontsize=20)
    page.insert_text((72, 110), "Tumbuhan membuat makanan sendiri.", fontsize=11)
    data = doc.tobytes()
    doc.close()
    return data


class FakeBucket:
    def __init__(self, uploads):
        self.uploads = uploads

    def upload(self, path, file, file_options):
        self.uploads.append({"path": path, "file": file, "options": file_options})


class FakeStorage:
    def __init__(self):
        self.uploads = []

    def from_(self, bucket):
        assert bucket == "materials-pdf"
        return FakeBucket(self.uploads)


@pytest.fixture
def storage(fake_db, monkeypatch):
    fake = FakeStorage()
    monkeypatch.setattr(main.supabase_admin, "storage", fake, raising=False)
    return fake


def upload(client, name, data, content_type):
    return client.post(
        "/teacher/materials/upload",
        data={"title": "Tumbuhan"},
        files={"file": (name, data, content_type)},
    )


def test_pdf_dari_hp_sebagai_octet_stream_diterima(client, login, storage):
    login("teacher")
    response = upload(client, "modul.pdf", make_pdf(), "application/octet-stream")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["material"]["title"] == "Tumbuhan"
    assert body["sections"]
    assert len(storage.uploads) == 1
    assert storage.uploads[0]["options"]["content-type"] == "application/pdf"


def test_ekstensi_pdf_huruf_besar_diterima(client, login, storage):
    login("teacher")
    response = upload(client, "MODUL.PDF", make_pdf(), "application/pdf")
    assert response.status_code == 200, response.text


def test_bukan_berakhiran_pdf_ditolak(client, login, storage):
    login("teacher")
    response = upload(client, "modul.docx", make_pdf(), "application/pdf")
    assert response.status_code == 400
    assert response.json()["detail"] == "File harus berformat PDF."
    assert storage.uploads == []


def test_isi_bukan_pdf_ditolak_meski_content_type_pdf(client, login, storage):
    login("teacher")
    response = upload(client, "palsu.pdf", b"bukan pdf sungguhan", "application/pdf")
    assert response.status_code == 400
    assert response.json()["detail"] == "Isi file bukan PDF yang valid."
    assert storage.uploads == []
